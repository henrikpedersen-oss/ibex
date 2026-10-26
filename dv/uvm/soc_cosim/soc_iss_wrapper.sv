// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// The reference model's instruction-set part: each RVFI item steps the ISS by one instruction of
// the same software image, and the outcome goes to the scoreboard as a soc_rvfi_exp_item.
//
// - RISC-V mode (SOC_COSIM_SPIKE): Spike, through Ibex's co-simulation (dv/cosim), as the Ibex UVM
//   bench uses it. Spike fetches from its own memory, loaded from the images in soc_cosim_cfg.
//   Data accesses come from the RVFI item, split into Spike's aligned word transactions; a load's
//   value is an event (written into Spike's memory before the step, so Spike reads what the chip
//   read). Spike still checks every access's address, type and store data, and every register
//   result, PC and trap. Interrupts, NMI and debug requests are taken where RVFI shows them taken.
//   Spike starts from the core's reset state, its PMP and mseccfg reset values included.
// - CHERIoT mode (SOC_COSIM_SAIL): CHERIoT-Sail (dv/cosim/cheriot_sail) executes the RVFI
//   instruction word: each integer load's value is an event again; capability loads read its own
//   memory and tags; interrupts are taken from its own state when RVFI shows one taken; every
//   result, capability tag and trap is checked, and every integer store's address and data.
// - Where the model starts (soc_cosim_cfg.start_mode):
//     SocStartRiscv:   Spike from reset; at the first instruction after the store to lock_addr,
//                      the state passes from Spike to CHERIoT-Sail, never from the chip: Spike's
//                      next PC must be where the chip continues; x1-x15 become untagged; PCC, MTCC
//                      and MEPCC the executable root at the PC, mtvec and mepc; mstatus.MIE/MPIE,
//                      mie, mcause, mtval carry over; Spike's memory over cfg.mem_base/mem_size
//                      becomes CHERIoT-Sail's (Earl Grey 2, REQ_SOC_07).
//     SocStartCheriot: CHERIoT-Sail from reset, at Ibex's CHERIoT reset state, with the images
//                      loaded into its memory (the CHERIoT RTOS test SoC).
// - SOC_COSIM_SYSMODEL: each data access also goes to the SystemC model (soc_sysmodel.sv), which
//   predicts the loads it can; its findings fail the instruction.
//
// Plusargs: +sb_corrupt=insn.rd (one register result corrupted before it is checked, from the
// 100th instruction), +sb_corrupt=insn.cheriot_rd (the same from the 100th CHERIoT-mode
// instruction); the run must fail. +soc_spike_log=1 (Spike's commit log, spike.model.log).

`ifdef SOC_COSIM_SPIKE
  `include "spike_cosim_dpi.svh"
  `include "cosim_dpi.svh"
  import "DPI-C" function int soc_cosim_load_elf(chandle cosim_handle, string path);
  import "DPI-C" function int unsigned soc_cosim_get_gpr(chandle cosim_handle, int idx);
  import "DPI-C" function int unsigned soc_cosim_get_pc(chandle cosim_handle);
  import "DPI-C" function int unsigned soc_cosim_get_csr(chandle cosim_handle, int csr_num);
  import "DPI-C" function int soc_cosim_copy_mem_to_cheriot_sail(chandle cosim_handle,
                                                                 int unsigned base,
                                                                 int unsigned size);
`endif
`ifdef SOC_COSIM_SAIL
  `include "cheriot_sail_cosim_dpi.svh"
  import "DPI-C" function int soc_cosim_load_elf_cheriot_sail(string path);
  // cheriot_sail_cosim_revocation.cc (dv/cosim/cheriot_sail).
  import "DPI-C" function void cheriot_sail_cosim_set_revocation(int unsigned heap_base,
                                                                  int unsigned heap_size,
                                                                  int unsigned bits_base);
  import "DPI-C" function void cheriot_sail_cosim_clear_tag(int unsigned addr);
  import "DPI-C" function int unsigned cheriot_sail_cosim_read_mem_byte(int unsigned addr);
