# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_dummy_instr -- data-independent timing and dummy instruction insertion with
# cheriot_enable_i asserted
# =============================================================================
# The same loop of CHERI work runs twice (capability derivation, CGet*, a CSC/CLC round trip and
# CSEQX, every result checked):
#   pass 1  cpuctrlsts.data_ind_timing set   (codes 10-12, trap 91)
#   pass 2  cpuctrlsts.dummy_instr_en set, dummy_instr_mask 0: a dummy instruction every few
#           real ones                        (codes 20-22, trap 92)
#
# Expected values: each CHERI result from the CHERIoT ISA; for pass 2, Ibex's documentation of
# dummy instruction insertion (doc/03_reference/security.rst): "The dummy instructions have no
# functional impact on processor state". So neither pass may trap and no result may change.
#
# cpuctrlsts in CHERIoT mode: Ibex implements it and so does the CHERIoT-Sail platform (spec
# GAP-CS-3). If an RTL change made it illegal, the first write would trap and the test would end
# with code 90.
#
# Found by code reading, not yet seen in simulation: ibex_dummy_instr.sv draws rs1 and rs2 of a
# dummy instruction from all 32 registers, while in CHERIoT mode ibex_decoder.sv's illegal_reg_16
# makes any instruction naming x16-x31 illegal, with no exemption for dummy instructions. A dummy
# instruction may then raise an illegal-instruction exception. Expected outcome:
#   FAIL, code 92   the finding is real: the first trap's mcause (2), mtval and MEPCC.address are
#                   in G_MCAUSE/G_MTVAL/G_MEPC and the entry count in G_ENTRIES (all visible as
#                   stores in the trace). An RTL finding, not a test error.
#   PASS            the finding is not real (dummy instructions never trap in CHERIoT mode).
#   FAIL, code 90   cpuctrlsts traps in CHERIoT mode (see above).
#
# Handler and dummy instructions: a trap in pass 2 enters the handler with dummy_instr_en still
# set, and a handler interleaved with dummies would re-trap on the next dummy naming x16-x31
# (a trap storm ending in a timeout, not code 92). So the first instruction of trap_handler is
# `csrci cpuctrlsts, dummy_instr_en` (MTCC has SR), and a cpuctrlsts write
# flushes the pipeline (ibex_id_stage.sv csr_pipe_flush), so no already-fetched dummy survives
# it. A dummy inserted at the handler's entry, before the csrci, can still trap once more: the
# handler therefore records mcause/mtval/MEPCC only on its first entry and counts entries in
# G_ENTRIES, so a re-entry shows up as G_MEPC = trap_handler instead of silently overwriting the
# original fault. Setup and pass 1 are vectored at trap_record, the same handler without the
# csrci: if cpuctrlsts itself were illegal, a csrci-first handler would trap on its own first
# instruction forever instead of reporting code 90. The vector moves to trap_handler only once
# pass 1 has proven cpuctrlsts writable.
#
# Cosim off: +disable_cosim=1 for Spike, and the CHERIoT-Sail oracle does not run when the pin is
# raised mid-test by +cheriot_enable_on_write (it runs only with +enable_cheriot_seq). Codes: 5/6 the cpuctrlsts bit did not read back as set; 9 debug entry; 90 a trap
# outside the passes (including a cpuctrlsts write), 91 / 92 a trap in pass 1 / pass 2; 99
# liveness (iterations completed).

#include "cheriot_dv.h"

#define G_PASS       0
#define G_DONE       4
#define G_MCAUSE     8
#define G_MTVAL      12
#define G_MEPC       16
#define G_ENTRIES    20      /* trap handler entries; > 1 or G_MEPC = trap_handler: a re-entry */
#define G_SLOT       24      /* 8-byte aligned capability slot */
#define GLOBALS_SIZE 32

#define NITER        32
#define CSR_CPUCTRLSTS 0x7c0
#define CPUCTRL_DIT    2
#define CPUCTRL_DUMMY  4
#define CPUCTRL_MASK   0x38  /* dummy_instr_mask */

    .option norvc

    DV_VECTORS unexpected_debug, unexpected_debug
_start:
    ENABLE_CHERIOT_VIA_TRIGGER
    j         main

    .text
