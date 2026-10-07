// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Feeds instruction packets from a TestRIG vengine (QuickCheckVEngine, run with
// --single-implementation) to the driver. Execution packets go back over the same socket from the
// agent as instructions retire; this sequence only adds the halt that closes each test.
//
// Plusargs:
//   +dii_port=<n>         TCP port to listen on (default 6000)
//   +dii_idle_polls=<n>   once packets have started, end after this many consecutive empty
//                         100 ms polls (default 50, i.e. 5 s of wall-clock silence)
class ibex_dii_socket_seq extends uvm_sequence #(ibex_dii_seq_item);
  `uvm_object_utils(ibex_dii_socket_seq)
  `uvm_declare_p_sequencer(ibex_dii_sequencer)

  int unsigned port       = 6000;
  int unsigned idle_polls = 50;

  int unsigned num_tests;
  int unsigned num_aborted;

  function new(string name = "ibex_dii_socket_seq");
    super.new(name);
  endfunction

  virtual task body();
    chandle    conn;
    bit        stream_begun;
    bit [31:0] dii_insn;
    bit [15:0] dii_time;
    bit [7:0]  dii_cmd;

    void'($value$plusargs("dii_port=%d", port));
    void'($value$plusargs("dii_idle_polls=%d", idle_polls));

    `uvm_info(`gfn, $sformatf("Waiting for a TestRIG connection on port %0d", port), UVM_LOW)
    conn = testrig_create(port);
    p_sequencer.testrig_conn = conn;

    forever begin
      int unsigned idle = 0;

      // Blocks for up to 100 ms of wall-clock time per poll; simulation time does not advance.
      while (!testrig_get_next_instruction(conn, dii_insn, dii_time, dii_cmd)) begin
        if (stream_begun && (++idle >= idle_polls)) begin
          `uvm_info(`gfn, $sformatf("No DII packet for %0d polls after %0d tests: stream ended",
                                    idle_polls, num_tests), UVM_LOW)
          return;
        end
      end
      stream_begun = 1'b1;

      req = ibex_dii_seq_item::type_id::create("req");
      start_item(req);
      if (!$cast(req.cmd, dii_cmd)) begin
        `uvm_fatal(`gfn, $sformatf("Unknown DII command 0x%02x (insn 0x%08x)", dii_cmd, dii_insn))
      end
      req.insn = dii_insn;
      finish_item(req);
      get_response(rsp);

      if (rsp.end_of_test) begin
        testrig_send_rvfi_halt(conn);
        num_tests++;
      end
      if (rsp.aborted) num_aborted++;
    end
  endtask : body
endclass : ibex_dii_socket_seq
