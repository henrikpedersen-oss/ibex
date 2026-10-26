// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Protocol checker for Ibex's OBI-style memory ports (instruction, data, revocation bitmap, and
// the TRVK's upstream and downstream ports), for simulation and formal alike.
//
// One module serves both, as OpenTitan's tlul_assert does for TL-UL. EndpointType says which end
// of the port the block under test is:
//   "Host"   - the block drives req and the address phase (ibex_top's ports, TRVK downstream and
//              bitmap ports). Its own outputs are asserted; what the memory drives is assumed.
//   "Device" - the block answers (TRVK upstream). The other way round.
// A simulator checks an assumption like an assertion, so in simulation every rule is checked; in
// formal the rules on the environment's signals constrain it.
//
// The rules are the OBI specification's (v1.x, rule numbers R-n as in the specification) where
// Ibex follows them, and Ibex's documentation where it adds to them (doc/03_reference/
// instruction_fetch.rst and load_store_unit.rst, "Protocol"):
//   - responses come back in order, exactly one per granted request, one or more cycles after
//     the grant;
//   - addresses are word aligned;
//   - err, the integrity bits and the CHERIoT tag accompany rvalid.
// Read-only ports tie we, be, wdata, wdata_intg and wtag to constants (we = 0, be = 4'hf).

`include "prim_assert.sv"

module ibex_obi_assert #(
  parameter string       EndpointType     = "Host", // "Host" or "Device", see above
  // Most granted requests without a response; 0 leaves it unchecked (the instruction port with an
  // ICache, whose limit depends on its fill buffers).
  parameter int unsigned MaxOutstanding   = 0,
  // rdata and rdata_intg are known on every response, not only on reads (SecureIbex checks the
  // integrity of write responses too).
  parameter bit          RdataOnWriteResp = 1'b0,
  // The port never writes (instruction and bitmap ports): we, be, wdata, wdata_intg and wtag are
  // tied off, and the write cover is left out rather than reported unreachable.
  parameter bit          ReadOnly         = 1'b0
) (
  input logic        clk_i,
  input logic        rst_ni,
  // Address phase
  input logic        req,
  input logic        gnt,
  input logic [31:0] addr,
  input logic        we,
  input logic [3:0]  be,
  input logic [31:0] wdata,
  input logic [6:0]  wdata_intg,
  input logic        wtag,
  // Response phase
  input logic        rvalid,
  input logic [31:0] rdata,
  input logic [6:0]  rdata_intg,
  input logic        err,
  input logic        rtag
);

  localparam bit IsHost = (EndpointType == "Host");
  // Depth of the read/write record of outstanding requests (enough for every Ibex port when
  // MaxOutstanding is 0).
  localparam int unsigned QDepth = (MaxOutstanding > 0) ? MaxOutstanding : 8;
  localparam int unsigned CntW   = $clog2(QDepth + 2);

  // A rule on what the host drives (asserted for a host, assumed for a device), and the reverse.
  // Both branches carry the same block name, so a rule's path is <instance>.g_<Name>.<Name>
  // whichever end the block is (for DV_ASSERT_CTRL).
`define IBEX_OBI_HOST_RULE(__name, __prop, __rst = !rst_ni)                     \
  if (IsHost) begin : g_``__name                                                \
    `ASSERT(__name, __prop, clk_i, __rst)                                       \
  end else begin : g_``__name                                                   \
    `ASSUME(__name, __prop, clk_i, __rst)                                       \
  end
