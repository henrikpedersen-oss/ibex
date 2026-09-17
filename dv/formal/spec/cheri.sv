// Copyright lowRISC contributors.
// Copyright 2024 University of Oxford, see also CREDITS.md.
// Licensed under the Apache License, Version 2.0 (see LICENSE for details).
// Original Author: Louis-Emile Ploix
// SPDX-License-Identifier: Apache-2.0

import ibex_cheriot_pkg::*;

function automatic t_Capability dataCap(logic [31:0] address);
    return '{
        B: '0,
        E: '0,
        T: '0,
        access_system_regs: '0,
        address: address,
        zglobal: '0,
        otype: '0,
        perm_user0: '0,
        permit_execute: '0,
        permit_load: '0,
        permit_load_global: '0,
        permit_load_mutable: '0,
        permit_load_store_cap: '0,
        permit_seal: '0,
        permit_store: '0,
        permit_store_local_cap: '0,
        permit_unseal: '0,
        reserved: '0,
        tag: '0
    };
endfunction

function automatic t_Capability nullCap();
    return dataCap(32'b0);
endfunction

function automatic t_Capability encodeDecodePermsOf(t_Capability capability);
    return encCapabilityToCapability(capability.tag, capToEncCap(capability));
endfunction

function automatic t_Capability regcap2sail(cap_t capability, logic [31:0] address);
    logic [63:0] bits;
    bits = {cheriot_cap_to_mem(capability)[31:0], address};
    return capBitsToCapability(capability.valid, bits);
endfunction

function automatic t_Capability fullcap2sail(decoded_cap_t capability, logic [31:0] address);
    return regcap2sail(cheriot_encode_cap(capability), address);
endfunction

function automatic t_Capability pcc2sail(decoded_cap_t capability, logic [31:0] address);
    return fullcap2sail(capability, address);
endfunction

// 'at least as strict', i.e. the DUT may clear a tag the spec wouldn't
function automatic logic alas(t_Capability spec, t_Capability dut);
    if (!dut.tag) spec.tag = 1'b0;
    return dut == spec;
endfunction

function automatic t_Capability revoke(t_Capability cap, logic strip);
    if (strip) cap.tag = 1'b0;
    return cap;
endfunction

function automatic t_Capability onlySealingPerms(t_Capability cap);
    cap.access_system_regs = '0;
    cap.zglobal = '0;
    cap.permit_execute = '0;
    cap.permit_load = '0;
    cap.permit_load_global = '0;
    cap.permit_load_mutable = '0;
    cap.permit_load_store_cap = '0;
    cap.permit_store = '0;
    cap.permit_store_local_cap = '0;
    return cap;
endfunction

// The following are used only by the DTI:

typedef struct packed {
    logic [31:0] base;
    logic [32:0] top;
} CapBoundBits;

typedef struct packed {
    logic       base_cor;
    logic [1:0] top_cor;
} CapBoundCorBits;

function automatic CapBoundBits getCapBoundsBitsRaw(logic [4:0] E, logic [8:0] B, logic [8:0] T, logic [31:0] a);
    logic[CBOUND_W-1:0] a_mid = {a >> E}[CBOUND_W-1:0];
    logic a_hi = a_mid < B;
    logic t_hi = T < B;
    logic [31:0] base_cor = 0 - a_hi;
    logic [31:0] top_cor = t_hi - a_hi;
    logic [31:0] a_top = a >> (E + CBOUND_W);

    logic [31:0] base = {a_top + signed'(base_cor), B}[ADDR_W-1:0];
    logic[ADDR_W:0] top = {a_top + signed'(top_cor), T}[ADDR_W:0];
    base <<= E;
    top <<= E;

    return '{base, top};
endfunction

function automatic CapBoundCorBits getCapBoundsCorBitsRaw(logic [4:0] E, logic [8:0] B, logic [8:0] T, logic [31:0] a);
    logic [1:0] base2, top2;

    logic[CBOUND_W-1:0] a_mid = {a >> E}[CBOUND_W-1:0];
    logic a_hi = a_mid < B;
    logic t_hi = T < B;
    logic base_cor = a_hi;
    logic [31:0] top_cor = t_hi - a_hi;
    
    return '{base_cor, top_cor[1:0]};
endfunction

function automatic logic[1:0] getRegCapTopCor(cap_t c, logic [31:0] a);
  exp_t    exp5  = cheriot_expand_exp(c.cexp);
  cbound_t a_mid = cbound_t'(a >> exp5);
  return cheriot_get_top_correction(cheriot_compute_corrections(c.top, c.base, a_mid));
endfunction

function automatic logic getRegCapBaseCor(cap_t c, logic [31:0] a);
  exp_t    exp5  = cheriot_expand_exp(c.cexp);
  cbound_t a_mid = cbound_t'(a >> exp5);
  return cheriot_get_base_correction(cheriot_compute_corrections(c.top, c.base, a_mid))[0];
endfunction
