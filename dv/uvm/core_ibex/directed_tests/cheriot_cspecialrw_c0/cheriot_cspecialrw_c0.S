# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_cspecialrw_c0 -- CSpecialRW read-only (cs1 = c0), write-only (cd = c0),
#                                read-write, and no-op forms on every SCR
# =============================================================================
# Expected behaviour from CHERIoT-Sail cheri_insts.sail:406-460 CSpecialRW(cd, scr, cs1):
#   C(cd) = scr_val;  if (cs1 != zeros()) then scr := legalise(C(cs1))
# The test is on the *register index* in the cs1 field, not on the value: cs1 = c0 only
# reads ("Writing NULL to a special capability register cannot be done with C0 as that
# only performs a read", cheri_insts.sail:396-400), while a nonzero cs1 index holding
# NULL does write NULL. A write to cd = c0 is discarded, and the SCR write still happens.
# MTCC and MEPCC are legalised on write (address[1:0] / address[0] cleared; the tag is
# cleared when cs1 is sealed, lacks EX or was misaligned: cheri_insts.sail:434-458);
# MTDC and MScratchC store cs1 unchanged (446-447). Every value written below is already legal, so the
# value read back must be bit-identical (CSEQX, cheri_insts.sail CSEQX compares the
# whole capability including tag and reserved bits), except NULL written to MTCC/MEPCC,
# which stays NULL with tag 0. Runs with PCC.SR throughout (the SR-less case is in
# cheriot_scr_faults).
#
# For each SCR S, i = 1 MTCC, 2 MTDC, 3 MScratchC, 4 MEPCC (codes 10i + k):
#   V (ca2) and W (ca5) are two distinct legal values:
#     MTCC  V = MTCC root & ~LG at .Lunexpected (perms 0x1E9), W = MTCC root there
#     MTDC  V = [buf, buf+64) cursor buf+8,  W = MTDC root at buf+16
#     MScr. V = that V sealed with otype 9,  W = CClearTag(MTDC V)
#     MEPCC V = MTCC root & ~LG at .Lmepcc_target+4, W = MTCC root at .Lmepcc_target
#   +0  cspecialrw c0, S, cV (write-only) left c0 null (tag 0, address 0)
#   +1  cspecialrw cX, S, c0 (read-only) returned V
#   +2  a second read-only returned V again: the first read did not write NULL
#   +3  that value is tagged (every V is tagged; MScratchC's is also sealed)
#   +4  cspecialrw cX, S, cW (read-write) returned V (old value)
#   +5  read-only now returns W
#   +6  cspecialrw cX, S, cN with cN = integer 0 (cs1 index != 0, value NULL) returned W
#   +7  read-only now returns tag 0 ...  +8 ... and address 0 (NULL was written)
#   +9  cspecialrw c0, S, c0 (no-op) left S unchanged (restores W first, then checks)
#   59  precondition: the MScratchC V is sealed (CGetType 9)
#   60  MTDC restored before return (CSEQX with the copy saved at entry)
#   250 unexpected trap;  251 liveness (fewer checks executed than assembled)
#
# Register use: x0-x15 only; s1 check count; t0/t1/t2/s0 integer scratch; ca2 = V,
# ca5 = W, ca3/ca4 read results, ca0/ca1 scratch. The MTDC root is saved on the stack
# at entry and restored on every exit path (crt_cheriot.S needs it to report the result).
# MTCC is restored to its V/W value (both valid vectors at .Lunexpected) right after
# NULL is written to it, before anything that could trap.

#include "cheriot_dv.h"

    .option norelax

