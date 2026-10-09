# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_repr_window_sweep -- CSetAddr/CIncAddr/CIncAddrImm across both
#       edges of the representable window, every byte within +-10
# =============================================================================
# Expected values come from CHERIoT-Sail (dv/cosim/cheriot-sail-model/src):
#   cheri_insts.sail:558-576  CSetAddr(cd, cs1, rs2): (representable, newCap) =
#       setCapAddr(cs1, rs2); cd = clearTagIf(newCap, not(representable))
#   cheri_insts.sail:518-556  CIncAddr / CIncAddrImmediate: the same with
#       incCapAddr(cs1, rs2 / sign_extend(imm12))
#   cheri_cap_common.sail:743-757, 817-822  representable = the bounds decode the same
#       with the new address (capBoundsEqual). With CHERIoT's encoding
#       (getCapBoundsBits, 399-422) that is the window [base, base + 2^(9+E)): the
#       address is always the requested one, and the tag is kept iff
#       0 <= address - base < 2^(9+E). No source here is sealed, so clearTagIfSealed
#       does not apply.
# The expected tags below were also computed with a transcription of those Sail functions
# (setCapBounds, getCapBoundsBits, capBoundsEqual); it agrees with the window rule for every
# case.
#
# Capabilities (MTDC root, CSetBoundsExact; E from setCapBounds, cheri_cap_common.sail:444-490).
# Each base is deliberately not aligned to the window size, so the window straddles a
# 2^(9+E)-aligned boundary and the decode needs its a_hi correction on one side of it:
#   n  base        length    E   window 2^(9+E)   upper edge
#   1  0x80104010  16        0   0x200            0x80104210
#   2  0x80104008  2112      3   0x1000           0x80105008
#   3  0x80140400  0x40000   10  0x80000          0x801C0400
#
# For each capability n, each edge (0 = base, 1 = base + 2^(9+E)) and each d in -10..10,
# with target = edge + d:
#   op 0  csetaddr    ca1, cap_n, target         (cursor at base)
#   op 1  cincaddr    ca1, cur, target - cursor  (rs2 = d - 16 or d + 16)
#   op 2  cincaddrimm ca1, cur, target - cursor
# where cur has its cursor 16 bytes inside the edge (base + 16, or base + 2^(9+E) - 16;
# for n = 1 that is past the bounds but inside the window, so still tagged). Expected:
# address = target, tag = (d >= 0) at the lower edge and (d < 0) at the upper edge.
#
# Checks and failure codes (main returns 0 or the first failing code)
#   n*1000 + edge*500 + op*100 + (d+10)*2      tag of the result
#   n*1000 + edge*500 + op*100 + (d+10)*2 + 1  address of the result
#   n*1000 + 900 / 901 / 902   cap_n tagged / CGetBase = base / CGetLen = length (exact)
#   n*1000 + 903 / 904         the base+16 / window-16 cursor capability is tagged
#   250    unexpected trap;  251 liveness (fewer checks executed than assembled)
#
# Register use: x0-x15 only; s1 check count; t0/t1/t2 integer scratch; ca3 = cap_n,
# ca4 = cursor at base + 16, ca5 = cursor at base + 2^(9+E) - 16, ca1 the result. aN and
# caN are the same register: no cget* result is written into a live capability register.
# c3 (gp), csp and cra are not touched.

#include "cheriot_dv.h"

    .option norelax

# Tag and address of the result in ca1.
.macro CHECK_RES tag, addr, code
    cgettag   t0, a1
    EXPECT_EQI t0, \tag, \code
    cgetaddr  t0, a1
    li        t1, \addr
    EXPECT_EQ t0, t1, (\code + 1)
.endm

# All three instructions at distance \d from edge \edge of capability \n.
.macro SWEEP_ONE n, base, win, edge, d
    .if \edge
    .if \d < 0
    .set      .Lexp_tag, 1
    .else
    .set      .Lexp_tag, 0
    .endif
    .else
    .if \d < 0
    .set      .Lexp_tag, 0
    .else
    .set      .Lexp_tag, 1
    .endif
    .endif
    li        t1, \base + \edge * \win + \d
    csetaddr  a1, a3, t1
    CHECK_RES .Lexp_tag, (\base + \edge * \win + \d), (\n * 1000 + \edge * 500 + (\d + 10) * 2)
    .if \edge
    li        t1, \d + 16
    cincaddr  a1, a5, t1
    .else
    li        t1, \d - 16
    cincaddr  a1, a4, t1
    .endif
    CHECK_RES .Lexp_tag, (\base + \edge * \win + \d), (\n * 1000 + \edge * 500 + 100 + (\d + 10) * 2)
    .if \edge
    cincaddrimm a1, a5, \d + 16
    .else
    cincaddrimm a1, a4, \d - 16
    .endif
    CHECK_RES .Lexp_tag, (\base + \edge * \win + \d), (\n * 1000 + \edge * 500 + 200 + (\d + 10) * 2)
.endm

# Build cap_n = [base, base + len) in ca3 and its two cursor capabilities, then sweep both edges.
.macro SWEEP_CAP n, base, len, win
    cspecialr a3, SCR_MTDC
    li        t1, \base
    csetaddr  a3, a3, t1
    li        t1, \len
    csetboundsexact a3, a3, t1
    cgettag   t0, a3
    EXPECT_EQI t0, 1, (\n * 1000 + 900)
    cgetbase  t0, a3
    li        t1, \base
    EXPECT_EQ t0, t1, (\n * 1000 + 901)
    cgetlen   t0, a3
    li        t1, \len
    EXPECT_EQ t0, t1, (\n * 1000 + 902)
    li        t1, \base + 16
    csetaddr  a4, a3, t1
    cgettag   t0, a4
    EXPECT_EQI t0, 1, (\n * 1000 + 903)
    li        t1, \base + \win - 16
    csetaddr  a5, a3, t1
    cgettag   t0, a5
    EXPECT_EQI t0, 1, (\n * 1000 + 904)
    .irp edge, 0, 1
    .irp d, -10, -9, -8, -7, -6, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
    SWEEP_ONE \n, \base, \win, \edge, \d
    .endr
    .endr
.endm

    .text
    .globl main
main:
    li        s1, 0
    SET_VEC   .Lunexpected, t0, t1

    SWEEP_CAP 1, 0x80104010, 16,      0x200
    SWEEP_CAP 2, 0x80104008, 2112,    0x1000
    SWEEP_CAP 3, 0x80140400, 0x40000, 0x80000

    CHECK_LIVENESS 251
    li        a0, 0
    j         .Lexit

    .balign 4
.Lunexpected:
    li        a0, 250
.Lexit:
    ret