`define IBEX_OBI_DEVICE_RULE(__name, __prop, __rst = !rst_ni)                   \
  if (IsHost) begin : g_``__name                                                \
    `ASSUME(__name, __prop, clk_i, __rst)                                       \
  end else begin : g_``__name                                                   \
    `ASSERT(__name, __prop, clk_i, __rst)                                       \
  end

  //////////////////////////////////////////
  // Outstanding requests (order, reads)  //
  //////////////////////////////////////////

  // Granted requests without a response yet, oldest first: whether each was a read. A response
  // retires the oldest. Never below zero, so a response without a request (which the rules below
  // flag) does not corrupt the count for the rest of a simulation that carries on.
  logic [CntW-1:0]   cnt_q, cnt_d;
  logic [QDepth-1:0] is_read_q, is_read_d;
  logic              a_accept, r_retire;
  logic              waiting_q;  // req held without a grant in the previous cycle

  assign a_accept = req & gnt;
  assign r_retire = rvalid & (cnt_q != '0);

  always_comb begin
    cnt_d     = cnt_q;
    is_read_d = is_read_q;
    if (r_retire) begin
      is_read_d = is_read_q >> 1;
      cnt_d     = cnt_q - 1'b1;
    end
    if (a_accept && (cnt_d < CntW'(QDepth))) begin
      is_read_d[cnt_d] = ~we;
      cnt_d            = cnt_d + 1'b1;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      cnt_q     <= '0;
      is_read_q <= '0;
      waiting_q <= 1'b0;
    end else begin
      cnt_q     <= cnt_d;
      is_read_q <= is_read_d;
      waiting_q <= req & ~gnt;
    end
  end

  logic head_is_read;
  assign head_is_read = is_read_q[0];

  // be holds a contiguous run of ones (R-7).
  logic be_contiguous;
  always_comb begin
    unique case (be)
      4'b0001, 4'b0010, 4'b0100, 4'b1000,
      4'b0011, 4'b0110, 4'b1100,
      4'b0111, 4'b1110,
      4'b1111: be_contiguous = 1'b1;
      default: be_contiguous = 1'b0;
    endcase
  end

  //////////////////////////////
  // Host: the address phase  //
  //////////////////////////////

  // R-2.1: no request while in reset. Checked in reset, so not disabled by it.
  `IBEX_OBI_HOST_RULE(ReqLowInReset, !rst_ni |-> !req, 1'b0)
  `IBEX_OBI_HOST_RULE(ReqKnown, !$isunknown(req))
  // R-3.1.2: a request stays up until it is granted.
  `IBEX_OBI_HOST_RULE(ReqHeldUntilGnt, req && !gnt |=> req)
  // R-3.1.1: the address phase does not change until it is granted. Split so a failure says which:
  // the transfer (addr, we, be), or the write data, which carries nothing on a read.
  `IBEX_OBI_HOST_RULE(APhaseStable, req && !gnt |=> $stable({addr, we, be}))
  `IBEX_OBI_HOST_RULE(WDataStable, req && !gnt && we |=> $stable({wdata, wdata_intg, wtag}))
  `IBEX_OBI_HOST_RULE(APhaseKnown, req |-> !$isunknown({addr, we, be}))
  `IBEX_OBI_HOST_RULE(WDataKnown, req && we |-> !$isunknown({wdata, wdata_intg, wtag}))
  // R-7: at least one byte enable, and the enabled bytes are contiguous.
  `IBEX_OBI_HOST_RULE(BeNotZero, req |-> be != 4'b0)
  `IBEX_OBI_HOST_RULE(BeContiguous, req |-> be_contiguous)
  // Ibex: word-aligned addresses only (which also satisfies R-8, address LSBs consistent with be).
  `IBEX_OBI_HOST_RULE(AddrWordAligned, req |-> addr[1:0] == 2'b00)
  // At most MaxOutstanding requests in flight. A new one may be issued in the cycle the oldest
  // gets its response.
  if (MaxOutstanding > 0) begin : g_max_outstanding
    `IBEX_OBI_HOST_RULE(MaxOutstandingRespected,
      req |-> (cnt_q < CntW'(MaxOutstanding)) || rvalid)
  end

  ////////////////////////////////
  // Device: the response phase //
  ////////////////////////////////

  // R-2.2: no response while in reset. Not driven yet (X/Z, e.g. a UVM agent driving through a
  // clocking block before its first edge) is not a response; RvalidKnown applies out of reset.
  `IBEX_OBI_DEVICE_RULE(RvalidLowInReset, !rst_ni |-> rvalid !== 1'b1, 1'b0)
  `IBEX_OBI_DEVICE_RULE(RvalidKnown, !$isunknown(rvalid))
  // R-5: a response only for a request granted in an earlier cycle (so never in the grant cycle
  // of the request it answers), one per request.
  `IBEX_OBI_DEVICE_RULE(RspOnlyOutstanding, rvalid |-> cnt_q != '0)
  // err and the tag go with every response; data and integrity with a good read response (every
  // response with RdataOnWriteResp, whose integrity the core checks even on a write or an error).
  `IBEX_OBI_DEVICE_RULE(RspStatusKnown, rvalid |-> !$isunknown({err, rtag}))
  `IBEX_OBI_DEVICE_RULE(RDataKnown,
    rvalid && (RdataOnWriteResp || (head_is_read && !err)) |->
      !$isunknown({rdata, rdata_intg}))

  ///////////
  // Cover //
  ///////////

  // The interesting timings each side may choose; a bench or proof that never reaches one of
  // these has not exercised it.
  `COVER(CvGntSameCycle, req && gnt && !waiting_q)
  `COVER(CvGntDelayed, req && gnt && waiting_q)
  `COVER(CvBackToBack, a_accept ##1 a_accept)
  // R-3.2.1: a grant without a request is allowed.
  `COVER(CvGntWithoutReq, gnt && !req)
  `COVER(CvRspWithNewReq, rvalid && req)
  `COVER(CvRspErr, rvalid && err)
  `COVER(CvRead, a_accept && !we)
  if (!ReadOnly) begin : g_cov_write
    `COVER(CvWrite, a_accept && we)
  end
  if (MaxOutstanding > 0) begin : g_cov_max
    `COVER(CvMaxOutstanding, cnt_q == CntW'(MaxOutstanding))
  end

`undef IBEX_OBI_HOST_RULE
`undef IBEX_OBI_DEVICE_RULE

endmodule
