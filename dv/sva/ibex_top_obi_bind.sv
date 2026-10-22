// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// OBI protocol checks on ibex_top's three memory ports (ibex_obi_assert.sv). ibex_top is the host
// on all three: its requests are checked, and what the memory answers is checked as well in
// simulation (assumed in formal).
//
// Paths for DV_ASSERT_CTRL: <ibex_top>.u_obi_assert_{instr,data,revbm}.g_<Rule>.<Rule>.

bind ibex_top ibex_obi_assert #(
  .EndpointType    ("Host"),
  // Prefetch buffer or ICache fill buffers: the limit depends on the configuration.
  .MaxOutstanding  (0),
  .ReadOnly        (1'b1)
) u_obi_assert_instr (
  .clk_i      (clk_i),
  .rst_ni     (rst_ni),
  .req        (instr_req_o),
  .gnt        (instr_gnt_i),
  .addr       (instr_addr_o),
  .we         (1'b0),
  .be         (4'hf),
  .wdata      (32'h0),
  .wdata_intg (7'h0),
  .wtag       (1'b0),
  .rvalid     (instr_rvalid_i),
  .rdata      (instr_rdata_i),
  .rdata_intg (instr_rdata_intg_i),
  .err        (instr_err_i),
  .rtag       (1'b0)
);

bind ibex_top ibex_obi_assert #(
  .EndpointType    ("Host"),
  .MaxOutstanding  (MaxOutstandingDSideAccesses),
  // SecureIbex checks the integrity of every response, so its data must be known on writes too.
  .RdataOnWriteResp(SecureIbex)
) u_obi_assert_data (
  .clk_i      (clk_i),
  .rst_ni     (rst_ni),
  .req        (data_req_o),
  .gnt        (data_gnt_i),
  .addr       (data_addr_o),
  .we         (data_we_o),
  .be         (data_be_o),
  .wdata      (data_wdata_o),
  .wdata_intg (data_wdata_intg_o),
  .wtag       (data_tag_o),
  .rvalid     (data_rvalid_i),
  .rdata      (data_rdata_i),
  .rdata_intg (data_rdata_intg_i),
  .err        (data_err_i),
  .rtag       (data_tag_i)
);

// The TRVK's revocation-bitmap reads: one in flight at a time (ibex_trvk.sv revbm_outstanding_q).
// Idle unless BaseIsa is CHERIoT.
bind ibex_top ibex_obi_assert #(
  .EndpointType    ("Host"),
  .MaxOutstanding  (1),
  .ReadOnly        (1'b1)
) u_obi_assert_revbm (
  .clk_i      (clk_i),
  .rst_ni     (rst_ni),
  .req        (trvk_revbm_req_o),
  .gnt        (trvk_revbm_gnt_i),
  .addr       (trvk_revbm_addr_o),
  .we         (1'b0),
  .be         (4'hf),
  .wdata      (32'h0),
  .wdata_intg (7'h0),
  .wtag       (1'b0),
  .rvalid     (trvk_revbm_rvalid_i),
  .rdata      (trvk_revbm_rdata_i),
  .rdata_intg (trvk_revbm_rdata_intg_i),
  .err        (trvk_revbm_err_i),
  .rtag       (1'b0)
);
