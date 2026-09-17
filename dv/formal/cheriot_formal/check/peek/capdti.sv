// Copyright lowRISC contributors.
// Copyright 2024 University of Oxford, see also CREDITS.md.
// Licensed under the Apache License, Version 2.0 (see LICENSE for details).
// Original Author: Louis-Emile Ploix
// SPDX-License-Identifier: Apache-2.0

/*
The following implements the datatype invariant properties
for each major basic block.
*/

function automatic logic regCapSatsMemConstraint(cap_t c, logic [31:0] a);
  exp_t        exp5   = cheriot_expand_exp(c.cexp);
  CapBoundBits bounds = getCapBoundsBitsRaw(exp5, c.base, c.top, a);
  return
    (c.valid -> (
          (bounds.top <= 33'h1_0000_0000) &&
          ((c.cexp == MAXCEXP) -> ~c.base[9'd8]) &&
          ((c.cexp != MAXCEXP) -> (unsigned'(bounds.base) <= unsigned'(bounds.top)))
        ));
endfunction

function automatic logic pccCapSatsMemConstraint(decoded_cap_t c, logic [31:0] a);
  return
    (c.valid -> (
        (c.top33 <= 33'h1_0000_0000) &&
        (c.cexp != MAXCEXP -> unsigned'(c.base32) <= unsigned'(c.top33))
      ));
endfunction

function automatic logic regCapSatsDTI(cap_t c, logic [31:0] a);
  exp_t    exp5   = cheriot_expand_exp(c.cexp);
  cbound_t a_mant = cbound_t'(a >> exp5);
  return (
    c.cap_cor == cheriot_compute_corrections(c.top, c.base, a_mant) &&
    regCapSatsMemConstraint(c, a)
  );
endfunction

function automatic logic fullCapSatsDTI(decoded_cap_t c, logic [31:0] a);
  exp_t    exp5   = cheriot_expand_exp(c.cexp);
  cbound_t a_mant = cbound_t'(a >> exp5);
  return  (
    c.cap_cor == cheriot_compute_corrections(c.top, c.base, a_mant) &&
    regCapSatsMemConstraint(cheriot_encode_cap(c), a) &&
    cheriot_expand_perms(c.cperms) == c.perms
  );
endfunction

function automatic logic pccCapSatsDTI(decoded_cap_t c, logic [31:0] a);
  exp_t        exp5   = cheriot_expand_exp(c.cexp);
  CapBoundBits bounds = getCapBoundsBitsRaw(exp5, c.base, c.top, a);
  return (
    pccCapSatsMemConstraint(c, a) &&
    cheriot_expand_perms(c.cperms) == c.perms &&
    (c.base32 == bounds.base && c.top33 == bounds.top)
  );
endfunction

function automatic logic fullCapSatsDTIStrong(decoded_cap_t c, logic [31:0] a);
  exp_t        exp5   = cheriot_expand_exp(c.cexp);
  cbound_t     a_mant = cbound_t'(a >> exp5);
  CapBoundBits bounds = getCapBoundsBitsRaw(exp5, c.base, c.top, a);
  return (
    (c.base32 == bounds.base && c.top33 == bounds.top) &&
    c.cap_cor == cheriot_compute_corrections(c.top, c.base, a_mant) &&
    regCapSatsMemConstraint(cheriot_encode_cap(c), a) &&
    cheriot_expand_perms(c.cperms) == c.perms
  );
endfunction

function automatic logic fullCapSatsDTIStrongNoCor(decoded_cap_t c, logic [31:0] a);
  exp_t        exp5   = cheriot_expand_exp(c.cexp);
  CapBoundBits bounds = getCapBoundsBitsRaw(exp5, c.base, c.top, a);
  return (
    (c.base32 == bounds.base && c.top33 == bounds.top) &&
    regCapSatsMemConstraint(cheriot_encode_cap(c), a) &&
    cheriot_expand_perms(c.cperms) == c.perms
  );
endfunction

///////////////// Execute Block (stateless) /////////////////

logic ex_in_sats;
assign ex_in_sats =
  regCapSatsDTI(`CE.fwd_wcap_i, `CE.fwd_wdata_i) &&
  regCapSatsDTI(`CE.rf_rcap_a_i, `CE.rf_rdata_a_i) &&
  regCapSatsDTI(`CE.rf_rcap_b_i, `CE.rf_rdata_b_i) &&
  regCapSatsDTI(`CE.csr_rcap_i, `CE.csr_rdata_i) &&
  pccCapSatsDTI(`CE.pcc_cap_i, pcc_address_q);

logic ex_out_csr_sats;
assign ex_out_csr_sats = regCapSatsDTI(`CE.csr_wcap_o, `CE.csr_wdata_o);

logic ex_out_lsu_sats;
assign ex_out_lsu_sats = regCapSatsDTI(`CE.lsu_wcap_o, `CE.lsu_wdata_o[31:0]);

logic ex_out_result_sats;
assign ex_out_result_sats = regCapSatsDTI(`CE.result_cap_o, `CE.result_data_o);

logic ex_out_pcc_sats;
assign ex_out_pcc_sats = pccCapSatsDTI(`CE.pcc_cap_o, `CE.rf_rdata_a);

logic ex_inner_sats;
assign ex_inner_sats =
    fullCapSatsDTIStrong(`CE.rf_fullcap_a, `CE.rf_rdata_a) &&
    fullCapSatsDTIStrong(`CE.rf_fullcap_b, `CE.rf_rdata_b);

///////////////// CSR Block /////////////////

`define DutCSRs(X) \
  `X(mtvec, `CSR.mtvec_cap, `CSR.mtvec_q) \
  `X(mepc, `CSR.mepc_cap, `CSR.mepc_q) \
  `X(mtdc, `CSRG.mtdc_cap, `CSRG.mtdc_data) \
  `X(mscratchc, `CSRG.mscratchc_cap, `CSRG.mscratchc_data) \
  `X(depc, `CSR.depc_cap, `CSR.depc_q) \
  `X(dscratch0, `CSR.dscratch0_cap, `CSR.dscratch0_q) \
  `X(dscratch1, `CSR.dscratch1_cap, `CSR.dscratch1_q)

`define X(nm, cap, data) \
  logic csr_``nm``_sats; \
  assign csr_``nm``_sats = regCapSatsDTI(cap, data);
`DutCSRs(X)
`undef X

logic csr_out_pcc_sats;
assign csr_out_pcc_sats = pccCapSatsDTI(`CSR.pcc_cap_o, pcc_address_q);

logic csr_int;
`define X(nm, cap, data) csr_``nm``_sats &&
assign csr_int = `DutCSRs(X) csr_out_pcc_sats;
`undef X

logic csr_in;
assign csr_in =
  csr_int && regCapSatsDTI(`CSR.cheriot_csr_wcap_i, `CSR.cheriot_csr_wdata_i) &&
  (`CSR.cheriot_branch_req_i -> pccCapSatsDTI(`CSR.pcc_cap_i, pcc_address_d));

logic csr_out_rdata_sats;
assign csr_out_rdata_sats = regCapSatsDTI(`CSR.cheriot_csr_rcap_o, `CSR.cheriot_csr_rdata_o);

// `define Y(nm, cap1, data1) \
//   DTI_CSR``nm: assert property (nm``_sats);
// `DutCSRs(Y)
// `undef Y

///////////////// Writeback Block /////////////////

logic wb_in;
assign wb_in = regCapSatsDTI(`WB.cheriot_rf_wcap_i, `WB.cheriot_rf_wdata_i);

logic wb_int;
assign wb_int = regCapSatsDTI(`WBG.cheriot_rf_wcap_q, `WBG.cheriot_rf_wdata_q);

logic wb_in_lsu;
assign wb_in_lsu = regCapSatsDTI(`WB.rf_wcap_lsu_i, `WB.rf_wdata_lsu_i);

logic wb_out;
assign wb_out =
    regCapSatsDTI(`WB.rf_wcap_fwd_wb_o, `WB.rf_wdata_fwd_wb_o) &&
    regCapSatsDTI(`WB.rf_wcap_wb_o, `WB.rf_wdata_wb_o);

// This is part of the DTI, which is true - meaning anything written to memory
// satisfies this, meaning anything loaded from memory would, hence this assumption is 'safe'.
// FIXME: This should really be on the raw capability bits, instead of the decoded capability.
MemConstraint: assume property (regCapSatsMemConstraint(`WB.rf_wcap_lsu_i, `WB.rf_wdata_lsu_i));

///////////////// RF Block (16 regs) /////////////////

`define RFC(i) regCapSatsDTI(`RF.g_cheriot_rf.rf_shared[i], `RF.g_cheriot_rf.rf_data[i]) &&

// Splitting this up makes these properties prove faster
logic rf_group1, rf_group2, rf_all;

assign rf_group1 = `RFC(1) `RFC(2) `RFC(3) `RFC(4) `RFC(5) `RFC(6) `RFC(7) `RFC(8) 1;
assign rf_group2 = `RFC(9) `RFC(10) `RFC(11) `RFC(12) `RFC(13) `RFC(14) `RFC(15) 1;
assign rf_all = rf_group1 & rf_group2;

logic rf_in;
assign rf_in = regCapSatsDTI(`RF.wcap_a_i, `RF.wdata_a_i);

logic rf_out_a;
assign rf_out_a = regCapSatsDTI(`RF.rcap_a_o, `RF.rdata_a_o);
logic rf_out_b;
assign rf_out_b = regCapSatsDTI(`RF.rcap_b_o, `RF.rdata_b_o);
