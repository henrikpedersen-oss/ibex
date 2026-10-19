# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_minstret_exact -- minstret in CHERIoT mode counts exactly the instructions retired
# =============================================================================
# The CHERIoT counterpart of minstret_exact (RISC-V mode). Written for the TestRIG cheriot
# mismatches of 2026-10-19: with minstret/instret reads compared, the core read up to 14 more than
# CHERIoT-Sail, always in QuickCheckVEngine's capcsr pattern -- AUIPCC, CAndPerm clearing SR,
# CSpecialW MTCC (a trap vector without SR), a CJALR that traps, then counter CSRs read in the
# handler without SR. The checks below are exact counts from the specifications, so the test says
# whether the core counts correctly; CHERIoT-Sail cosim stays on (it compares minstret/instret
# reads since 2026-10-19), so the same run says whether the model agrees.
#
# Method: each check brackets a short sequence between two reads (s0, then a4) and compares the
# difference with the instructions that retire in between, plus 1 for the first read itself. With
# PCC.SR the reads are minstret (0xB02); without SR they are instret (0xC02). Both are on CHERIoT's
# list of CSRs readable without SR (with mcycle and the h halves: CHERIoT-Sail cheri_addr_checks.sail
# ext_check_CSR, ibex_decoder.sv csr_cheriot_always_ok_o), so the SR fault uses mscratch. Trap
# handlers are exactly two instructions (cspecialw MEPCC, mret) with the resume capability built
# beforehand, so a trap check expects 1 + 2 = 3.
#
# Expected behaviour (not taken from the RTL):
#   - RISC-V Unprivileged ISA, Zicsr: a read returns the count of the instructions retired before
#     it. Privileged ISA: an instruction that takes an exception does not retire; mret retires.
#   - CHERIoT ISA / CHERIoT-Sail: the CHERI instructions (AUIPCC, CAndPerm, CSetAddr, CSetBounds,
#     CSpecialR/W, CLC, CSC, CJALR) are instructions like any other: one each when they complete.
#     A CSR access that needs SR (any but the counter reads on the allowlist), executed without
#     SR, raises a CHERI exception (mcause 28, mtval 0x418) and does not retire. A CJALR through an untagged c0 raises a CHERI exception.
#
# Checks and failure codes (main returns 0 or the first failing code; a2 = the difference
# measured, so the trace shows what the core counted)
#   10-19  with SR: nothing, AUIPCC, CAndPerm, CSetAddr, CSetBounds, CSpecialR, CLC, CSC, CJALR
#          (taken, no trap), instret around a nop
#   20/21  CJALR through c0 traps (3), mcause 28
#   22/23  an unimplemented CSR (time, 0xC01) traps (3), mcause 2
#   34/35  a CLC beyond its authority's bounds traps (3; a fault reported in WB), mcause 28
#   24     without SR: instret around a nop (2)
#   26-28  without SR: an mscratch read faults on SR (3), mcause 28, mtval 0x418
#   30-32  the TestRIG pattern: CSpecialW MTCC (no SR), CJALR traps into the SR-less handler,
#          which jumps back (3); mcause 28; MTCC restored
#   250    an unexpected trap        251  liveness (not every check ran)
#
# Proving it can fail (build-time switch, not in the testlist):
#   -DCHERIOT_MINSTRET_INJECT_FAIL  adds an uncounted nop to check 11's sequence -> 11

#include "cheriot_dv.h"

#define CSR_MINSTRET 0xB02
#define CSR_INSTRET  0xC02
#define CSR_TIME     0xC01

    .option norelax
    .option norvc

# a4 - s0 must be \exp (the difference left in a2).
.macro DELTA exp, code
    sub       a2, a4, s0
    EXPECT_EQI a2, \exp, \code
.endm

# ca0 := MTCC without SR (bit 7), as cheriot_mshwm builds it.
.macro MTCC_NOSR
    cspecialr a0, SCR_MTCC
    li        t0, 0xF7F
    candperm  a0, a0, t0
