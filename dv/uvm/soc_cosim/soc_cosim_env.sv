// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// The checking stack as one environment: an RVFI source (the monitor on soc_cosim_if, or a replay
// of a recording), the ISS (soc_iss_wrapper), and the scoreboard. The SoC's environment creates it,
// gives it a soc_cosim_cfg before build, puts the interface in the config DB as "soc_cosim_vif",
// and writes its UARTs' bytes to uart_export (soc_byte_item). +soc_cosim_replay=<file> replaces the
// RTL with a recording: the configuration then comes from the recording too.

class soc_cosim_env extends uvm_env;
  `uvm_component_utils(soc_cosim_env)

  soc_cosim_cfg        cfg;
  soc_rvfi_monitor     monitor;
  soc_cosim_replay     replay;
  soc_iss_wrapper      iss;
  soc_cosim_scoreboard sb;
  // The SoC's UART bytes (sent and received) into the scoreboard.
  uvm_analysis_export #(soc_byte_item) uart_export;

  `uvm_component_new

  function void build_phase(uvm_phase phase);
    int           replay_fd;
    string        pending;
    soc_cosim_cfg replay_cfg;
    soc_cosim_vif vif;
    super.build_phase(phase);
    replay_cfg = soc_cosim_replay::read_cfg(replay_fd, pending);
    if (replay_cfg != null) begin
      cfg    = replay_cfg;
      replay = soc_cosim_replay::type_id::create("replay", this);
      replay.set_source(replay_fd, pending);
    end else begin
      if (cfg == null) `uvm_fatal(`gfn, "soc_cosim_env: no soc_cosim_cfg (set env.cfg before build)")
      if (uvm_config_db#(soc_cosim_vif)::get(this, "", "soc_cosim_vif", vif)) begin
        monitor     = soc_rvfi_monitor::type_id::create("monitor", this);
        monitor.vif = vif;
      end else begin
        `uvm_info(`gfn, "No RVFI interface (soc_cosim_vif): the checking stack is off", UVM_LOW)
      end
    end
    iss         = soc_iss_wrapper::type_id::create("iss", this);
    sb          = soc_cosim_scoreboard::type_id::create("sb", this);
    iss.cfg     = cfg;
    sb.cfg      = cfg;
    uart_export = new("uart_export", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    bit source = monitor != null || replay != null;
    super.connect_phase(phase);
    if (monitor != null) begin
      monitor.analysis_port.connect(iss.rvfi_fifo.analysis_export);
      monitor.analysis_port.connect(sb.rvfi_fifo.analysis_export);
    end
    if (replay != null) begin
      replay.rvfi_port.connect(iss.rvfi_fifo.analysis_export);
      replay.rvfi_port.connect(sb.rvfi_fifo.analysis_export);
      replay.uart_port.connect(sb.uart_fifo.analysis_export);
`ifdef SOC_COSIM_SYSMODEL
      replay.model_hook = soc_sysmodel_hook::get();
`endif
    end
    uart_export.connect(sb.uart_fifo.analysis_export);
    iss.exp_port.connect(sb.rvfi_exp_fifo.analysis_export);
    iss.enabled     = source;
    sb.rvfi_enabled = source;
    sb.insn_enabled = source && soc_iss_wrapper::compiled() && cfg.iss_off_reason == "";
  endfunction

  function void start_of_simulation_phase(uvm_phase phase);
    super.start_of_simulation_phase(phase);
    if (replay == null && monitor != null) soc_cosim_record::open(cfg);
  endfunction

  // The testbench's UART bytes (soc_cosim_tb_link) into the scoreboard.
  virtual task run_phase(uvm_phase phase);
    if (replay != null) return;
    forever begin
      while (soc_cosim_tb_link::bytes.size() == 0) #(1us);
      sb.uart_fifo.analysis_export.write(soc_cosim_tb_link::bytes.pop_front());
    end
  endtask

  // Waits until the testbench asks the run to end (soc_cosim_tb_link::request_end).
  static task wait_end();
    while (!soc_cosim_tb_link::end_requested) #(1us);
  endtask
endclass

// A test that runs the checking stack on a recording, with no RTL (soc_cosim_replay_tb.sv).
class soc_cosim_replay_test extends uvm_test;
  `uvm_component_utils(soc_cosim_replay_test)

  soc_cosim_env env;

  `uvm_component_new

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = soc_cosim_env::type_id::create("env", this);
  endfunction

  function void report_phase(uvm_phase phase);
    uvm_report_server rs = uvm_report_server::get_server();
    super.report_phase(phase);
    if (rs.get_severity_count(UVM_ERROR) + rs.get_severity_count(UVM_FATAL) == 0) begin
      `uvm_info(`gfn, "SOC_COSIM REPLAY PASSED", UVM_LOW)
    end else begin
      `uvm_info(`gfn, "SOC_COSIM REPLAY FAILED", UVM_LOW)
    end
  endfunction
endclass
