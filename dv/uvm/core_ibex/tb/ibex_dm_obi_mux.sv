// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

`include "prim_assert.sv"

// Address decode and arbitration between the core's two OBI ports, the UVM memory response agents
// and the single slave port of the real debug module (dm_top). DM builds only (IBEX_DM_REAL, file
// list ibex_dv_dm.f).
//
// Decode: an access whose address lies in [DmBaseAddr, DmBaseAddr + DmAddrMask] goes to the DM;
// everything else goes to the memory agent of the same bus. The agents never see a DM access: their
// request line is the core's request with DM addresses masked out, and the grant/response the core
// sees for a DM access comes from here. The addr/we/be/wdata lines of the agents' interfaces stay
// connected to the core directly (they only mean anything while the agent's request is high).
//
// DM slave port timing (dm_mem): a request is accepted in the cycle req_i is high, and rdata_o /
// err_o belong to it one cycle later; back-to-back requests are pipelined. So a DM access is granted
// in the cycle it is presented and its rvalid comes exactly one cycle later.
//
// Ordering: OBI responses come back in request order on each bus, and the core matches them to its
// requests by order alone. A DM access is therefore only granted while no memory-agent access is
// outstanding on the same bus (the agent may take many cycles to respond, the DM always takes one).
// The reverse needs no rule: a memory access granted after a DM access cannot respond before the
// DM's fixed one-cycle response. Instruction fetches can have several accesses in flight (prefetch
// buffer / icache fill buffers), and a debug request makes the core discard fetches that are still
// outstanding, so this case does occur on entry to the debug ROM.
//
// Arbitration: one DM access per cycle. If both buses present an eligible DM access in the same
// cycle, the bus that was not granted last time wins.
//
// Integrity: the core checks *_rdata_intg_i (SecureIbex: MemECC), so DM responses carry the same
// inverted SECDED(39,32) code the memory agents generate (prim_secded_inv_39_32_enc).
//
// Tags: a DM response returns tag 0 (the DM stores plain words). A capability the core stores into
// the DM loses its tag; dm_data0_wr_o / dm_data0_wtag_o let the testbench observe the tag of stores
// to data0 (DmBaseAddr + 0x380), which the DMI cannot report.
module ibex_dm_obi_mux #(
  parameter logic [31:0] DmBaseAddr = 32'h1A11_0000,
  parameter logic [31:0] DmAddrMask = 32'h0000_0FFF
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  // Core instruction port (OBI host side)
  input  logic        core_instr_req_i,
  input  logic [31:0] core_instr_addr_i,
  output logic        core_instr_gnt_o,
  output logic        core_instr_rvalid_o,
  output logic [31:0] core_instr_rdata_o,
  output logic [6:0]  core_instr_rintg_o,
  output logic        core_instr_err_o,

  // Instruction memory agent (OBI device side)
  output logic        mem_instr_req_o,
  input  logic        mem_instr_gnt_i,
  input  logic        mem_instr_rvalid_i,
  input  logic [31:0] mem_instr_rdata_i,
  input  logic [6:0]  mem_instr_rintg_i,
  input  logic        mem_instr_err_i,
  input  logic        mem_instr_spurious_i,

  // Core data port
  input  logic        core_data_req_i,
  input  logic [31:0] core_data_addr_i,
  input  logic        core_data_we_i,
  input  logic [3:0]  core_data_be_i,
  input  logic [31:0] core_data_wdata_i,
  input  logic        core_data_wtag_i,
  output logic        core_data_gnt_o,
  output logic        core_data_rvalid_o,
  output logic [31:0] core_data_rdata_o,
  output logic [6:0]  core_data_rintg_o,
  output logic        core_data_err_o,
  output logic        core_data_rtag_o,

  // Data memory agent (and the tag sidecar ibex_tag_mem behind it)
  output logic        mem_data_req_o,
  input  logic        mem_data_gnt_i,
  input  logic        mem_data_rvalid_i,
  input  logic [31:0] mem_data_rdata_i,
  input  logic [6:0]  mem_data_rintg_i,
  input  logic        mem_data_err_i,
  input  logic        mem_data_spurious_i,
  input  logic        mem_data_rtag_i,

  // Debug module slave port (dm_top slave_*)
  output logic        dm_req_o,
  output logic        dm_we_o,
  output logic [31:0] dm_addr_o,
  output logic [3:0]  dm_be_o,
  output logic [31:0] dm_wdata_o,
  input  logic [31:0] dm_rdata_i,
  input  logic        dm_err_i,

  // A store to the DM's data0 word is granted this cycle; dm_data0_wtag_o is its capability tag.
  output logic        dm_data0_wr_o,
  output logic        dm_data0_wtag_o
);

  localparam logic [31:0] DmData0Addr = DmBaseAddr + 32'h380;

  function automatic logic in_dm(logic [31:0] addr);
    return (addr & ~DmAddrMask) == (DmBaseAddr & ~DmAddrMask);
  endfunction

  ///////////////////
  // Decode        //
  ///////////////////

  logic i_dm_sel, d_dm_sel;
  assign i_dm_sel = core_instr_req_i & in_dm(core_instr_addr_i);
  assign d_dm_sel = core_data_req_i  & in_dm(core_data_addr_i);

  assign mem_instr_req_o = core_instr_req_i & ~in_dm(core_instr_addr_i);
  assign mem_data_req_o  = core_data_req_i  & ~in_dm(core_data_addr_i);

  /////////////////////////////////////////////
  // Outstanding memory-agent accesses       //
  /////////////////////////////////////////////

  // A spurious response (ibex_mem_intf_response_seq, +disable_spurious_dside_responses=0) answers
  // no request, so it does not retire one.
  logic       i_mem_acc, i_mem_rsp, d_mem_acc, d_mem_rsp;
  logic [7:0] i_mem_out_q, d_mem_out_q;

  assign i_mem_acc = mem_instr_req_o & mem_instr_gnt_i;
  assign i_mem_rsp = mem_instr_rvalid_i & ~mem_instr_spurious_i;
  assign d_mem_acc = mem_data_req_o & mem_data_gnt_i;
  assign d_mem_rsp = mem_data_rvalid_i & ~mem_data_spurious_i;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      i_mem_out_q <= '0;
      d_mem_out_q <= '0;
    end else begin
      i_mem_out_q <= i_mem_out_q + 8'(i_mem_acc) - 8'(i_mem_rsp);
      d_mem_out_q <= d_mem_out_q + 8'(d_mem_acc) - 8'(d_mem_rsp);
    end
  end

  ///////////////////////////
  // DM arbitration        //
  ///////////////////////////

  logic i_dm_ok, d_dm_ok, i_dm_gnt, d_dm_gnt;
  logic prio_d_q;  // on a tie the data bus wins when set

  assign i_dm_ok  = i_dm_sel & (i_mem_out_q == '0);
  assign d_dm_ok  = d_dm_sel & (d_mem_out_q == '0);
  assign i_dm_gnt = i_dm_ok & (~d_dm_ok | ~prio_d_q);
  assign d_dm_gnt = d_dm_ok & (~i_dm_ok |  prio_d_q);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      prio_d_q <= 1'b1;
    end else if (i_dm_gnt) begin
      prio_d_q <= 1'b1;
    end else if (d_dm_gnt) begin
      prio_d_q <= 1'b0;
    end
  end

  assign dm_req_o   = i_dm_gnt | d_dm_gnt;
  assign dm_we_o    = d_dm_gnt & core_data_we_i;
  assign dm_addr_o  = d_dm_gnt ? core_data_addr_i : core_instr_addr_i;
  assign dm_be_o    = d_dm_gnt ? core_data_be_i   : 4'hF;
  assign dm_wdata_o = core_data_wdata_i;

  assign dm_data0_wr_o   = d_dm_gnt & core_data_we_i & (core_data_addr_i == DmData0Addr);
  assign dm_data0_wtag_o = core_data_wtag_i;

  ///////////////////////////
  // Responses             //
  ///////////////////////////

  logic i_dm_rsp_q, d_dm_rsp_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      i_dm_rsp_q <= 1'b0;
      d_dm_rsp_q <= 1'b0;
    end else begin
      i_dm_rsp_q <= i_dm_gnt;
      d_dm_rsp_q <= d_dm_gnt;
    end
  end

  logic [38:0] dm_rdata_enc;
  assign dm_rdata_enc = prim_secded_pkg::prim_secded_inv_39_32_enc(dm_rdata_i);

  // A DM access is never granted by the memory agent, a memory access never by the DM.
  assign core_instr_gnt_o    = i_dm_sel ? i_dm_gnt : mem_instr_gnt_i;
  assign core_instr_rvalid_o = i_dm_rsp_q | mem_instr_rvalid_i;
  assign core_instr_rdata_o  = i_dm_rsp_q ? dm_rdata_i          : mem_instr_rdata_i;
  assign core_instr_rintg_o  = i_dm_rsp_q ? dm_rdata_enc[38:32] : mem_instr_rintg_i;
  assign core_instr_err_o    = i_dm_rsp_q ? dm_err_i            : mem_instr_err_i;

  assign core_data_gnt_o     = d_dm_sel ? d_dm_gnt : mem_data_gnt_i;
  assign core_data_rvalid_o  = d_dm_rsp_q | mem_data_rvalid_i;
  assign core_data_rdata_o   = d_dm_rsp_q ? dm_rdata_i          : mem_data_rdata_i;
  assign core_data_rintg_o   = d_dm_rsp_q ? dm_rdata_enc[38:32] : mem_data_rintg_i;
  assign core_data_err_o     = d_dm_rsp_q ? dm_err_i            : mem_data_err_i;
  assign core_data_rtag_o    = d_dm_rsp_q ? 1'b0                : mem_data_rtag_i;

  ///////////////////////////
  // Assertions            //
  ///////////////////////////

  // The ordering rule above keeps a memory response and a DM response from landing in the same
  // cycle on one bus; if one did, the core would get two responses at once and lose one.
  `ASSERT(DmMuxNoInstrRspCollision, !(i_dm_rsp_q && mem_instr_rvalid_i), clk_i, !rst_ni)
  `ASSERT(DmMuxNoDataRspCollision,  !(d_dm_rsp_q && mem_data_rvalid_i),  clk_i, !rst_ni)
  // A memory response with nothing outstanding means the counters above are wrong.
  `ASSERT(DmMuxInstrOutstandingNoUnderflow, i_mem_rsp |-> (i_mem_out_q != '0), clk_i, !rst_ni)
  `ASSERT(DmMuxDataOutstandingNoUnderflow,  d_mem_rsp |-> (d_mem_out_q != '0), clk_i, !rst_ni)
  // At most one DM access per cycle.
  `ASSERT(DmMuxOneDmGrant, !(i_dm_gnt && d_dm_gnt), clk_i, !rst_ni)

endmodule
