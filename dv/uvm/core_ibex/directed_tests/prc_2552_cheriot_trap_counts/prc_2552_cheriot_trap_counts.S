# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: prc_2552_cheriot_trap_counts -- CHERIoT faults the PR names do not retire
#                                       (lowRISC/ibex PR #2552)
# =============================================================================
# PR #2552 says a CHERIoT fault raised in writeback still incremented minstret. Its reproduction
# programs (in the PR description) cover cases that cheriot_minstret_exact does not:
#   40/41  c.jr through an untagged register (compressed CJALR): traps (mcause 28), not counted
#   42/43  CSpecialR of MSCRATCHC from code without SR: traps (mcause 28), not counted
#   44/45  CSpecialR of SCR 0 (no such SCR): illegal instruction (mcause 2), not counted
# (cheriot_minstret_exact already covers CJALR through c0, an mscratch read without SR and a CLC
# out of bounds.) The PR's fifth case, CSetBounds with cdbg_ctrl[0] = 1, does not apply here:
# cdbg_ctrl is not a CSR in this core.
#
# Method as in cheriot_minstret_exact: each check brackets the faulting instruction between two
# reads (s0, a4) of minstret (instret without SR); the trap handler is exactly two instructions
# (cspecialw MEPCC, mret), so the difference must be 1 + 2 = 3 (Privileged ISA: an instruction
# that takes an exception does not retire). CHERIoT-Sail cosim on.
#
# Codes (main returns 0 or the first failing code; a2 = the difference measured):
#   40 c.jr count   41 its mcause   42 CSpecialR MSCRATCHC count   43 its mcause
#   44 SCR 0 count  45 its mcause   250 an unexpected trap         251 liveness

#include "cheriot_dv.h"

#define CSR_MINSTRET 0xB02
#define CSR_INSTRET  0xC02
# CSpecialRW cd, scr, cs1 (cs1 = c0: a read), raw: SCR 0 has no assembler name.
#define CSPECIALR_RAW(cd, scr) .word (0x01<<25)|((scr)<<20)|((cd)<<7)|0x5b
#define REG_A5 15

    .option norelax
    .option norvc

.macro DELTA exp, code
    sub       a2, a4, s0
    EXPECT_EQI a2, \exp, \code
.endm

# ca0 := MTCC without SR (bit 7).
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

    # ── 40/41: c.jr through an untagged register ─────────────────────────────
    MTCC_AT   a3, .Lr40
    SET_VEC   .Lh40, t0, t1
    li        a0, 0x80000000                # integer write: a0 untagged
    csrr      s0, CSR_MINSTRET
    .hword    0x8502                        # c.jr a0: CJALR through an untagged capability
    .hword    0x0001                        # c.nop (alignment; never reached)
    .balign 4
.Lh40:
    cspecialw SCR_MEPCC, a3
    mret
    .balign 4
.Lr40:
    csrr      a4, CSR_MINSTRET
    SET_VEC   .Lunexpected, t0, t1
    DELTA     3, 40
    csrr      t1, mcause
    EXPECT_EQI t1, MCAUSE_CHERI, 41

    # ── 42/43: without SR, CSpecialR of MSCRATCHC faults ─────────────────────
    MTCC_NOSR
    MTCC_AT   a3, .Lb42                     # way back, with SR
    LA_FAR    t0, .Lr42, a2
    csetaddr  a2, a0, t0                    # ca2 = the resume point, without SR
    SET_VEC   .Lh42, t0, t1                 # the handler runs on MTCC: with SR
    ENTER_NOSR .Ln42
    .balign 4
.Ln42:
    csrr      s0, CSR_INSTRET
    cspecialr a5, SCR_MSCRATCHC             # needs SR: CHERI exception
    .balign 4
.Lh42:
    cspecialw SCR_MEPCC, a2
    mret
    .balign 4
.Lr42:
    csrr      a4, CSR_INSTRET
    jalr      zero, 0(a3)
    .balign 4
.Lb42:
    SET_VEC   .Lunexpected, t0, t1
    DELTA     3, 42
    csrr      t1, mcause
    EXPECT_EQI t1, MCAUSE_CHERI, 43

    # ── 44/45: CSpecialR of SCR 0: illegal instruction ───────────────────────
    MTCC_AT   a3, .Lr44
    SET_VEC   .Lh44, t0, t1
    csrr      s0, CSR_MINSTRET
    CSPECIALR_RAW(REG_A5, 0)
    .balign 4
.Lh44:
    cspecialw SCR_MEPCC, a3
    mret
    .balign 4
.Lr44:
    csrr      a4, CSR_MINSTRET
    SET_VEC   .Lunexpected, t0, t1
    DELTA     3, 44
    csrr      t1, mcause
    EXPECT_EQI t1, 2, 45

    CHECK_LIVENESS 251
    li        a0, 0
    j         .Lexit

    .balign 4
.Lunexpected:
    li        a0, 250
.Lexit:
    ret
