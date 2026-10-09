// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// CSR test class
class core_ibex_csr_test extends core_ibex_base_test;

  `uvm_component_utils(core_ibex_csr_test)
  `uvm_component_new

endclass

// Test that corrupts the PC and checks that an appropriate alert occurs.
class core_ibex_pc_intg_test extends core_ibex_base_test;

  `uvm_component_utils(core_ibex_pc_intg_test)
  `uvm_component_new

  uvm_report_server rs;

  virtual task send_stimulus();
    string core_path, if_stage_path, glitch_path, core_busy_path, instr_seq_path,
           alert_major_internal_path;
    int unsigned bit_idx;
    logic [31:0] orig_pc, glitch_mask, glitched_pc;
    logic core_busy, exp_alert, alert_major_internal;

    vseq.start(env.vseqr);
    clk_vif.wait_n_clks($urandom_range(2000));

    // Set path to the core and the PC to be glitched.
    core_path = "core_ibex_tb_top.dut.u_ibex_top.u_ibex_core";
    if_stage_path = $sformatf("%s.if_stage_i", core_path);
    glitch_path = $sformatf("%s.pc_if_o", if_stage_path);

    // Ensure we are still running (sample busy signal).  If not, skip the test without injecting an
    // error.
    core_busy_path = $sformatf("%s.core_busy_o", core_path);
    `DV_CHECK_FATAL(uvm_hdl_read(core_busy_path, core_busy))
    `DV_CHECK_FATAL(!$isunknown(core_busy))
    if (core_busy != 1'b1) begin
      `uvm_info(`gfn, "Skipping test because core is not busy when PC should be glitched", UVM_LOW)
      return;
    end

    // Sample PC value prior to glitching.
    `DV_CHECK_FATAL(uvm_hdl_read(glitch_path, orig_pc))

    // Pick one bit in the PC and glitch it.
    bit_idx = $urandom_range(31);
    glitch_mask = 1 << bit_idx;
    glitched_pc = orig_pc ^ glitch_mask;

    // Disable TB assertion for alerts.
    `DV_ASSERT_CTRL_REQ("tb_no_alerts_triggered", 1'b0)

    // Force the glitched value onto the PC.
    `DV_CHECK_FATAL(uvm_hdl_force(glitch_path, glitched_pc));
    `uvm_info(`gfn, $sformatf("Forcing %s to value 'h%0x", glitch_path, glitched_pc), UVM_LOW)

    // The check will only fire if the current instruction is a sequential one.  Depending on that
    // we expect an alert or we don't.
    instr_seq_path = $sformatf("%s.g_secure_pc.prev_instr_seq_d", if_stage_path);
    `DV_CHECK_FATAL(uvm_hdl_read(instr_seq_path, exp_alert))
    `DV_CHECK_FATAL(!$isunknown(exp_alert))

    // Leave glitch applied for one clock cycle.
    clk_vif.wait_n_clks(1);

    // Check that the alert matches our expectation.
    alert_major_internal_path = $sformatf("%s.alert_major_internal_o", core_path);
    `DV_CHECK_FATAL(uvm_hdl_read(alert_major_internal_path, alert_major_internal))
    `DV_CHECK_EQ_FATAL(alert_major_internal, exp_alert, "Major alert did not match expectation!")

    // Release glitch.
    `DV_CHECK_FATAL(uvm_hdl_release(glitch_path))
    `uvm_info(`gfn, $sformatf("Releasing force of %s", glitch_path), UVM_LOW)

    // Re-enable TB assertion for alerts.
    `DV_ASSERT_CTRL_REQ("tb_no_alerts_triggered", 1'b1)

    // Complete the test at this point because cosimulation does not know about the glitched PC and
    // will mismatch.
    rs = uvm_report_server::get_server();
    rs.report_summarize();
    $finish();
  endtask

endclass

// Test that corrupts data read from the register file and checks that an appropriate alert occurs.
class core_ibex_rf_intg_test extends core_ibex_base_test;

  `uvm_component_utils(core_ibex_rf_intg_test)
  `uvm_component_new

  uvm_report_server rs;

  int unsigned reg_file_data_width;

  string ibex_top_path = "core_ibex_tb_top.dut.u_ibex_top";

  function automatic uvm_hdl_data_t read_data(string subpath);
    uvm_hdl_data_t result;
    string path = $sformatf("%s.%s", ibex_top_path, subpath);
    `DV_CHECK_FATAL(uvm_hdl_read(path, result))
    return result;
  endfunction

  function automatic int unsigned read_uint(string subpath);
    return read_data(subpath);
  endfunction

  function automatic void force_data(string subpath, uvm_hdl_data_t value);
    string path = $sformatf("%s.%s", ibex_top_path, subpath);
    `DV_CHECK_FATAL(uvm_hdl_force(path, value))
  endfunction

  function automatic void release_force(string subpath);
    string path = $sformatf("%s.%s", ibex_top_path, subpath);
    `DV_CHECK_FATAL(uvm_hdl_release(path))
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // Obtain value of parameter defining data width of register file.
    reg_file_data_width = read_uint("RegFileDataWidth");
  endfunction

  virtual task send_stimulus();
    int    rnd_delay;
    bit    port_idx;
    string port_name;
    int unsigned lockstep_delay;

    vseq.start(env.vseqr);

    // Pick port to corrupt.
    port_idx = $urandom_range(1);
    port_name = port_idx ? "rf_rdata_b" : "rf_rdata_a";

    lockstep_delay = read_data("gen_lockstep.u_ibex_lockstep.LockstepOffset");

    `DV_CHECK_STD_RANDOMIZE_WITH_FATAL(rnd_delay, rnd_delay > 1000; rnd_delay < 10_000;)
    clk_vif.wait_n_clks(rnd_delay);

    forever begin
      logic rf_ren, rf_rd_wb_match, rf_write_wb;
      int unsigned bit_idx;
      uvm_hdl_data_t data, mask;
      logic exp_alert, alert_major_internal;

      clk_vif.wait_n_clks(1);

      rf_write_wb = dut_vif.signal_probe_rf_write_wb(dv_utils_pkg::SignalProbeSample);

      // Check if port is being read.
      if (port_idx) begin
        rf_ren = dut_vif.signal_probe_rf_ren_b(dv_utils_pkg::SignalProbeSample);
        rf_rd_wb_match = dut_vif.signal_probe_rf_rd_b_wb_match(dv_utils_pkg::SignalProbeSample);
      end else begin
        rf_ren = dut_vif.signal_probe_rf_ren_a(dv_utils_pkg::SignalProbeSample);
        rf_rd_wb_match = dut_vif.signal_probe_rf_rd_a_wb_match(dv_utils_pkg::SignalProbeSample);
      end

      // Only corrupt port if it is read.
      if (!(rf_ren == 1'b1 && (rf_rd_wb_match == 1'b0 || rf_write_wb == 1'b0))) continue;

      data = read_data(port_name);
      `uvm_info(`gfn, $sformatf("Corrupting %s; original value: 'h%0x", port_name, data), UVM_LOW)

      // Corrupt one bit of the data.
      bit_idx = $urandom_range(reg_file_data_width - 1);
      mask = 1 << bit_idx;
      data ^= mask;

      // Disable TB assertion for alerts.
      `DV_ASSERT_CTRL_REQ("tb_no_alerts_triggered", 1'b0)

      // Force the corrupt value.
      `uvm_info(`gfn, $sformatf("Forcing corrupt value: 'h%0x", data), UVM_LOW)
      force_data(port_name, data);

      // Determine whether an alert is expected: if the instruction is valid.
      exp_alert = read_data("u_ibex_core.instr_valid_id");

      // Wait LockstepOffset cycles before reading the error.
      clk_vif.wait_n_clks(lockstep_delay);

      // Check if the major alert matches our expectation.
      alert_major_internal = read_data("alert_major_internal_o");
      `DV_CHECK_EQ_FATAL(alert_major_internal, exp_alert)

      // Release force after one clock cycle.
      clk_vif.wait_n_clks(1);
      release_force(port_name);

      // Complete test if alert has been correctly triggered.
      if (exp_alert) break;
    end

    // Stop test at this point because cosim will mismatch.
    rs = uvm_report_server::get_server();
    rs.report_summarize();
    $finish();
  endtask

endclass

class core_ibex_rf_addr_intg_test extends core_ibex_base_test;
  `uvm_component_utils(core_ibex_rf_addr_intg_test)
  `uvm_component_new

  uvm_report_server rs;

  virtual task send_stimulus();
    int          rnd_delay;
    int unsigned bit_idx;
    logic [31:0] orig_val, glitch_val;
    logic [1:0]  ecc_err;
    string       glitch_path, ecc_alert_path, lockstep_delay_path;
    string       trgt_core_path[];
    string       ctrl_signals[];
    string       err_signals[];
    int unsigned ctrl_signal_idx;
    int unsigned trgt_core_idx;
    string       top_path = "core_ibex_tb_top.dut.u_ibex_top";
    // Main core signals.
    string       ibex_rf_path = {top_path, ".gen_regfile_ff.register_file_i"};
    // Shadow core signals.
    string       lockstep_path = {top_path, ".gen_lockstep.u_ibex_lockstep"};
    string       shdw_ecc_path =  {lockstep_path, ".u_shadow_core.gen_regfile_ecc"};
    string       shdw_rf_path = {lockstep_path, ".gen_shadow_regfile_ff.register_file_shadow_i"};
    // The lockstep delay.
    int unsigned lockstep_delay;

    trgt_core_path = {
      ibex_rf_path,
      shdw_rf_path
    };

    ctrl_signals = {
      "raddr_a_i",
      "raddr_b_i"
    };

    err_signals = {
      "rf_ecc_err_a",
      "rf_ecc_err_b"
    };

    `DV_CHECK_STD_RANDOMIZE_WITH_FATAL(trgt_core_idx, trgt_core_idx < trgt_core_path.size();)
    `DV_CHECK_STD_RANDOMIZE_WITH_FATAL(ctrl_signal_idx, ctrl_signal_idx < ctrl_signals.size();)
    `DV_CHECK_STD_RANDOMIZE_WITH_FATAL(rnd_delay, rnd_delay > 1000; rnd_delay < 10_000;)

    glitch_path = $sformatf("%s.%s", trgt_core_path[trgt_core_idx], ctrl_signals[ctrl_signal_idx]);

    // Read the lockstep delay.
    lockstep_delay_path = $sformatf("%s.%s", lockstep_path, "LockstepOffset");
    `DV_CHECK_FATAL(uvm_hdl_read(lockstep_delay_path, lockstep_delay));

    vseq.start(env.vseqr);
    clk_vif.wait_n_clks(rnd_delay);

    // Disable TB assertion for alerts.
    `DV_ASSERT_CTRL_REQ("tb_no_alerts_triggered", 1'b0)

    ecc_alert_path = $sformatf("%s.%s", shdw_ecc_path, err_signals[ctrl_signal_idx]);

    // Early in the program most registers still hold their reset value 0, so every alias
    // can be undetectable (seed 23332: x11/x19/x25/x26/x27/x31 all unwritten). Retry later
    // rather than fail; a run that never finds a detectable glitch still fails below.
    ecc_err = 0;
    for (int attempt = 0; attempt < 10 && !(|ecc_err); attempt++) begin
      if (attempt > 0) clk_vif.wait_n_clks(500);

      `uvm_info(`gfn, $sformatf("Reading value of %s", glitch_path), UVM_LOW)
      `DV_CHECK_FATAL(uvm_hdl_read(glitch_path, orig_val));
      `uvm_info(`gfn, $sformatf("Read %x", orig_val), UVM_LOW)

      // Try each address bit in turn rather than a single random one.
      //
      // Glitching the read address aliases one register's data onto another
      // register's check bits, which only produces a non-zero syndrome if the two
      // registers hold DIFFERENT data. Identical data gives identical check bits
      // and no error -- physically undetectable, not an RTL defect.
      //
      // The old code picked one random bit and asserted the error must fire, so a
      // pass was luck. Checked against the DUT trace for all five failing seeds in
      // the 2026-09-23 regression and the aliased pair held identical data every
      // time (21577 x21/x23 both 0, 244 x11/x9 both 0, 30629 x2/x18 both 0, 30639
      // x9/x25 both 0x80000000, 5642 x28/x30 both 0) -- 5 of 5. Note two of those
      // force the MAIN regfile, so this is not shadow-specific.
      //
      // Reading the register contents directly to pre-select a good pair would be
      // fragile here: the opentitan config is BaseIsaRV32IorCHERIoT, so x0-x15 and
      // x16-x31 live in two different generate branches of
      // ibex_register_file_ff.sv. Probing for a detectable glitch avoids depending
      // on either path, and asks the question we actually care about: is an
      // address glitch detectable at all right now?
      for (bit_idx = 0; bit_idx < 5; bit_idx++) begin
        glitch_val = orig_val;
        glitch_val[bit_idx] = ~glitch_val[bit_idx];

        `uvm_info(`gfn, $sformatf("Forcing %s to value 'h%0x (bit %0d)",
                                  glitch_path, glitch_val, bit_idx), UVM_LOW)
        `DV_CHECK_FATAL(uvm_hdl_force(glitch_path, glitch_val));

        // Determine how long it takes until the error gets noticed.
        if (trgt_core_idx == 0) begin
          // When we are faulting the main core RF, it takes lockstep_delay until we detect the
          // fault. This is because the shadow core ECC checker is responsible for detecting the
          // fault.
          clk_vif.wait_n_clks(lockstep_delay);
        end else begin
          // When we are faulting the shadow core RF, the fault is immediately detected.
          #1step;
        end

        `DV_CHECK_FATAL(uvm_hdl_read(ecc_alert_path, ecc_err))
        if (|ecc_err) break;

        // Undetectable with this bit -- the aliased register holds the same data.
        // Release and try the next one.
        `uvm_info(`gfn, $sformatf(
                  "No ECC error for bit %0d (aliased register holds identical data); trying next",
                  bit_idx), UVM_LOW)
        `DV_CHECK_FATAL(uvm_hdl_release(glitch_path))
      end
    end

    // Every address bit aliased onto a register holding identical data. That is
    // possible (e.g. most of the regfile still zero) but it means nothing was
    // exercised, so it must not be reported as a pass.
    `DV_CHECK_FATAL(|ecc_err,
                    "ECC alert did not fire for ANY address bit -- no detectable glitch available")

    // Release glitch.
    `DV_CHECK_FATAL(uvm_hdl_release(glitch_path))
    `uvm_info(`gfn, $sformatf("Releasing force of %s", glitch_path), UVM_LOW)

    // Re-enable TB assertion for alerts.
    `DV_ASSERT_CTRL_REQ("tb_no_alerts_triggered", 1'b1)

    // Complete the test at this point because cosimulation does not model faults so will cause
    // a mis-match and a test failure.
    rs = uvm_report_server::get_server();
    rs.report_summarize();
    $finish();
  endtask
endclass

class core_ibex_ram_intg_test extends core_ibex_base_test;
  `uvm_component_utils(core_ibex_ram_intg_test)
  `uvm_component_new

  uvm_report_server rs;

  virtual task send_stimulus();
    int          rnd_delay;
    int unsigned bit_idx;
    logic [31:0] orig_val, glitch_val;
    logic        alert_major_internal;
    string       glitch_path, alert_major_internal_path;
    string       glitch_paths[];
    string       signals[];
    string       scr_signals[];
    int unsigned scr_signals_idx;
    string       adv_signals[];
    int unsigned adv_signals_idx;
    string       ram_path;
    int unsigned bank_idx, ram_idx, glitch_idx;
    string       top_path = "core_ibex_tb_top.dut.u_ibex_top";
    string       bank_paths[];

    // Hard coded paths for the data and tag bank.
    bank_paths = {
      "gen_rams.gen_rams_inner[0].gen_scramble_rams.tag_bank",
      "gen_rams.gen_rams_inner[1].gen_scramble_rams.tag_bank",
      "gen_rams.gen_rams_inner[0].gen_scramble_rams.data_bank",
      "gen_rams.gen_rams_inner[1].gen_scramble_rams.data_bank"
    };

    // All banks contain a single prim_ram_1p_adv instance.
    ram_path = "u_prim_ram_1p_adv";

    scr_signals = {
      "write_en_d",
      "write_en_q",
      "addr_collision_d",
      "addr_collision_q",
      "write_scr_pending_d",
      "write_pending_q",
      "rvalid_q",
      "read_en_buf"
    };

    adv_signals = {
      "req_q",
      "req_d",
      "write_q",
      "write_d",
      "rvalid_q",
      "rvalid_d",
      "rvalid_sram_q",
      "rvalid_sram_d"
    };

    `DV_CHECK_STD_RANDOMIZE_WITH_FATAL(scr_signals_idx, scr_signals_idx < scr_signals.size();)
    `DV_CHECK_STD_RANDOMIZE_WITH_FATAL(adv_signals_idx, adv_signals_idx < adv_signals.size();)
    `DV_CHECK_STD_RANDOMIZE_WITH_FATAL(bank_idx, bank_idx < bank_paths.size();)
    `DV_CHECK_STD_RANDOMIZE_WITH_FATAL(rnd_delay, rnd_delay > 1000; rnd_delay < 10_000;)

    signals = {
      scr_signals[scr_signals_idx],
      adv_signals[adv_signals_idx]
    };

    // Assemble paths and do the final muxing of the target glitch path below.
    glitch_paths = {
      $sformatf("%s.%s.%s", top_path, bank_paths[bank_idx], signals[0]),
      $sformatf("%s.%s.%s.%s", top_path, bank_paths[bank_idx], ram_path, signals[1])
    };

    `DV_CHECK_STD_RANDOMIZE_WITH_FATAL(glitch_idx, glitch_idx < glitch_paths.size();)

    glitch_path = glitch_paths[glitch_idx];

    vseq.start(env.vseqr);
    clk_vif.wait_n_clks(rnd_delay);

    `uvm_info(`gfn, $sformatf("Reading value of %s", glitch_path), UVM_LOW)
    `DV_CHECK_FATAL(uvm_hdl_read(glitch_path, orig_val));
    `uvm_info(`gfn, $sformatf("Read %x", orig_val), UVM_LOW)

    `DV_CHECK_STD_RANDOMIZE_WITH_FATAL(bit_idx, bit_idx < 4;)

    glitch_val = orig_val;
    glitch_val ^= 1 << bit_idx;

    // Disable TB assertion for alerts.
    `DV_ASSERT_CTRL_REQ("tb_no_alerts_triggered", 1'b0)

    `uvm_info(`gfn, $sformatf("Forcing %s to value 'h%0x", glitch_path, glitch_val), UVM_LOW)
    `DV_CHECK_FATAL(uvm_hdl_force(glitch_path, glitch_val));

    // Leave glitch applied for one clock cycle.
    clk_vif.wait_n_clks(1);

    // Check that the alert matches our expectation.
    alert_major_internal_path = $sformatf("%s.alert_major_internal_o", top_path);
    `DV_CHECK_FATAL(uvm_hdl_read(alert_major_internal_path, alert_major_internal))
    `DV_CHECK_FATAL(alert_major_internal, "Major alert did not fire!")

    // Release glitch.
    `DV_CHECK_FATAL(uvm_hdl_release(glitch_path))
    `uvm_info(`gfn, $sformatf("Releasing force of %s", glitch_path), UVM_LOW)

    // Re-enable TB assertion for alerts.
    `DV_ASSERT_CTRL_REQ("tb_no_alerts_triggered", 1'b1)

    // Complete the test at this point because cosimulation does not model faults so will cause
    // a mis-match and a test failure.
    rs = uvm_report_server::get_server();
    rs.report_summarize();
    $finish();
  endtask
endclass

// Test that corrupts the instruction cache and checks that an appropriate alert occurs.
class core_ibex_icache_intg_test extends core_ibex_base_test;

  `uvm_component_utils(core_ibex_icache_intg_test)
  `uvm_component_new

  string ibex_top_path = "core_ibex_tb_top.dut.u_ibex_top";

  int unsigned num_ways, num_entries, tag_size, line_size;

  bit data_valid[][];
  bit tag_valid[][];

  function automatic int unsigned read_uint(string subpath);
    int unsigned result;
    string path = $sformatf("%s.%s", ibex_top_path, subpath);
    `DV_CHECK_FATAL(uvm_hdl_read(path, result))
    return result;
  endfunction

  function automatic uvm_hdl_data_t read_data(string subpath);
    uvm_hdl_data_t result;
    string path = $sformatf("%s.%s", ibex_top_path, subpath);
    `DV_CHECK_FATAL(uvm_hdl_read(path, result))
    return result;
  endfunction

  function automatic void force_data(string subpath, uvm_hdl_data_t value);
    string path = $sformatf("%s.%s", ibex_top_path, subpath);
    `DV_CHECK_FATAL(uvm_hdl_force(path, value))
  endfunction

  function automatic void release_force(string subpath);
    string path = $sformatf("%s.%s", ibex_top_path, subpath);
    `DV_CHECK_FATAL(uvm_hdl_release(path))
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // Obtain value of parameters defining shape of cache.
    num_ways = ibex_pkg::IC_NUM_WAYS;
    num_entries = 1 << ibex_pkg::IC_INDEX_W;
    tag_size = read_uint("TagSizeECC");
    line_size = read_uint("LineSizeECC");

    // Initialize memory entry status arrays.
    data_valid = new[num_ways];
    foreach (data_valid[i]) data_valid[i] = new[num_entries];
    tag_valid = new[num_ways];
    foreach (tag_valid[i]) tag_valid[i] = new[num_entries];
  endfunction

  function automatic void reset_icache_status();
    foreach (data_valid[i]) begin
      foreach (data_valid[i][j]) data_valid[i][j] = 1'b0;
    end
    foreach (tag_valid[i]) begin
      foreach (tag_valid[i][j]) tag_valid[i][j] = 1'b0;
    end
  endfunction

  // Track the status of the instruction cache (optimistically).  Whenever a write to a data or tag
  // entry is observed on the icache ports, that data or tag is set to valid in the test.  The test
  // then uses this information to corrupt only data or tags that are considered valid.  The tracked
  // status is a necessary but not sufficient condition for the actual validity of a data or tag.
  task automatic track_icache_status();
    reset_icache_status();
    forever begin
      uvm_hdl_data_t data_req, data_write, data_addr, tag_req, tag_write, tag_addr;
      clk_vif.wait_clks(1);
      if (!clk_vif.rst_n) begin
        reset_icache_status();
        continue;
      end
      // Set data entries to valid based on data writes.
      data_req = dut_vif.signal_probe_ic_data_req(dv_utils_pkg::SignalProbeSample);
      data_write = dut_vif.signal_probe_ic_data_write(dv_utils_pkg::SignalProbeSample);
      if (data_req != '0 && data_write == 1'b1) begin
        data_addr = dut_vif.signal_probe_ic_data_addr(dv_utils_pkg::SignalProbeSample);
        for (int unsigned i = 0; i < num_ways; i++) begin
          if (data_req[i]) data_valid[i][data_addr] = 1'b1;
        end
      end
      // Set tag entries to valid based on tag writes.
      tag_req = dut_vif.signal_probe_ic_tag_req(dv_utils_pkg::SignalProbeSample);
      tag_write = dut_vif.signal_probe_ic_tag_write(dv_utils_pkg::SignalProbeSample);
      if (tag_req != '0 && tag_write == 1'b1) begin
        tag_addr = dut_vif.signal_probe_ic_tag_addr(dv_utils_pkg::SignalProbeSample);
        for (int unsigned i = 0; i < num_ways; i++) begin
          if (tag_req[i]) tag_valid[i][tag_addr] = 1'b1;
        end
      end
    end
  endtask

  task automatic corrupt_used_icache_data();
    clk_vif.wait_n_clks(1);
    forever begin
      uvm_hdl_data_t data_req, data_write, data_addr;
      data_req = dut_vif.signal_probe_ic_data_req(dv_utils_pkg::SignalProbeSample);
      data_write = dut_vif.signal_probe_ic_data_write(dv_utils_pkg::SignalProbeSample);

      // Check if at least one data way is being read.
      if (data_req != '0 && data_write == 1'b0) begin
        int unsigned valid_and_used_ways[$];

        // Probe the data address.
        data_addr = dut_vif.signal_probe_ic_data_addr(dv_utils_pkg::SignalProbeSample);

        // Find out which data ways are valid and used in this clock cycle.
        for (int unsigned i = 0; i < num_ways; i++) begin
          if (data_req[i] && data_valid[i][data_addr]) valid_and_used_ways.push_back(i);
        end

        // The response comes in the next clock cycle, so wait one cycle.
        clk_vif.wait_n_clks(1);

        // Filter to ways that also have a tag hit in IC1.  hit_data_ecc_ic1 is
        // built by ORing ic_data_rdata_i[way] only for ways where tag_match_ic1[way]
        // is true (ibex_icache.sv:509-513).  Corrupting a way that does not have a
        // tag match does not affect hit_data_ecc_ic1 and produces no ECC error, so
        // such ways must be excluded from the candidate set.
        begin
          uvm_hdl_data_t tag_match;
          tag_match = read_data(
              "u_ibex_core.if_stage_i.gen_icache.icache_i.tag_match_ic1");
          valid_and_used_ways =
              valid_and_used_ways.find(way) with (tag_match[way] == 1'b1);
        end

        // Check if at least one data way is valid and used.
        if (valid_and_used_ways.size() > 0) begin
          int unsigned way_idx, bit_idx;
          uvm_hdl_data_t data_rdata, mask, lookup_valid, tag_hit, alert_minor;
          logic exp_alert_minor;

          `uvm_info(`gfn,
              $sformatf("The following I$ data ways are valid and used in this clock cycle: %p",
                        valid_and_used_ways), UVM_LOW)

          // Pick a way to corrupt.  valid_and_used_ways holds actual way indices;
          // index into it rather than using the list position directly as the way number.
          way_idx = valid_and_used_ways[$urandom_range(valid_and_used_ways.size() - 1)];
          `uvm_info(`gfn, $sformatf("Corrupting data way %0d", way_idx), UVM_LOW)

          // Probe response data.
          data_rdata = read_data($sformatf("ic_data_rdata[%0d]", way_idx));
          `uvm_info(`gfn, $sformatf("Original data_rdata of way %0d: 'h%0x", way_idx, data_rdata),
                    UVM_LOW)

          // Pick a bit to corrupt.
          bit_idx = $urandom_range(line_size - 1);
          mask = 1 << bit_idx;
          data_rdata ^= mask;
          `uvm_info(`gfn, $sformatf("Corrupting data_rdata: 'h%0x", data_rdata), UVM_LOW)

          // Disable TB assertion for alerts.
          `DV_ASSERT_CTRL_REQ("tb_no_alerts_triggered", 1'b0)

          // Decide if an error is expected: if the lookup is valid and the tag hit.
          // Read BEFORE the force: lookup_valid_ic1 and tag_hit_ic1 are registered
          // signals that are not affected by forcing ic_data_rdata, so reading
          // them here vs. after the force is equivalent.  Reading before avoids
          // any delta-cycle ambiguity when the force triggers combinational
          // re-evaluation.
          lookup_valid = read_data($sformatf(
              "u_ibex_core.if_stage_i.gen_icache.icache_i.lookup_valid_ic1"));
          tag_hit = read_data($sformatf(
              "u_ibex_core.if_stage_i.gen_icache.icache_i.tag_hit_ic1"));
          exp_alert_minor = lookup_valid & tag_hit;
          `DV_CHECK_FATAL(!$isunknown(exp_alert_minor))

          // Force the bit error into the data way.
          //
          // ibex_icache.sv:585 computes
          //   ecc_err_ic1 = lookup_valid_ic1 & (((|data_err_ic1) & tag_hit_ic1) | (|tag_err_ic1))
          // purely combinationally from ic_data_rdata_i, and the path to
          // alert_minor_o (ibex_core.sv:1337) adds no register -- so the main
          // core responds in the cycle of the force, not the next one.
          //
          // However, uvm_hdl_force schedules the update through the PLI, and a
          // read straight after it observes the pre-force value (0).  A #0 is
          // not enough in Xcelium either: it failed on 15/15 seeds.
          //
          // alert_minor_o is not used here because it ORs in the lockstep shadow
          // core's delayed response (ibex_top.sv:1373); the shadow core reacts
          // one cycle later (LockstepOffset = 1, ibex_lockstep.sv:282-298, 541),
          // so alert_minor_o at T+1 would reflect the shadow's alert against the
          // main core's T+1 state -- an unrelated comparison.
          force_data($sformatf("ic_data_rdata[%0d]", way_idx), data_rdata);

          // We are at a negedge (wait_n_clks), so a quarter period crosses no
          // clock edge: the registered lookup_valid/tag_hit read above still hold,
          // and the combinational ECC chain has fully settled on the forced data.
          #((clk_vif.clk_period_ps / 4) * 1ps);

          // Check the main core's own alert, not the OR with the lockstep shadow.
          alert_minor = read_data("u_ibex_core.icache_ecc_error");
          `DV_CHECK_EQ_FATAL(alert_minor, exp_alert_minor)

          // Hold the corrupt data to the next falling edge, across the rising one: released
          // within the quarter period, the error was never there at a clock edge, so the icache
          // never acted on it (treat as a miss, refetch) and uarch_cg.cp_icache_ecc_err, sampled
          // on the rising edge, was never hit. A lookup of this way in the next cycle also sees
          // the flipped bit, a single-bit error SECDED always detects, so it misses as well.
          clk_vif.wait_n_clks(1);

          // Release force. The lockstep shadow core sees the corrupt data LockstepOffset (1)
          // cycles later and raises its own minor alert then: wait for it to pass before
          // returning, which re-enables NoAlertsTriggered.
          release_force($sformatf("ic_data_rdata[%0d]", way_idx));
          clk_vif.wait_n_clks(4);
          return;
        end
      end else begin
        clk_vif.wait_n_clks(1);
      end
    end
  endtask

  task automatic corrupt_used_icache_tag();
    clk_vif.wait_n_clks(1);
    forever begin
      uvm_hdl_data_t tag_req, tag_write, tag_addr;
      tag_req = dut_vif.signal_probe_ic_tag_req(dv_utils_pkg::SignalProbeSample);
      tag_write = dut_vif.signal_probe_ic_tag_write(dv_utils_pkg::SignalProbeSample);

      // Check if at least one tag way is being read.
      if (tag_req != '0 && tag_write == 1'b0) begin
        int unsigned valid_and_used_ways[$];

        // Probe the tag address.
        tag_addr = dut_vif.signal_probe_ic_tag_addr(dv_utils_pkg::SignalProbeSample);

        // Find out which tag ways are valid and used in this clock cycle.
        for (int unsigned i = 0; i < num_ways; i++) begin
          if (tag_req[i] && tag_valid[i][tag_addr]) valid_and_used_ways.push_back(i);
        end

        // The response comes in the next clock cycle, so wait one cycle.
        clk_vif.wait_n_clks(1);

        // Check if at least one tag way is valid and used.
        if (valid_and_used_ways.size() > 0) begin
          int unsigned way_idx, bit_idx;
          uvm_hdl_data_t tag_rdata, mask, alert_minor;
          logic lookup_valid;

          `uvm_info(`gfn,
              $sformatf("The following I$ tag ways are valid and used in this clock cycle: %p",
                        valid_and_used_ways), UVM_LOW)

          // Pick a way to corrupt.
          way_idx = $urandom_range(valid_and_used_ways.size() - 1);
          `uvm_info(`gfn, $sformatf("Corrupting tag way %0d", way_idx), UVM_LOW)

          // Probe response data.
          tag_rdata = read_data($sformatf("ic_tag_rdata[%0d]", way_idx));
          `uvm_info(`gfn, $sformatf("Original tag_rdata of way %0d: 'h%0x", way_idx, tag_rdata),
                    UVM_LOW)

          // Pick a bit to corrupt.
          bit_idx = $urandom_range(tag_size - 1);
          mask = 1 << bit_idx;
          tag_rdata ^= mask;
          `uvm_info(`gfn, $sformatf("Corrupting tag_rdata: 'h%0x", tag_rdata), UVM_LOW)

          // Disable TB assertion for alerts.
          `DV_ASSERT_CTRL_REQ("tb_no_alerts_triggered", 1'b0)

          // Force the corrupt value.
          force_data($sformatf("ic_tag_rdata[%0d]", way_idx), tag_rdata);

          // Give the DUT one clock cycle to react.
          clk_vif.wait_n_clks(1);

          // Decide if an error is expected: if the lookup is valid.
          lookup_valid = read_data($sformatf(
              "u_ibex_core.if_stage_i.gen_icache.icache_i.lookup_valid_ic1"));
          `DV_CHECK_FATAL(!$isunknown(lookup_valid))

          // Check that the minor alert matches the expectation.
          alert_minor = dut_vif.signal_probe_alert_minor(dv_utils_pkg::SignalProbeSample);
          `DV_CHECK_EQ_FATAL(alert_minor, lookup_valid)

          // Release force and complete task.
          release_force($sformatf("ic_tag_rdata[%0d]", way_idx));
          return;
        end
      end else begin
        clk_vif.wait_n_clks(1);
      end
    end
  endtask

  task automatic corrupt_used_icache_entries();
    fork
      corrupt_used_icache_data();
      corrupt_used_icache_tag();
    join_any

    // Re-enable TB assertion for alerts.
    `DV_ASSERT_CTRL_REQ("tb_no_alerts_triggered", 1'b1)
  endtask

  virtual task send_stimulus();
    vseq.start(env.vseqr);
    fork
      track_icache_status();
      corrupt_used_icache_entries();
    join_any
  endtask

endclass

// Reset test
class core_ibex_reset_test extends core_ibex_base_test;

  `uvm_component_utils(core_ibex_reset_test)
  `uvm_component_new

  bit [5:0] num_reset;

  virtual task send_stimulus();
    vseq.start(env.vseqr);
    `DV_CHECK_STD_RANDOMIZE_WITH_FATAL(num_reset, num_reset > 20;)
    for (int i = 0; i < num_reset; i = i + 1) begin
      // Mid-test reset is possible in a wide range of times
      clk_vif.wait_clks($urandom_range(0, 50000));

      dut_vif.dut_cb.fetch_enable <= ibex_pkg::IbexMuBiOff;
      clk_vif.apply_reset(.reset_width_clks (100));
      dut_vif.dut_cb.fetch_enable <= ibex_pkg::IbexMuBiOn;
    end
  endtask

endclass

// Performance counter test class
class core_ibex_perf_test extends core_ibex_base_test;

  `uvm_component_utils(core_ibex_perf_test)
  `uvm_component_new

  virtual task check_perf_stats();
    bit [63:0] num_cycles, num_instr_ret, num_cycles_lsu, num_cycles_if, num_loads, num_stores,
               num_jumps, num_branches, num_branches_taken, num_instr_ret_c;
    wait_for_csr_write(CSR_MCYCLE);
    num_cycles[31:0] = signature_data;
    wait_for_csr_write(CSR_MCYCLEH);
    num_cycles[63:32] = signature_data;
    wait_for_csr_write(CSR_MINSTRET);
    num_instr_ret[31:0] = signature_data;
    wait_for_csr_write(CSR_MINSTRETH);
    num_instr_ret[63:32] = signature_data;
    wait_for_csr_write(CSR_MHPMCOUNTER3);
    num_cycles_lsu[31:0] = signature_data;
    wait_for_csr_write(CSR_MHPMCOUNTER4);
    num_cycles_if[31:0] = signature_data;
    wait_for_csr_write(CSR_MHPMCOUNTER5);
    num_loads[31:0] = signature_data;
    wait_for_csr_write(CSR_MHPMCOUNTER6);
    num_stores[31:0] = signature_data;
    wait_for_csr_write(CSR_MHPMCOUNTER7);
    num_jumps[31:0] = signature_data;
    wait_for_csr_write(CSR_MHPMCOUNTER8);
    num_branches[31:0] = signature_data;
    wait_for_csr_write(CSR_MHPMCOUNTER9);
    num_branches_taken[31:0] = signature_data;
    wait_for_csr_write(CSR_MHPMCOUNTER10);
    num_instr_ret_c[31:0] = signature_data;
    wait_for_csr_write(CSR_MHPMCOUNTER3H);
    num_cycles_lsu[63:32] = signature_data;
    wait_for_csr_write(CSR_MHPMCOUNTER4H);
    num_cycles_if[63:32] = signature_data;
    wait_for_csr_write(CSR_MHPMCOUNTER5H);
    num_loads[63:32] = signature_data;
    wait_for_csr_write(CSR_MHPMCOUNTER6H);
    num_stores[63:32] = signature_data;
    wait_for_csr_write(CSR_MHPMCOUNTER7H);
    num_jumps[63:32] = signature_data;
    wait_for_csr_write(CSR_MHPMCOUNTER8H);
    num_branches[63:32] = signature_data;
    wait_for_csr_write(CSR_MHPMCOUNTER9H);
    num_branches_taken[63:32] = signature_data;
    wait_for_csr_write(CSR_MHPMCOUNTER10H);
    num_instr_ret_c[63:32] = signature_data;
    `uvm_info(`gfn, $sformatf("NUM_CYCLES: 0x%0x", num_cycles), UVM_LOW)
    `uvm_info(`gfn, $sformatf("NUM_INSTR_RET: 0x%0x", num_instr_ret), UVM_LOW)
    `uvm_info(`gfn, $sformatf("NUM_CYCLES_LSU: 0x%0x", num_cycles_lsu), UVM_LOW)
    `uvm_info(`gfn, $sformatf("NUM_CYCLES_IF: 0x%0x", num_cycles_if), UVM_LOW)
    `uvm_info(`gfn, $sformatf("NUM_LOADS: 0x%0x", num_loads), UVM_LOW)
    `uvm_info(`gfn, $sformatf("NUM_STORES: 0x%0x", num_stores), UVM_LOW)
    `uvm_info(`gfn, $sformatf("NUM_JUMPS: 0x%0x", num_jumps), UVM_LOW)
    `uvm_info(`gfn, $sformatf("NUM_BRANCHES: 0x%0x", num_branches), UVM_LOW)
    `uvm_info(`gfn, $sformatf("NUM_BRANCHES_TAKEN: 0x%0x", num_branches_taken), UVM_LOW)
    `uvm_info(`gfn, $sformatf("NUM_INSTR_RET_COMPRESSED: 0x%0x", num_instr_ret_c), UVM_LOW)
  endtask

