// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Compares every retired instruction of a DII run against a Sail reference model stepped with the
// same instruction word. The base class holds the flow; a flavour subclass supplies the model and
// is selected with a factory override, e.g.
//   +uvm_set_type_override=ibex_dii_scoreboard,ibex_dii_cheriot_sail_scoreboard
//
// The comparison itself (trap, next PC, integer and capability destination, memory access, and
// every exclusion) lives in ibex_sail_rvfi_cmp, shared with the UVM cosim's RISC-V Sail checker.
//
// Plusargs (to prove the checks can fail):
//   +dii_sb_corrupt=<n>             corrupt the RTL side of the n-th retired instruction (1-based)
//                                   that exercises the chosen field
//   +dii_sb_corrupt_field=<field>   rd | pc | trap | mem (default rd)
//   +dii_sb_max_errors=<n>          print only the first n mismatches (default 100); all are counted
class ibex_dii_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(ibex_dii_scoreboard)

  uvm_analysis_imp #(ibex_rvfi_seq_item, ibex_dii_scoreboard) rvfi_imp;

  typedef ibex_sail_rvfi_cmp::model_result_t model_result_t;

  protected virtual clk_rst_if clk_vif;
  protected ibex_sail_rvfi_cmp cmp;

  int unsigned num_steps;
  int unsigned num_mismatches;
  // Only the first max_errors mismatches are printed; one divergence usually cascades.
  int unsigned max_errors = 100;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    rvfi_imp = new("rvfi_imp", this);
    cmp      = ibex_sail_rvfi_cmp::type_id::create("cmp");
  endfunction

  // ---- Flavour hooks ------------------------------------------------------------------------

  virtual function bit is_cheriot();
    `uvm_fatal(`gfn, {"No DII scoreboard selected: override ibex_dii_scoreboard with ",
                      "ibex_dii_riscv_sail_scoreboard or ibex_dii_cheriot_sail_scoreboard"})
    return 1'b0;
  endfunction

  // (Re)initialise the model to the core's reset state, with empty memory.
  virtual function void model_init();
  endfunction

  // Step the model over one retired instruction. Flavour-specific checks append to errs.
  virtual function void model_step(ibex_rvfi_seq_item item, output model_result_t res,
                                   ref string errs[$]);
    res = '{default: '0};
  endfunction

  // ---- Common ---------------------------------------------------------------------------------

  virtual function void build_phase(uvm_phase phase);
    string cfg_err;
    super.build_phase(phase);
    void'(is_cheriot());
    if (!uvm_config_db#(virtual clk_rst_if)::get(this, "", "clk_if", clk_vif)) begin
      `uvm_fatal(`gfn, "clk_if must be provided")
    end
    cfg_err = cmp.configure_corruption("dii_sb");
    if (cfg_err != "") `uvm_fatal(`gfn, cfg_err)
    void'($value$plusargs("dii_sb_max_errors=%d", max_errors));
  endfunction

  virtual task run_phase(uvm_phase phase);
    model_init();
    // Every DII test ends in a core reset; the model must start the next one from reset too.
    // Re-initialise on reset release, not assertion: the monitor delivers each retirement a
    // cycle late (clocking block), and the driver asserts reset on exactly that cycle, so on
    // negedge the test's last instruction has not been stepped yet.
    clk_vif.wait_for_reset();
    forever begin
      @(posedge clk_vif.rst_n);
      model_init();
      cmp.reset();
    end
  endtask

  virtual function void write(ibex_rvfi_seq_item item);
    ibex_rvfi_seq_item rtl;
    model_result_t     model;
    string             errs[$];
    string             info;

    if (item.irq_only) return;

    rtl = cmp.maybe_corrupt(item, info);
    if (info != "") `uvm_info(`gfn, {"+dii_sb_corrupt: ", info}, UVM_NONE)
    cmp.check_trap_target(rtl, errs);
    model_step(rtl, model, errs);
    cmp.compare(rtl, model, errs);
    num_steps++;

    foreach (errs[i]) begin
      num_mismatches++;
      if (num_mismatches <= max_errors) begin
        `uvm_error(`gfn, $sformatf("pc=0x%08x insn=0x%08x: %s", rtl.pc, rtl.insn, errs[i]))
        if (num_mismatches == max_errors) begin
          `uvm_info(`gfn, $sformatf("%0d mismatches: further ones are counted, not printed",
                                    max_errors), UVM_NONE)
        end
      end
    end
  endfunction

  virtual function void check_phase(uvm_phase phase);
    string never_applied;
    super.check_phase(phase);
    if (num_steps == 0) begin
      `uvm_error(`gfn, "No instructions were compared: the run checked nothing")
    end
    never_applied = cmp.corruption_never_applied("dii_sb");
    if (never_applied != "") `uvm_error(`gfn, never_applied)
  endfunction

  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(`gfn, $sformatf("%s: %0d instructions compared, %0d mismatches", get_type_name(),
                              num_steps, num_mismatches), UVM_NONE)
  endfunction
endclass : ibex_dii_scoreboard

class ibex_dii_cheriot_sail_scoreboard extends ibex_dii_scoreboard;
  `uvm_component_utils(ibex_dii_cheriot_sail_scoreboard)
  `uvm_component_new

  // Matches BOOT_ADDR in core_ibex_testrig_tb_top.sv.
  localparam bit [31:0] BootAddr = 32'h8000_0000;

  virtual function bit is_cheriot();
    return 1'b1;
  endfunction

  virtual function void model_init();
    // Re-initialising also frees the model's memory (model_fini -> cleanup_rts -> kill_mem).
    cheriot_sail_cosim_init(BootAddr);
  endfunction

  virtual function void model_step(ibex_rvfi_seq_item item, output model_result_t res,
                                   ref string errs[$]);
    // The model's counters do not advance on their own; later arithmetic on a mcycle read would
    // otherwise diverge.
    cheriot_sail_cosim_set_mcycle(item.mcycle);
    cheriot_sail_cosim_clear_errors();
    // compare() checks the destination for both flavours, so step()'s own checks are switched
    // off: cheri_rf_we=0 skips its capability check and rtl_trap=1 its rd_wdata check. The model
    // is stepped identically either way; any error left is a failure to step at all.
    void'(cheriot_sail_cosim_step(item.insn, item.pc, 1'b0, item.rd_addr, item.rd_wcap[32],
                                  item.rd_wdata, 1'b1));
    for (int i = 0; i < cheriot_sail_cosim_get_num_errors(); i++) begin
      errs.push_back(cheriot_sail_cosim_get_error(i));
    end

    res.trap      = cheriot_sail_cosim_get_trap();
    res.pc_wdata  = cheriot_sail_cosim_get_pc_wdata();
    // DPI getters return 32/64-bit words; the model's register numbers are 5-bit, masks 8-bit.
    res.rd_addr   = 5'(cheriot_sail_cosim_get_rd_addr());
    res.rd_wdata  = cheriot_sail_cosim_get_rd_wdata();
    res.cd_addr   = 5'(cheriot_sail_cosim_get_cd_addr());
    res.cd_wdata  = cheriot_sail_cosim_get_cd_wdata();
    res.cd_wtag   = cheriot_sail_cosim_get_cd_wtag();
    res.mem_addr  = cheriot_sail_cosim_get_mem_addr();
    res.mem_rmask = 8'(cheriot_sail_cosim_get_mem_rmask());
    res.mem_wmask = 8'(cheriot_sail_cosim_get_mem_wmask());
    res.mem_rdata = cheriot_sail_cosim_get_mem_rdata();
    res.mem_wdata = cheriot_sail_cosim_get_mem_wdata();
  endfunction
endclass : ibex_dii_cheriot_sail_scoreboard

class ibex_dii_riscv_sail_scoreboard extends ibex_dii_scoreboard;
  `uvm_component_utils(ibex_dii_riscv_sail_scoreboard)
  `uvm_component_new

  // Matches BOOT_ADDR in core_ibex_testrig_tb_top.sv.
  localparam bit [31:0] BootAddr = 32'h8000_0000;

  virtual function bit is_cheriot();
    return 1'b0;
  endfunction

  // Must match DataMemBase / DataMemSize in core_ibex_testrig_tb_top.sv (the bridge's defaults).
  localparam bit [31:0] RamBase = 32'h8000_0000;
  localparam bit [31:0] RamSize = 32'h0080_0000;

  // The core's PMP configuration, from core_ibex_testrig_tb_top.sv (ibex_configs.yaml). Without
  // it the model has no PMP entries (the bridge's default) while the core has PMPNumRegions of
  // them: pmpcfg*/pmpaddr* accesses would then be illegal on the model and legal on the core.
  int pmp_num_regions = 0;
  int pmp_granularity = 0;

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(int)::get(this, "", "pmp_num_regions", pmp_num_regions) ||
        !uvm_config_db#(int)::get(this, "", "pmp_granularity", pmp_granularity)) begin
      `uvm_fatal(`gfn, "pmp_num_regions / pmp_granularity must be set by the testbench top")
    end
  endfunction

  virtual function void model_init();
    // Applied by the init that follows; repeated each time as init re-reads it.
    riscv_sail_cosim_configure(RamBase, RamSize, pmp_num_regions, pmp_granularity);
    riscv_sail_cosim_init(BootAddr);
  endfunction

  virtual function void model_step(ibex_rvfi_seq_item item, output model_result_t res,
                                   ref string errs[$]);
    res = '{default: '0};
    riscv_sail_cosim_set_mcycle(item.mcycle);
    riscv_sail_cosim_clear_errors();
    void'(riscv_sail_cosim_step(item.insn, item.pc));
    for (int i = 0; i < riscv_sail_cosim_get_num_errors(); i++) begin
      errs.push_back(riscv_sail_cosim_get_error(i));
    end

    res.trap      = riscv_sail_cosim_get_trap();
    res.pc_wdata  = riscv_sail_cosim_get_pc_wdata();
    res.rd_addr   = 5'(riscv_sail_cosim_get_rd_addr());
    res.rd_wdata  = riscv_sail_cosim_get_rd_wdata();
    res.mem_addr  = riscv_sail_cosim_get_mem_addr();
    res.mem_rmask = 8'(riscv_sail_cosim_get_mem_rmask());
    res.mem_wmask = 8'(riscv_sail_cosim_get_mem_wmask());
    res.mem_rdata = riscv_sail_cosim_get_mem_rdata();
    res.mem_wdata = riscv_sail_cosim_get_mem_wdata();
  endfunction
endclass : ibex_dii_riscv_sail_scoreboard
