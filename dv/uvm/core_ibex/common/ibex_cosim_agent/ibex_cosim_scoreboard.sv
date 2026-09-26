// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

`include "spike_cosim_dpi.svh"
`include "cosim_dpi.svh"
`include "cheriot_sail_cosim_dpi.svh"

class ibex_cosim_scoreboard extends uvm_scoreboard;
  chandle cosim_handle;

  core_ibex_cosim_cfg cfg;

  // Whether this test runs the DUT with cheriot_enable_i asserted.  The
  // CHERIoT-Sail oracle models CHERIoT unconditionally, so it is only a valid
  // reference when the DUT is in CHERIoT mode too -- see the gates below.
  bit cheriot_seq_en;

  uvm_tlm_analysis_fifo #(ibex_rvfi_seq_item)       rvfi_port;
  uvm_tlm_analysis_fifo #(ibex_mem_intf_seq_item)   dmem_port;
  uvm_tlm_analysis_fifo #(ibex_mem_intf_seq_item)   imem_port;
  uvm_tlm_analysis_fifo #(ibex_ifetch_seq_item)     ifetch_port;
  uvm_tlm_analysis_fifo #(ibex_ifetch_pmp_seq_item) ifetch_pmp_port;

  virtual core_ibex_instr_monitor_if instr_vif;
  virtual core_ibex_dut_probe_if     dut_vif;

  uvm_event reset_e;
  uvm_event check_inserted_iside_error_e;

  // mtval that Ibex will write when it takes an internal (memory-integrity) NMI.
  //
  // Read hierarchically rather than taken from RVFI because mtval is not on the
  // RVFI interface at all. The ISS cannot derive it: Ibex sets mtval to the
  // address of the transaction that returned bad integrity
  // (ibex_controller.sv:438), while a standard RISC-V model zeroes mtval on any
  // interrupt -- so a `csrr rd, mtval` in the handler diverges. Nor can it be
  // reconstructed from the preceding synchronous trap's tval, because the NMI
  // carries the dside integrity-error address rather than whatever faulted
  // first.
  //
  // irq_nm_int_mtval is declared at module scope in ibex_controller.sv (line
  // 183), not inside the `if (MemECC)` generate block that drives it, so this
  // path resolves in every configuration.
  //
  // A hierarchical peek is deliberate: the alternative was adding an RVFI
  // output, which would edit RTL the team is actively changing. Keep this in DV
  // so it collides with nothing; replace it with a real RVFI signal later if one
  // appears.
  local string nmi_int_mtval_path =
      "core_ibex_tb_top.dut.u_ibex_top.u_ibex_core.id_stage_i.controller_i.irq_nm_int_mtval";

  // ── mtval / exception-cause checker (#824) ────────────────────────────────
  //
  // The architectural mtval the DUT settled on. Read from the CSR itself rather
  // than csr_mtval_o so the value is the committed one, not the value being
  // driven during the trap cycle.
  local string dut_mtval_path =
      "core_ibex_tb_top.dut.u_ibex_top.u_ibex_core.cs_registers_i.mtval_q";

  // Set when the previous RVFI item trapped, so the comparison happens on the
  // next item once both sides have settled. Also records whether that trap was
  // an internal NMI -- see check_mtval_after_trap for why that case is skipped.
  local bit prev_item_trapped;
  local bit prev_item_was_nmi_int;
  local bit dut_mtval_read_failed;

  // OFF unless +check_mtval=1. Deliberately opt-in, not enabled by default.
  //
  // Ibex's mtval on a trap is implementation-defined in places where Spike will
  // not necessarily agree, and none of it is covered by fixup_csr (which exists
  // precisely because "Spike and Ibex have different WARL behaviours" but does
  // not handle mtval). Two known divergence risks, both from
  // ibex_controller.sv:
  //   :866-868  illegal instruction -> Ibex writes the instruction word
  //             (non-CHERIoT mode); a standard model may write 0
  //   :861      instruction access fault -> Ibex writes the PC
  // riscv_illegal_instr_test runs illegal_instr_ratio=25, so if Spike disagrees
  // this would fire thousands of times and drown the regression.
  //
  // So: implemented and available, but must be characterised on a real run
  // before being turned on by default. Enable it on a single test first and
  // look at what it reports; if the only mismatches are the WARL cases above,
  // add them to fixup_csr and then flip the default.
  local bit check_mtval_en;

  function void check_mtval_after_trap(ibex_rvfi_seq_item rvfi_instr);
    uvm_hdl_data_t dut_val;
    bit [31:0]     iss_mtval;

    if (!check_mtval_en) return;

    if (prev_item_trapped) begin
      // Skip internal NMIs. set_nmi_int() pushes the DUT's mtval into the ISS
      // (because Ibex writes the integrity-error address where a standard
      // RISC-V model zeroes mtval), so comparing here would be tautological --
      // the DUT's own value checked against itself. Nothing is lost: that path
      // is covered by the NMI handling, and CHERI faults, which is what this
      // check exists for, are unaffected.
      if (prev_item_was_nmi_int) begin
        prev_item_trapped     = 1'b0;
        prev_item_was_nmi_int = 1'b0;
        return;
      end

      if (!uvm_hdl_read(dut_mtval_path, dut_val)) begin
        if (!dut_mtval_read_failed) begin
          dut_mtval_read_failed = 1'b1;
          `uvm_error(`gfn, $sformatf("Could not read %0s; mtval will not be checked",
                                     dut_mtval_path))
        end
      end else begin
        riscv_cosim_get_csr(cosim_handle, ibex_pkg::CSR_MTVAL, iss_mtval);
        if (dut_val[31:0] !== iss_mtval) begin
          // UVM_ERROR rather than FATAL so a run reports every mtval divergence
          // instead of stopping at the first, matching the CHERIoT-Sail check
          // below. In CHERIoT mode the decoded fields are far more useful than
          // the raw word, so print both.
          if (cheriot_seq_en) begin
            `uvm_error(`gfn, $sformatf(
                {"mtval mismatch after trap at pc 0x%08x: DUT 0x%08x (capcause 0x%02x, ",
                 "cap_idx %0d) vs ISS 0x%08x (capcause 0x%02x, cap_idx %0d)"},
                rvfi_instr.pc, dut_val[31:0], dut_val[4:0], dut_val[10:5],
                iss_mtval, iss_mtval[4:0], iss_mtval[10:5]))
          end else begin
            `uvm_error(`gfn, $sformatf("mtval mismatch after trap at pc 0x%08x: DUT 0x%08x vs ISS 0x%08x",
                                       rvfi_instr.pc, dut_val[31:0], iss_mtval))
          end
        end
      end

      prev_item_trapped     = 1'b0;
      prev_item_was_nmi_int = 1'b0;
    end

    if (rvfi_instr.trap) begin
      prev_item_trapped     = 1'b1;
      prev_item_was_nmi_int = rvfi_instr.nmi_int;
    end
  endfunction

  // ── mcounteren sync ───────────────────────────────────────────────────────
  //
  // mcounteren gates U-mode access to the unprivileged counters
  // (ibex_cs_registers.sv:618, `illegal_csr = (priv_lvl_q == PRIV_LVL_U) &&
  // !mcounteren[mhpmcounter_idx]`), but it is not on RVFI and was never pushed
  // to the ISS, so Spike kept it at its reset value of zero. A U-mode
  // `csrr t0, hpmcounter3` then trapped on the ISS and retired on the DUT.
  //
  // The DUT is correct there. From riscv_dv's mcounteren_test on 2026-09-24:
  //     csrrw x0, mcounteren, x5    x5=0xffffffff
  //     csrrs x18, mcounteren, x0   x18=0x00001ffd   <- bit 3 set
  // so mcounteren[3] == 1 and the U-mode read is permitted. Spike trapped only
  // because it had never been told.
  //
  // Pushed rather than compared, for the same reason the mhpmcounter* registers
  // above are pushed: mcounteren is WARL with implementation-defined width and
  // masking (bit 1 tied low for the unimplemented `time` counter, bits above
  // MHPMCounterNum+MHPMCOUNTER_BASE tied low), which the ISS cannot be expected
  // to reproduce without being told.
  //
  // This does mean mcounteren itself is no longer checked here. That coverage is
  // not lost overall -- it moves to the Sail equivalence proof, which compares
  // mcounteren properly as of the 2026-09-24 fix to formal-cheriot's abs.sv
  // (it had been pinning the DUT side to zero with the comment "ibex hardwires
  // to zero", which is false). Formal is the stronger check of the two.
  local string dut_mcounteren_path =
      "core_ibex_tb_top.dut.u_ibex_top.u_ibex_core.cs_registers_i.mcounteren";
  local bit dut_mcounteren_read_failed;

  function bit [31:0] get_dut_mcounteren();
    uvm_hdl_data_t val;
    if (!uvm_hdl_read(dut_mcounteren_path, val)) begin
      if (!dut_mcounteren_read_failed) begin
        dut_mcounteren_read_failed = 1'b1;
        `uvm_error(`gfn, $sformatf(
            "Could not read %0s; the ISS will keep mcounteren at 0 and U-mode counter reads will mismatch",
            dut_mcounteren_path))
      end
      return 32'h0;
    end
    return val[31:0];
  endfunction

  // Returns the DUT's pending internal-NMI mtval, or 0 if the path cannot be
  // read. A failed read is reported once rather than silently returning 0,
  // because silently returning 0 would reintroduce exactly the divergence this
  // exists to fix.
  local bit nmi_int_mtval_read_failed;
  function bit [31:0] get_nmi_int_mtval();
    uvm_hdl_data_t val;
    if (!uvm_hdl_read(nmi_int_mtval_path, val)) begin
      if (!nmi_int_mtval_read_failed) begin
        nmi_int_mtval_read_failed = 1'b1;
        `uvm_error(`gfn, $sformatf(
            "Could not read %0s; internal-NMI mtval will be passed as 0 and a csrr of mtval in the NMI handler will mismatch",
            nmi_int_mtval_path))
      end
      return 32'h0;
    end
    return val[31:0];
  endfunction

  bit failed_iside_accesses [bit[31:0]];
  bit iside_pmp_failure     [bit[31:0]];

  typedef struct {
    bit [63:0] order;
    bit [31:0] addr;
  } iside_err_t;

  iside_err_t iside_error_queue [$];

  `uvm_component_utils(ibex_cosim_scoreboard)

  function new(string name="", uvm_component parent=null);
    super.new(name, parent);

    rvfi_port                    = new("rvfi_port", this);
    dmem_port                    = new("dmem_port", this);
    imem_port                    = new("imem_port", this);
    ifetch_port                  = new("ifetch_port", this);
    ifetch_pmp_port              = new("ifetch_pmp_port", this);
    cosim_handle                 = null;
    reset_e                      = new();
    check_inserted_iside_error_e = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(core_ibex_cosim_cfg)::get(this, "", "cosim_cfg", cfg)) begin
      `uvm_fatal(`gfn, "Cannot get cosim configuration")
    end

    if (!uvm_config_db#(virtual core_ibex_instr_monitor_if)::get(null, "", "instr_monitor_if",
                                                                 instr_vif)) begin
      `uvm_fatal(`gfn, "Cannot get instr_monitor_if")
    end

    if (!uvm_config_db#(virtual core_ibex_dut_probe_if)::get(null, "", "dut_if",
                                                                 dut_vif)) begin
      `uvm_fatal(`gfn, "Cannot get dut_probe_if")
    end

    init_cosim();
  endfunction : build_phase

  protected function void init_cosim();
    cleanup_cosim();

    `DV_CHECK_FATAL(cfg.dm_start_addr > 0, "Debug module start address configured to zero.")
    `DV_CHECK_FATAL(cfg.dm_end_addr > 0, "Debug module end address configured to zero.")

    // TODO: Ensure log file on reset gets append rather than overwrite?
    cosim_handle = spike_cosim_init(cfg.isa_string, cfg.start_pc, cfg.start_mtvec, cfg.log_file,
      cfg.pmp_num_regions, cfg.pmp_granularity, cfg.mhpm_counter_num, cfg.secure_ibex, cfg.icache,
      cfg.dm_start_addr, cfg.dm_end_addr);

    if (cosim_handle == null) begin
      `uvm_fatal(`gfn, "Could not initialise cosim")
    end

    // The CHERIoT-Sail oracle models CHERIoT unconditionally, so it is only a
    // valid reference when the DUT is running with cheriot_enable_i asserted
    // (see cfg.enable_cheriot_seq plumbing in core_ibex_env_cfg/base_test).
    // Gated on cfg.secure_ibex too, matching the config the CHERIoT directed
    // tests run under (opentitan: SecureIbex=1) -- see ibex-private's history
    // for why cfg.secure_ibex alone is not a valid CHERIoT-mode gate.
    void'($value$plusargs("enable_cheriot_seq=%0b", cheriot_seq_en));

    // mtval/exception-cause checker (#824) -- opt-in, see check_mtval_en.
    void'($value$plusargs("check_mtval=%0b", check_mtval_en));
    if (check_mtval_en) begin
      `uvm_info(`gfn, "mtval/exception-cause checking ENABLED (+check_mtval=1)", UVM_LOW)
    end
    if (cfg.secure_ibex && cheriot_seq_en) begin
      cheriot_sail_cosim_init(cfg.start_pc);
      `uvm_info(`gfn, "CHERIoT-Sail oracle initialised", UVM_LOW)
    end
  endfunction

  protected function void cleanup_cosim();
     if (cosim_handle) begin
        spike_cosim_release(cosim_handle);
     end
     cosim_handle = null;
     // Same gate as the init above, so cleanup is never called on an oracle
     // that was never initialised. Safe on the first call from init_cosim(),
     // where cheriot_seq_en is still 0 and nothing has been set up yet.
     if (cfg != null && cfg.secure_ibex && cheriot_seq_en) begin
       cheriot_sail_cosim_cleanup();
     end
  endfunction

  virtual task run_phase(uvm_phase phase);
    forever begin
      @(negedge instr_vif.reset)
      fork : isolation_fork
        run_cosim_rvfi();
        run_cosim_dmem();
        run_cosim_imem_errors();
        run_cosim_prune_imem_errors();
        if (cfg.probe_imem_for_errs) begin
          run_cosim_imem();
        end else begin
          fork
            run_cosim_ifetch();
            run_cosim_ifetch_pmp();
          join_any
        end
      join_none
      reset_e.wait_trigger();
      disable fork;
      handle_reset();
    end // forever
  endtask : run_phase

  task run_cosim_rvfi();
    ibex_rvfi_seq_item rvfi_instr;

    forever begin
      rvfi_port.get(rvfi_instr);

      if (rvfi_instr.irq_only) begin
        // RVFI item is only notifying about new interrupts, not a retired instruction, so provide
        // cosim with interrupt information and loop back to await the next item.
        riscv_cosim_set_nmi(cosim_handle, rvfi_instr.nmi);
        riscv_cosim_set_nmi_int(cosim_handle, rvfi_instr.nmi_int, get_nmi_int_mtval());
        riscv_cosim_set_mip(cosim_handle, rvfi_instr.pre_mip, rvfi_instr.pre_mip);

        continue;
      end

      if (iside_error_queue.size() > 0) begin
        // Remove entries from iside_error_queue where the instruction never reaches the RVFI
        // interface because it was flushed.
        while (iside_error_queue.size() > 0 && iside_error_queue[0].order < rvfi_instr.order) begin
          iside_error_queue.pop_front();
        end

        // Check if the top of the iside_error_queue relates to the current RVFI instruction. If so
        // notify the cosim environment of an instruction error.
        if (iside_error_queue.size() !=0 && iside_error_queue[0].order == rvfi_instr.order) begin
          riscv_cosim_set_iside_error(cosim_handle, iside_error_queue[0].addr);
          iside_error_queue.pop_front();
        end
      end

      // Note these must be called in this order to ensure debug vs nmi vs normal interrupt are
      // handled with the correct priority when they occur together.
      riscv_cosim_set_debug_req(cosim_handle, rvfi_instr.debug_req);
      riscv_cosim_set_nmi(cosim_handle, rvfi_instr.nmi);
      riscv_cosim_set_nmi_int(cosim_handle, rvfi_instr.nmi_int, get_nmi_int_mtval());
      riscv_cosim_set_mip(cosim_handle, rvfi_instr.pre_mip, rvfi_instr.post_mip);
      riscv_cosim_set_mcycle(cosim_handle, rvfi_instr.mcycle);

      // Set performance counters through a pseudo-backdoor write
      for (int i=0; i < 10; i++) begin
        riscv_cosim_set_csr(cosim_handle,
                            ibex_pkg::CSR_MHPMCOUNTER3 + i, rvfi_instr.mhpmcounters[i]);
        riscv_cosim_set_csr(cosim_handle,
                            ibex_pkg::CSR_MHPMCOUNTER3H + i, rvfi_instr.mhpmcountersh[i]);
      end

      // Must be before the step: the ISS checks mcounteren when it executes the
      // counter read, so pushing it afterwards would be a cycle too late.
      riscv_cosim_set_csr(cosim_handle, ibex_pkg::CSR_MCOUNTEREN, get_dut_mcounteren());

      riscv_cosim_set_ic_scr_key_valid(cosim_handle, rvfi_instr.ic_scr_key_valid);

      // more_ops: a non-final operation of an expanded (Zcmp) instruction. The
      // cosim defers stepping the ISS until the final one, so that every memory
      // access the instruction performs has been observed and queued before the
      // ISS issues its own -- see deferred_dut_writes in spike_cosim.h.
      if (!riscv_cosim_step(cosim_handle, rvfi_instr.rd_addr, rvfi_instr.rd_wdata, rvfi_instr.pc,
                            rvfi_instr.intr, rvfi_instr.trap, rvfi_instr.rf_wr_suppress,
                            rvfi_instr.expanded_insn_valid &&
                            !rvfi_instr.expanded_insn_last)) begin
        // cosim instruction step doesn't match rvfi captured instruction, report a fatal error
        // with the details
        if (cfg.relax_cosim_check) begin
          `uvm_info(`gfn, get_cosim_error_str(), UVM_LOW)
        end else begin
          `uvm_fatal(`gfn, get_cosim_error_str())
        end
      end

      // mtval / exception-cause check (#824).
      //
      // riscv_cosim_step() compares only rd_addr, rd_wdata, pc and trap, so
      // mtval was never checked at all -- and in CHERIoT mode mtval is where the
      // exception detail lives: capcause in [4:0], cap_idx in [10:5]
      // (ibex_cheriot_pkg.sv, cheriot_violation_cause()).
      //
      // Deliberately compared on the instruction AFTER a trap rather than on the
      // trapping item itself. Both sides settle by then: Spike writes mtval
      // inside the step for the trapping instruction, and the DUT's mtval_q is
      // written on the trap cycle, long before the next instruction retires.
      // Sampling on the trapping item would race both.
      check_mtval_after_trap(rvfi_instr);

      // Must match the gate on cheriot_sail_cosim_init() above: stepping an
      // oracle that was never initialised, or comparing a CHERIoT model
      // against a DUT running plain RV32, both produce spurious mismatches.
      // Trap instructions are also stepped so Sail can produce the correct
      // zmtval/zmcause for exception-cause checks; the rd_wdata comparison is
      // skipped for them (RTL's rd_wdata is undefined when trap=1).
      if (cfg.secure_ibex && cheriot_seq_en) begin
        // On a trap the RTL doesn't commit a capability write, so clear cheri_we.
        automatic bit cheri_we  = (rvfi_instr.rd_addr != 5'h0) && !rvfi_instr.rf_wr_suppress
                                  && !rvfi_instr.trap;
        automatic bit cheri_tag = rvfi_instr.rd_wcap[32];
        if (cheriot_sail_cosim_step(rvfi_instr.insn, rvfi_instr.pc,
                                    cheri_we, rvfi_instr.rd_addr, cheri_tag,
                                    rvfi_instr.rd_wdata, rvfi_instr.trap) != 0) begin
          // UVM_ERROR (not FATAL) so simulation continues to collect all mismatches
          `uvm_error(`gfn, get_cheriot_sail_error_str())
        end
      end
    end
  endtask: run_cosim_rvfi

  task run_cosim_dmem();
    ibex_mem_intf_seq_item mem_op;

    forever begin
      dmem_port.get(mem_op);
      // Notify the cosim of all dside accesses emitted by the RTL
      riscv_cosim_notify_dside_access(cosim_handle, mem_op.read_write == WRITE, mem_op.addr,
        mem_op.data, mem_op.be, mem_op.error, mem_op.misaligned_first, mem_op.misaligned_second,
        mem_op.misaligned_first_saw_error, mem_op.m_mode_access);
    end
  endtask: run_cosim_dmem

  task run_cosim_imem();
    ibex_mem_intf_seq_item mem_op;

    forever begin
      // Take stream of transaction from imem monitor. Where an imem access has an error record it
      // in failed_iside_accesses. If an access has succeeded remove it from failed_imem_accesses if
      // it's there.
      // Note all transactions are 32-bit aligned.
      imem_port.get(mem_op);
      if (mem_op.error) begin
        failed_iside_accesses[mem_op.addr] = 1'b1;
      end else begin
        if (failed_iside_accesses.exists(mem_op.addr)) begin
          failed_iside_accesses.delete(mem_op.addr);
        end
      end
    end
  endtask: run_cosim_imem

  task run_cosim_ifetch();
    ibex_ifetch_seq_item ifetch;
    bit [31:0] aligned_fetch_addr;
    bit [31:0] aligned_fetch_addr_next;

    forever begin
      ifetch_port.get(ifetch);
      aligned_fetch_addr = {ifetch.fetch_addr[31:2], 2'b0};
      aligned_fetch_addr_next = aligned_fetch_addr + 32'd4;

      if (ifetch.fetch_err) begin
        // Instruction error observed in fetch stage
        bit [31:0] failing_addr;

        // Determine which address failed.
        if (ifetch.fetch_err_plus2) begin
          // Instruction crosses a 32-bit boundary and second half failed
          failing_addr = aligned_fetch_addr_next;
        end else begin
          failing_addr = aligned_fetch_addr;
        end

        failed_iside_accesses[failing_addr] = 1'b1;
      end else begin
        if (ifetch.fetch_addr[1:0] != 0 && ifetch.fetch_rdata[1:0] == 2'b11) begin
          // Instruction crosses 32-bit boundary, so remove any failed accesses on the other side of
          // the 32-bit boundary.
          if (failed_iside_accesses.exists(aligned_fetch_addr_next)) begin
            failed_iside_accesses.delete(aligned_fetch_addr_next);
          end
        end

        if (failed_iside_accesses.exists(aligned_fetch_addr)) begin
          failed_iside_accesses.delete(aligned_fetch_addr);
        end
      end
    end
  endtask: run_cosim_ifetch

  task run_cosim_ifetch_pmp();
    ibex_ifetch_pmp_seq_item ifetch_pmp;

    // Keep track of which addresses have seen PMP failures.
    forever begin
      ifetch_pmp_port.get(ifetch_pmp);

      if (ifetch_pmp.fetch_pmp_err) begin
        iside_pmp_failure[ifetch_pmp.fetch_addr] = 1'b1;
      end else begin
        if (iside_pmp_failure.exists(ifetch_pmp.fetch_addr)) begin
          iside_pmp_failure.delete(ifetch_pmp.fetch_addr);
        end
      end
    end
  endtask

  task run_cosim_imem_errors();
    bit [63:0] latest_order = 64'hffffffff_ffffffff;
    bit [31:0] aligned_addr;
    bit [31:0] aligned_next_addr;
    forever begin
      // Wait for new instruction to appear in ID stage
      wait (instr_vif.instr_cb.rvfi_id_done &&
            latest_order != instr_vif.instr_cb.rvfi_order_id);

      latest_order = instr_vif.instr_cb.rvfi_order_id;

      if (dut_vif.dut_cb.wb_exception)
        // If an exception in writeback occurs the instruction in ID will be flushed and hence not
        // produce an iside error so skip the rest of the loop. A writeback exception may occur
        // after this cycle before the instruction in ID moves out of the ID stage. The
        // `run_cosim_prune_imem_errors` task deals with this case.
        continue;

      // Determine if the instruction comes from an address that has seen an error that wasn't a PMP
      // error (the icache records both PMP errors and fetch errors with the same error bits). If a
      // fetch error was seen add the instruction order ID and address to iside_error_queue.
      aligned_addr      = instr_vif.instr_cb.pc_id & 32'hfffffffc;
      aligned_next_addr = aligned_addr + 32'd4;

      if (failed_iside_accesses.exists(aligned_addr) && !iside_pmp_failure.exists(aligned_addr))
      begin
        iside_error_queue.push_back('{order : instr_vif.instr_cb.rvfi_order_id,
                                      addr  : aligned_addr});
        check_inserted_iside_error_e.trigger();
      end else if (!instr_vif.instr_cb.is_compressed_id &&
                   (instr_vif.instr_cb.pc_id & 32'h3) != 0 &&
                   failed_iside_accesses.exists(aligned_next_addr) &&
                   !iside_pmp_failure.exists(aligned_next_addr))
      begin
        // Where an instruction crosses a 32-bit boundary, check if an error was seen on the other
        // side of the boundary
        iside_error_queue.push_back('{order : instr_vif.instr_cb.rvfi_order_id,
                                      addr  : aligned_next_addr});
        check_inserted_iside_error_e.trigger();
      end

    end
  endtask: run_cosim_imem_errors;

  task run_cosim_prune_imem_errors();
    // Errors are added to the iside error queue the first cycle the instruction that sees the error
    // is in the ID stage. Cycles following this the writeback stage may cause an exception flushing
    // the ID stage so the iside error never occurs. When this happens we need to pop the new iside
    // error off the queue.
    forever begin
      // Wait until the `run_cosim_imem_errors` task notifies us it's added a error to the queue
      check_inserted_iside_error_e.wait_ptrigger();
      // Wait for the next clock
      @(instr_vif.instr_cb);
      // Wait for a new instruction or a writeback exception. When a new instruction has entered the
      // ID stage and we haven't seen a writeback exception we know the instruction associated with the
      // error just added to the queue isn't getting flushed.
      wait (instr_vif.instr_cb.rvfi_id_done || dut_vif.dut_cb.wb_exception);

      if (!instr_vif.instr_cb.rvfi_id_done && dut_vif.dut_cb.wb_exception) begin
        // If we hit a writeback exception without seeing a new instruction then the newly added
        // error relates to an instruction just flushed from the ID stage so pop it from the
        // queue.
        iside_error_queue.pop_back();
      end
    end
  endtask: run_cosim_prune_imem_errors

  function string get_cosim_error_str();
      string error = "Cosim mismatch ";
      for (int i = 0; i < riscv_cosim_get_num_errors(cosim_handle); ++i) begin
        error = {error, riscv_cosim_get_error(cosim_handle, i), "\n"};
      end
      riscv_cosim_clear_errors(cosim_handle);

      return error;
  endfunction : get_cosim_error_str

  function string get_cheriot_sail_error_str();
    string error = "CHERIoT-Sail mismatch ";
    for (int i = 0; i < cheriot_sail_cosim_get_num_errors(); ++i) begin
      error = {error, cheriot_sail_cosim_get_error(i), "\n"};
    end
    cheriot_sail_cosim_clear_errors();
    return error;
  endfunction : get_cheriot_sail_error_str

  function void final_phase(uvm_phase phase);
    super.final_phase(phase);

    `uvm_info(`gfn, $sformatf("Co-simulation matched %d instructions",
                                riscv_cosim_get_insn_cnt(cosim_handle)), UVM_LOW)

    cleanup_cosim();
  endfunction : final_phase

  // If the UVM_EXIT action is triggered (such as by reaching max_quit_count), this callback is run.
  // This ensures proper cleanup, such as committing the logfile to disk.
  function void pre_abort();
    cleanup_cosim();
  endfunction

  task handle_reset();
    init_cosim();
  endtask
endclass : ibex_cosim_scoreboard
