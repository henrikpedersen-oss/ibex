// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// The scoreboard: it receives sequence items on analysis FIFOs, the actual side (RVFI, the UARTs'
// bytes) and the expected side (the reference model's verdict per instruction, the SystemC model's
// UART bytes), and compares them. Every item is counted and written to <name>.chip.log in the run
// directory; a UART the test must reach that saw nothing is an error.
//
// Instruction comparator: soc_rvfi_exp_item carries the ISS's verdict on each retired instruction
// (soc_iss_wrapper); a mismatch is reported with the chip's last instructions before it.
//
// Plusargs:
//   +soc_sb_log=0                 no per-item logs (counts only)
//   +sb_corrupt=<check>.<field>   checker fault injection: rvfi.count, uart<N>.count (the count is
//                                 zeroed before it is checked); insn.rd, insn.cheriot_rd (one
//                                 register result corrupted before the ISS checks it). The run must
//                                 fail.

class soc_cosim_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(soc_cosim_scoreboard)

  soc_cosim_cfg cfg;

  // Actual side.
  uvm_tlm_analysis_fifo #(soc_rvfi_item) rvfi_fifo;
  uvm_tlm_analysis_fifo #(soc_byte_item) uart_fifo;
  // Expected side: the reference model's verdict per retired instruction.
  uvm_tlm_analysis_fifo #(soc_rvfi_exp_item) rvfi_exp_fifo;

  // Set by the environment: whether there is an RVFI source, and whether the ISS check runs.
  bit rvfi_enabled;
  bit insn_enabled;

  protected int unsigned rvfi_count;
  protected int unsigned insn_count;
  protected int unsigned insn_mismatches;
  // The chip's last instructions, printed with a mismatch.
  protected string       history[$];
  localparam int unsigned HistoryLen = 8;
  protected int unsigned uart_count[];
  protected bit          en_log = 1'b1;
  protected int          rvfi_log;
  protected int          uart_log[];
  protected string       sb_corrupt;

`ifdef SOC_COSIM_SYSMODEL
  // Each UART's sent bytes compared with the SystemC model's, in order; the bytes the chip received
  // go into the model.
  protected string       uart_act[][$];
  protected int unsigned uart_compared[];
  protected int unsigned uart_mismatched[];
  // The model's items the chip had not sent when the run ended (a byte still on the line).
  localparam int unsigned UartInFlight = 2;
`endif

  `uvm_component_new

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    rvfi_fifo     = new("rvfi_fifo", this);
    rvfi_exp_fifo = new("rvfi_exp_fifo", this);
    uart_fifo     = new("uart_fifo", this);
    uart_count = new[cfg.num_uarts];
    uart_log   = new[cfg.num_uarts];
`ifdef SOC_COSIM_SYSMODEL
    uart_act        = new[cfg.num_uarts];
    uart_compared   = new[cfg.num_uarts];
    uart_mismatched = new[cfg.num_uarts];
