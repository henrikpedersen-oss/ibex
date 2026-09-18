// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Capability tag storage for the UVM data bus.
//
// Why this exists
// ---------------
// core_ibex_tb_top.sv drove `data_tag_i` with a constant 1'b0 and left
// `data_tag_o` unconnected, so a CSC's tag was discarded on the way out and
// every CLC read back an untagged capability. Any capability round-trip test
// therefore failed on its first `cgettag` check regardless of what the RTL did
// -- cheriot_cap_readback aborted at check 1 of ~20, which made the gap look
// like a single narrow failure rather than the whole capability load/store path
// being unmodelled.
//
// This is a sidecar, not a memory. The UVM memory agent
// (ibex_mem_intf_response_seq) still owns data, the request/response protocol
// and its randomised delays. All that is added here is the one bit per granule
// the agent has no concept of, sampled and returned in step with it.
//
// Granule, not word
// -----------------
// A CHERIoT capability is 8 bytes and carries one tag, but the data bus is 32
// bits wide, so a CSC is two transactions sharing a tag. Storage is therefore
// keyed by 8-byte granule (addr[31:3]), not by word -- keying by word would
// give one capability two independent tags that could disagree.
//
// Tag clearing is the security-relevant part: any write that is not a full
// capability store clears the granule's tag. Writing a byte into a capability
// destroys it, and a model that failed to do that would let a test forge a
// capability by assembling one with ordinary stores.
//
// Sparse by necessity
// -------------------
// Addresses reach beyond 0x80080000, so storage is an associative array like
// the agent's own memory model. An unwritten granule reads back tag 0, which is
// exactly the previous behaviour -- so non-capability traffic is unaffected.

module ibex_tag_mem (
    input  logic        clk_i,
    input  logic        rst_ni,

    // Data bus, snooped. Address/we/be/wtag are sampled on an accepted request
    // (req & gnt); the tag is returned with rvalid.
    input  logic        req_i,
    input  logic        gnt_i,
    input  logic        we_i,
    input  logic [3:0]  be_i,
    input  logic [31:0] addr_i,
    input  logic        wtag_i,
    input  logic        rvalid_i,

    output logic        rtag_o
);

  // One tag per 8-byte granule, keyed by addr[31:3].
  bit tag_mem [bit [28:0]];

  // Reads can be outstanding and the agent's response delay is randomised, so
  // the tag cannot simply be looked up when rvalid arrives -- by then the
  // address may have moved on, and a later write could have changed the tag.
  // Capture at accept time and return in order.
  //
  // One entry per *accepted request*, reads and writes alike. Ibex asserts
  // data_rvalid_i for store responses as well as loads, so a queue fed only by
  // reads but drained by every rvalid desynchronises: a write response steals
  // the tag belonging to a queued read. That is not hypothetical -- it is what
  // made cheriot_cap_readback's third round-trip return an untagged capability
  // while the memory model held the correct data. Its two CSC beats were 220 ns
  // apart (vs 20 ns for the first round-trip), so their responses landed after
  // the following CLC's reads had been queued, and drained them.
  typedef struct {
    bit is_read;
    bit tag;
  } pending_t;
  pending_t pending_q [$];

  logic [28:0] granule;
  assign granule = addr_i[31:3];

  // A tag survives only a full-width write that is itself part of a capability
  // store. Everything else -- a byte/halfword write, or a full word written by
  // an ordinary sw -- clears it.
  logic keeps_tag;
  assign keeps_tag = wtag_i && (be_i == 4'b1111);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      tag_mem.delete();
      pending_q.delete();
    end else if (req_i && gnt_i) begin
      if (we_i) begin
        tag_mem[granule] = keeps_tag;
        // Queued so the response stream stays in lockstep; the tag is unused.
        pending_q.push_back('{is_read: 1'b0, tag: 1'b0});
      end else begin
        pending_q.push_back('{is_read: 1'b1,
                              tag    : tag_mem.exists(granule) ? tag_mem[granule] : 1'b0});
      end
    end
  end

  // The tag must be valid in the same cycle as rvalid, alongside rdata, so it
  // is presented combinationally from the head of the queue and only retired at
  // the clock edge. Registering it on rvalid would deliver it a cycle late.
  // Guarded so a stray rvalid cannot underflow the queue -- returning 0 then
  // matches the old tie-off.
  assign rtag_o = (rvalid_i && (pending_q.size() > 0) && pending_q[0].is_read) ?
                  pending_q[0].tag : 1'b0;

  // TEMPORARY instrumentation -- remove once the capability round-trip is
  // understood. data_tag_o is driven by TRVK's downstream_tag_o, not straight
  // from the LSU, so it is not obvious that wtag_i is phase-aligned with
  // req/gnt the way this module assumes.
  always_ff @(posedge clk_i) begin
    if (rst_ni && req_i && gnt_i && (addr_i[31:12] == 20'h80080)) begin
      $display("[TAGMEM] %0t %s addr=%08h be=%b wtag=%b -> granule_tag=%b",
               $time, we_i ? "WR" : "RD", addr_i, be_i, wtag_i,
               we_i ? keeps_tag : (tag_mem.exists(granule) ? tag_mem[granule] : 1'b0));
    end
    if (rst_ni && rvalid_i) begin
      $display("[TAGMEM] %0t RSP is_read=%b rtag=%b depth=%0d", $time,
               (pending_q.size() > 0) ? pending_q[0].is_read : 1'b0,
               rtag_o, pending_q.size());
    end
  end

  always_ff @(posedge clk_i) begin
    if (rst_ni && rvalid_i && (pending_q.size() > 0)) begin
      void'(pending_q.pop_front());
    end
  end

endmodule