main:
    SET_VEC   trap_record, t1, t0         # no csrci until cpuctrlsts is known to be writable
    SIG_INIT
    DCAP_FAR  a5, globals, t0
    li        t0, GLOBALS_SIZE
    csetboundsexact a5, a5, t0
    li        t0, 0x1800
    csrs      mstatus, t0
    SIG_CSR   0x300
    SIG_CSR   0x304
    SIG_STATUS ST_INITIALIZED

# NITER iterations of CHERI work; a1/a2 derived from a5, each result checked. Codes \code ..
# \code+2. Counts completed iterations in G_DONE. Clobbers s0, a1, a2, t0, t1.
.macro WORK code
    li        s0, NITER
6:  cmove     a1, a5
    cincaddrimm a1, a1, 8
    csetboundsimm a1, a1, 16
    cgetlen   t0, a1
    CHECK_EQI t0, 16, \code, t1
    cgetbase  t0, a1
    cgetbase  t1, a5
    addi      t1, t1, 8
    CHECK_EQ  t0, t1, \code+1
    csc       a1, a5, G_SLOT
    clc       a2, a5, G_SLOT
    cseqx     t0, a1, a2
    CHECK_EQI t0, 1, \code+2, t1
    lw        t0, G_DONE(a5)
    addi      t0, t0, 1
    sw        t0, G_DONE(a5)
    addi      s0, s0, -1
    bnez      s0, 6b
.endm

    # ── pass 1: data-independent timing ──────────────────────────────────────
    # G_PASS after the CSR write: a trap on the write itself (cpuctrlsts illegal)
    # must read as code 90, not as a pass-1 trap.
    csrsi     CSR_CPUCTRLSTS, CPUCTRL_DIT
    csrr      t0, CSR_CPUCTRLSTS
    andi      t0, t0, CPUCTRL_DIT
    CHECK_EQI t0, CPUCTRL_DIT, 5, t1
    li        t0, 1
    sw        t0, G_PASS(a5)
    WORK      10
    csrci     CSR_CPUCTRLSTS, CPUCTRL_DIT
    sw        zero, G_PASS(a5)

    # ── pass 2: dummy instruction insertion ──────────────────────────────────
    SET_VEC   trap_handler, t1, t0        # pass 1 proved cpuctrlsts writable: csrci-first handler
    # G_PASS before the enable: a dummy can trap on the very next instruction (seed 8082,
    # 2026-10-08: MEPCC = the instruction after the read-back, reported as code 90).
    li        t0, 2
    sw        t0, G_PASS(a5)
    li        t0, CPUCTRL_MASK
    csrc      CSR_CPUCTRLSTS, t0
    csrsi     CSR_CPUCTRLSTS, CPUCTRL_DUMMY
    csrr      t0, CSR_CPUCTRLSTS
    andi      t0, t0, CPUCTRL_DUMMY
    CHECK_EQI t0, CPUCTRL_DUMMY, 6, t1
    WORK      20
    csrci     CSR_CPUCTRLSTS, CPUCTRL_DUMMY
    sw        zero, G_PASS(a5)

    lw        t0, G_DONE(a5)
    CHECK_EQI t0, 2 * NITER, 99, t1
    li        a0, 0
test_end:
    TEST_END_A0

unexpected_debug:
    li        a0, 9
    j         test_end

# ---- Trap handler: no trap is expected; record the first one and fail with 90 + pass ----------
# trap_handler (vector in pass 2): stop dummy insertion before anything else, see the header.
# trap_record (vector in setup and pass 1): the same handler without the csrci.
    .balign 4
trap_handler:
    csrci     CSR_CPUCTRLSTS, CPUCTRL_DUMMY   # first instruction: no dummies in the handler
trap_record:
    DCAP_FAR  a1, globals, t0
    lw        t0, G_ENTRIES(a1)
    addi      t0, t0, 1
    sw        t0, G_ENTRIES(a1)
    li        t1, 1
    bne       t0, t1, 1f                  # record the first entry only
    csrr      t0, mcause
    sw        t0, G_MCAUSE(a1)
    csrr      t0, mtval
    sw        t0, G_MTVAL(a1)
    cspecialr a2, SCR_MEPCC
    cgetaddr  t0, a2
    sw        t0, G_MEPC(a1)
1:  lw        t0, G_PASS(a1)
    addi      a0, t0, 90
    j         test_end

    .data
    .balign 8
globals:
    .fill GLOBALS_SIZE / 4, 4, 0