`endif
    void'($value$plusargs("soc_sb_log=%b", en_log));
    void'($value$plusargs("sb_corrupt=%s", sb_corrupt));
    if (sb_corrupt != "" && !(sb_corrupt inside {"rvfi.count", "insn.rd", "insn.cheriot_rd"}) &&
        !(sb_corrupt.substr(0, 3) == "uart" && sb_corrupt.len() > 10 &&
          sb_corrupt.substr(sb_corrupt.len() - 6, sb_corrupt.len() - 1) == ".count")) begin
      `uvm_fatal(`gfn, $sformatf("+sb_corrupt=%s: no such check.field", sb_corrupt))
    end
  endfunction

  function void start_of_simulation_phase(uvm_phase phase);
    super.start_of_simulation_phase(phase);
    if (!en_log) return;
    if (rvfi_enabled) rvfi_log = open_log("rvfi.chip.log");
    foreach (uart_log[i]) uart_log[i] = open_log($sformatf("uart%0d.chip.log", i));
  endfunction

  virtual task run_phase(uvm_phase phase);
    fork
      collect_rvfi();
      compare_insn();
      collect_uart();
    join_none
  endtask

  protected task collect_rvfi();
    soc_rvfi_item item;
    forever begin
      rvfi_fifo.get(item);
      if (!item.reset) rvfi_count++;
      if (rvfi_log) $fdisplay(rvfi_log, "%s", item.log_line());
    end
  endtask

  // Instruction comparator: the reference model's verdict on each instruction it stepped.
  protected task compare_insn();
    soc_rvfi_exp_item exp;
    forever begin
      rvfi_exp_fifo.get(exp);
      insn_count++;
      if (!exp.match) begin
        string last;
        insn_mismatches++;
        foreach (history[i]) last = {last, "\n    ", history[i]};
        `uvm_error(`gfn, $sformatf({"SOC_SB insn mismatch at order %0d pc %08h: %s",
                                    "\n  chip: %s\n  instructions before it:%s"},
                                   exp.order, exp.pc, exp.errors, exp.act.log_line(), last))
      end
      history.push_back(exp.act.log_line());
      if (history.size() > HistoryLen) void'(history.pop_front());
    end
  endtask

  protected task collect_uart();
    soc_byte_item b;
    forever begin
      uart_fifo.get(b);
      soc_cosim_record::uart(b);
      if (b.idx >= cfg.num_uarts) begin
        `uvm_error(`gfn, $sformatf("SOC_SB uart%0d: only %0d UARTs configured", b.idx, cfg.num_uarts))
        continue;
      end
      if (b.rx) begin
`ifdef SOC_COSIM_SYSMODEL
        soc_sysmodel::give_input($sformatf("uart%0d.rx", b.idx), b.data);
`endif
        continue;
      end
      uart_count[b.idx]++;
      if (uart_log[b.idx]) $fdisplay(uart_log[b.idx], "%s", byte_text(b.data));
`ifdef SOC_COSIM_SYSMODEL
      uart_act[b.idx].push_back(byte_text(b.data));
      compare_uart(b.idx);
`endif
    end
  endtask

  static function string byte_text(bit [7:0] d);
    return $sformatf("%02h %s", d, (d inside {[8'h20:8'h7e]}) ? string'(d) : ".");
  endfunction

`ifdef SOC_COSIM_SYSMODEL
  // The chip's items against the model's, in order, as far as both have come (the model's time
  // follows the chip's; its item can come a little after the chip's).
  protected function void compare_uart(int idx);
    string inst = $sformatf("uart%0d", idx);
    if (!soc_sysmodel::active() || soc_sysmodel::stop_reason() != "") return;
    soc_sysmodel::step();
    while (uart_act[idx].size() > 0 && soc_sysmodel::pending(inst) > 0) begin
      string act = uart_act[idx].pop_front();
      string exp = soc_sysmodel::pull(inst);
      uart_compared[idx]++;
      if (soc_sysmodel::corrupt == inst && uart_compared[idx] == 10) begin
        act = "00 .";  // +soc_model_corrupt=uart<N>: the run must fail
        `uvm_info(`gfn, $sformatf("+soc_model_corrupt=%s: item 10 corrupted", inst), UVM_LOW)
      end
      if (act != exp) begin
        uart_mismatched[idx]++;
        `uvm_error(`gfn, $sformatf("SOC_SB %s item %0d: chip \"%s\", model \"%s\"", inst,
                                   uart_compared[idx], act, exp))
      end
    end
  endfunction

  // At the end: what is left on either side.
  protected function void check_uart_end(int idx);
    string inst = $sformatf("uart%0d", idx);
    int    left;
    if (!soc_sysmodel::active()) return;
    compare_uart(idx);
    if (soc_sysmodel::stop_reason() != "") begin
      if (uart_act[idx].size() > 0) begin
        `uvm_info(`gfn, $sformatf("SOC_SB %s: %0d items after the model stopped, not compared",
                                  inst, uart_act[idx].size()), UVM_LOW)
      end
      return;
    end
    if (uart_act[idx].size() > 0) begin
      `uvm_error(`gfn, $sformatf("SOC_SB %s: the chip sent %0d items the model does not (first \"%s\")",
                                 inst, uart_act[idx].size(), uart_act[idx][0]))
    end
    left = soc_sysmodel::pending(inst);
    if (left > UartInFlight) begin
      `uvm_error(`gfn, $sformatf("SOC_SB %s: the model sent %0d items the chip did not (first \"%s\")",
                                 inst, left, soc_sysmodel::pull(inst)))
    end else if (left > 0) begin
      `uvm_info(`gfn, $sformatf("SOC_SB %s: %0d model items still in flight at the end", inst,
                                left), UVM_LOW)
    end
  endfunction
`endif

  function void report_phase(uvm_phase phase);
    string table_s;
    super.report_phase(phase);
    if (sb_corrupt == "rvfi.count") rvfi_count = 0;
    foreach (uart_count[i]) if (sb_corrupt == $sformatf("uart%0d.count", i)) uart_count[i] = 0;
    table_s = $sformatf("\n  rvfi   %0d%s", rvfi_count, rvfi_enabled ? "" : " (no RVFI source)");
    table_s = {table_s, $sformatf("\n  insn   %0d compared, %0d mismatched%s", insn_count,
                                  insn_mismatches, insn_enabled ? "" : " (no reference model)")};
    foreach (uart_count[i]) table_s = {table_s, $sformatf("\n  uart%0d  %0d", i, uart_count[i])};
`ifdef SOC_COSIM_SYSMODEL
    foreach (uart_act[i]) check_uart_end(i);
    foreach (uart_compared[i]) begin
      table_s = {table_s, $sformatf("\n  uart%0d  %0d compared with the SystemC model, %0d mismatched",
                                    i, uart_compared[i], uart_mismatched[i])};
    end
    table_s = {table_s, "\n  model  ", soc_sysmodel::summary()};
`endif
    `uvm_info(`gfn, {"SOC_SB counts (items seen per monitor):", table_s}, UVM_LOW)

    if (insn_enabled && insn_count == 0) begin
      `uvm_error(`gfn, "SOC_SB insn: the reference model compared no instruction")
    end
    if (rvfi_enabled && rvfi_count == 0) begin
      `uvm_error(`gfn, "SOC_SB rvfi: there is an RVFI source but no instruction retired")
    end
    foreach (uart_count[i]) begin
      if (i < cfg.uart_required.size() && cfg.uart_required[i] && uart_count[i] == 0) begin
        `uvm_error(`gfn, $sformatf("SOC_SB uart%0d: the test uses it but its monitor saw nothing", i))
      end
    end
  endfunction

  function void final_phase(uvm_phase phase);
    super.final_phase(phase);
    if (rvfi_log) $fclose(rvfi_log);
    foreach (uart_log[i]) if (uart_log[i]) $fclose(uart_log[i]);
    soc_cosim_record::close();
  endfunction

  protected function int open_log(string name);
    int fd = $fopen(name, "w");
    if (!fd) `uvm_error(`gfn, $sformatf("SOC_SB cannot open %s", name))
    return fd;
  endfunction
endclass