# All the checks for one SCR. V in ca2, W in ca5 on entry.
.macro SCR_CHECKS scr, i
    cspecialrw zero, \scr, a2               # write-only: S := V, cd = c0
    cgettag   t0, zero
    cgetaddr  t1, zero
    or        t0, t0, t1
    EXPECT_EQ t0, zero, (\i * 10 + 0)
    cspecialrw a3, \scr, zero               # read-only
    cseqx     t0, a3, a2
    EXPECT_EQI t0, 1, (\i * 10 + 1)
    cspecialrw a4, \scr, zero               # read-only again
    cseqx     t0, a4, a2
    EXPECT_EQI t0, 1, (\i * 10 + 2)
    cgettag   t0, a4
    EXPECT_EQI t0, 1, (\i * 10 + 3)
    cspecialrw a3, \scr, a5                 # read-write: returns V, S := W
    cseqx     t0, a3, a2
    EXPECT_EQI t0, 1, (\i * 10 + 4)
    cspecialrw a4, \scr, zero
    cseqx     t0, a4, a5
    EXPECT_EQI t0, 1, (\i * 10 + 5)
    li        a1, 0                         # ca1 = NULL through a nonzero cs1 index
    cspecialrw a3, \scr, a1                 # returns W, S := NULL (legalised: still NULL)
    cspecialrw a4, \scr, zero
    cspecialrw zero, \scr, a5               # S := W again at once (MTCC must stay valid)
    cseqx     t0, a3, a5
    EXPECT_EQI t0, 1, (\i * 10 + 6)
    cgettag   t0, a4
    EXPECT_EQ t0, zero, (\i * 10 + 7)
    cgetaddr  t0, a4
    EXPECT_EQ t0, zero, (\i * 10 + 8)
    cspecialrw zero, \scr, zero             # no-op
    cspecialrw a4, \scr, zero
    cseqx     t0, a4, a5
    EXPECT_EQI t0, 1, (\i * 10 + 9)
.endm

    .text
    .globl main
main:
    cincaddrimm sp, sp, -16
    cspecialr a0, SCR_MTDC
    csc       a0, sp, 0                     # MTDC root; .Lexit puts it back
    li        s1, 0
    SET_VEC   .Lunexpected, t0, t1

    # ── 1x: MTCC ─────────────────────────────────────────────────────────────
    LA_FAR    t0, .Lunexpected, t1
    cspecialr a5, SCR_MTCC
    csetaddr  a5, a5, t0                    # W: MTCC root at the vector
    li        t1, 0xFFD
    candperm  a2, a5, t1                    # V: without LG (0x1E9), same vector
    SCR_CHECKS SCR_MTCC, 1

    # ── 2x: MTDC ─────────────────────────────────────────────────────────────
    DCAP_FAR  a2, buf, t1
    li        t0, 64
    csetboundsexact a2, a2, t0
    cincaddrimm a2, a2, 8                   # V: [buf, buf+64) at buf+8
    DCAP_FAR  a5, buf + 16, t1              # W: MTDC root at buf+16
    SCR_CHECKS SCR_MTDC, 2
    clc       a0, sp, 0
    cspecialw SCR_MTDC, a0                  # MTDC root back for the rest

    # ── 3x: MScratchC ────────────────────────────────────────────────────────
    cspecialr a1, SCR_MSCRATCHC             # sealing root
    li        t0, 9
    csetaddr  a1, a1, t0
    DCAP_FAR  a0, buf, t1
    li        t0, 64
    csetboundsexact a0, a0, t0
    cincaddrimm a0, a0, 8
    cseal     a2, a0, a1                    # V: sealed, otype 9
    ccleartag a5, a0                        # W: untagged
    cgettype  t0, a2
    EXPECT_EQI t0, 9, 59                    # precondition: V really is sealed
    SCR_CHECKS SCR_MSCRATCHC, 3

    # ── 4x: MEPCC ────────────────────────────────────────────────────────────
    LA_FAR    t0, .Lmepcc_target, t1
    cspecialr a5, SCR_MTCC
    csetaddr  a5, a5, t0                    # W: executable root at the label
    li        t1, 0xFFD
    candperm  a2, a5, t1
    cincaddrimm a2, a2, 4                   # V: without LG, label+4
    SCR_CHECKS SCR_MEPCC, 4

    # ── 60: MTDC restored ────────────────────────────────────────────────────
    clc       a0, sp, 0
    cspecialw SCR_MTDC, a0
    cspecialr a3, SCR_MTDC
    cseqx     t0, a3, a0
    EXPECT_EQI t0, 1, 60

    CHECK_LIVENESS 251
    li        a0, 0
    j         .Lexit

    .balign 4
.Lunexpected:
    li        a0, 250
.Lexit:
    clc       a1, sp, 0
    cspecialw SCR_MTDC, a1
    cincaddrimm sp, sp, 16
    ret

    .balign 4
.Lmepcc_target:                             # never executed: only an MEPCC address
    nop
    nop

    .data
    .balign 64
buf:
    .space  64