endclass

// Debug test class
class core_ibex_debug_intr_basic_test extends core_ibex_base_test;

  `uvm_component_utils(core_ibex_debug_intr_basic_test)
  `uvm_component_new

  bit [ibex_mem_intf_pkg::DATA_WIDTH-1:0] core_init_mstatus;
  bit [ibex_mem_intf_pkg::DATA_WIDTH-1:0] core_init_mie;
  priv_lvl_e                                    init_operating_mode;
  priv_lvl_e                                    operating_mode;
  bit [$clog2(irq_agent_pkg::DATA_WIDTH)-1:0]   irq_id;
  irq_seq_item                                  irq_txn;
  bit [irq_agent_pkg::DATA_WIDTH-1:0]           irq;
  bit [ibex_mem_intf_pkg::DATA_WIDTH-1:0] mstatus;
  bit [ibex_mem_intf_pkg::DATA_WIDTH-1:0] mcause;
  bit [ibex_mem_intf_pkg::DATA_WIDTH-1:0] mip;
  bit [ibex_mem_intf_pkg::DATA_WIDTH-1:0] mie;
  bit                                           in_nested_trap;

  virtual task send_stimulus();
    fork
      begin
        vseq.start(env.vseqr);
      end
      begin
        if (cfg.require_signature_addr) begin
          wait_for_core_setup();
        end else begin
          // If no signature_addr functionality is desired, then the test will simply wait for an
          // adequate number of cycles
          clk_vif.wait_clks(stimulus_delay);
        end
        fork
          begin
            if (enable_irq_seq) begin
              forever begin
                send_irq_stimulus();
              end
            end
          end
          begin
            if (cfg.enable_debug_seq) begin
              stress_debug();
            end
          end
        join_none
        // Stop checking at the end-of-test handshake, as core_ibex_directed_test does. An irq
        // raised just before the test program's final ecall is not taken before it: the ecall
        // enters the exception handler, whose HANDLING_EXCEPTION status write the pending
        // check_next_core_status(HANDLING_IRQ) then reads as a failure of a test that has passed.
        wait (test_done === 1'b1);
        // disable below can kill processes that are running sequences. As a result they never
        // stop and the simulation never ends. So wait for all sequences to stop before doing the
        // disable.
        vseq.wait_for_stop();
        disable fork;
        // Each killed check_next_core_status/wait_for_csr_write/wait_ret leaves its objection
        // raised (irq and debug checkers can both be mid-check); run_phase holds the last one.
        while (cur_run_phase != null && cur_run_phase.get_objection_count(this) > 1) begin
          cur_run_phase.drop_objection(this);
        end
      end
    join_none
  endtask

  function priv_lvl_e select_mode();
    if (in_nested_trap) return operating_mode;
    else return init_operating_mode;
  endfunction

  virtual task wait_for_core_setup();
    wait_for_csr_write(CSR_MSTATUS, 10000);
    core_init_mstatus = signature_data;
    // capture the initial privilege mode ibex will boot into
    init_operating_mode = priv_lvl_e'(core_init_mstatus[12:11]);
    wait_for_csr_write(CSR_MIE, 5000);
    core_init_mie = signature_data;
    check_next_core_status(INITIALIZED, "Core initialization handshake failure", 5000);
  endtask

  function bit determine_irq_from_txn();
    bit irq_valid;

    irq = {irq_txn.irq_nm, irq_txn.irq_fast, 4'b0, irq_txn.irq_external, 3'b0,
           irq_txn.irq_timer, 3'b0, irq_txn.irq_software, 3'b0};
    `uvm_info(`gfn, $sformatf("irq: 0x%0x", irq), UVM_LOW)

    irq_valid = get_valid_irq_id(irq);
    `uvm_info(`gfn, $sformatf("irq_id: 0x%0x", irq_id), UVM_LOW)

    return irq_valid;
  endfunction

  virtual task send_irq_stimulus_start(input bit no_nmi,
                                       input bit no_fast,
                                       output bit ret_val);
    // send the interrupt
    if (cfg.enable_irq_single_seq)        vseq.start_irq_raise_single_seq(no_nmi, no_fast);
    else if (cfg.enable_irq_multiple_seq) vseq.start_irq_raise_seq(no_nmi, no_fast);

    send_irq_stimulus_inner(ret_val);
  endtask

  virtual task send_nmi_stimulus_start(output bit ret_val);
    vseq.start_nmi_raise_seq();
    send_irq_stimulus_inner(ret_val);
  endtask

  virtual task send_irq_stimulus_inner(output bit ret_val);
    bit irq_valid;
    irq_collected_port.get(irq_txn);
    // Get the bit position of the highest priority interrupt - ibex will only handle this one if
    // there are multiple irqs asserted at once.
    irq_valid = determine_irq_from_txn();
    // If the interrupt is maskable, and the corresponding bit in MIE is not set, skip the next
    // checks, as it means the interrupt in question is not enabled by Ibex, and drop the interrupt
    // lines to avoid locking up the simulation.
    if (!irq_valid) begin
      vseq.start_irq_drop_seq();
      irq_collected_port.get(irq_txn);
      determine_irq_from_txn();
      `DV_CHECK_EQ_FATAL(irq, 0, "Interrupt lines have not been dropped")
      ret_val = irq_valid;
      return;
    end

    check_irq_handle();

    ret_val = irq_valid;
  endtask

  virtual task check_irq_handle();
    check_next_core_status(HANDLING_IRQ, "Core did not jump to vectored interrupt handler", 7500);
    check_priv_mode(PRIV_LVL_M);
    operating_mode = dut_vif.dut_cb.priv_mode;
    // check mstatus
    wait_for_csr_write(CSR_MSTATUS, 5000);
    mstatus = signature_data;
    `DV_CHECK_EQ_FATAL(mstatus[12:11], select_mode(), "Incorrect mstatus.mpp")
    // mstatus.MPIE must be 1 when trap from M mode otherwise not necessarily be 1
    // as lower priv modes could trap when mstatus.MPIE is 0, or even nmi interrupt
    `DV_CHECK_EQ_FATAL(mstatus[7] | ~&mstatus[12:11] | (irq_id == ExcCauseIrqNm.lower_cause), 1'b1,
        "mstatus.mpie was not set to 1'b1 after entering handler")
    `DV_CHECK_EQ_FATAL(mstatus[3], 1'b0, "mstatus.mie was not set to 1'b0 after entering handler")
    // check mcause against the interrupt id
    check_mcause(1'b1, irq_id);
    // Wait for MIE and MIP to be written regardless of what interrupt ibex is dealing with, to
    // prevent the case where MIP/MIE stays at 0 due to a nonmaskable interrupt, which will falsely
    // trigger the following call of check_next_core_status()
    wait_for_csr_write(CSR_MIE, 5000);
    mie = signature_data;
    wait_for_csr_write(CSR_MIP, 5000);
    mip = signature_data;
    // only check mip, and mie if the interrupt is not irq_nm, as Ibex's implementation of MIP and
    // MIE CSRs do not contain a bit for irq_nm
    if (!irq_txn.irq_nm) begin
      // check that the proper bit in MIE is high
      `DV_CHECK_EQ_FATAL(mie[irq_id], 1'b1,
          $sformatf("mie[%0d] is not set, but core responded to corresponding interrupt", irq_id))
      // check that the proper bit in MIP is high
      `DV_CHECK_EQ_FATAL(mip[irq_id], 1'b1,
          $sformatf("mip[%0d] is not set, but core responded to corresponding interrupt", irq_id))
    end
  endtask

  virtual task send_irq_stimulus_end();
    // As Ibex interrupts are level sensitive, core must write to memory mapped address to
    // indicate that irq stimulus be dropped
    check_next_core_status(FINISHED_IRQ, "Core did not signal end of interrupt properly", 6000);
    // Will receive irq_seq_item indicating that lines have been dropped
    vseq.start_irq_drop_seq();
    // Want to skip this .get() call on the second MRET of nested interrupt scenarios
    if (!(cfg.enable_nested_irq && !in_nested_trap)) begin
      irq_collected_port.get(irq_txn);
      irq = {irq_txn.irq_nm, irq_txn.irq_fast, 4'b0, irq_txn.irq_external, 3'b0,
             irq_txn.irq_timer, 3'b0, irq_txn.irq_software, 3'b0};
      `DV_CHECK_EQ_FATAL(irq, 0, "Interrupt lines have not been dropped")
    end
    wait_ret("mret", 10000);
  endtask

  virtual task send_irq_stimulus(bit no_nmi = 1'b0, bit no_fast = 1'b0);
    bit ret_val;
    send_irq_stimulus_start(no_nmi, no_fast, ret_val);
    if (ret_val) send_irq_stimulus_end();
  endtask

  virtual task send_nmi_stimulus();
    bit ret_val;
    send_nmi_stimulus_start(ret_val);
    if (ret_val) send_irq_stimulus_end();
  endtask

  function int get_valid_irq_id(bit [irq_agent_pkg::DATA_WIDTH-1:0] irq);
    int i;
    bit have_irq = 1'b0;
    // Ibex implementation of MIE does not mask NM interrupts, so need to check this separately
    if (irq[irq_agent_pkg::DATA_WIDTH - 1]) begin
      irq_id = irq_agent_pkg::DATA_WIDTH - 1;
      return 1;
    end
    for (i = irq_agent_pkg::DATA_WIDTH - 2; i >= 16; i = i - 1) begin
      // Fast interrupts (IDs 30-16) are prioritised with the lowest ID first, but any fast
      // interrupt has priority over other interrupts.
      if (irq[i] == 1'b1 && core_init_mie[i] == 1'b1) begin
        irq_id = i;
        have_irq = 1'b1;
      end
    end

    if (!have_irq) begin
      // If there was no enabled fast interrupt, check the other interrupts
      if (irq[11] && core_init_mie[11]) begin
        // External interrupt
        irq_id = 11;
        have_irq = 1'b1;
      end else if (irq[3] && core_init_mie[3]) begin
        // Software interrupt
        irq_id = 3;
        have_irq = 1'b1;
      end else if (irq[7] && core_init_mie[7]) begin
        // Timer interrupt
        irq_id = 7;
        have_irq = 1'b1;
      end

      // Other interrupt IDs aren't implemented in Ibex
    end

    return have_irq;
  endfunction

  virtual task check_mcause(bit irq_or_exc, bit[ibex_mem_intf_pkg::DATA_WIDTH-2:0] cause);
    bit[ibex_mem_intf_pkg::DATA_WIDTH-1:0] mcause;
    wait_for_csr_write(CSR_MCAUSE, 10000);
    mcause = signature_data;
    `uvm_info(`gfn, $sformatf("mcause: 0x%0x", mcause), UVM_LOW)
    `DV_CHECK_EQ_FATAL(mcause[ibex_mem_intf_pkg::DATA_WIDTH-1], irq_or_exc,
                        $sformatf("mcause.interrupt is not set to 0x%0x", irq_or_exc))
    `DV_CHECK_EQ_FATAL(mcause[ibex_mem_intf_pkg::DATA_WIDTH-2:0], cause,
                       "mcause.exception_code is encoding the wrong exception type")
  endtask

  // Basic debug stimulus check for Ibex for debug stimulus stress tests: check that Ibex enters
  // debug mode properly after stimulus is sent and then check that a dret is encountered signifying
  // the end of debug mode.
  virtual task stress_debug();
    fork
      begin
        vseq.start_debug_stress_seq();
      end
      begin
        forever begin
          wait_for_core_status(IN_DEBUG_MODE);
          check_priv_mode(PRIV_LVL_M);
          wait_ret("dret", 100000);
        end
      end
    join_none
  endtask

  // Task that waits for xRET to be asserted, with no timeout or objection
  virtual task wait_ret_raw(string ret);
      priv_lvl_e tgt_mode;
      case (ret)
        "dret": begin
          wait (dut_vif.dut_cb.dret === 1'b1);
        end
        "mret": begin
          wait (dut_vif.dut_cb.mret === 1'b1);
        end
        default: begin
          `uvm_fatal(`gfn, $sformatf("Invalid xRET instruction %0s", ret))
        end
      endcase
      tgt_mode = select_mode();
      wait (dut_vif.dut_cb.priv_mode === tgt_mode);
  endtask

  // Task that waits for xRET to be asserted within a certain number of cycles
  virtual task wait_ret(string ret, int timeout);
    cur_run_phase.raise_objection(this);
    fork begin : isolation_fork
      fork
        begin
          wait_ret_raw(ret);
        end
        begin : ret_timeout
          clk_vif.wait_clks(timeout);
          `uvm_fatal(`gfn, $sformatf({"No %0s detected, or incorrect privilege mode switch in ",
                                     "timeout period of %0d cycles"}, ret, timeout))
        end
      join_any
      // Will only get here if dret successfully detected within timeout period
      disable fork;
    end join
    // run_phase nulls cur_run_phase once the test is done, and this task can still
    // be in flight at that point (send_stimulus is forked join_none). Dropping the
    // objection is pointless once the run phase has ended, so just skip it.
    if (cur_run_phase != null) begin
      cur_run_phase.drop_objection(this);
    end
  endtask

  virtual function void check_priv_mode(priv_lvl_e mode);
    `DV_CHECK_EQ_FATAL(dut_vif.dut_cb.priv_mode, mode,
                       "Incorrect privilege mode")
  endfunction

endclass

// Base class for directed debug and irq test scenarios
class core_ibex_directed_test extends core_ibex_debug_intr_basic_test;

  `uvm_component_utils(core_ibex_directed_test)
  `uvm_component_new

  instr_t     seen_instr[$];
  bit [15:0]  seen_compressed_instr[$];

  virtual task send_stimulus();
    fork
      begin
        vseq.start(env.vseqr);
      end
      begin
        if (!cfg.require_signature_addr) begin
          clk_vif.wait_clks(stimulus_delay);
          fork
            begin
              if (enable_irq_seq) begin
                forever begin
                  send_irq_stimulus();
                end
              end
            end
            begin
              if (cfg.enable_debug_seq) begin
                stress_debug();
              end
            end
          join_none
        end else begin
          // Wait for core initialization before starting the stimulus check loop - first write
          // to signature address is guaranteed to be core initialization info
          wait_for_core_setup();
          // Wait for a little bit to guarantee that the core has started executing <main>
          // before starting to generate stimulus for the core.
          clk_vif.wait_clks(50);
          // Should be extended by derived classes.
          // DO NOT use this test class directly.
          fork
            check_stimulus();
          join_none
          wait (test_done === 1'b1);
          // disable below can kill processes that are running sequences. As a result they never
          // stop and the simulation never ends. So wait for all sequences to stop before doing the
          // disable.
          vseq.wait_for_stop();
          disable fork;
          // wait_for_stop() above can take long enough that run_phase has already
          // finished and nulled cur_run_phase, so check before dereferencing it.
          if (cur_run_phase != null && cur_run_phase.get_objection_count(this) > 1) begin
            cur_run_phase.drop_objection(this);
          end
        end
      end
    join_none
  endtask

  virtual task check_stimulus();
    `uvm_fatal(`gfn, "Base class task should not be used")
  endtask

  //------------------------------------------------------
  // Checker functions/tasks that might be commonly used
  //------------------------------------------------------

  // Send a single debug request and perform all relevant checks
  virtual task send_debug_stimulus(priv_lvl_e mode, string debug_status_err_msg);
    vseq.start_debug_single_seq();
    check_next_core_status(IN_DEBUG_MODE, debug_status_err_msg, 10000);
    check_priv_mode(PRIV_LVL_M);
    wait_for_csr_write(CSR_DCSR, 5000);
    check_dcsr_prv(mode);
    check_dcsr_cause(DBG_CAUSE_HALTREQ);
    wait_ret("dret", 10000);
  endtask

  // Illegal instruction checker
  virtual task check_illegal_insn(string exception_msg);
    // Ibex will wait to change the privilege mode until it is allowed to FLUSH. This happens
    // because it is blocking the current instruction until the instruction from WB stage is ready.
    wait (dut_vif.dut_cb.ctrl_fsm_cs == FLUSH);
    clk_vif.wait_clks(2);
    check_priv_mode(PRIV_LVL_M);
    check_next_core_status(HANDLING_EXCEPTION,
                           "Core did not jump to vectored exception handler",
                           10000);
    check_next_core_status(ILLEGAL_INSTR_EXCEPTION, exception_msg, 10000);
    check_mcause(1'b0, ExcCauseIllegalInsn);
    wait_ret("mret", 15000);
  endtask

  // compares dcsr.ebreak against the privilege mode encoded in dcsr.prv
  virtual function void check_dcsr_ebreak();
    // dcsr.prv is the bottom two bits.
    case (signature_data[1:0])
      2'b11: begin
        `DV_CHECK_EQ_FATAL(signature_data[15], 1'b1, "dcsr.ebreakm is not set")
      end
      2'b01: begin
        `DV_CHECK_EQ_FATAL(signature_data[13], 1'b1, "dcsr.ebreaks is not set")
      end
      2'b00: begin
        `DV_CHECK_EQ_FATAL(signature_data[12], 1'b1, "dcsr.ebreaku is not set")
      end
      default: begin
        `uvm_fatal(`gfn, "dcsr.prv is an unsupported privilege mode")
      end
    endcase
  endfunction

  virtual function void check_dcsr_cause(dbg_cause_e cause);
    `DV_CHECK_EQ_FATAL(cause, signature_data[8:6], "dcsr.cause has been incorrectly updated")
  endfunction

  virtual function void check_dcsr_prv(priv_lvl_e mode);
    `DV_CHECK_EQ_FATAL(mode, signature_data[1:0],
                       "Incorrect dcsr.prv value!")
  endfunction

  // Check if we have seen the same type of instruction before by comparing the instruction
  // currently in the ID stage against the global seen_instr[$] queue.
  // If we've seen the same type of instruction before, return 0, otherwise add it to the
  // seen_instr[$] queue and return 1.
  virtual function bit decode_instr(bit [ibex_mem_intf_pkg::DATA_WIDTH-1:0] instr);
    ibex_pkg::opcode_e                            opcode;
    bit [2:0]                                     funct3;
    bit [6:0]                                     funct7;
    bit [12:0]                                    system_imm;
    instr_t                                       instr_fields;

    opcode      = ibex_pkg::opcode_e'(instr[6:0]);
    funct3      = instr[14:12];
    funct7      = instr[31:25];
    system_imm  = instr[31:20];

    // Now we search seen_instr[$] to check if a same instruction has been seen before.
    case (opcode)
      OPCODE_LUI, OPCODE_AUIPC, OPCODE_JAL: begin
        // these instructions only depend on opcode.
        foreach (seen_instr[i]) begin
          if (opcode == seen_instr[i].opcode) begin
            return 0;
          end
        end
      end
      OPCODE_JALR, OPCODE_BRANCH, OPCODE_LOAD,
      OPCODE_STORE, OPCODE_MISC_MEM: begin
        // these instructions only depend on opcode and funct3
        // to be identified.
        foreach (seen_instr[i]) begin
          if (opcode == seen_instr[i].opcode &&
              funct3 == seen_instr[i].funct3) begin
            return 0;
          end
        end
      end
      OPCODE_OP_IMM: begin
        // register-immediate arithmetic instructions are handled separately
        // as slli/srli/srai rely on funct7 in addition to opcode/funct3.
        foreach (seen_instr[i]) begin
          if (opcode == seen_instr[i].opcode &&
              funct3 == seen_instr[i].funct3) begin
            // handle slli/srli/srai instructions.
            if (funct3 inside {3'b001, 3'b101}) begin
              if (funct7 == seen_instr[i].funct7) begin
                return 0;
              end
            end else begin
              return 0;
            end
          end
        end
      end
      OPCODE_OP: begin
        // all register-register arithmetic instructions rely on
        // opcode/funct3/funct7 for identification.
        foreach (seen_instr[i]) begin
          if (opcode == seen_instr[i].opcode &&
              funct3 == seen_instr[i].funct3 &&
              funct7 == seen_instr[i].funct7) begin
            return 0;
          end
        end
      end
      OPCODE_SYSTEM: begin
        // explicitly set is_seen to 0 and return on WFI instructions,
        // as if we don't interrupt them, every test will timeout.
        if (funct3 == 3'b000 && system_imm == 12'h105) begin
          return 1;
        end else if (funct3 == 3'b000 && system_imm != 12'h001) begin
          // raise is_seen if ecall/mret/dret is detected,
          // we exclude them for now (this leads to nested traps).
          return 0;
        end else begin
          foreach (seen_instr[i]) begin
            if (opcode == seen_instr[i].opcode &&
                funct3 == seen_instr[i].funct3 &&
                system_imm == seen_instr[i].system_imm) begin
              return 0;
            end
          end
        end
      end
      default: begin
        `uvm_fatal(`gfn, "Illegal instruction detected")
      end
    endcase

    // We haven't seen this type of instruction before, so add it to seen_instr[$]
    // to flag it as 'seen' the next time we decode an instruction.
    instr_fields = '{opcode, funct3, funct7, system_imm};
    seen_instr.push_back(instr_fields);
    return 1;

  endfunction

  // Similarly to decode_instr(...), this function checks whether we have seen the
  // compressed instruction currently in the ID stage before by comparing it to the
  // global seen_compressed_instr[$] queue.
  // If we have seen it before, it returns 0, otherwise the instruction is added to the
  // and it returns 1.
  virtual function bit decode_compressed_instr(bit [15:0] instr);

    foreach (seen_compressed_instr[i]) begin
      if (instr[1:0] == seen_compressed_instr[i][1:0]) begin
        case (instr[1:0])
          2'b00: begin
            if (instr[15:13] == seen_compressed_instr[i][15:13]) begin
              return 0;
            end
          end
          2'b01: begin
            if (instr[15:13] == seen_compressed_instr[i][15:13]) begin
              case (instr[15:13])
                3'b000, 3'b001, 3'b010,
                3'b011, 3'b101, 3'b110, 3'b111: begin
                  return 0;
                end
                3'b100: begin
                  if (instr[11:10] == seen_compressed_instr[i][11:10]) begin
                    case (instr[11:10])
                      2'b00, 2'b01, 2'b10: begin
                        return 0;
                      end
                      2'b11: begin
                        if (instr[12] == seen_compressed_instr[i][12] &&
                            instr[6:5] == seen_compressed_instr[i][6:5]) begin
                          return 0;
                        end
                      end
                    endcase
                  end
                end
                default: begin
                  `uvm_fatal(`gfn, "Invalid C1 compressed instruction")
                end
              endcase
            end
          end
          2'b10: begin
            if (instr[15:13] == seen_compressed_instr[i][15:13]) begin
              case (instr[15:13])
                3'b000, 3'b010, 3'b110: begin
                  return 0;
                end
                3'b100: begin
                  if (instr[12] == seen_compressed_instr[i][12]) begin
                    return 0;
                  end
                end
                default: begin
                  `uvm_fatal(`gfn, "Illegal C2 compressed instruction")
                end
              endcase
            end
          end
          default: begin
            `uvm_fatal(`gfn, "Instruction is not compressed")
          end
        endcase
      end
    end

    // If we get here we have not seen the current instruction before,
    // so add it to seen_compressed_instr[$].
    seen_compressed_instr.push_back(instr);
    return 1'b1;

  endfunction

endclass

// A directed interrupt test that sends interrupt stimulus into the core
// after seeing every unique (and supported) RISC-V instruction in the core's
// Instruction Decode stage.
class core_ibex_interrupt_instr_test extends core_ibex_directed_test;

  `uvm_component_utils(core_ibex_interrupt_instr_test)
  `uvm_component_new

  virtual task check_stimulus();
    vseq.irq_raise_single_seq_h.max_delay = 0;
    vseq.irq_raise_single_seq_h.max_interval = 0;
    forever begin
      // hold until we see a valid instruction in the ID stage of the pipeline or the core goes to
      // sleep
      wait ((instr_vif.instr_cb.valid_id && !(instr_vif.instr_cb.err_id || dut_vif.illegal_instr))
        || dut_vif.core_sleep);

      // We don't want to send fast interrupts, as due to the random setup of MIE,
      // there's no guarantee that the interrupt will actually be taken.
      if (dut_vif.core_sleep) begin
        // Testbench waits for 50 clocks before calling check_stimulus. If a WFI is executed during
        // these 50 clocks the test would sleep forever, so if the core enters sleep send irq
        // stimulus to wake it up.
        send_irq_stimulus(.no_fast(1'b1));
      end else if (instr_vif.instr_cb.is_compressed_id) begin
        if (decode_compressed_instr(instr_vif.instr_cb.instr_compressed_id)) begin
          send_irq_stimulus(.no_fast(1'b1));
        end
      end else begin
        if (decode_instr(instr_vif.instr_cb.instr_id)) begin
          send_irq_stimulus(.no_fast(1'b1));
        end
      end
      clk_vif.wait_clks(1);
    end
  endtask

endclass

// Interrupt WFI test class
class core_ibex_irq_wfi_test extends core_ibex_directed_test;

  `uvm_component_utils(core_ibex_irq_wfi_test)
  `uvm_component_new

  virtual task check_stimulus();
    forever begin
      wait (dut_vif.dut_cb.core_sleep === 1'b1);
      send_irq_stimulus();
    end
  endtask

endclass

// Interrupt CSR test class
class core_ibex_irq_csr_test extends core_ibex_directed_test;

  `uvm_component_utils(core_ibex_irq_csr_test)
  `uvm_component_new

  virtual task check_stimulus();
    vseq.irq_raise_single_seq_h.max_delay = 0;
    // wait for a write to mstatus - should be in init code
    wait (csr_vif.csr_cb.csr_access === 1'b1 &&
          csr_vif.csr_cb.csr_addr === CSR_MSTATUS &&
          csr_vif.csr_cb.csr_op != CSR_OP_READ);
    // send interrupt immediately after detection
    send_irq_stimulus();
    // wait for a write to mie - should be in init code
    wait (csr_vif.csr_cb.csr_access === 1'b1 &&
          csr_vif.csr_cb.csr_addr === CSR_MIE &&
          csr_vif.csr_cb.csr_op != CSR_OP_READ);
    // send interrupt immediately after detection
    send_irq_stimulus();
  endtask

endclass

// Tests irqs asserted in debug mode
class core_ibex_irq_in_debug_test extends core_ibex_directed_test;

  `uvm_component_utils(core_ibex_irq_in_debug_test)
  `uvm_component_new

  virtual task check_stimulus();
    bit detected_irq = 1'b0;
    bit seen_dret = 1'b0;
    bit irq_valid = 1'b0;

    forever begin
      // Drive core into debug mode
      vseq.start_debug_single_seq();
      check_next_core_status(IN_DEBUG_MODE, "Core did not enter debug mode properly", 10000);
      check_priv_mode(PRIV_LVL_M);
      wait_for_csr_write(CSR_DCSR, 5000);
      check_dcsr_prv(init_operating_mode);
      check_dcsr_cause(DBG_CAUSE_HALTREQ);

      seen_dret = 1'b0;
      detected_irq = 1'b0;
      irq_valid = 1'b0;

      // Test will generate an IRQ whilst in debug mode, depending on the random delay on the IRQ it
      // may remain enabled when DRET is executed (so the IRQ should be taken). The fork below
      // splits into three, one process stimulates the IRQ and waits for the DRET. The others check
      // for the IRQ being handled during debug and deal with the IRQ remained asserted after DRET
      // case.
      fork
        begin : wait_irq
          // Get IRQ raise transaction from IRQ monitor
          irq_collected_port.get(irq_txn);
          irq_valid = determine_irq_from_txn();
          detected_irq = 1'b1;

          if (!seen_dret) begin
            // If the DRET hasn't been seen yet await IRQ handler, if it is seen before this process
            // is disabled there is an error.
            wait_for_core_status(HANDLING_IRQ);
            `uvm_fatal(`gfn, "Core is handling interrupt detected in debug mode")
          end
        end
        begin : wait_dret
          wait_ret_raw("dret");
          seen_dret = 1'b1;

          wait (detected_irq);

          // If execution reaches this point the DRET has been seen whilst an IRQ id raised.
          // Disable `wait_irq` at this point as it's no longer an error for the interrupt handler
          // to execute
          disable wait_irq;

          `uvm_info(`gfn, "dret seen before IRQ dropped", UVM_LOW)

          if (irq_valid) begin
            // IRQ isn't disabled so IRQ will get handled
            `uvm_info(`gfn, "IRQ is enabled, interrupt should be taken", UVM_LOW)
            check_irq_handle();
            send_irq_stimulus_end();
          end else begin
            `uvm_info(`gfn, "IRQ is disabled, no interrupt should be taken", UVM_LOW)
            // IRQ is disabled so just drop IRQ
            vseq.start_irq_drop_seq();
            irq_collected_port.get(irq_txn);
          end
        end
        begin : dbg_irq_stimulate
          // Raise interrupts while the core is in debug mode
          vseq.start_irq_raise_seq();
          clk_vif.wait_clks(100);
          if (!seen_dret) begin
            // Reached end of wait and DRET not seen, so core remains in debug mode. Disable
            // `wait_dret` and `wait_irq` as we're dropping the IRQ now
            disable wait_dret;
            disable wait_irq;

            if (detected_irq) begin
              // Drop the IRQ if one was raised
              vseq.start_irq_drop_seq();
            end

            // Wait for DRET
            wait_ret("dret", 10000);
            // Get IRQ drop transaction from IRQ monitor
            irq_collected_port.get(irq_txn);
          end
        end
      join

      clk_vif.wait_clks($urandom_range(250, 500));
    end
  endtask

endclass

// Tests debug mode asserted during irq handler
class core_ibex_debug_in_irq_test extends core_ibex_directed_test;

  `uvm_component_utils(core_ibex_debug_in_irq_test)
  `uvm_component_new

  virtual task check_stimulus();
    // send first part of irq/checking routine
    // then assert basic debug stimulus
    // check that core enters and exits debug mode correctly
    // then finish interrupt handling routine
    bit valid_irq;
    forever begin
      send_irq_stimulus_start(1'b0, 1'b0, valid_irq);
      if (valid_irq) begin
        fork
          begin
            send_debug_stimulus(operating_mode, "Core did not enter debug mode from interrupt handler");
          end
          begin
            wait (dut_vif.dut_cb.dret == 1'b1);
            send_irq_stimulus_end();
          end
        join
      end
      clk_vif.wait_clks($urandom_range(250, 500));
    end
  endtask

endclass

// Nested interrupt test class (with multiple interrupts)
class core_ibex_nested_irq_test extends core_ibex_directed_test;

  `uvm_component_utils(core_ibex_nested_irq_test)
  `uvm_component_new

  virtual task check_stimulus();
    bit valid_irq;
    bit valid_nested_irq;
    int unsigned initial_irq_delay;
    vseq.irq_raise_seq_h.max_delay = 5000;
    forever begin
      send_irq_stimulus_start(1'b1, 1'b0, valid_irq);
      if (valid_irq) begin
        initial_irq_delay = vseq.irq_raise_nmi_seq_h.max_delay;
        vseq.irq_raise_nmi_seq_h.max_delay = 0;
        // Send nested interrupt after the checks of the first interrupt have finished
        in_nested_trap = 1'b1;
        // wait until we are setting mstatus.mie to 1'b1 to send the next set of interrupts
        wait (csr_vif.csr_cb.csr_access === 1'b1 &&
             csr_vif.csr_cb.csr_addr === CSR_MSTATUS &&
             csr_vif.csr_cb.csr_op != CSR_OP_READ);
        send_nmi_stimulus();
        vseq.irq_raise_nmi_seq_h.max_delay = initial_irq_delay;
        in_nested_trap = 1'b0;
        send_irq_stimulus_end();
      end
    end
  endtask

endclass

// A directed debug test that sends debug stimulus into the core
// after seeing every unique (and supported) RISC-V instruction in the core's
// Instruction Decode stage.
class core_ibex_debug_instr_test extends core_ibex_directed_test;

  `uvm_component_utils(core_ibex_debug_instr_test)
  `uvm_component_new

  virtual task check_stimulus();
    vseq.debug_seq_single_h.max_delay = 0;
    vseq.debug_seq_single_h.max_interval = 0;
    forever begin
      // hold until we see a valid instruction in the ID stage of the pipeline or the core goes to
      // sleep
      wait ((instr_vif.instr_cb.valid_id && !(instr_vif.instr_cb.err_id || dut_vif.illegal_instr)) || dut_vif.core_sleep);

      if (dut_vif.core_sleep) begin
        // Testbench waits for 50 clocks before calling check_stimulus. If a WFI is executed during
        // these 50 clocks the test would sleep forever, so if the core enters sleep send debug
        // stimulus to wake it up.
        send_debug_stimulus(init_operating_mode,
                            $sformatf("Did not jump into debug mode after instruction[0x%0x]",
                                      instr_vif.instr_cb.instr_compressed_id));
      end else if (instr_vif.instr_cb.is_compressed_id) begin
        if (decode_compressed_instr(instr_vif.instr_cb.instr_compressed_id)) begin
          send_debug_stimulus(init_operating_mode,
                              $sformatf("Did not jump into debug mode after instruction[0x%0x]",
                                        instr_vif.instr_cb.instr_compressed_id));
        end
      end else begin
        if (decode_instr(instr_vif.instr_cb.instr_id)) begin
          send_debug_stimulus(init_operating_mode,
                              $sformatf("Did not jump into debug mode after instruction[0x%0x]",
                                        instr_vif.instr_cb.instr_id));
        end
      end
      clk_vif.wait_clks(1);
    end
  endtask

endclass

// Debug WFI test class
class core_ibex_debug_wfi_test extends core_ibex_directed_test;

  `uvm_component_utils(core_ibex_debug_wfi_test)
  `uvm_component_new

  virtual task check_stimulus();
    forever begin
      // A wfi that retires before this loop starts (it starts 50 clocks after core setup) leaves
      // no pulse to see, and the core then sleeps until woken: seeds 23327/23329 hung this way.
      // core_sleep is only raised by a WFI once the core is running, so accept it directly.
      if (dut_vif.dut_cb.core_sleep !== 1'b1) begin
        wait (dut_vif.dut_cb.wfi === 1'b1);
      end
      wait (dut_vif.dut_cb.core_sleep === 1'b1);
      clk_vif.wait_clks($urandom_range(100));
      send_debug_stimulus(init_operating_mode, "Core did not jump into debug mode from WFI state");
    end
  endtask

endclass

// Debug CSR entry test
class core_ibex_debug_csr_test extends core_ibex_directed_test;

  `uvm_component_utils(core_ibex_debug_csr_test)
  `uvm_component_new

  virtual task check_stimulus();
    vseq.debug_seq_single_h.max_delay = 0;
    // wait for a dummy write to mstatus in init code
    wait (csr_vif.csr_cb.csr_access === 1'b1 &&
          csr_vif.csr_cb.csr_addr === CSR_MSTATUS &&
          csr_vif.csr_cb.csr_op != CSR_OP_READ);
    send_debug_stimulus(init_operating_mode, "Core did not trap to debug mode upon debug stimulus");
    // wait for a dummy write to mie in the init code
    wait (csr_vif.csr_cb.csr_access === 1'b1 &&
          csr_vif.csr_cb.csr_addr === CSR_MIE &&
          csr_vif.csr_cb.csr_op != CSR_OP_READ);
    send_debug_stimulus(init_operating_mode, "Core did not trap to debug mode upon debug stimulus");
  endtask

endclass

// DRET test class
class core_ibex_dret_test extends core_ibex_directed_test;

  `uvm_component_utils(core_ibex_dret_test)
  `uvm_component_new

  virtual task check_stimulus();
    forever begin
      wait (dut_vif.dut_cb.dret === 1'b1);
      check_illegal_insn("Core did not treat dret like illegal instruction");
    end
  endtask

endclass

// Normal debug ebreak test class
class core_ibex_debug_ebreak_test extends core_ibex_directed_test;

  `uvm_component_utils(core_ibex_debug_ebreak_test)
  `uvm_component_new

  bit[ibex_mem_intf_pkg::DATA_WIDTH-1:0] dpc;
  bit[ibex_mem_intf_pkg::DATA_WIDTH-1:0] dcsr;

  virtual task check_stimulus();
    forever begin
      vseq.start_debug_single_seq();
      check_next_core_status(IN_DEBUG_MODE, "Core did not properly jump into debug mode", 10000);
      // capture the first write of dcsr
      check_priv_mode(PRIV_LVL_M);
      wait_for_csr_write(CSR_DCSR, 5000);
      check_dcsr_prv(init_operating_mode);
      dcsr = signature_data;
      // We also want to check that dcsr.cause has been set correctly
      check_dcsr_cause(DBG_CAUSE_HALTREQ);
      // capture the first write of dpc
      wait_for_csr_write(CSR_DPC, 5000);
      dpc = signature_data;
      wait (dut_vif.dut_cb.ebreak === 1'b1);
      // compare the second writes of dcsr and dpc against the captured values
      wait_for_csr_write(CSR_DCSR, 5000);
      `DV_CHECK_EQ_FATAL(dcsr, signature_data,
                         "ebreak inside the debug rom has changed the value of DCSR")
      wait_for_csr_write(CSR_DPC, 5000);
      `DV_CHECK_EQ_FATAL(dpc, signature_data,
                         "ebreak inside the debug rom has changed the value of DPC")
      wait_ret("dret", 10000);
      clk_vif.wait_clks($urandom_range(250, 500));
    end
  endtask

endclass

// Debug ebreak test with dcsr.ebreak(m/s/u) set
class core_ibex_debug_ebreakmu_test extends core_ibex_directed_test;

  `uvm_component_utils(core_ibex_debug_ebreakmu_test)
  `uvm_component_new

  bit seen_ebreak;

  virtual task send_stimulus();
    seen_ebreak = 0;
    fork
      begin : detect_ebreak
        wait (dut_vif.dut_cb.ebreak === 1'b1);
        seen_ebreak = 1;
      end
      begin : run_stimulus
        core_ibex_directed_test::send_stimulus();
      end
    join
  endtask

  virtual task check_stimulus();
    fork begin
      fork
        begin : dbg_setup
          // send a single debug request after core initialization to configure dcsr
          vseq.start_debug_single_seq();
          check_next_core_status(IN_DEBUG_MODE,
                                 "Core did not enter debug mode after debug_req stimulus", 10000);
          check_priv_mode(PRIV_LVL_M);
          // Read dcsr and verify the appropriate ebreak(m/s/u) bit has been set based on the prv field,
          // as well as the cause field
          wait_for_csr_write(CSR_DCSR, 5000);
          check_dcsr_prv(init_operating_mode);
          check_dcsr_ebreak();
          check_dcsr_cause(DBG_CAUSE_HALTREQ);
          wait_ret("dret", 10000);
        end
        begin : detect_ebreak
          wait (seen_ebreak == 1);
          `uvm_fatal(`gfn, {"EBreak seen whilst doing initial debug initialization, KNOWN FAILURE ",
            "SEE https://github.com/lowRISC/ibex/issues/1313"})
        end
      join_any
      disable fork;
    end join

    forever begin
      wait (dut_vif.dut_cb.ebreak === 1'b1);
      check_next_core_status(IN_DEBUG_MODE,
                             "Core did not enter debug mode after execution of ebreak", 10000);
      check_priv_mode(PRIV_LVL_M);
      // Read dcsr and verify the appropriate ebreak(m/s/u) bit has been set based on the prv field
      wait_for_csr_write(CSR_DCSR, 5000);
      check_dcsr_prv(init_operating_mode);
      check_dcsr_ebreak();
      check_dcsr_cause(DBG_CAUSE_EBREAK);
      wait_ret("dret", 10000);
    end
  endtask

endclass

// Debug single step test
class core_ibex_debug_single_step_test extends core_ibex_directed_test;

  `uvm_component_utils(core_ibex_debug_single_step_test)
  `uvm_component_new

  uvm_event e1;
  int       cnt;
  int       debug_mode_end_dwell_cycles = 3000;

  virtual task check_stimulus();
    e1 = new();
    fork
      begin
        forever begin
          // Create an event (e1) whenever we are out of debug_mode for a configurable length of time.
          // This allows us to detect when the system has stopped single-stepping.
          cnt = 0;
          @(negedge dut_vif.dut_cb.debug_mode);
          while (dut_vif.dut_cb.debug_mode == '0) begin
            clk_vif.wait_clks(1);
            cnt++;
            if (cnt == debug_mode_end_dwell_cycles) begin
              e1.trigger();
              break;
            end
          end
        end
      end
      begin
        forever begin
          clk_vif.wait_clks(2000);
          vseq.start_debug_single_seq();
          // Wait for the above event (e1) before sending another debug_req
          e1.wait_trigger();
        end
      end
    join_none
  endtask

endclass


class core_ibex_single_debug_pulse_test extends core_ibex_directed_test;

  `uvm_component_utils(core_ibex_single_debug_pulse_test)
  `uvm_component_new

    virtual task check_stimulus();
      vseq.debug_seq_single_h.max_interval = 0;
      // Start as soon as device is initialized.
      vseq.start_debug_single_seq();
      wait (test_done === 1'b1);
    endtask

endclass

// Memory interface error test class
class core_ibex_mem_error_test extends core_ibex_directed_test;

  `uvm_component_utils(core_ibex_mem_error_test)
  `uvm_component_new

  int illegal_instruction_threshold = 20;
  int illegal_instruction_exceptions_seen = 0;

  virtual task check_stimulus();
    memory_error_seq memory_error_seq_h;
    memory_error_seq_h = memory_error_seq::type_id::create("memory_error_seq_h", this);

    `uvm_info(`gfn, "Running core_ibex_mem_error_test", UVM_LOW)
    memory_error_seq_h.vseq = vseq;
    memory_error_seq_h.iteration_modes = InfiniteRuns;
    memory_error_seq_h.stimulus_delay_cycles_min = 800; // Interval between injected errors
    memory_error_seq_h.stimulus_delay_cycles_max = 5000;
    memory_error_seq_h.intg_err_pct = cfg.enable_mem_intg_err ? 75 : 0;
    memory_error_seq_h.skip_on_exc = 1'b1;
    fork
      run_illegal_instr_watcher();
      memory_error_seq_h.start(env.vseqr);
    join_none
  endtask

  task run_illegal_instr_watcher();
    // When integrity errors are present loads that see them won't write to the register file.
    // Generated code from RISC-DV may be using the loads to produce known constants in register
    // that are then used elsewhere, in particular for jump targets. As the register write doesn't
    // occur this results in jumping to places that weren't intended which in turn can result in
    // illegal instruction exceptions.
    //
    // As a simple fix for this we observe illegal instruction exceptions and terminate the test
    // with a pass after hitting a certain threshold when the test is generating integrity errors.
    //
    // We don't terminate immediately as sometimes the test hits an illegal instruction exception
    // but finds its way back to generated code and terminates as usual. Sometimes it doesn't. The
    // threshold allows for normal test termination in cases where that's possible.
    if (!cfg.enable_mem_intg_err) begin
      return;
    end

    forever begin
      wait_for_core_exception(ibex_pkg::ExcCauseIllegalInsn);
      ++illegal_instruction_exceptions_seen;
    end
  endtask

  virtual task wait_for_custom_test_done();
    wait(illegal_instruction_exceptions_seen == illegal_instruction_threshold);
    `uvm_info(`gfn, "Terminating test early due to illegal instruction threshold reached", UVM_LOW)
  endtask

endclass

// Memory errors with interrupts and debug requests on top: the bus/PMP error injection of
// core_ibex_mem_error_test plus the irq/debug generators of
// core_ibex_assorted_traps_interrupts_debug_test. Targets the irq_pending/debug_req bins of
// uarch_cg.exception_stall_instr_cross, which neither test reaches on its own. Independent
// generators rarely have a request pending in the cycle an error arrives, so raise_on_dside_error()
// also raises an interrupt or a debug request the moment a data-side bus error is decided: the
// access is then outstanding, the core cannot take the request before the response (an interrupt
// or debug entry waits for ID to drain), and the request is pending when the error is reported.
class core_ibex_mem_error_traps_test extends core_ibex_mem_error_test;

  debug_new_seq debug_new_seq_h;
  irq_new_seq   irq_new_seq_h;

  // Error-synchronised debug requests per test (each one runs the debug program).
  int unsigned  err_sync_debug_max = 20;

  `uvm_component_utils(core_ibex_mem_error_traps_test)
  `uvm_component_new

  // On each data-side bus error: half the time an interrupt pulse, a quarter of the time a debug
  // request pulse (up to err_sync_debug_max), otherwise nothing, so errors without a pending
  // request stay in the mix.
  virtual task raise_on_dside_error();
    int unsigned n_dbg = 0;
    forever begin
      @(vseq.data_intf_seq.error_armed);
      randcase
        2: fork
          begin
            irq_new_seq irq_sync_h = irq_new_seq::type_id::create("irq_sync_h");
            irq_sync_h.iteration_modes = SingleRun;
            irq_sync_h.zero_delay_pct = 100;
            irq_sync_h.min_delay = 50;
            irq_sync_h.max_delay = 300;
            irq_sync_h.no_nmi = 1'b1;  // see send_stimulus()
            irq_sync_h.start(env.vseqr.irq_seqr);
          end
        join_none
        1: if (n_dbg < err_sync_debug_max) begin
          n_dbg++;
          fork
            begin
              dut_vif.dut_cb.debug_req <= 1'b1;
              clk_vif.wait_clks($urandom_range(20, 200));
              dut_vif.dut_cb.debug_req <= 1'b0;
            end
          join_none
        end
        1: ;
      endcase
    end
  endtask

  virtual task send_stimulus();
    `DV_CHECK_FATAL(cfg.require_signature_addr, "+require_signature_addr=1 is mandatory for this test.")

    irq_new_seq_h   = irq_new_seq::type_id::create("irq_new_seq_h", this);
    debug_new_seq_h = debug_new_seq::type_id::create("debug_new_seq_h", this);

    irq_new_seq_h.iteration_modes = InfiniteRuns;
    irq_new_seq_h.stimulus_delay_cycles_min = 300;
    irq_new_seq_h.stimulus_delay_cycles_max = 1500;
    irq_new_seq_h.zero_delay_pct = 10;
    // No NMIs, as in core_ibex_irq_traps_test: Ibex takes an NMI with MIE=0, and the riscv-dv trap
    // handlers are not NMI-reentrant. An NMI between the kernel-stack decrement and the end of the
    // register save overlaps the two frames; the outer handler restores a clobbered sp, its pushes
    // then land on .text and the program runs the overwritten code, which the DUT (ICache, no
    // fence.i) and Spike legally see differently (riscv_mem_error_traps_test 28607, 2026-10-09).
    // cp_irq_pending also counts ordinary pending interrupts with MIE=0, so the targeted
    // exception_stall_instr_cross bins stay reachable.
    irq_new_seq_h.no_nmi = 1'b1;
    debug_new_seq_h.iteration_modes = MultipleRuns;
    debug_new_seq_h.iteration_cnt_max = 10;
    debug_new_seq_h.pulse_length_cycles_min = 3000;
    debug_new_seq_h.pulse_length_cycles_max = 5000;
    debug_new_seq_h.stimulus_delay_cycles_min = 5000;
    debug_new_seq_h.stimulus_delay_cycles_max = 8000;
    debug_new_seq_h.zero_delay_pct = 0;

    `uvm_info(`gfn, "Running core_ibex_mem_error_traps_test", UVM_LOW)
    fork
      vseq.start(env.vseqr);
      begin
        wait_for_core_setup();
        clk_vif.wait_clks(50);
        // check_stimulus() is what starts the memory error injection in
        // core_ibex_mem_error_test; the base send_stimulus() calls it, this override must too.
        fork
          check_stimulus();
          debug_new_seq_h.start(env.vseqr.irq_seqr);
          irq_new_seq_h.start(env.vseqr.irq_seqr);
          raise_on_dside_error();
        join_none
      end
    join_any
  endtask

endclass

// U-mode mstatus.tw test class
class core_ibex_umode_tw_test extends core_ibex_directed_test;

  `uvm_component_utils(core_ibex_umode_tw_test)
  `uvm_component_new

  virtual task check_stimulus();
    bit [ibex_mem_intf_pkg::DATA_WIDTH-1:0] mcause;
    forever begin
      wait (dut_vif.dut_cb.wfi === 1'b1);
      check_illegal_insn("Core did not treat U-mode WFI as illegal");
    end
  endtask

endclass

// Priv-mode CSR access test
class core_ibex_invalid_csr_test extends core_ibex_directed_test;

  `uvm_component_utils(core_ibex_invalid_csr_test)
  `uvm_component_new

  virtual task check_stimulus();
    forever begin
      // Wait for a CSR access
      wait (csr_vif.csr_cb.csr_access == 1'b1);
      check_illegal_insn($sformatf("Core did not treat access to CSR 0x%0x from %0s as illegal",
                                   csr_vif.csr_cb.csr_addr, init_operating_mode));
    end
  endtask

endclass

class core_ibex_fetch_en_chk_test extends core_ibex_directed_test;

  `uvm_component_utils(core_ibex_fetch_en_chk_test)
  `uvm_component_new

  virtual task send_stimulus();
    fetch_enable_seq fetch_enable_seq_h;
    fetch_enable_seq_h = fetch_enable_seq::type_id::create("fetch_enable_seq_h", this);
    `uvm_info(`gfn, "Running core_ibex_fetch_en_chk_test", UVM_LOW)
    fork
      begin
        vseq.start(env.vseqr);
      end
      begin
        fetch_enable_seq_h.start(env.vseqr);
      end
    join_any
  endtask

endclass

// Stimulate a combination of traps/debug requests
// - exceptions are inserted through the instruction generator cfg (testlist.yaml)
// - interrupts/debug requests are inserted through testbench stimulus
class core_ibex_assorted_traps_interrupts_debug_test extends core_ibex_directed_test;

   debug_new_seq debug_new_seq_h;
   irq_new_seq irq_new_seq_h;

   `uvm_component_utils(core_ibex_assorted_traps_interrupts_debug_test)
   `uvm_component_new

   virtual task send_stimulus();
     `DV_CHECK_FATAL(cfg.require_signature_addr, "+require_signature_addr=1 is mandatory for this test.")

     irq_new_seq_h = irq_new_seq::type_id::create("irq_new_seq_h", this);
     debug_new_seq_h = debug_new_seq::type_id::create("debug_new_seq_h", this);

     irq_new_seq_h.iteration_modes = InfiniteRuns;
     irq_new_seq_h.stimulus_delay_cycles_min = 500; // Interval between requests
     irq_new_seq_h.stimulus_delay_cycles_max = 2000;
     irq_new_seq_h.zero_delay_pct = 10;
     debug_new_seq_h.iteration_modes = MultipleRuns;
     debug_new_seq_h.iteration_cnt_max = 10; // Limit this or the test will never end.
     debug_new_seq_h.pulse_length_cycles_min = 3000;   // Length of debug request pulse
     debug_new_seq_h.pulse_length_cycles_max = 5000;
     debug_new_seq_h.stimulus_delay_cycles_min = 5000; // Interval between requests
     debug_new_seq_h.stimulus_delay_cycles_max = 8000;
     debug_new_seq_h.zero_delay_pct = 0;

     `uvm_info(`gfn, "Running test:->core_ibex_assorted_traps_interrupts_debug_test", UVM_LOW)
     // Fork and never-join the different stimulus generators.
     // Irq and Debug-Request generators should run independently to each other,
     // and continue running until the end of the test binary.
     fork
       begin
          // Calls body() in core_ibex_vseq.sv
          // This starts the memory interface sequences
          // (It also configures sequences enabled by plusargs, but they're not used here)
          vseq.start(env.vseqr);
       end
       begin
         // Wait for the hart to initialize
         wait_for_core_setup();
         // Wait for a little bit to guarantee that the core has started executing <main>
         // before starting to generate stimulus for the core.
         clk_vif.wait_clks(50);
         // Now start the independent stimulus generators
         fork
           begin
             debug_new_seq_h.start(env.vseqr.irq_seqr);
           end
           begin
             irq_new_seq_h.start(env.vseqr.irq_seqr);
           end
         join_none
       end
     join_any
   endtask

endclass

// Interrupts only, as stimulus (no per-interrupt checks): core_ibex_assorted_traps_interrupts_debug_test
// without its debug-request generator. For random-PMP programs: Ibex exempts the debug module
// address range from PMP in debug mode and Spike does not, so a random PMP configuration that
// denies execute on the debug ROM makes every debug entry a cosim mismatch (riscv_pmp_traps_test
// seeds 1 and 3, 2026-10-04).
class core_ibex_irq_traps_test extends core_ibex_assorted_traps_interrupts_debug_test;

  `uvm_component_utils(core_ibex_irq_traps_test)
  `uvm_component_new

  virtual task send_stimulus();
    `DV_CHECK_FATAL(cfg.require_signature_addr, "+require_signature_addr=1 is mandatory for this test.")

    irq_new_seq_h = irq_new_seq::type_id::create("irq_new_seq_h", this);
    irq_new_seq_h.iteration_modes = InfiniteRuns;
    irq_new_seq_h.stimulus_delay_cycles_min = 300;
    irq_new_seq_h.stimulus_delay_cycles_max = 1500;
    irq_new_seq_h.zero_delay_pct = 10;
    // No NMIs: Ibex takes an NMI even with MIE=0, and the riscv-dv trap handlers are not
    // NMI-reentrant. An NMI between the kernel-stack decrement and the end of the register save
    // overlaps the two frames; the outer handler then restores clobbered registers and a stray
    // store patches .text (riscv_pmp_traps_test 24870, 24886, 2026-10-06). NMIs are covered by
    // riscv_nmi_at_exc_test and the NMI tests with their own handlers.
    irq_new_seq_h.no_nmi = 1'b1;

    `uvm_info(`gfn, "Running core_ibex_irq_traps_test", UVM_LOW)
    fork
      vseq.start(env.vseqr);
      begin
        // Not wait_for_core_setup(): with a random PMP configuration the program can trap during
        // its own initialisation, so the first signature write is an exception status (8), not
        // INITIALIZED, and the handshake check fails (riscv_pmp_traps_test, 17 of 50 seeds,
        // 2026-10-04). riscv_pmp_full_random_test never checks that handshake either. Start the
        // interrupts after a fixed delay instead, well past the program's setup code.
        clk_vif.wait_clks(2000);
        fork
          irq_new_seq_h.start(env.vseqr.irq_seqr);
        join_none
      end
    join_any
  endtask

endclass

// NMIs while an excepting instruction is in ID: ECALL, EBREAK (exception, no debug section) or an
// illegal instruction. An interrupt is taken only with ID empty, ahead of the instruction there,
// so an NMI pending while such an instruction waits in ID is taken with that instruction as the
// last category -- the nmi = 1 bins of uarch_cg.interrupt_taken_instr_cross that random NMIs
// reach only by chance. The NMI is raised the cycle the instruction is seen in ID; when the
// instruction leaves ID before the NMI arrives it is an ordinary random NMI. Stimulus only, as
// core_ibex_irq_traps_test: the cosim checks every trap.
class core_ibex_nmi_at_exc_test extends core_ibex_irq_traps_test;

  `uvm_component_utils(core_ibex_nmi_at_exc_test)
  `uvm_component_new

  // ECALL, EBREAK, C.EBREAK or an illegal instruction is in ID.
  function bit excepting_in_id();
    if (!instr_vif.instr_cb.valid_id) return 1'b0;
    if (dut_vif.illegal_instr) return 1'b1;
    if (instr_vif.instr_cb.is_compressed_id) return instr_vif.instr_cb.instr_compressed_id == 16'h9002;
    return instr_vif.instr_cb.instr_id inside {32'h0000_0073, 32'h0010_0073};
  endfunction

  virtual task nmi_at_exc();
    forever begin
      clk_vif.wait_clks(1);
      if (!excepting_in_id()) continue;
      // One in two: the rest keep excepting instructions without an NMI in the mix.
      if ($urandom_range(0, 1)) begin
        nmi_pulse_seq nmi_h = nmi_pulse_seq::type_id::create("nmi_h");
        nmi_h.iteration_modes = SingleRun;
        nmi_h.zero_delay_pct = 100;
        nmi_h.min_delay = 20;
        nmi_h.max_delay = 100;
        nmi_h.start(env.vseqr.irq_seqr);
      end
      // Past this instruction and its trap before looking again.
      clk_vif.wait_clks(50);
    end
  endtask

  virtual task send_stimulus();
    `DV_CHECK_FATAL(cfg.require_signature_addr, "+require_signature_addr=1 is mandatory for this test.")

    irq_new_seq_h = irq_new_seq::type_id::create("irq_new_seq_h", this);
    irq_new_seq_h.iteration_modes = InfiniteRuns;
    irq_new_seq_h.stimulus_delay_cycles_min = 1000;
    irq_new_seq_h.stimulus_delay_cycles_max = 3000;
    irq_new_seq_h.zero_delay_pct = 10;
    irq_new_seq_h.no_nmi = 1'b1;

    `uvm_info(`gfn, "Running core_ibex_nmi_at_exc_test", UVM_LOW)
    fork
      vseq.start(env.vseqr);
      begin
        clk_vif.wait_clks(2000);
        fork
          irq_new_seq_h.start(env.vseqr.irq_seqr);
          nmi_at_exc();
        join_none
      end
    join_any
  endtask

endclass

// Raises (raise = 1) or drops (raise = 0) irq_nm_i and leaves the maskable lines alone, so a timer
// that irq_timer_hold_seq holds stays as it is. core_ibex_stall_events_test holds an NMI with it
// until the core takes it.
class nmi_level_seq extends uvm_sequence #(irq_seq_item);

  `uvm_object_utils(nmi_level_seq)
  `uvm_object_new

  bit raise;

  virtual task body();
    irq_seq_item irq;
    irq = irq_seq_item::type_id::create("irq");
    irq.drive_maskable = 1'b0;
    start_item(irq);
    `DV_CHECK_RANDOMIZE_WITH_FATAL(irq, num_of_interrupt == int'(raise); irq_nm == raise;)
    finish_item(irq);
    get_response(irq);
  endtask

endclass

// Debug requests, NMIs, a held timer interrupt and fetch-enable drops raised at chosen pipeline
// events (core_ibex_dut_probe_if), for the timing-dependent bins of uarch_cg that free-running
// generators reach only by chance. A debug request or interrupt that is pending before an
// instruction reaches ID halts IF, so ID is empty by the time a stall or fault is seen; these
// triggers raise it while the instruction is already there. Every trigger is off unless its
// plusarg is given:
//   +dbg_on_stall_pct=<n>       an instruction stays in ID into the next cycle (id_instr_held):
//                               debug_req from that next cycle on, n% of such cycles
//   +dbg_on_pmp_err_pct=<n>     a PMP-blocked data access reports its error next cycle
//                               (lsu_pmp_err_next): debug_req in exactly the report cycle, the
//                               first cycle of the next instruction in ID
//   +dbg_on_dside_err_pct=<n>   the d-side response sequence decides a bus error (error_armed, the
//                               cycle after the grant): debug_req from that cycle on
//   +dbg_after_flush_pct=<n>    a trap FLUSH holds a load/store stalled on memory in ID (FLUSH and
//   +nmi_after_flush_pct=<n>    id_stall_mem): debug_req or an NMI pulse that arrives in the second
//                               DECODE cycle after it, while ID is still empty, so the entry sees
//                               category None just unstalled
//   +fetch_off_on_stall_pct=<n> an instruction stays in ID: fetch_enable_i off for 1-4 cycles, IF
//                               idle while ID holds it
//   +irq_timer_on_wfi=1         the first WFI seen in ID raises irq_timer_i and holds it high to the
//                               end; the program masks it with mie / mstatus.MIE from then on
//   +dbg_req_on_write=<hex>     every store to <hex> raises a debug request (a program doorbell)
//   +dbg_gap_min/max=<n>        quiet cycles after a debug exit before the next triggered request
//                               (default 20 / 200)
//   +gnt_trig_lo/hi=<hex>       a data-side grant of a word in [lo, hi] (the bus monitor's address
//                               phase, so independent of how long the access then takes) acts on
//                               the bits of its offset from lo, which the program chooses:
//                               0x10 debug_req from the cycle after the grant (the first cycle of
//                               the next instruction in ID); 0x20 an NMI from the second cycle after
//                               it, held until the core takes it (IRQ_TAKEN), then dropped; 0x40
//                               fetch_enable_i off from the second cycle after it for
//                               +gnt_fetch_off_cycles (default 40). Combine with +dside_bus_err_lo/hi
//                               over part of the window for faulting triggers.
//   +mem_mode_on_write=<hex>    a store of V to <hex> sets the memory agents' timing for later
//                               accesses: V[7:0] = 0 the run's own data-side delays, 1 no data-side
//                               delays, n in 2..29 data-side responses n to 2n+4 cycles after the
//                               grant; V[8] = 1 no instruction-side delays, 0 the run's own;
//                               V[23:16] = m in 2..125 instead: instruction-side responses m to
//                               2m+4 cycles apart (the response driver serves them in order, each
//                               delay counted from the one before), so the core waits at least m
//                               cycles for every fetched word. Takes effect after that store's
//                               response.
//   With +gnt_trig_lo/hi and +mem_mode_on_write the program times the event against its own
//   instructions, so these triggers are not held back by the start-up rule below.
// With +irq_timer_on_wfi or +dbg_req_on_write the program is one that sets itself up first (its
// debug handler's registers, PMP), so the stall and fetch-off triggers, the only ones a start-up
// can produce, are held off until the first WFI in ID or the first doorbell write, whichever
// comes first. Without either plusarg they run from reset. The WFI that +irq_timer_on_wfi serves
// is also left alone by them until the core has slept on it: a debug request while it waits in
// ID would send FLUSH to DBG_TAKEN_IF instead of WAIT_SLEEP, and lose the irq_wfi_cross
// enter_sleep bin the timer interrupt is raised for.
// Checks: every debug request raised is taken, debug mode within +dbg_entry_timeout cycles
// (default 2000) -- a halt request must halt the hart (RISC-V Debug Spec 4.1); and every trigger
// that is enabled fired at least once, as a trigger that never fired means the program never
// produced its event and none of the bins it is for could be reached. The program checks the rest
// (directed_tests/pmp_fault_hazard).
class core_ibex_stall_events_test extends core_ibex_base_test;

  `uvm_component_utils(core_ibex_stall_events_test)
  `uvm_component_new

  int unsigned dbg_on_stall_pct;
  int unsigned dbg_on_pmp_err_pct;
  int unsigned dbg_on_dside_err_pct;
  int unsigned dbg_after_flush_pct;
  int unsigned nmi_after_flush_pct;
  int unsigned fetch_off_on_stall_pct;
  bit          irq_timer_on_wfi;
  bit [31:0]   dbg_req_on_write;
  int unsigned dbg_gap_min = 20;
  int unsigned dbg_gap_max = 200;
  int unsigned dbg_entry_timeout = 2000;
  bit [31:0]   gnt_trig_lo, gnt_trig_hi;
  bit          gnt_trig_en;
  int unsigned gnt_fetch_off_cycles = 40;
  bit [31:0]   mem_mode_on_write;

  // Debug requests raised, per trigger; NMI pulses; fetch-enable drops.
  int unsigned n_dbg[string];
  int unsigned n_nmi;
  int unsigned n_fetch_off;
  // Grants in the +gnt_trig window; NMIs held and fetch-enable drops they raised; mode changes.
  int unsigned n_gnt_trig;
  int unsigned n_gnt_nmi;
  int unsigned n_gnt_fetch_off;
  int unsigned n_mem_mode;
  // The run's own memory-agent timing, restored by +mem_mode_on_write V[7:0] = 0 / V[8] = 0.
  bit          dmem_zero_delays_orig, imem_zero_delays_orig;
  int unsigned dmem_valid_min_orig, dmem_valid_max_orig;
  int unsigned imem_valid_min_orig, imem_valid_max_orig;
  bit          timer_raised;
  bit          dbg_busy;
  bit          nmi_busy;
  bit          fetch_off_busy;
  // Stall and fetch-off triggers enabled: from reset, or from the program's first WFI in ID or
  // first doorbell write when +irq_timer_on_wfi / +dbg_req_on_write says it has a start-up.
  bit          program_ready;
  // The core has been in SLEEP: the WFI +irq_timer_on_wfi serves has reached it.
  bit          wfi_slept;

  uvm_tlm_analysis_fifo #(ibex_mem_intf_seq_item) doorbell_port;
  // Data-side address phases (request and grant), for +gnt_trig_lo/hi.
  uvm_tlm_analysis_fifo #(ibex_mem_intf_seq_item) dgnt_port;

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    void'($value$plusargs("dbg_on_stall_pct=%0d", dbg_on_stall_pct));
    void'($value$plusargs("dbg_on_pmp_err_pct=%0d", dbg_on_pmp_err_pct));
    void'($value$plusargs("dbg_on_dside_err_pct=%0d", dbg_on_dside_err_pct));
    void'($value$plusargs("dbg_after_flush_pct=%0d", dbg_after_flush_pct));
    void'($value$plusargs("nmi_after_flush_pct=%0d", nmi_after_flush_pct));
    void'($value$plusargs("fetch_off_on_stall_pct=%0d", fetch_off_on_stall_pct));
    void'($value$plusargs("irq_timer_on_wfi=%0d", irq_timer_on_wfi));
    void'($value$plusargs("dbg_req_on_write=%h", dbg_req_on_write));
    void'($value$plusargs("dbg_gap_min=%0d", dbg_gap_min));
    void'($value$plusargs("dbg_gap_max=%0d", dbg_gap_max));
    void'($value$plusargs("dbg_entry_timeout=%0d", dbg_entry_timeout));
    gnt_trig_en = $value$plusargs("gnt_trig_lo=%h", gnt_trig_lo) &&
                  $value$plusargs("gnt_trig_hi=%h", gnt_trig_hi);
    void'($value$plusargs("gnt_fetch_off_cycles=%0d", gnt_fetch_off_cycles));
    void'($value$plusargs("mem_mode_on_write=%h", mem_mode_on_write));
    if (dbg_gap_max < dbg_gap_min) dbg_gap_max = dbg_gap_min;
    program_ready = !irq_timer_on_wfi && (dbg_req_on_write == 0);
    doorbell_port = new("doorbell_port", this);
    dgnt_port = new("dgnt_port", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (dbg_req_on_write != 0 || mem_mode_on_write != 0) begin
      env.data_if_response_agent.monitor.item_collected_port.connect(doorbell_port.analysis_export);
    end
    if (gnt_trig_en) begin
      env.data_if_response_agent.monitor.addr_ph_port.connect(dgnt_port.analysis_export);
    end
  endfunction

  function bit roll(int unsigned pct);
    return (pct != 0) && ($urandom_range(99) < pct);
  endfunction

  function int unsigned n_dbg_of(string why);
    return n_dbg.exists(why) ? n_dbg[why] : 0;
  endfunction

  // Raise debug_req. Called in the time step of a dut_cb clocking event, so the request is seen
  // from the cycle that event starts. Nothing is raised while a request is in progress or the core
  // is in debug mode.
  task automatic request_debug(string why, output bit raised);
    raised = 1'b0;
    if (dbg_busy || dut_vif.dut_cb.debug_mode) return;
    dbg_busy = 1'b1;
    raised = 1'b1;
    dut_vif.dut_cb.debug_req <= 1'b1;
    n_dbg[why] = n_dbg_of(why) + 1;
    fork
      serve_debug_request(why);
    join_none
  endtask

  // Hold the request until the core is in debug mode, then wait for the handler's dret and a quiet
  // gap before the next request may be raised.
  task automatic serve_debug_request(string why);
    int unsigned waited = 0;
    while (dut_vif.dut_cb.debug_mode !== 1'b1 && !test_done) begin
      @(dut_vif.dut_cb);
      if (++waited > dbg_entry_timeout) begin
        `uvm_error(`gfn, $sformatf("debug_req (%0s) held for %0d cycles without debug mode entry",
                                   why, dbg_entry_timeout))
        break;
      end
    end
    dut_vif.dut_cb.debug_req <= 1'b0;
    while (dut_vif.dut_cb.debug_mode === 1'b1 && !test_done) @(dut_vif.dut_cb);
    repeat ($urandom_range(dbg_gap_min, dbg_gap_max)) @(dut_vif.dut_cb);
    dbg_busy = 1'b0;
  endtask

  // The stall and fetch-off triggers may act on the instruction held in ID: not before the program
  // is ready, and not on the WFI the timer interrupt is for until the core has slept on it.
  function bit stall_triggers_allowed();
    if (!program_ready) return 1'b0;
    if (irq_timer_on_wfi && !wfi_slept && dut_vif.dut_cb.wfi === 1'b1) return 1'b0;
    return 1'b1;
  endfunction

  task automatic watch_pipeline();
    bit raised;
    forever begin
      @(dut_vif.dut_cb);
      if (test_done) return;
      if (dut_vif.dut_cb.reset) continue;
      if (dut_vif.dut_cb.ctrl_fsm_cs == ibex_pkg::SLEEP) wfi_slept = 1'b1;
      if (dut_vif.dut_cb.lsu_pmp_err_next) begin
        if (roll(dbg_on_pmp_err_pct)) request_debug("pmp_err", raised);
      end else if (dut_vif.dut_cb.id_instr_held && stall_triggers_allowed()) begin
        if (roll(dbg_on_stall_pct)) request_debug("stall", raised);
        if (!fetch_off_busy && roll(fetch_off_on_stall_pct)) fetch_off();
      end
      if (dut_vif.dut_cb.ctrl_fsm_cs == ibex_pkg::FLUSH && dut_vif.dut_cb.id_stall_mem) begin
        if (roll(dbg_after_flush_pct)) begin
          fork after_flush_debug(); join_none
        end else if (!nmi_busy && roll(nmi_after_flush_pct)) begin
          fork after_flush_nmi(); join_none
        end
      end
    end
  endtask

  // The FLUSH cycle has just ended and the first DECODE (ID empty) starts. A request seen there
  // is taken with the flushed load/store as the last category, so raise it for the second DECODE
  // cycle (1 in 4: the third, in case the handler's first instruction is not there yet).
  task automatic after_flush_debug();
    bit raised;
    repeat (($urandom_range(3) == 0) ? 2 : 1) @(dut_vif.dut_cb);
    request_debug("after_flush", raised);
  endtask

  // The irq agent drives on the falling edge after the next clock event, so a pulse started now is
  // seen from the middle of the second DECODE cycle after the FLUSH (1 in 4: one cycle later). Two
  // cycles long: taken there, or after the handler's first instruction, or not at all.
  task automatic after_flush_nmi();
    nmi_pulse_seq nmi_h;
    nmi_busy = 1'b1;
    if ($urandom_range(3) == 0) @(dut_vif.dut_cb);
    nmi_h = nmi_pulse_seq::type_id::create("nmi_after_flush_h");
    nmi_h.iteration_modes = SingleRun;
    nmi_h.zero_delay_pct = 100;
    nmi_h.min_delay = 2;
    nmi_h.max_delay = 2;
    n_nmi++;
    nmi_h.start(env.vseqr.irq_seqr);
    nmi_busy = 1'b0;
  endtask

  task automatic fetch_off();
    fetch_off_busy = 1'b1;
    n_fetch_off++;
    dut_vif.dut_cb.fetch_enable <= ibex_pkg::IbexMuBiOff;
    fork
      begin
        repeat ($urandom_range(1, 4)) @(dut_vif.dut_cb);
        // After test_done the base test turns fetch off for good; leave it off.
        if (!test_done) dut_vif.dut_cb.fetch_enable <= ibex_pkg::IbexMuBiOn;
        fetch_off_busy = 1'b0;
      end
    join_none
  endtask

  // +gnt_trig offset bit 0x20: irq_nm_i from the second cycle after the grant (the irq agent drives
  // on the falling edge after its next clock event), held until the core takes it, so it is taken
  // at the first point it can be: with the triggering access's instruction or a later one waiting
  // in ID, after they leave (the ID stage is empty when an interrupt is taken).
  task automatic nmi_until_taken();
    nmi_level_seq nmi_h;
    int unsigned  waited = 0;
    nmi_busy = 1'b1;
    n_gnt_nmi++;
    nmi_h = nmi_level_seq::type_id::create("nmi_gnt_raise_h");
    nmi_h.raise = 1'b1;
    nmi_h.start(env.vseqr.irq_seqr);
    do begin
      @(dut_vif.dut_cb);
      if (++waited > dbg_entry_timeout) begin
        `uvm_error(`gfn, $sformatf("NMI (+gnt_trig) held for %0d cycles without being taken",
                                   dbg_entry_timeout))
        break;
      end
    end while (dut_vif.dut_cb.ctrl_fsm_cs != ibex_pkg::IRQ_TAKEN && !test_done);
    nmi_h = nmi_level_seq::type_id::create("nmi_gnt_drop_h");
    nmi_h.raise = 1'b0;
    nmi_h.start(env.vseqr.irq_seqr);
    nmi_busy = 1'b0;
  endtask

  // +gnt_trig offset bit 0x40: fetch_enable_i off from the second cycle after the grant. One cycle
  // later than debug_req, so that an instruction after the access that redirects the PC (a jump in
  // the next cycle) still has its target looked up before fetching stops.
  task automatic gnt_fetch_off();
    fetch_off_busy = 1'b1;
    n_gnt_fetch_off++;
    @(dut_vif.dut_cb);
    dut_vif.dut_cb.fetch_enable <= ibex_pkg::IbexMuBiOff;
    repeat (gnt_fetch_off_cycles) @(dut_vif.dut_cb);
    // After test_done the base test turns fetch off for good; leave it off.
    if (!test_done) dut_vif.dut_cb.fetch_enable <= ibex_pkg::IbexMuBiOn;
    fetch_off_busy = 1'b0;
  endtask

  // Wakes in the time step of the data monitor's clocking event for the grant, as dut_cb's, so a
  // debug request raised here is seen from the cycle after the grant.
  task automatic watch_gnt_trigger();
    ibex_mem_intf_seq_item txn;
    bit [31:0]             off;
    bit                    raised;
    forever begin
      dgnt_port.get(txn);
      if (test_done) return;
      if (!(txn.addr inside {[gnt_trig_lo : gnt_trig_hi]})) continue;
      off = txn.addr - gnt_trig_lo;
      n_gnt_trig++;
      if (off[4]) begin
        request_debug("gnt", raised);
        if (!raised) begin
          `uvm_error(`gfn, $sformatf("+gnt_trig: grant of 0x%08h asks for a debug request, but one is still in progress",
                                     txn.addr))
        end
      end
      if (off[5]) begin
        if (nmi_busy) begin
          `uvm_error(`gfn, $sformatf("+gnt_trig: grant of 0x%08h asks for an NMI, but one is still held",
                                     txn.addr))
        end else begin
          fork nmi_until_taken(); join_none
        end
      end
      if (off[6]) begin
        if (fetch_off_busy) begin
          `uvm_error(`gfn, $sformatf("+gnt_trig: grant of 0x%08h asks for a fetch-enable drop, but one is in progress",
                                     txn.addr))
        end else begin
          fork gnt_fetch_off(); join_none
        end
      end
    end
  endtask

  task automatic watch_dside_errors();
    bit raised;
    forever begin
      // Fires in the time step of the monitor's clocking event for the grant, as dut_cb's.
      @(vseq.data_intf_seq.error_armed);
      if (test_done) return;
      if (roll(dbg_on_dside_err_pct)) request_debug("dside_err", raised);
    end
  endtask

  task automatic raise_timer_on_wfi();
    irq_timer_hold_seq timer_h;
    do @(dut_vif.dut_cb); while (dut_vif.dut_cb.wfi !== 1'b1);
    program_ready = 1'b1;
    timer_h = irq_timer_hold_seq::type_id::create("irq_timer_hold_h");
    timer_h.start(env.vseqr.irq_seqr);
    timer_raised = 1'b1;
    `uvm_info(`gfn, "WFI in ID: irq_timer_i raised and held", UVM_LOW)
  endtask

  // +mem_mode_on_write: see the class header. The response sequence reads dmem_cfg / imem_cfg for
  // every access it answers (ibex_mem_intf_response_seq, _driver), so this applies from the next
  // one. Data-side response delays n..2n+4 keep every range of the sequence's delay distribution
  // non-empty (valid_delay_min + 1 <= valid_delay_max / 2 - 1).
  function automatic void set_mem_mode(bit [31:0] v);
    n_mem_mode++;
    unique case (v[7:0]) inside
      8'd0: begin
        dmem_cfg.zero_delays     = dmem_zero_delays_orig;
        dmem_cfg.valid_delay_min = dmem_valid_min_orig;
        dmem_cfg.valid_delay_max = dmem_valid_max_orig;
      end
      8'd1: begin
        dmem_cfg.zero_delays     = 1'b1;
      end
      [8'd2:8'd29]: begin
        dmem_cfg.zero_delays     = 1'b0;
        dmem_cfg.valid_delay_min = v[7:0];
        dmem_cfg.valid_delay_max = 2 * v[7:0] + 4;
      end
      default: begin
        `uvm_fatal(`gfn, $sformatf("+mem_mode_on_write: data-side mode %0d is not 0, 1 or 2..29 (value 0x%08h)",
                                   v[7:0], v))
      end
    endcase
    unique case (v[23:16]) inside
      8'd0: begin
        imem_cfg.zero_delays     = v[8] ? 1'b1 : imem_zero_delays_orig;
        imem_cfg.valid_delay_min = imem_valid_min_orig;
        imem_cfg.valid_delay_max = imem_valid_max_orig;
      end
      [8'd2:8'd125]: begin
        imem_cfg.zero_delays     = 1'b0;
        imem_cfg.valid_delay_min = v[23:16];
        imem_cfg.valid_delay_max = 2 * v[23:16] + 4;
      end
      default: begin
        `uvm_fatal(`gfn, $sformatf("+mem_mode_on_write: instruction-side mode %0d is not 0 or 2..125 (value 0x%08h)",
                                   v[23:16], v))
      end
    endcase
    `uvm_info(`gfn, $sformatf("memory mode 0x%06h: dside zero_delays %0d, rvalid delay %0d..%0d; iside zero_delays %0d, rvalid delay %0d..%0d",
                              v[23:0], dmem_cfg.zero_delays, dmem_cfg.valid_delay_min,
                              dmem_cfg.valid_delay_max, imem_cfg.zero_delays,
                              imem_cfg.valid_delay_min, imem_cfg.valid_delay_max), UVM_LOW)
  endfunction

  task automatic watch_doorbell();
    ibex_mem_intf_seq_item txn;
    bit                    raised;
    forever begin
      doorbell_port.get(txn);
      if (txn.read_write != WRITE) continue;
      if (mem_mode_on_write != 0 && txn.addr == mem_mode_on_write) begin
        set_mem_mode(txn.data);
        continue;
      end
      if (dbg_req_on_write == 0 || txn.addr != dbg_req_on_write) continue;
      program_ready = 1'b1;
      do begin
        @(dut_vif.dut_cb);
        if (test_done) return;
        request_debug("doorbell", raised);
      end while (!raised);
    end
  endtask

  virtual task send_stimulus();
    `uvm_info(`gfn, "Running core_ibex_stall_events_test", UVM_LOW)
    dmem_zero_delays_orig = dmem_cfg.zero_delays;
    dmem_valid_min_orig   = dmem_cfg.valid_delay_min;
    dmem_valid_max_orig   = dmem_cfg.valid_delay_max;
    imem_zero_delays_orig = imem_cfg.zero_delays;
    imem_valid_min_orig   = imem_cfg.valid_delay_min;
    imem_valid_max_orig   = imem_cfg.valid_delay_max;
    fork
      vseq.start(env.vseqr);
      watch_pipeline();
      if (dbg_on_dside_err_pct != 0) watch_dside_errors();
      if (irq_timer_on_wfi) raise_timer_on_wfi();
      if (dbg_req_on_write != 0 || mem_mode_on_write != 0) watch_doorbell();
      if (gnt_trig_en) watch_gnt_trigger();
    join_none
  endtask

  function void check_fired(string knob, int unsigned pct, int unsigned fired);
    if (pct != 0 && fired == 0) begin
      `uvm_error(`gfn, $sformatf("+%0s is set but its trigger never fired: the program never produced the event",
                                 knob))
    end
  endfunction

  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(`gfn, $sformatf("debug requests raised %p, NMI pulses %0d, fetch-enable drops %0d, timer raised %0d",
                              n_dbg, n_nmi, n_fetch_off, timer_raised), UVM_LOW)
    `uvm_info(`gfn, $sformatf("+gnt_trig grants %0d (NMIs held %0d, fetch-enable drops %0d), memory mode changes %0d",
                              n_gnt_trig, n_gnt_nmi, n_gnt_fetch_off, n_mem_mode), UVM_LOW)
    check_fired("gnt_trig_lo/hi", gnt_trig_en, n_gnt_trig);
    check_fired("mem_mode_on_write", mem_mode_on_write != 0, n_mem_mode);
    check_fired("dbg_on_stall_pct", dbg_on_stall_pct, n_dbg_of("stall"));
    check_fired("dbg_on_pmp_err_pct", dbg_on_pmp_err_pct, n_dbg_of("pmp_err"));
    check_fired("dbg_on_dside_err_pct", dbg_on_dside_err_pct, n_dbg_of("dside_err"));
    check_fired("dbg_after_flush_pct", dbg_after_flush_pct, n_dbg_of("after_flush"));
    check_fired("nmi_after_flush_pct", nmi_after_flush_pct, n_nmi);
    check_fired("fetch_off_on_stall_pct", fetch_off_on_stall_pct, n_fetch_off);
    check_fired("irq_timer_on_wfi", irq_timer_on_wfi, timer_raised);
    check_fired("dbg_req_on_write", dbg_req_on_write != 0, n_dbg_of("doorbell"));
  endfunction

endclass

class core_ibex_mcounteren_lock_test extends core_ibex_base_test;
  `uvm_component_utils(core_ibex_mcounteren_lock_test)
  `uvm_component_new

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    // Relaxes co-simulation tracking so mismatches during lock don't abort
    cosim_cfg.relax_cosim_check = 1'b1;
  endfunction

  virtual task send_stimulus();
    // Fork the binary execution in the background
    fork
      vseq.start(env.vseqr);
    join_none

    // Wait for a write to MCYCLE to indicate locking the mcounteren CSRs
    wait_for_live_csr_write(CSR_MCYCLE);
    dut_vif.dut_cb.mcounteren_writable <= ibex_pkg::IbexMuBiOff;
    `uvm_info(`gfn, "Write to MCYCLE: locking mcounteren!", UVM_LOW)

    // Wait for a write to MCYCLEH to indicate unlocking the mcounteren CSRs
    wait_for_live_csr_write(CSR_MCYCLEH);
    dut_vif.dut_cb.mcounteren_writable <= ibex_pkg::IbexMuBiOn;
    `uvm_info(`gfn, "Write to MCYCLEH: unlocking mcounteren!", UVM_LOW)
  endtask

  // Snoop the CSR interface to catch writes to the specified CSR addresses
  task wait_for_live_csr_write(bit [11:0] addr);
    forever begin
      @(csr_vif.csr_cb);
      if (csr_vif.csr_cb.csr_access === 1'b1 &&
          csr_vif.csr_cb.csr_addr   === addr &&
          csr_vif.csr_cb.csr_op     != CSR_OP_READ) begin
        break;
      end
    end
  endtask

endclass

// ---------------------------------------------------------------------------------------------
// CHERIoT-mode trap, debug and memory-error tests. Each drives a self-checking directed program
// in directed_tests/ (cheriot_irq_cheri, cheriot_debug_mode, cheriot_mem_err) that speaks the
// riscv-dv signature handshake from a CHERIoT-correct trap handler.
// ---------------------------------------------------------------------------------------------

// Interrupts with cheriot_enable_i asserted (+enable_cheriot_seq=1, CHERIoT-Sail oracle on).
//
// Same flow as core_ibex_debug_intr_basic_test with +enable_irq_single_seq, with two changes:
//  - Only timer, external and software interrupts. CHERIoT-Sail models neither NMI nor the ibex
//    fast interrupts (its legalize_mie keeps only MEIE/MTIE/MSIE, and the scoreboard does not
//    hand NMIs to the model), so either would make the oracle diverge rather than test anything.
//  - mip is not read back by the handler. The CHERIoT-Sail DPI receives the DUT's pending bits
//    only inside cheriot_sail_cosim_take_interrupt(), so a `csrr mip` reads the model's stale mip
//    and mismatches. The interrupt identity is still checked through mcause, and that the line
//    the agent raised is the one taken is checked against the agent's own transaction.
class core_ibex_cheriot_irq_test extends core_ibex_debug_intr_basic_test;

  `uvm_component_utils(core_ibex_cheriot_irq_test)
  `uvm_component_new

  int unsigned irqs_checked;

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!cfg.enable_cheriot_seq) begin
      `uvm_fatal(`gfn, "core_ibex_cheriot_irq_test needs +enable_cheriot_seq=1")
    end
    if (cfg.enable_irq_nmi_seq || cfg.enable_nested_irq || cfg.enable_irq_multiple_seq) begin
      `uvm_fatal(`gfn, {"core_ibex_cheriot_irq_test supports +enable_irq_single_seq only: ",
                        "NMIs are not modelled by CHERIoT-Sail"})
    end
  endfunction

  virtual task send_irq_stimulus(bit no_nmi = 1'b0, bit no_fast = 1'b0);
    super.send_irq_stimulus(.no_nmi(1'b1), .no_fast(1'b1));
  endtask

  virtual task check_irq_handle();
    // callee_id runs 150 loop iterations with MIE=0 (interrupt-disabling sentry): ~7.3k cycles
    // at slow fetch latency before the IRQ can be taken, so 7500 timed out (seed 22756).
    check_next_core_status(HANDLING_IRQ, "Core did not jump to the MTCC interrupt handler", 20000);
    check_priv_mode(PRIV_LVL_M);
    operating_mode = dut_vif.dut_cb.priv_mode;
    wait_for_csr_write(CSR_MSTATUS, 5000);
    mstatus = signature_data;
    `DV_CHECK_EQ_FATAL(mstatus[12:11], PRIV_LVL_M, "mstatus.mpp is not M after the interrupt")
    `DV_CHECK_EQ_FATAL(mstatus[7], 1'b1, "mstatus.mpie was not set to 1'b1 after entering handler")
    `DV_CHECK_EQ_FATAL(mstatus[3], 1'b0, "mstatus.mie was not set to 1'b0 after entering handler")
    check_mcause(1'b1, irq_id);
    wait_for_csr_write(CSR_MIE, 5000);
    mie = signature_data;
    `DV_CHECK_EQ_FATAL(mie[irq_id], 1'b1,
        $sformatf("mie[%0d] is not set, but core responded to corresponding interrupt", irq_id))
    `DV_CHECK_EQ_FATAL(irq[irq_id], 1'b1,
        $sformatf("core took interrupt %0d, which the agent did not raise (0x%0x)", irq_id, irq))
    irqs_checked++;
  endtask

  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(`gfn, $sformatf("%0d CHERIoT-mode interrupts checked", irqs_checked), UVM_LOW)
    if (irqs_checked == 0) begin
      `uvm_error(`gfn, "No interrupt was taken and checked")
    end
  endfunction

endclass

// Debug mode with cheriot_enable_i asserted. Phase 1: one debug request, checked as in
// send_debug_stimulus (IN_DEBUG_MODE, dcsr.prv, dcsr.cause = haltreq, dret); the program then
// drives the deterministic ebreak/single-step/invalid-DEPCC scenarios itself. Phase 2 starts when
// the program reports IN_MACHINE_MODE: random debug requests until the end of the test.
class core_ibex_cheriot_debug_test extends core_ibex_directed_test;

  `uvm_component_utils(core_ibex_cheriot_debug_test)
  `uvm_component_new

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!cfg.enable_debug_seq || !cfg.require_signature_addr) begin
      `uvm_fatal(`gfn, "core_ibex_cheriot_debug_test needs +enable_debug_seq=1 +require_signature_addr=1")
    end
  endfunction

  virtual task check_stimulus();
    send_debug_stimulus(init_operating_mode, "Core did not enter debug mode (CHERIoT mode)");
    wait_for_core_status(IN_MACHINE_MODE);
    `uvm_info(`gfn, "Program reached phase 2: starting random debug requests", UVM_LOW)
    stress_debug();
  endtask

endclass

// Bus and integrity errors with cheriot_enable_i asserted. The errors are injected by address
// (the +{d,i}side_{bus,intg}_err_{lo,hi} windows of ibex_mem_intf_response_seq), so the program
// alone decides which access sees one. Integrity errors raise alert_major_bus_o by design, so
// NoAlertsTriggered is switched off and replaced by a narrower check: no minor or internal major
// alert ever, and at least +cheriot_mem_err_min_bus_alerts (default 4, one per integrity probe in
// cheriot_mem_err) bus-alert episodes.
class core_ibex_cheriot_mem_err_test extends core_ibex_base_test;

  `uvm_component_utils(core_ibex_cheriot_mem_err_test)
  `uvm_component_new

  int unsigned min_bus_alerts = 4;
  int unsigned bus_alerts;
  int unsigned other_alerts;

  virtual task run_phase(uvm_phase phase);
    void'($value$plusargs("cheriot_mem_err_min_bus_alerts=%0d", min_bus_alerts));
    `DV_ASSERT_CTRL_REQ("tb_no_alerts_triggered", 1'b0)
    fork
      monitor_alerts();
    join_none
    super.run_phase(phase);
  endtask

  task monitor_alerts();
    bit prev_bus;
    forever begin
      @(dut_vif.dut_cb);
      if (dut_vif.dut_cb.alert_minor || dut_vif.dut_cb.alert_major_internal) begin
        other_alerts++;
      end
      if (dut_vif.dut_cb.alert_major_bus && !prev_bus) bus_alerts++;
      prev_bus = dut_vif.dut_cb.alert_major_bus;
    end
  endtask

  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(`gfn, $sformatf("bus-alert episodes: %0d, other alert cycles: %0d",
                              bus_alerts, other_alerts), UVM_LOW)
    if (other_alerts != 0) begin
      `uvm_error(`gfn, $sformatf("%0d cycles with a minor or internal major alert", other_alerts))
    end
    if (bus_alerts < min_bus_alerts) begin
      `uvm_error(`gfn, $sformatf("Only %0d bus-alert episodes; every injected integrity error must raise alert_major_bus_o (expected >= %0d)",
                                 bus_alerts, min_bus_alerts))
    end
  endfunction

endclass

// A trap taken while MTCC is untagged (directed_tests/cheriot_fatal_err_mtcc). The RTL records it
// in the sticky cheriot_fatal_err_q (ibex_cs_registers.sv gen_scr: "fatal error condition
// (unrecoverable, need external reset)") and raises alert_major_internal_o; the core is then stuck
// re-trapping to the untagged MTCC and the program can never reach the signature handshake, so the
// verdict is taken here. The program announces the trap with CORE_STATUS HANDLING_EXCEPTION;
// from that point this test requires:
//  - the first trap after the announcement is the program's ecall (mcause 11), within
//    +cheriot_fatal_trap_timeout cycles, with alert_major_internal_o still low when it is taken;
//  - alert_major_internal_o within +cheriot_fatal_alert_latency cycles of the trap, then held for
//    +cheriot_fatal_hold_cycles cycles (sticky: nothing short of a reset clears it);
//  - no alert of any kind before the announcement, and no minor or bus alert at any time.
// It then ends the run (wait_for_custom_test_done, as core_ibex_mem_error_test does). The spec
// leaves a trap through an untagged MTCC undefined (REQ_PER_03); the alert is the RTL's stated
// design intent, checked here until the spec takes a position. NoAlertsTriggered is off for the
// whole run, replaced by the checks above. The double-fault detector is off: every re-trap after
// the first is a double fault by construction, and its fatal threshold would end the run first.
class core_ibex_cheriot_fatal_err_test extends core_ibex_base_test;

  `uvm_component_utils(core_ibex_cheriot_fatal_err_test)
  `uvm_component_new

  int unsigned trap_timeout  = 20000;
  int unsigned alert_latency = 4;
  int unsigned hold_cycles   = 2000;
  bit          armed;
  bit          checked;
  int unsigned early_alert_cycles;
  int unsigned other_alert_cycles;

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    void'($value$plusargs("cheriot_fatal_trap_timeout=%0d", trap_timeout));
    void'($value$plusargs("cheriot_fatal_alert_latency=%0d", alert_latency));
    void'($value$plusargs("cheriot_fatal_hold_cycles=%0d", hold_cycles));
    if (!cfg.enable_cheriot_seq && cfg.cheriot_enable_on_write == 0) begin
      `uvm_fatal(`gfn, {"core_ibex_cheriot_fatal_err_test needs cheriot_enable_i On ",
                        "(+enable_cheriot_seq=1 or +cheriot_enable_on_write)"})
    end
    cfg.enable_double_fault_detector = 1'b0;
  endfunction

  virtual task run_phase(uvm_phase phase);
    `DV_ASSERT_CTRL_REQ("tb_no_alerts_triggered", 1'b0)
    fork
      monitor_alerts();
    join_none
    super.run_phase(phase);
  endtask

  task monitor_alerts();
    forever begin
      @(dut_vif.dut_cb);
      if (dut_vif.dut_cb.reset) continue;
      if (dut_vif.dut_cb.alert_minor || dut_vif.dut_cb.alert_major_bus) other_alert_cycles++;
      if (dut_vif.dut_cb.alert_major_internal && !armed) early_alert_cycles++;
    end
  endtask

  virtual task wait_for_custom_test_done();
    bit                   trap_seen;
    bit                   alert_up;
    ibex_pkg::exc_cause_t cause;

    wait_for_core_status(HANDLING_EXCEPTION);
    armed = 1'b1;
    `uvm_info(`gfn, "Program armed the trap through an untagged MTCC", UVM_LOW)

    fork begin : isolation_fork
      fork
        begin
          wait (dut_vif.csr_save_cause === 1'b1 && dut_vif.ctrl_fsm_cs == ibex_pkg::FLUSH);
          trap_seen = 1'b1;
        end
        clk_vif.wait_clks(trap_timeout);
      join_any
      disable fork;
    end join
    if (!trap_seen) begin
      `uvm_fatal(`gfn, $sformatf("No trap within %0d cycles of the program arming it",
                                 trap_timeout))
    end
    cause = dut_vif.exc_cause;
    if (cause != ibex_pkg::ExcCauseEcallMMode) begin
      `uvm_error(`gfn, $sformatf({"First trap after arming has cause 0x%0x (irq_ext %0b, irq_int ",
                                  "%0b), expected the program's ecall (11)"},
                                 cause.lower_cause, cause.irq_ext, cause.irq_int))
    end
    if (dut_vif.alert_major_internal !== 1'b0) begin
      `uvm_error(`gfn, "alert_major_internal_o was already high when the trap was taken")
    end

    for (int unsigned i = 0; i <= alert_latency; i++) begin
      @(dut_vif.dut_cb);
      if (dut_vif.dut_cb.alert_major_internal) begin
        alert_up = 1'b1;
        `uvm_info(`gfn, $sformatf("alert_major_internal_o raised %0d cycle(s) after the trap",
                                  i + 1), UVM_LOW)
        break;
      end
    end
    if (!alert_up) begin
      `uvm_error(`gfn, $sformatf({"Trap with an untagged MTCC: alert_major_internal_o not raised ",
                                  "within %0d cycles (cheriot_fatal_err_q)"}, alert_latency))
    end else begin
      for (int unsigned i = 0; i < hold_cycles; i++) begin
        @(dut_vif.dut_cb);
        if (!dut_vif.dut_cb.alert_major_internal) begin
          `uvm_error(`gfn, $sformatf({"alert_major_internal_o dropped %0d cycles after it was ",
                                      "raised; the fatal error must hold until reset"}, i + 1))
          break;
        end
      end
    end
    checked = 1'b1;
    `uvm_info(`gfn, "Test done: fatal-error check on a trap through an untagged MTCC complete",
              UVM_LOW)
  endtask

  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    if (!checked) begin
      `uvm_error(`gfn, "The run ended before the fatal-error check completed")
    end
    if (early_alert_cycles != 0) begin
      `uvm_error(`gfn, $sformatf("alert_major_internal_o high for %0d cycles before the trap was armed",
                                 early_alert_cycles))
    end
    if (other_alert_cycles != 0) begin
      `uvm_error(`gfn, $sformatf("%0d cycles with a minor or bus alert", other_alert_cycles))
    end
  endfunction

endclass