.endm

# Jump to \label through ca0 (no SR).
.macro ENTER_NOSR label
    LA_FAR    t0, \label, a5
    csetaddr  a5, a0, t0
    jalr      zero, 0(a5)
.endm

# \cd := MTCC with its cursor at \sym (built while PCC has SR).
.macro MTCC_AT cd, sym
    LA_FAR    t0, \sym, \cd
    cspecialr \cd, SCR_MTCC
    csetaddr  \cd, \cd, t0
.endm

    .text
    .globl main
main:
    li        s1, 0
    SET_VEC   .Lunexpected, t0, t1
    cspecialr a1, SCR_MTDC
    LA_FAR    t0, cbuf, a2
    csetaddr  a1, a1, t0                    # ca1 = MTDC @ cbuf: load / store authority

    # ── 10-19: with SR ───────────────────────────────────────────────────────
    csrr      s0, CSR_MINSTRET
    csrr      a4, CSR_MINSTRET
    DELTA     1, 10

    csrr      s0, CSR_MINSTRET
    auipcc    a3, 0
#ifdef CHERIOT_MINSTRET_INJECT_FAIL
    nop
#endif
    csrr      a4, CSR_MINSTRET
    DELTA     2, 11

    li        t0, 0xFFF
    csrr      s0, CSR_MINSTRET
    candperm  a3, a1, t0
    csrr      a4, CSR_MINSTRET
    DELTA     2, 12

    li        t0, 0x10
    add       t0, t0, a1
    csrr      s0, CSR_MINSTRET
    csetaddr  a3, a1, t0
    csrr      a4, CSR_MINSTRET
    DELTA     2, 13

    li        t0, 16
    csrr      s0, CSR_MINSTRET
    csetbounds a3, a1, t0
    csrr      a4, CSR_MINSTRET
    DELTA     2, 14

    csrr      s0, CSR_MINSTRET
    cspecialr a3, SCR_MTDC
    csrr      a4, CSR_MINSTRET
    DELTA     2, 15

    csrr      s0, CSR_MINSTRET
    clc       a3, a1, 0
    csrr      a4, CSR_MINSTRET
    DELTA     2, 16

    csrr      s0, CSR_MINSTRET
    csc       a1, a1, 8
    csrr      a4, CSR_MINSTRET
    DELTA     2, 17

    MTCC_AT   a3, .Lj18
    csrr      s0, CSR_MINSTRET
    jalr      zero, 0(a3)
    nop                                     # skipped
    .balign 4
.Lj18:
    csrr      a4, CSR_MINSTRET
    DELTA     2, 18

    csrr      s0, CSR_INSTRET
    nop
    csrr      a4, CSR_INSTRET
    DELTA     2, 19

    # ── 20-23: traps taken with SR (handlers are 2 instructions) ─────────────
    MTCC_AT   a3, .Lr20
    SET_VEC   .Lh20, t0, t1
    csrr      s0, CSR_MINSTRET
    jalr      zero, 0(zero)                 # CJALR through c0: untagged
    .balign 4
.Lh20:
    cspecialw SCR_MEPCC, a3
    mret
    .balign 4
.Lr20:
    csrr      a4, CSR_MINSTRET
    SET_VEC   .Lunexpected, t0, t1
    DELTA     3, 20
    csrr      t1, mcause
    EXPECT_EQI t1, MCAUSE_CHERI, 21

    MTCC_AT   a3, .Lr22
    SET_VEC   .Lh22, t0, t1
    csrr      s0, CSR_MINSTRET
    csrr      t1, CSR_TIME                  # not implemented: illegal instruction
    .balign 4
.Lh22:
    cspecialw SCR_MEPCC, a3
    mret
    .balign 4
