// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

typedef class ibex_dii_agent;

// Injects DII instructions at the fetch output (the DII_SIM blocks in ibex_fetch_fifo.sv and
// ibex_icache.sv) and handles the end-of-test reset. Every item gets exactly one response;
// end_of_test is set once per test, which is what the instruction source turns into its single halt.
//
// Every injected word the core takes is handed to the scoreboard, which steps the reference model
// with it and checks that the core retired that word. Before the closing reset one probe NOP is
// injected (and not reported to the instruction source), so the last instruction of a test has a
// successor: a trap or mret there has its target checked like any other.
//
// A test that cannot complete (no dii_ack, an instruction that never retires, an incomplete drain)
// is a UVM_ERROR: a hung core must not pass.
//
// Plusargs:
//   +dii_drain_timeout=<n> cycles to wait for injected instructions to retire at the end of a
//                         test before resetting anyway (default 1000)
//   +dii_ack_timeout=<n>  cycles to wait for ibex to take an instruction before aborting the
//                         test (default 32)
//   +dii_retire_timeout=<n> cycles to wait for an injected instruction to retire before
//                         offering the next; exceeding it aborts the test (default 200)
class ibex_dii_driver extends uvm_driver #(ibex_dii_seq_item);
  `uvm_component_utils(ibex_dii_driver)
  `uvm_component_new

  // Filler for the interrupt barrier slot and the end-of-test probe: retires harmlessly.
  localparam bit [31:0] DII_DRAIN_INSN = 32'h0000_0013; // addi x0, x0, 0

  ibex_dii_agent agent;

  protected virtual core_ibex_dii_intf dii_vif;
  protected virtual clk_rst_if         clk_vif;

  int unsigned ack_timeout    = 32;
  int unsigned drain_timeout  = 1000;
  int unsigned retire_timeout = 200;

  // Per-test state, counted here on dii_ack.
  protected bit          insn_injected;
  protected int unsigned num_injected;
  // Set when a test was aborted; its remaining instructions and closing RST are swallowed.
  protected bit          test_aborted;

  int unsigned num_aborted_tests;
  int unsigned num_drain_timeouts;

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual clk_rst_if)::get(this, "", "clk_if", clk_vif)) begin
      `uvm_fatal(`gfn, "clk_if must be provided")
    end
    if (!uvm_config_db#(virtual core_ibex_dii_intf)::get(this, "", "dii_if", dii_vif)) begin
      `uvm_fatal(`gfn, "dii_if must be provided")
    end
    void'($value$plusargs("dii_ack_timeout=%d", ack_timeout));
    void'($value$plusargs("dii_drain_timeout=%d", drain_timeout));
    void'($value$plusargs("dii_retire_timeout=%d", retire_timeout));
  endfunction

  virtual task run_phase(uvm_phase phase);
    clk_vif.wait_for_reset();
    @(dii_vif.cb);

    forever begin
      seq_item_port.get_next_item(req);
      $cast(rsp, req.clone());
      rsp.set_id_info(req);
      rsp.end_of_test = 1'b0;
      rsp.aborted     = 1'b0;
      `uvm_info(`gfn, $sformatf("DII %s 0x%08x", req.cmd.name(), req.insn), UVM_HIGH)

      case (req.cmd)
        DII_CMD_RST:          end_test();
        DII_CMD_INSN:         inject(req.insn);
        DII_CMD_INTR_REQ:     raise_irq(req.insn[3:0]);
        DII_CMD_INTR_BARRIER: irq_barrier();
        default: `uvm_fatal(`gfn, $sformatf("Unhandled DII command %s", req.cmd.name()))
      endcase

      seq_item_port.item_done(rsp);
    end
  endtask : run_phase

  protected task end_test();
    if (test_aborted) begin
      // Already drained, reset and halted when the test was aborted.
      `uvm_info(`gfn, "RST after an aborted test: discarded", UVM_MEDIUM)
      test_aborted = 1'b0;
    end else if (!insn_injected) begin
      // TestRIG sends an empty test first. Resetting with nothing in flight has previously
      // looped until xmsim aborted, so just report the (empty) test as complete.
      `uvm_info(`gfn, "RST with no instructions injected: halt without reset", UVM_MEDIUM)
      rsp.end_of_test = 1'b1;
    end else begin
      // The instruction source has had a reply for every instruction it sent; the probe's
      // retirement is the scoreboard's alone.
      agent.hold_rvfi(num_injected);
      inject(DII_DRAIN_INSN);
      if (test_aborted) begin
        // The probe could not complete: abort_test() has drained, reset and set end_of_test,
        // and this RST is the one that closes the test.
        test_aborted = 1'b0;
        return;
      end
      drain_and_reset();
      rsp.end_of_test = 1'b1;
    end
  endtask

  protected task inject(bit [31:0] insn);
    int unsigned wait_cycles;
    bit          retired;

    if (test_aborted) begin
      `uvm_info(`gfn, $sformatf("Aborted test: skipping 0x%08x", insn), UVM_HIGH)
      return;
    end

    // Offer the instruction; the fetch FIFO consumes it once (dii_ack).
    dii_vif.set_dii_insn(insn);
    dii_vif.set_dii_ready(1'b1);
    @(dii_vif.cb);
    while (!dii_vif.cb.dii_ack) begin
      if (++wait_cycles > ack_timeout) begin
        abort_test($sformatf("No dii_ack for 0x%08x within %0d cycles after %0d instructions",
                             insn, ack_timeout, num_injected));
        return;
      end
      @(dii_vif.cb);
    end
    dii_vif.set_dii_ready(1'b0);
    insn_injected = 1'b1;
    num_injected++;
    agent.scoreboard.injected(insn);

    // One instruction in flight: offer the next only once this one has retired (or trapped),
    // so a redirect (branch, jump, trap, fence.i) never flushes an instruction already taken.
    wait_retired(retire_timeout, retired);
    if (!retired) begin
      abort_test($sformatf("0x%08x did not retire within %0d cycles (instruction %0d)",
                           insn, retire_timeout, num_injected));
    end
  endtask

  protected task abort_test(string why);
    dii_vif.set_dii_ready(1'b0);
    `uvm_error(`gfn, {why, ": aborting test"})
    drain_and_reset();
    test_aborted    = 1'b1;
    rsp.end_of_test = 1'b1;
    rsp.aborted     = 1'b1;
    num_aborted_tests++;
  endtask

  // Waits (bounded) until every injected instruction has retired.
  // The outer fork isolates the race so `disable fork` cancels only the losing branch.
  // The result goes through a member, not the output argument: IEEE 1800-2023 13.2.2 forbids
  // writing an automatic task's output after a timing control (Verilator enforces it).
  protected bit wait_retired_result;
  protected task wait_retired(int unsigned timeout, output bit retired);
    wait_retired_result = 1'b0;
    fork begin
      fork
        begin
          wait (dii_vif.instr_out >= num_injected);
          wait_retired_result = 1'b1;
        end
        repeat (timeout) @(dii_vif.cb);
      join_any
      disable fork;
    end join
    retired = wait_retired_result;
  endtask

  // Everything injected has normally retired already (one in flight); confirm, then reset.
  protected task drain_and_reset();
    bit retired;

    dii_vif.set_dii_ready(1'b0);
    agent.hold_rvfi(num_injected);
    wait_retired(drain_timeout, retired);
    if (!retired) begin
      `uvm_error(`gfn, $sformatf("Drain incomplete after %0d cycles (%0d of %0d retired): resetting anyway",
                                 drain_timeout, dii_vif.instr_out, num_injected))
      num_drain_timeouts++;
    end
    @(dii_vif.cb);

    clk_vif.apply_reset(.reset_width_clks(2));
    @(dii_vif.cb);

    agent.release_rvfi();
    insn_injected = 1'b0;
    num_injected  = 0;
  endtask

  protected task raise_irq(bit [3:0] channel);
    case (channel)
      4'd3:    dii_vif.cb.irq_software <= 1'b1;
      4'd7:    dii_vif.cb.irq_timer    <= 1'b1;
      4'd11:   dii_vif.cb.irq_external <= 1'b1;
      default: `uvm_error(`gfn, $sformatf("Unknown DII interrupt channel %0d", channel))
    endcase
  endtask

  // The barrier slot takes a reply like any instruction, so it is counted and waited for.
  protected task irq_barrier();
    inject(DII_DRAIN_INSN);
    dii_vif.cb.irq_software <= 1'b0;
    dii_vif.cb.irq_timer    <= 1'b0;
    dii_vif.cb.irq_external <= 1'b0;
  endtask

  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    // Each was already reported as a UVM_ERROR when it happened.
    if (num_aborted_tests != 0) begin
      `uvm_info(`gfn, $sformatf("%0d test(s) aborted", num_aborted_tests), UVM_NONE)
    end
    if (num_drain_timeouts != 0) begin
      `uvm_info(`gfn, $sformatf("%0d end-of-test drain(s) timed out", num_drain_timeouts), UVM_NONE)
    end
  endfunction
endclass : ibex_dii_driver
