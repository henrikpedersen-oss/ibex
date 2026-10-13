// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Debug host driver of the CHERIoT RTOS test SoC testbench (tb/cheriot_rtos_tb.sv).
//
// Plays the debug transport module on the SoC's DMI port (there is no JTAG TAP), and drives the
// SoC's debug access enable (dbg_en_i, the model of OpenTitan's lc_hw_debug_en), to serve the
// requests of firmware/dbg_host_test: testplan non_core_bus_masters, tests
// bus_master_dbg_host_tag_clear and bus_master_dbg_host_locked. The DMI access is the UVM
// testbench's core_ibex_dmi_host (one request at a time, response taken in the first cycle it is
// valid), without UVM.
//
// Protocol with the firmware (dbg_host_test.cc):
//   1. The firmware prints  "DBGHOST REQ <op> <slot> <value> <flag>"  on UART0 (all 0x-prefixed
//      hex). cheriot_rtos_tb decodes the line, puts the fields on req_*_i and increments
//      req_count_i.
//   2. This module serves the request over the DMI:
//        op 1 (tag clear): debug access enabled; SBA write of <value> to the word at <slot>.
//        op 2 (locked):    debug access DISABLED; SBA write of <value> to <slot>, which the
//                          SoC's debug-access gate must refuse; then debug access enabled again.
//      Then, with debug access enabled, an SBA read of <slot>, and an SBA write of
//        DoneMagic | op << 12 | sberror << 8 | readback << 4 | 1
//      to the word at <flag>, where sberror is sbcs.sberror after the write to <slot> (2 = bus
//      error) and readback says the read of <slot> returned <value>.
//   3. Debug access is disabled again (its state out of reset).
//   4. The firmware, polling <flag>, reloads <slot> with a capability load and reports the
//      verdict. The checks are the firmware's: only a core load shows the tag.
// With the DMI idle (no request) the debug module stays inactive: this module issues nothing
// until a firmware asks.
//
// Plusargs:
//   +dbg_host_drv=0   log requests but do not serve them (the firmware must then report FAIL for
//                     both tests: its liveness check)
module cheriot_rtos_dbg_host (
  input  logic                 clk_i,
  input  logic                 rst_ni,

  // Request decoded from UART0 by the testbench.
  input  int unsigned          req_count_i,
  input  logic [31:0]          req_op_i,
  input  logic [31:0]          req_slot_i,
  input  logic [31:0]          req_value_i,
  input  logic [31:0]          req_flag_i,

  // Debug access enable of the SoC (lc_tx_t encoding).
  output ibex_pkg::ibex_mubi_t dbg_en_o,

  // DMI.
  output logic                 dmi_req_valid_o,
  input  logic                 dmi_req_ready_i,
  output dm::dmi_req_t         dmi_req_o,
  input  logic                 dmi_resp_valid_i,
  output logic                 dmi_resp_ready_o,
  input  dm::dmi_resp_t        dmi_resp_i
);

  // Shared with firmware/dbg_host_test/dbg_host_test.cc.
  localparam logic [31:0] OpTagClear = 32'd1;
  localparam logic [31:0] OpLocked   = 32'd2;
  localparam logic [31:0] DoneMagic  = 32'hDB60_0000;

  // Bound on each DMI handshake and on each SBA access, in cycles. An SBA access to the SRAM
  // takes a few cycles; this only turns a hang into a failure.
  localparam int unsigned Timeout = 10_000;

  // sbcs (Debug Spec 0.13, dm::sbcs_t)
  localparam int unsigned SbcsBusy      = 21;
  localparam int unsigned SbcsBusyError = 22;
  localparam logic [31:0] SbcsAccess32  = 32'(3'd2) << 17;
  localparam logic [31:0] SbcsReadOnAddr = 32'h1 << 20;
  // W1C: sbbusyerror and sberror
  localparam logic [31:0] SbcsClearErrors = (32'h1 << SbcsBusyError) | (32'h7 << 12);

  // One DMI access. The request is accepted at the first clock edge with valid and ready high;
  // the debug module's response FIFO answers on a later edge, and resp_ready is held high, so the
  // response is taken at the first edge it is valid. Signals are driven at the falling edge and
  // sampled at the rising one.
  task automatic dmi(input dm::dtm_op_e op, input dm::dm_csr_e addr, input logic [31:0] wdata,
                     output logic [31:0] rdata);
    int unsigned n;
    @(negedge clk_i);
    dmi_req_o       = '{addr: 32'(addr), op: op, data: wdata};
    dmi_req_valid_o = 1'b1;
    n = 0;
    do begin
      @(posedge clk_i);
      if (++n > Timeout) begin
        $fatal(1, "[dbg_host] DMI request to %s not accepted within %0d cycles", addr.name(),
               Timeout);
      end
    end while (dmi_req_ready_i !== 1'b1);
    @(negedge clk_i);
    dmi_req_valid_o = 1'b0;
    n = 0;
    do begin
      @(posedge clk_i);
      if (++n > Timeout) begin
        $fatal(1, "[dbg_host] no DMI response for %s within %0d cycles", addr.name(), Timeout);
      end
    end while (dmi_resp_valid_i !== 1'b1);
    rdata = dmi_resp_i.data;
    if (dmi_resp_i.resp != dm::DTM_SUCCESS) begin
      $error("[dbg_host] DMI %s of %s answered with status %0d (2 = error, 3 = busy)",
             op.name(), addr.name(), dmi_resp_i.resp);
    end
  endtask

  // Wait for the SBA access in progress to end; return sbcs.
  task automatic sba_wait(output logic [31:0] sbcs);
    int unsigned n;
    // sbcs.sbbusy follows the SBA engine one cycle late (dm_csrs): do not read it too early.
    repeat (4) @(posedge clk_i);
    n = 0;
    do begin
      dmi(dm::DTM_READ, dm::SBCS, '0, sbcs);
      if (++n > Timeout) $fatal(1, "[dbg_host] SBA access still busy after %0d sbcs reads", n);
    end while (sbcs[SbcsBusy]);
    if (sbcs[SbcsBusyError]) $error("[dbg_host] sbcs.sbbusyerror set (sbcs %h)", sbcs);
  endtask

  // 32-bit SBA write; returns sbcs.sberror (0 = done, 2 = bus error).
  task automatic sba_write(input logic [31:0] addr, input logic [31:0] data,
                           output logic [2:0] sberror);
    logic [31:0] unused, sbcs;
    dmi(dm::DTM_WRITE, dm::SBCS, SbcsAccess32 | SbcsClearErrors, unused);
    dmi(dm::DTM_WRITE, dm::SBAddress0, addr, unused);
    dmi(dm::DTM_WRITE, dm::SBData0, data, unused);  // starts the write
    sba_wait(sbcs);
    sberror = sbcs[14:12];
  endtask

  // 32-bit SBA read (sbreadonaddr: writing sbaddress0 starts it); returns sbcs.sberror.
  task automatic sba_read(input logic [31:0] addr, output logic [31:0] data,
                          output logic [2:0] sberror);
    logic [31:0] unused, sbcs;
    dmi(dm::DTM_WRITE, dm::SBCS, SbcsAccess32 | SbcsReadOnAddr | SbcsClearErrors, unused);
    dmi(dm::DTM_WRITE, dm::SBAddress0, addr, unused);  // starts the read
    sba_wait(sbcs);
    sberror = sbcs[14:12];
    dmi(dm::DTM_READ, dm::SBData0, '0, data);  // sbreadondata = 0: no further read
  endtask

  // Change the debug access enable while SBA is idle, and give the gate time to drain or open.
  task automatic set_dbg_en(input logic on);
    @(negedge clk_i);
    dbg_en_o = on ? ibex_pkg::IbexMuBiOn : ibex_pkg::IbexMuBiOff;
    $display("[dbg_host] %0t: debug access %s", $time, on ? "enabled" : "disabled");
    repeat (8) @(posedge clk_i);
  endtask

  task automatic serve(input logic [31:0] op, input logic [31:0] slot, input logic [31:0] value,
                       input logic [31:0] flag);
    logic [31:0] unused, rdata, done;
    logic [2:0]  sberror, rd_err, flag_err;
    logic        readback;

    $display("[dbg_host] %0t: request %0d (%s): SBA write %h to %h, done flag at %h", $time, op,
             op == OpTagClear ? "tag clear" : op == OpLocked ? "locked" : "?", value, slot, flag);
    if (op != OpTagClear && op != OpLocked) begin
      $error("[dbg_host] unknown request %0d: not served", op);
      return;
    end

    set_dbg_en(op == OpTagClear);
    // Activate the debug module; until dmactive is set it holds everything else in reset.
    dmi(dm::DTM_WRITE, dm::DMControl, 32'h1, unused);
    dmi(dm::DTM_READ, dm::DMControl, '0, rdata);
    if (!rdata[0]) $error("[dbg_host] dmcontrol.dmactive did not set (dmcontrol %h)", rdata);

    sba_write(slot, value, sberror);
    $display("[dbg_host] %0t: SBA write %h to %h with debug access %s: sbcs.sberror = %0d",
             $time, value, slot, op == OpTagClear ? "enabled" : "disabled", sberror);

    if (op == OpLocked) set_dbg_en(1'b1);
    sba_read(slot, rdata, rd_err);
    readback = (rd_err == '0) && (rdata == value);
    $display("[dbg_host] %0t: SBA read of %h: %h (sberror %0d)%s", $time, slot, rdata, rd_err,
             readback ? ", the value written" : "");

    done = DoneMagic | (32'(op[3:0]) << 12) | (32'(sberror) << 8) | (32'(readback) << 4) | 32'h1;
    sba_write(flag, done, flag_err);
    if (flag_err != '0) begin
      $error("[dbg_host] SBA write of the done flag %h to %h failed (sberror %0d)", done, flag,
             flag_err);
    end
    set_dbg_en(1'b0);
  endtask

  initial begin : serve_requests
    int unsigned seen;
    int          enabled;
    dbg_en_o         = ibex_pkg::IbexMuBiOff;
    dmi_req_valid_o  = 1'b0;
    dmi_req_o        = '0;
    dmi_resp_ready_o = 1'b1;
    if (!$value$plusargs("dbg_host_drv=%d", enabled)) enabled = 1;
    seen = 0;
    @(posedge rst_ni);
    forever begin
      @(req_count_i);
      // The request fields change in the same time step as the count; read them a clock edge
      // later, when every port has settled.
      @(negedge clk_i);
      // The firmware waits for each request to be served, so at most one is pending.
      while (seen != req_count_i) begin
        seen++;
        if (enabled == 0) begin
          $display("[dbg_host] %0t: request %0d ignored (+dbg_host_drv=0)", $time, req_op_i);
        end else begin
          serve(req_op_i, req_slot_i, req_value_i, req_flag_i);
        end
      end
    end
  end

endmodule
