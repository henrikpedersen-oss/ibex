// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Revocation-bitmap responder for the UVM testbench.
//
// Why this exists
// ---------------
// core_ibex_tb_top.sv tied the whole TRVK bitmap port off -- `revbm_gnt_i` and
// `revbm_rvalid_i` were both constant 1'b0. That was survivable only because
// `data_tag_i` was also tied to zero: with no tagged capability ever reaching
// the core, TRVK had no revocation lookup to perform and simply passed
// responses through.
//
// Once capability tags are modelled (see ibex_tag_mem.sv), loading a tagged
// capability makes TRVK consult the bitmap before releasing it. With the port
// tied off the request is never granted, TRVK stalls, its downstream response
// store backs up, and `DsRspFifoNoOverflow_A` fires. The assertion is right --
// the testbench was incomplete.
//
// Note core_ibex_tb_top.sv already disables TRVK's `AlignValidOnRsp_A` "alongside
// the other spurious response checks". Disabling `DsRspFifoNoOverflow_A` the same
// way was rejected: it would restore a testbench that cannot fail, which is the
// problem this whole area already had once.
//
// Policy: nothing is ever revoked
// -------------------------------
// Every lookup returns a zero bitmap word, so no capability is reported revoked.
// TRVK computes
//
//   revbm_revoked = revbm_rdata_i[bit_select] || revbm_err_i || |intg_error
//
// so zero data, no error and valid integrity bits together mean "live". That
// matches what the directed tests expect -- none of them frees a heap granule,
// so a revoked capability would be wrong, not merely unmodelled.
//
// This is deliberately not a revocation model. Exercising real revocation needs
// the bitmap to be written by an allocator and read back coherently, which is
// SoC-level behaviour (cheri_tbre) with no counterpart in the standalone core.
// A test that wants to verify revocation cannot use this responder.
//
// Integrity bits must be generated, not guessed
// ---------------------------------------------
// TRVK instantiates prim_secded_inv_39_32_dec and folds any integrity error
// straight into `revbm_revoked`, so bad ECC would silently read as "revoked"
// rather than as a testbench bug. The scheme is *inverted* SECDED, so the
// codeword for all-zero data is not all-zero -- the encoder is instantiated here
// rather than hardcoding a constant.

module ibex_revbm_responder (
    input  logic        clk_i,
    input  logic        rst_ni,

    input  logic        revbm_req_i,
    output logic        revbm_gnt_o,
    output logic        revbm_rvalid_o,
    input  logic [31:0] revbm_addr_i,
    output logic [31:0] revbm_rdata_o,
    output logic [6:0]  revbm_rdata_intg_o,
    output logic        revbm_err_o
);

  // Single outstanding lookup, one cycle latency: grant immediately, respond on
  // the next edge. Keeping rvalid strictly downstream of an accepted request is
  // what satisfies TRVK's own RevbmRspOnlyWhenOutstanding_A assertion.
  assign revbm_gnt_o = revbm_req_i;

  logic rvalid_q;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rvalid_q <= 1'b0;
    end else begin
      rvalid_q <= revbm_req_i & revbm_gnt_o;
    end
  end

  assign revbm_rvalid_o = rvalid_q;
  assign revbm_rdata_o   = 32'b0;
  assign revbm_err_o     = 1'b0;

  // Valid integrity bits for the all-zero word returned above.
  logic [38:0] enc_word;
  prim_secded_inv_39_32_enc u_revbm_intg_enc (
    .data_i (32'b0   ),
    .data_o (enc_word)
  );
  assign revbm_rdata_intg_o = enc_word[38:32];

  // Address is not used: the bitmap is uniformly zero, so every lookup has the
  // same answer. Tied off explicitly so lint does not flag it as dangling.
  logic [31:0] unused_addr;
  assign unused_addr = revbm_addr_i;

endmodule
