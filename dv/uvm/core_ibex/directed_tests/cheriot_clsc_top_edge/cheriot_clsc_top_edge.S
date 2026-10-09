# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_clsc_top_edge -- CLC bounds checks against a top of 2^32
# =============================================================================
# REQ_BND_01, REQ_BND_02. Expected values come from CHERIoT-Sail LoadCapImm
# (cheri_insts.sail): with a tagged, unsealed authority that has Permit_Load,
# the next check is inCapBounds(cs1, cs1.address + imm, 8), i.e.
# base <= addr and addr + 8 <= top, in unbounded arithmetic; failing it raises
# CapEx_BoundsViolation against cs1 (mtval = cs1 << 5 | 0x01, mcause 28) before
# the alignment check and before any memory access, and cd is not written.
#
# The authorities end at 2^32, so the 33-bit top is what the check compares
# against. CSetBoundsExact from MTDC (setCapBounds, exact at E = 0):
#   ca1 = [0xFFFFFFFE, 2^32): cursor at the base, imm -1, -3, -5. The address is
#         1, 3 or 5 bytes below the base and 3, 5 or 7 bytes below the top.
#   ca4 = [0xFFFFFFF0, 2^32): cursor at the base, imm 9. The address is inside,
#         7 bytes below the top, so addr + 8 = 2^32 + 1 > top.
# None of them accesses memory, so the bench memory map plays no part.
#
# Checks and failure codes (main returns 0 or the first failing code)
#   1-3   ca1 tag 1, CGetBase 0xFFFFFFFE, CGetLen 2
#   4-6   ca4 tag 1, CGetBase 0xFFFFFFF0, CGetLen 16
#   Each probe, codes B..B+4: no trap / mcause 28 / mtval / MEPCC.address = the CLC /
#   cd (ca2, preset to an integer) unchanged:
#   10-14  clc ca2, -1(ca1)    mtval 0x161
#   20-24  clc ca2, -3(ca1)    mtval 0x161
#   30-34  clc ca2, -5(ca1)    mtval 0x161
#   40-44  clc ca2, 9(ca4)     mtval 0x1C1
#   250 unexpected trap;  251 liveness (fewer checks executed than assembled)
#
# Register use: x0-x15 only; s1 check count; t0/t1/t2 integer scratch; ca1, ca4
# authorities; ca2 CLC destination; ca3 scratch capability.

#include "cheriot_dv.h"

    .option norelax

# clc ca2, \imm(\auth) must raise a bounds violation with \mtval. Codes \code..\code+4.
.macro CLC_FAULT auth, imm, mtval, code
    li        a2, 0x5A5A5A5A
    SET_VEC   .Ltrap\@, t0, t1
.Lfault\@:
    clc       a2, \auth, \imm
    li        a0, \code
    j         .Lexit
    .balign 4
.Ltrap\@:
    SET_VEC   .Lunexpected, t0, t1
    csrr      t1, mcause
    EXPECT_EQI t1, 28, (\code + 1)
    csrr      t1, mtval
    EXPECT_EQI t1, \mtval, (\code + 2)
    cspecialr a3, SCR_MEPCC
    cgetaddr  t1, a3
    LA_FAR    t0, .Lfault\@, a3
    EXPECT_EQ t1, t0, (\code + 3)
    EXPECT_EQI a2, 0x5A5A5A5A, (\code + 4)
    RESUME    .Lnext\@, a3, t0
.Lnext\@:
.endm

# \cd := MTDC @ \base with exact length \len; check tag 1, base, length (codes \c..\c+2).
.macro TOP_AUTH cd, base, len, c
    cspecialr \cd, SCR_MTDC
    li        t0, \base
    csetaddr  \cd, \cd, t0
    li        t1, \len
    csetboundsexact \cd, \cd, t1
    cgettag   t2, \cd
    li        t0, 1
    EXPECT_EQ t2, t0, \c
    cgetbase  t2, \cd
    li        t0, \base
    EXPECT_EQ t2, t0, (\c + 1)
    cgetlen   t2, \cd
    EXPECT_EQ t2, t1, (\c + 2)
.endm

    .text
    .globl main
main:
    li        s1, 0
    SET_VEC   .Lunexpected, t0, t1

    TOP_AUTH  a1, 0xFFFFFFFE, 2, 1
    TOP_AUTH  a4, 0xFFFFFFF0, 16, 4

    CLC_FAULT a1, -1, 0x161, 10
    CLC_FAULT a1, -3, 0x161, 20
    CLC_FAULT a1, -5, 0x161, 30
    CLC_FAULT a4, 9, 0x1C1, 40

    CHECK_LIVENESS 251
    li        a0, 0
    j         .Lexit

    .balign 4
.Lunexpected:
    li        a0, 250
.Lexit:
    ret