.Lr22:
    csrr      a4, CSR_MINSTRET
    SET_VEC   .Lunexpected, t0, t1
    DELTA     3, 22
    csrr      t1, mcause
    EXPECT_EQI t1, 2, 23

    # ── 34/35: a CLC beyond its authority's bounds traps (load fault, reported in WB) ──
    li        t0, 8
    csetbounds a2, a1, t0                   # ca2 = 8 bytes at cbuf
    MTCC_AT   a3, .Lr34
    SET_VEC   .Lh34, t0, t1
    csrr      s0, CSR_MINSTRET
    clc       a5, a2, 16                    # cbuf + 16: outside ca2
    .balign 4
.Lh34:
    cspecialw SCR_MEPCC, a3
    mret
    .balign 4
.Lr34:
    csrr      a4, CSR_MINSTRET
    SET_VEC   .Lunexpected, t0, t1
    DELTA     3, 34
    csrr      t1, mcause
    EXPECT_EQI t1, MCAUSE_CHERI, 35

    # ── 24: without SR, instret around a nop ─────────────────────────────────
    MTCC_NOSR
    MTCC_AT   a3, .Lb24                     # way back, with SR
    ENTER_NOSR .Ln24
    .balign 4
.Ln24:
    csrr      s0, CSR_INSTRET
    nop
    csrr      a4, CSR_INSTRET
    jalr      zero, 0(a3)
    .balign 4
.Lb24:
    DELTA     2, 24

    # ── 26-28: without SR, an mscratch read faults on SR and does not retire ──
    MTCC_NOSR
    MTCC_AT   a3, .Lb26                     # way back, with SR
    LA_FAR    t0, .Lr26, a2
    csetaddr  a2, a0, t0                    # ca2 = the resume point, without SR
    SET_VEC   .Lh26, t0, t1                 # the handler runs on MTCC: with SR
    ENTER_NOSR .Ln26
    .balign 4
.Ln26:
    csrr      s0, CSR_INSTRET
    csrr      t1, mscratch                  # needs SR: CHERI exception
    .balign 4
.Lh26:
    cspecialw SCR_MEPCC, a2
    mret
    .balign 4
.Lr26:
    csrr      a4, CSR_INSTRET
    jalr      zero, 0(a3)
    .balign 4
.Lb26:
    SET_VEC   .Lunexpected, t0, t1
    DELTA     3, 26
    csrr      t1, mcause
    EXPECT_EQI t1, MCAUSE_CHERI, 27
    csrr      t1, mtval
    EXPECT_EQI t1, 0x418, 28

    # ── 30-32: the TestRIG capcsr pattern ────────────────────────────────────
    cspecialr a5, SCR_MTCC                  # the MTCC to restore (with SR)
    MTCC_AT   a3, .Lb30                     # way back, with SR
    cspecialr a0, SCR_MTCC
    li        t0, 0xF7F
    candperm  a0, a0, t0                    # MTCC without SR ...
    LA_FAR    t0, .Lh30, a2
    csetaddr  a0, a0, t0                    # ... at .Lh30
    csrr      s0, CSR_MINSTRET
    cspecialw SCR_MTCC, a0                  # a trap vector without SR
    jalr      zero, 0(zero)                 # traps into .Lh30, without SR
    .balign 4
.Lh30:
    jalr      zero, 0(a3)                   # back to SR code
    .balign 4
.Lb30:
    csrr      a4, CSR_MINSTRET
    cspecialw SCR_MTCC, a5
    SET_VEC   .Lunexpected, t0, t1
    DELTA     3, 30
    csrr      t1, mcause
    EXPECT_EQI t1, MCAUSE_CHERI, 31
    cspecialr a3, SCR_MTCC
    cgetperm  t1, a3
    cgetperm  t0, a5
    EXPECT_EQ t1, t0, 32

    CHECK_LIVENESS 251
    li        a0, 0
    j         .Lexit

    .balign 4
.Lunexpected:
    li        a0, 250
.Lexit:                                     # may run without SR: no CSR access here
    ret

    .data
    .balign 16
cbuf:
    .space  32