`endif

class soc_iss_wrapper extends uvm_component;
  `uvm_component_utils(soc_iss_wrapper)

  soc_cosim_cfg cfg;

  uvm_tlm_analysis_fifo #(soc_rvfi_item) rvfi_fifo;
  uvm_analysis_port #(soc_rvfi_exp_item) exp_port;

  // Set by the environment: the RVFI source exists (an interface, or a replay).
  bit enabled;

  protected chandle      cosim;
  protected bit          stopped;
  protected bit          off_said;
  // CHERIoT mode: CHERIoT-Sail has the state.
  protected bit          sail_active;
  protected bit          sail_prev_trap;
  protected bit [31:0]   boot_addr_q;
  protected bit          corrupt_rd;
  protected bit          corrupt_cheriot_rd;
  protected int unsigned sail_steps;
  protected int unsigned stepped;

  `uvm_component_new

  // Compiled with a reference model.
  static function bit compiled();
`ifdef SOC_COSIM_SPIKE
    return 1'b1;
`elsif SOC_COSIM_SAIL
    return 1'b1;
`else
    return 1'b0;
`endif
  endfunction

  function void build_phase(uvm_phase phase);
    string sb_corrupt;
    super.build_phase(phase);
    rvfi_fifo = new("rvfi_fifo", this);
    exp_port  = new("exp_port", this);
    void'($value$plusargs("sb_corrupt=%s", sb_corrupt));
    corrupt_rd         = sb_corrupt == "insn.rd";
    corrupt_cheriot_rd = sb_corrupt == "insn.cheriot_rd";
  endfunction

  virtual task run_phase(uvm_phase phase);
    soc_rvfi_item item;
    if (!enabled || !compiled()) return;
    forever begin
      rvfi_fifo.get(item);
      handle(item);
    end
  endtask

  protected function void handle(soc_rvfi_item item);
    if (item.reset) begin
      sail_active = 1'b0;
      if (cfg.iss_off_reason != "") begin
        if (!off_said) `uvm_info(`gfn, {"SOC_ISS off: ", cfg.iss_off_reason}, UVM_LOW)
        off_said = 1'b1;
        stopped  = 1'b1;
        return;
      end
      if (cfg.start_mode == soc_cosim_cfg::SocStartCheriot) restart_cheriot(item.boot_addr);
      else restart_spike(item.boot_addr);
`ifdef SOC_COSIM_SYSMODEL
      if (!stopped) soc_sysmodel::chip_reset(cfg);
`endif
      return;
    end
    if (stopped) return;
    // The store to the lock that switches the mode retires after its write has changed the mode,
    // so its item already reads CHERIoT; it executed in RISC-V mode and is Spike's. The handover is
    // at the next instruction.
    if (item.cheriot && !(!sail_active && is_lock_store(item))) begin
      if (item.irq_only) return;  // CHERIoT-Sail takes interrupts from its own state
      if (!sail_active) handover(item);
      sail_step(item);
      return;
    end
    spike_step(item);
  endfunction

  // A store to the lock (SocStartRiscv).
  protected function bit is_lock_store(soc_rvfi_item item);
    return cfg.start_mode == soc_cosim_cfg::SocStartRiscv && item.mem_wmask != 0 &&
           item.mem_addr == cfg.lock_addr;
  endfunction

  protected function soc_rvfi_exp_item new_exp(soc_rvfi_item item);
    soc_rvfi_exp_item exp = soc_rvfi_exp_item::type_id::create("exp");
    exp.order = item.order;
    exp.pc    = item.pc;
    exp.act   = item;
    return exp;
  endfunction

  // ---- RISC-V mode: Spike ----

  protected function void restart_spike(bit [31:0] boot_addr);
`ifdef SOC_COSIM_SPIKE
    bit en_log;
    if (cosim != null) spike_cosim_release(cosim);
    void'($value$plusargs("soc_spike_log=%b", en_log));
    boot_addr_q = boot_addr;
    // Ibex starts at boot_addr + 0x80 with mtvec at boot_addr, vectored.
    cosim = spike_cosim_init(cfg.isa_string(), boot_addr + 32'h80, boot_addr | 32'h1,
                             en_log ? "spike.model.log" : "", cfg.pmp_num_regions,
                             cfg.pmp_granularity, cfg.mhpm_counter_num, cfg.secure_ibex,
                             cfg.icache, cfg.dm_base_addr, cfg.dm_base_addr + cfg.dm_addr_mask);
    if (cosim == null) `uvm_fatal(`gfn, "SOC_ISS cannot start Spike")
    set_pmp_reset();
    // Spike's cpuctrlsts never initialises its stored value (riscv-isa-sim 4b97396,
    // riscv/csrs.cc cpuctrlsts_csr_t), so sync_exc_seen and double_fault_seen can read 1
    // before any trap. Ibex resets the register to 0.
    riscv_cosim_set_csr(cosim, int'(ibex_pkg::CSR_CPUCTRLSTS), 32'h0);
    foreach (cfg.images[i]) begin
      int n = soc_cosim_load_elf(cosim, cfg.images[i]);
      if (n < 0) `uvm_fatal(`gfn, $sformatf("SOC_ISS cannot load %s into Spike", cfg.images[i]))
      `uvm_info(`gfn, $sformatf("SOC_ISS %0d bytes of %s loaded", n, cfg.images[i]), UVM_MEDIUM)
    end
    stopped = 1'b0;
    `uvm_info(`gfn, $sformatf("SOC_ISS Spike started: %s, pc %08h", cfg.isa_string(),
                              boot_addr + 32'h80), UVM_LOW)
`else
    `uvm_fatal(`gfn, "SOC_ISS: this SoC starts in RISC-V mode, and the build has no Spike (SOC_COSIM_SPIKE)")
`endif
  endfunction

`ifdef SOC_COSIM_SPIKE
  // The PMP and mseccfg reset values (ibex_pmp_reset_pkg). mseccfg first: Smepmp lets RLB be set
  // only while no entry is locked, so written after the locked reset entries it would stay 0 in
  // Spike, while the chip resets with RLB = 1 and the ROM rewrites locked entries. Then addresses
  // before configurations (a locked entry refuses address writes).
  protected function void set_pmp_reset();
    bit [31:0] pmpcfg[4];
    riscv_cosim_set_csr(cosim, int'(ibex_pkg::CSR_MSECCFG),
                        {29'b0, ibex_pmp_reset_pkg::PmpMseccfgRst.rlb,
                         ibex_pmp_reset_pkg::PmpMseccfgRst.mmwp,
                         ibex_pmp_reset_pkg::PmpMseccfgRst.mml});
    for (int i = 0; i < 16; i++) begin
      ibex_pkg::pmp_cfg_t c = ibex_pmp_reset_pkg::PmpCfgRst[i];
      riscv_cosim_set_csr(cosim, int'(ibex_pkg::CSR_PMPADDR0) + i,
                          ibex_pmp_reset_pkg::PmpAddrRst[i][33:2]);
      pmpcfg[i / 4][8 * (i % 4) +: 8] = {c.lock, 2'b00, 2'(c.mode), c.exec, c.write, c.read};
    end
    foreach (pmpcfg[i]) riscv_cosim_set_csr(cosim, int'(ibex_pkg::CSR_PMPCFG0) + i, pmpcfg[i]);
  endfunction

  // Hand the instruction's data access to Spike as aligned word transactions. RVFI gives the
  // unaligned address, a mask of 1, 2 or 4 bytes from it, and the value unshifted.
  protected function void notify_mem(soc_rvfi_item item);
    bit        store = item.mem_wmask != 0;
    bit [3:0]  mask  = store ? item.mem_wmask : item.mem_rmask;
    bit [31:0] data  = store ? item.mem_wdata : item.mem_rdata;
    bit [31:0] word0;
    int        n, off, n0;
    bit        misaligned;
    if (mask == 0) return;
    // A trap with no error response is a fault Spike raises itself (PMP): no access happened.
    if (item.trap && !item.mem_error) return;
    n          = $countones(mask);
    off        = item.mem_addr[1:0];
    n0         = (off + n > 4) ? 4 - off : n;
    word0      = {item.mem_addr[31:2], 2'b00};
    misaligned = (item.mem_addr % n) != 0;
    // A load's value is an event: Spike reads what the chip read.
    if (!store && !item.mem_error) begin
      for (int b = 0; b < n; b++) begin
        riscv_cosim_write_mem_byte(cosim, item.mem_addr + b, data[8 * b +: 8]);
      end
    end
    riscv_cosim_notify_dside_access(cosim, store, word0, data << (8 * off),
                                    4'((1 << n0) - 1) << off, item.mem_error, misaligned, 1'b0,
                                    1'b0, item.mode == 2'b11);
    if (n0 < n) begin
      riscv_cosim_notify_dside_access(cosim, store, word0 + 4, data >> (8 * n0),
                                      4'((1 << (n - n0)) - 1), item.mem_error, 1'b0, 1'b1,
                                      item.mem_error, item.mode == 2'b11);
    end
  endfunction
`endif

  protected function void spike_step(soc_rvfi_item item);
`ifdef SOC_COSIM_SPIKE
    soc_rvfi_exp_item exp;
    bit [31:0] rd_wdata;
    if (cosim == null) return;
    if (item.irq_only) begin
      // Only an interrupt notification: no instruction retired.
      riscv_cosim_set_nmi(cosim, item.nmi);
      riscv_cosim_set_nmi_int(cosim, item.nmi_int, item.nmi_int_mtval);
      riscv_cosim_set_mip(cosim, item.pre_mip, item.pre_mip);
      // The core committed to the interrupt: the ISS takes it ahead of a later NMI or debug request.
      riscv_cosim_set_irq_taken(cosim);
      return;
    end
    notify_mem(item);
    // In this order, so debug, NMI and interrupts arriving together are taken by priority.
    riscv_cosim_set_debug_req(cosim, item.debug_req);
    riscv_cosim_set_nmi(cosim, item.nmi);
    riscv_cosim_set_nmi_int(cosim, item.nmi_int, item.nmi_int_mtval);
    riscv_cosim_set_mip(cosim, item.pre_mip, item.post_mip);
    riscv_cosim_set_mcycle(cosim, item.mcycle);
    for (int i = 0; i < 10; i++) begin
      riscv_cosim_set_csr(cosim, int'(ibex_pkg::CSR_MHPMCOUNTER3) + i, item.mhpmcounters[i]);
      riscv_cosim_set_csr(cosim, int'(ibex_pkg::CSR_MHPMCOUNTER3H) + i, item.mhpmcountersh[i]);
    end
    riscv_cosim_set_ic_scr_key_valid(cosim, item.ic_scr_key_valid);

    rd_wdata = item.rd_wdata;
    if (corrupt_rd && item.rd_addr != 0 && stepped >= 100) begin
      rd_wdata   = ~rd_wdata;
      corrupt_rd = 1'b0;
      `uvm_info(`gfn, $sformatf("+sb_corrupt=insn.rd: x%0d of order %0d corrupted",
                                item.rd_addr, item.order), UVM_LOW)
    end
    exp = new_exp(item);
    // A Zcmp micro-operation that is not the last only records its register write; the ISS steps
    // the whole instruction on the last one (spike_cosim.cc).
    exp.match = riscv_cosim_step(cosim, item.rd_addr, rd_wdata, item.pc, item.intr, item.trap,
                                 item.rf_wr_suppress, item.more_ops);
    if (!exp.match) begin
      for (int i = 0; i < riscv_cosim_get_num_errors(cosim); i++) begin
        exp.errors = {exp.errors, riscv_cosim_get_error(cosim, i), "; "};
      end
      riscv_cosim_clear_errors(cosim);
    end
`ifdef SOC_COSIM_SYSMODEL
    model_check(exp, soc_sysmodel::access(item));
`endif
    stepped++;
    exp_port.write(exp);
`endif
  endfunction

  // ---- CHERIoT mode: CHERIoT-Sail ----

  // CHERIoT-Sail's memory: the whole address space (its RAM segment at 0x80000000, its second
  // segment below); devices' values are events, written before each load.
  protected function void sail_platform();
`ifdef SOC_COSIM_SAIL
    cheriot_sail_cosim_set_mhpm_counter_num(cfg.mhpm_counter_num);
    cheriot_sail_cosim_set_rom(32'h0000_0000, 32'h8000_0000);
    cheriot_sail_cosim_set_ram_size(32'h7fff_0000);
`endif
  endfunction

  // Debug: +soc_cosim_peek=<addr>[,<addr>...] prints CHERIoT-Sail's memory word at each address
  // with the first mismatch.
  protected bit peeked;
  protected function void sail_peek();
`ifdef SOC_COSIM_SAIL
    string arg, w[$];
    if (peeked || !$value$plusargs("soc_cosim_peek=%s", arg)) return;
    peeked = 1'b1;
    foreach (arg[i]) if (arg[i] == ",") arg[i] = " ";
    soc_split(arg, w);
    foreach (w[i]) begin
      bit [31:0] a, v;
      void'($sscanf(w[i], "%h", a));
      for (int b = 0; b < 4; b++) v[8 * b +: 8] = 8'(cheriot_sail_cosim_read_mem_byte(a + b));
      `uvm_info(`gfn, $sformatf("SOC_ISS peek: CHERIoT-Sail [%08h] = %08h", a, v), UVM_LOW)
    end
`endif
  endfunction

  // After every CHERIoT-Sail init: the SoC's revocation layout.
  protected function void sail_revocation();
`ifdef SOC_COSIM_SAIL
    if (cfg.rev_bits_base == 0) return;
    cheriot_sail_cosim_set_revocation(cfg.rev_heap_base, cfg.rev_heap_size, cfg.rev_bits_base);
`endif
  endfunction

  // Tags another bus master (a revocation engine) cleared since the last step: CHERIoT-Sail's
  // memory follows, as it would after a DMA write. Recorded for a replay.
  protected function void sail_tag_clears();
`ifdef SOC_COSIM_SAIL
    while (soc_cosim_tb_link::tag_clears.size() > 0) begin
      bit [31:0]       a = soc_cosim_tb_link::tag_clears.pop_front();
      longint unsigned t = soc_cosim_tb_link::tag_clear_times.pop_front();
      soc_cosim_record::tag_clear(t, a);
      if (sail_active) cheriot_sail_cosim_clear_tag(a);
    end
`endif
  endfunction

  // SocStartCheriot: CHERIoT-Sail at the core's CHERIoT reset state, loaded with the images.
  protected function void restart_cheriot(bit [31:0] boot_addr);
`ifdef SOC_COSIM_SAIL
    int total;
    if (sail_active) cheriot_sail_cosim_cleanup();
    boot_addr_q = boot_addr;
    sail_platform();
    cheriot_sail_cosim_init(boot_addr);
    sail_revocation();
    foreach (cfg.images[i]) begin
      int n = soc_cosim_load_elf_cheriot_sail(cfg.images[i]);
      if (n < 0) `uvm_fatal(`gfn, $sformatf("SOC_ISS cannot load %s into CHERIoT-Sail", cfg.images[i]))
      total += n;
    end
    sail_active    = 1'b1;
    sail_prev_trap = 1'b0;
    stopped        = 1'b0;
    `uvm_info(`gfn, $sformatf("SOC_ISS CHERIoT-Sail started from reset at pc %08h (%0d bytes of %0d images)",
                              {boot_addr[31:8], 8'h80}, total, cfg.images.size()), UVM_LOW)
`else
    `uvm_fatal(`gfn, "SOC_ISS: this SoC starts in CHERIoT mode, and the build has no CHERIoT-Sail (SOC_COSIM_SAIL)")
`endif
  endfunction

  // SocStartRiscv: the handover at the lock: Spike's state into a fresh CHERIoT-Sail.
  protected function void handover(soc_rvfi_item item);
`ifdef SOC_COSIM_SPIKE
`ifdef SOC_COSIM_SAIL
    bit [31:0] spike_pc = soc_cosim_get_pc(cosim);
    int        copied;
    if (spike_pc != item.pc) begin
      // The switch point itself is checked: Spike's next instruction is where the chip goes on.
      soc_rvfi_exp_item exp = new_exp(item);
      exp.match  = 1'b0;
      exp.errors = $sformatf("handover: Spike's next PC is %08h, the chip continues at %08h",
                             spike_pc, item.pc);
      exp_port.write(exp);
    end
    sail_platform();
    cheriot_sail_cosim_init(boot_addr_q);
    sail_revocation();
    cheriot_sail_cosim_null_gprs();
    foreach (cfg.mem_base[r]) begin
      int n = soc_cosim_copy_mem_to_cheriot_sail(cosim, cfg.mem_base[r], cfg.mem_size[r]);
      if (n < 0) `uvm_fatal(`gfn, $sformatf("SOC_ISS handover: cannot copy %08h", cfg.mem_base[r]))
      copied += n;
    end
    for (int r = 1; r < 16; r++) cheriot_sail_cosim_set_gpr_int(5'(r), soc_cosim_get_gpr(cosim, r));
    cheriot_sail_cosim_handover(spike_pc,
                                soc_cosim_get_csr(cosim, int'(ibex_pkg::CSR_MTVEC)),
                                soc_cosim_get_csr(cosim, int'(ibex_pkg::CSR_MEPC)),
                                soc_cosim_get_csr(cosim, int'(ibex_pkg::CSR_MSTATUS)),
                                soc_cosim_get_csr(cosim, int'(ibex_pkg::CSR_MIE)),
                                soc_cosim_get_csr(cosim, int'(ibex_pkg::CSR_MCAUSE)),
                                soc_cosim_get_csr(cosim, int'(ibex_pkg::CSR_MTVAL)));
    sail_active    = 1'b1;
    sail_prev_trap = 1'b0;
    `uvm_info(`gfn, $sformatf({"SOC_ISS handover to CHERIoT-Sail at order %0d, pc %08h, after %0d ",
                               "RISC-V-mode instructions (%0d bytes of memory)"},
                              item.order, item.pc, stepped, copied), UVM_LOW)
`endif
`endif
  endfunction

  // One CHERIoT-mode instruction on CHERIoT-Sail.
  protected function void sail_step(soc_rvfi_item item);
`ifdef SOC_COSIM_SAIL
    soc_rvfi_exp_item exp = new_exp(item);
    bit [31:0] rd_wdata = item.rd_wdata;
    bit        cheri_we = item.rd_addr != 0 && !item.rf_wr_suppress && !item.trap;
    sail_tag_clears();
    cheriot_sail_cosim_clear_errors();

    // Inputs that depend on timing or the bench, before the step.
    cheriot_sail_cosim_set_mcycle(item.mcycle);
    for (int i = 0; i < cfg.mhpm_counter_num && i < 10; i++) begin
      cheriot_sail_cosim_set_mhpmcounter(3 + i, {item.mhpmcountersh[i], item.mhpmcounters[i]});
    end
    cheriot_sail_cosim_set_ic_scr_key_valid(item.ic_scr_key_valid);
    // The core entered an interrupt handler: the model takes the interrupt from its own state.
    if (item.intr && !sail_prev_trap && !item.nmi && !item.nmi_int && !item.debug_req) begin
      void'(cheriot_sail_cosim_take_interrupt(item.pre_mip));
    end
    // An integer load's value is an event: CHERIoT-Sail reads what the chip read.
    if (item.mem_rmask != 0 && !item.mem_is_cap && !item.mem_error && !item.trap) begin
      for (int b = 0; b < $countones(item.mem_rmask); b++) begin
        cheriot_sail_cosim_write_mem_byte(item.mem_addr + b, item.mem_rdata[8 * b +: 8]);
      end
    end
    if ((corrupt_rd && stepped >= 100 || corrupt_cheriot_rd && sail_steps >= 100) &&
        item.rd_addr != 0 && !item.trap) begin
      rd_wdata           = ~rd_wdata;
      corrupt_rd         = 1'b0;
      corrupt_cheriot_rd = 1'b0;
      `uvm_info(`gfn, $sformatf("+sb_corrupt: x%0d of order %0d (CHERIoT mode) corrupted",
                                item.rd_addr, item.order), UVM_LOW)
    end
    exp.match = cheriot_sail_cosim_step(item.insn, item.pc, cheri_we, item.rd_addr,
                                        item.rd_wcap[32], rd_wdata, item.trap) == 0;
    for (int i = 0; i < cheriot_sail_cosim_get_num_errors(); i++) begin
      exp.errors = {exp.errors, cheriot_sail_cosim_get_error(i), "; "};
    end
    // Every capability result in full, address and metadata, as ibex_sail_rvfi_cmp compares it for
    // TestRIG: cheriot_sail_cosim_step compares only a capability write's register and tag.
    if (cheri_we && cheriot_sail_cosim_get_cd_addr() != 0 &&
        cheriot_sail_cosim_get_cd_addr() == item.rd_addr &&
        {item.rd_wcap[31:0], rd_wdata} != cheriot_sail_cosim_get_cd_wdata()) begin
      exp.match  = 1'b0;
      exp.errors = {exp.errors, $sformatf("cap rd data (c%0d): chip 0x%08x_%08x, CHERIoT-Sail 0x%016x; ",
                                          item.rd_addr, item.rd_wcap[31:0], rd_wdata,
                                          cheriot_sail_cosim_get_cd_wdata())};
    end
    // Every integer store's address and data, from the model's RVFI packet.
    if (item.mem_wmask != 0 && !item.mem_is_cap && !item.trap) begin
      bit [31:0] mask = '0;
      for (int b = 0; b < 4; b++) if (item.mem_wmask[b]) mask[8 * b +: 8] = 8'hff;
      if (!cheriot_sail_cosim_get_mem_present() ||
          cheriot_sail_cosim_get_mem_addr() != item.mem_addr ||
          (cheriot_sail_cosim_get_mem_wdata() & mask) != (item.mem_wdata & mask)) begin
        exp.match  = 1'b0;
        exp.errors = {exp.errors, $sformatf("store: chip [%08h]=%08h, CHERIoT-Sail [%08h]=%08h; ",
                                            item.mem_addr, item.mem_wdata & mask,
                                            cheriot_sail_cosim_get_mem_addr(),
                                            32'(cheriot_sail_cosim_get_mem_wdata()) & mask)};
      end
    end
`ifdef SOC_COSIM_SYSMODEL
    model_check(exp, soc_sysmodel::access(item));
`endif
    if (!exp.match) sail_peek();
    sail_prev_trap = item.trap;
    sail_steps++;
    stepped++;
    exp_port.write(exp);
`endif
  endfunction

`ifdef SOC_COSIM_SYSMODEL
  // The SystemC model's findings on the instruction's data access (soc_sysmodel.sv) fail it too.
  protected function void model_check(soc_rvfi_exp_item exp, string errors);
    if (errors == "") return;
    exp.match  = 1'b0;
    exp.errors = {exp.errors, errors};
  endfunction
`endif

  function void final_phase(uvm_phase phase);
    super.final_phase(phase);
`ifdef SOC_COSIM_SPIKE
    if (cosim != null) spike_cosim_release(cosim);
`endif
    cosim = null;
`ifdef SOC_COSIM_SAIL
    if (sail_active) cheriot_sail_cosim_cleanup();
`endif
`ifdef SOC_COSIM_SYSMODEL
    soc_sysmodel::close();
`endif
  endfunction

  function int unsigned num_stepped();
    return stepped;
  endfunction
endclass
