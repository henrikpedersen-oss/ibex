# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_auipcc_auicgp_repr -- AUIPCC and AUICGP at the representable-window edges
# =============================================================================
# Expected values come from CHERIoT-Sail (dv/cosim/cheriot-sail-model/src):
#   cheri_insts.sail:70-75  AUIPCC(imm, cd): off = sign_extend(imm) << 11;
#       (representable, newCap) = setCapAddr(PCC, PC + off);
#       cd = clearTagIf(newCap, not(representable))   -- PCC is never sealed
#   cheri_insts.sail:82-88  AUICGP(imm, cd): off = sign_extend(imm) << 11;
#       (representable, newCap) = incCapAddr(CGP = c3, off);
#       cd = clearTagIf(newCap, isCapSealed(c3) | not(representable))
#   cheri_cap_common.sail:743-757, 817-822  representable = the bounds decode the same
#       with the new address (capBoundsEqual). With CHERIoT's encoding
#       (getCapBoundsBits, 399-422) that is the window [base, base + 2^(9+E)) for E < 24
#       and every address for E = 24.
# Both instructions shift by 11, not 12: imm 0xFFFFF is -2048 and imm 1 is +2048.
#
# Capabilities used (E from setCapBounds, cheri_cap_common.sail:444-490):
#   length 2112 on an 8-aligned base: E = 3, exact, window 4096 bytes;
#   length 16: E = 0, exact, window 512 bytes.
# With an E = 3 capability whose address is base + 2048 + d, offset -2048 lands at
# base + d (kept iff d >= 0) and +2048 at base + 4096 + d (kept iff d < 0).
# The expected tags below were computed with a transcription of those Sail functions.
#
# AUIPCC. The PC is at least 2-aligned and an E = 3 base 8-aligned, so the distances
# from the window edges are even; -1 is unreachable for AUIPCC, -2 and 0 are the edges.
# Four small code blocks run each from their own PCC (MTCC root, CSetBoundsExact 2112
# from a base chosen so the block's first instruction is at base + 2048 + d):
#   block   first instr   second instr   d of first   expected tags (first, second)
#   A       lo (-2048)    hi (+2048)      0           1 (window base), 0 (d_hi = +4)
#   B       hi            lo              0           0 (one past the top), 1 (d_lo = +4)
#   C       lo            hi             -2           0 (2 below base), 0 (d_hi = +2)
#   D       hi            lo             -2           1 (2 below top), 1 (d_lo = +2)
#   E       auipcc 0      lo             E = 0 PCC [P, P+16): 1, 0 (window is 512 bytes)
#   F       auipcc 0 and hi from the full PCC (E = 24): both tagged
#   G, H    one block stored at 0x80FFF7FC: auipcc imm -8191 at 0x80FFF7FE, result
#           0x7FFFFFFE. G: PCC [0x80000000, 0x81000000), E = 24 (every address is
#           representable, so 2 below the base keeps the tag): 1. H: PCC
#           [0x80F00000, 0x81000000), E = 12: below the base, tag 0.
# AUICGP. CGP (c3) is set to MTDC root bounded [Bg, Bg + 2112), Bg = 0x80104008
# (no memory is accessed through it), cursor Bg + 2048 + d:
#   d = -1: -2048 -> Bg - 1 (tag 0), +2048 -> Bg + 4095 (tag 1)
#   d =  0: -2048 -> Bg     (tag 1), +2048 -> Bg + 4096 (tag 0)
#   d = -2: -2048 -> Bg - 2 (tag 0), +2048 -> Bg + 4094 (tag 1, 2 below the window top)
#   E = 0 CGP [Bg, Bg + 16), cursor Bg: imm 0 tag 1, imm 1 tag 0
#   sealed CGP (otype 9): imm 0 gives tag 0 and keeps otype 9
#   untagged CGP: imm 1 gives tag 0, address cursor + 2048
#   full CGP (E = 24): imm 0x7FFFF (+0x3FFFF800) keeps the tag
#
# Checks and failure codes (main returns 0 or the first failing code)
#   10n+1 / 10n+2  tag of the first / second result of block n (A=1 .. F=6)
#   10n+3 / 10n+4  address of the first / second result (pc -2048 / +2048 / +0)
#   10n+5          the block's PCC was built tagged (CSetBoundsExact exact); not for F
#   101/103/105    block G: tag, address, PCC tagged;  111/113/115 the same for H
#   71-74  AUICGP d = -1: lo tag, lo address, hi tag, hi address
#   75-78  AUICGP d =  0: lo tag, lo address, hi tag, hi address
#   80-84  E = 0 CGP: address imm 0, tag imm 0, tag imm 1, address imm 1, CGetLen 16
#   85-87  sealed CGP: tag 0, otype 9, address unchanged
#   88-89  untagged CGP: tag 0, address +2048
#   91-92  full CGP: tag 1, address +0x3FFFF800
#   93     c3 restored (CSEQX with the saved copy) before returning
#   94-97  AUICGP d = -2: lo tag, lo address, hi tag, hi address
#   250    unexpected trap;  251 liveness (fewer checks executed than assembled)
#
# Register use: x0-x15 only; s1 check count; t0/t1/t2/s0 integer scratch; ca0 the block
# PCC, ca5 the return capability, ca1/ca2 the AUIPCC results, ca3/ca4 scratch. gp (c3)
# is saved to the stack at entry and restored on every exit path. aN and caN are the
# same register: no cget* result is written into a live capability register.

#include "cheriot_dv.h"

    .option norelax

# Run code block \blk under a PCC [base, base + \len) with base = \blk + \koff - 2048
# (or base = \blk when \len is 16). Codes \n*10 + 5 checks the PCC was built tagged.
.macro RUN_BLOCK blk, koff, len, n
    LA_FAR    t0, \blk, t1                  # t0 = block address
    .if \len == 16
    mv        t1, t0
    .else
    li        t1, \koff - 2048
    add       t1, t0, t1                    # t1 = base
    .endif
    cspecialr a0, SCR_MTCC
    csetaddr  a0, a0, t1
    li        t1, \len
    csetboundsexact a0, a0, t1
    csetaddr  a0, a0, t0                    # cursor = block entry, inside the bounds
    cgettag   t1, a0
    EXPECT_EQI t1, 1, (\n * 10 + 5)
    LA_FAR    t1, .Lret\@, a5
    cspecialr a5, SCR_MTCC
    csetaddr  a5, a5, t1                    # return capability (full PCC)
    mv        s0, t0                        # s0 = block address (pc of the first instr)
    jalr      zero, 0(a0)                   # CJALR into the block
.Lret\@:
.endm

# Run the block at 0x80FFF7FC from 0x80FFF7FE under a PCC [\base, \base + \len).
.macro RUN_FAR base, len, n
    cspecialr a0, SCR_MTCC
    li        t1, \base
    csetaddr  a0, a0, t1
    li        t1, \len
    csetboundsexact a0, a0, t1
    li        t0, 0x80FFF7FE
    csetaddr  a0, a0, t0
    cgettag   t1, a0
    EXPECT_EQI t1, 1, (\n * 10 + 5)
    LA_FAR    t1, .Lret\@, a5
    cspecialr a5, SCR_MTCC
    csetaddr  a5, a5, t1                    # return capability (full PCC)
    jalr      zero, 0(a0)
.Lret\@:
.endm

# Tag of its result, whose address is 0x7FFFFFFE.
.macro CHECK_FAR tag, n
    cgettag   t0, a1
    EXPECT_EQI t0, \tag, (\n * 10 + 1)
    cgetaddr  t0, a1
    li        t1, 0x7FFFFFFE
    EXPECT_EQ t0, t1, (\n * 10 + 3)
.endm

# Tag and address of the two block results.
.macro CHECK_BLOCK tag1, off1, tag2, off2, n
    cgettag   t0, a1
    EXPECT_EQI t0, \tag1, (\n * 10 + 1)
    cgettag   t0, a2
    EXPECT_EQI t0, \tag2, (\n * 10 + 2)
    cgetaddr  t0, a1
    li        t1, \off1
    add       t1, t1, s0
    EXPECT_EQ t0, t1, (\n * 10 + 3)
    cgetaddr  t0, a2
    li        t1, \off2 + 4                 # the second instruction is at block + 4
    add       t1, t1, s0
    EXPECT_EQ t0, t1, (\n * 10 + 4)
.endm

# cd := AUICGP result; checks tag and address against cursor (s0) + \off.
.macro CHECK_CGP imm, tag, off, ctag, caddr
    auicgp    a1, \imm
    cgettag   t0, a1
    EXPECT_EQI t0, \tag, \ctag
    cgetaddr  t0, a1
    li        t1, \off
    add       t1, t1, s0
    EXPECT_EQ t0, t1, \caddr
.endm

    .text
    .globl main
main:
    cincaddrimm sp, sp, -16
    csc       gp, sp, 0                     # save c3; .Lexit restores it
    li        s1, 0
    SET_VEC   .Lunexpected, t0, t1

    # ── AUIPCC, blocks A-E ───────────────────────────────────────────────────
    RUN_BLOCK blk_a, 0, 2112, 1
    CHECK_BLOCK 1, -2048, 0, 2048, 1
    RUN_BLOCK blk_b, 0, 2112, 2
    CHECK_BLOCK 0, 2048, 1, -2048, 2
    RUN_BLOCK blk_c, 2, 2112, 3
    CHECK_BLOCK 0, -2048, 0, 2048, 3
    RUN_BLOCK blk_d, 2, 2112, 4
    CHECK_BLOCK 1, 2048, 1, -2048, 4
    RUN_BLOCK blk_e, 0, 16, 5
    CHECK_BLOCK 1, 0, 0, -2048, 5

    # ── AUIPCC from the full PCC (block F, inline) ───────────────────────────
    LA_FAR    s0, .Lblk_f, t0
    .option push
    .option norvc
.Lblk_f:
    auipcc    a1, 0
    auipcc    a2, 1
    .option pop
    CHECK_BLOCK 1, 0, 1, 2048, 6

    # ── AUIPCC at 0x80FFF7FE from an E = 24 and an E = 12 PCC (blocks G, H) ───
    # The block's address must be 0x7FE mod 0x800 and known when it is assembled, so it
    # is stored at run time: c.nop; auipcc ca1, 0xfe001 (-8191 * 2048); c.jr ca5.
    cspecialr a3, SCR_MTDC
    li        t0, 0x80FFF7FC
    csetaddr  a3, a3, t0
    li        t1, 0x15970001
    sw        t1, 0(a3)
    li        t1, 0x8782FE00
    sw        t1, 4(a3)
    fence.i
    RUN_FAR   0x80000000, 0x01000000, 10
    CHECK_FAR 1, 10
    RUN_FAR   0x80F00000, 0x00100000, 11
    CHECK_FAR 0, 11

    # ── AUICGP, E = 3 CGP ────────────────────────────────────────────────────
    cspecialr a3, SCR_MTDC
    li        t0, 0x80104008                # Bg
    csetaddr  a3, a3, t0
    li        t1, 2112
    csetboundsexact a3, a3, t1
    li        s0, 0x80104008 + 2048 - 1     # cursor, d = -1
    csetaddr  gp, a3, s0
    CHECK_CGP 0xfffff, 0, -2048, 71, 72
    CHECK_CGP 1,       1,  2048, 73, 74
    li        s0, 0x80104008 + 2048         # d = 0
    csetaddr  gp, a3, s0
    CHECK_CGP 0xfffff, 1, -2048, 75, 76
    CHECK_CGP 1,       0,  2048, 77, 78
    li        s0, 0x80104008 + 2048 - 2     # d = -2
    csetaddr  gp, a3, s0
    CHECK_CGP 0xfffff, 0, -2048, 94, 95
    CHECK_CGP 1,       1,  2048, 96, 97

    # ── AUICGP, E = 0 CGP ────────────────────────────────────────────────────
    cspecialr a3, SCR_MTDC
    li        s0, 0x80104008
    csetaddr  a3, a3, s0
    li        t1, 16
    csetboundsexact gp, a3, t1
    CHECK_CGP 0, 1, 0,    81, 80
    auicgp    a1, 1
    cgettag   t0, a1
    EXPECT_EQ t0, zero, 82
    cgetaddr  t0, a1
    li        t1, 2048
    add       t1, t1, s0
    EXPECT_EQ t0, t1, 83
    cgetlen   t0, gp
    EXPECT_EQI t0, 16, 84

    # ── AUICGP, sealed CGP ───────────────────────────────────────────────────
    cspecialr a3, SCR_MSCRATCHC
    li        t0, 9
    csetaddr  a3, a3, t0
    cseal     gp, gp, a3                    # CGP = [Bg, Bg+16) sealed, otype 9
    auicgp    a1, 0
    cgettag   t0, a1
    EXPECT_EQ t0, zero, 85
    cgettype  t0, a1
    EXPECT_EQI t0, 9, 86
    cgetaddr  t0, a1
    EXPECT_EQ t0, s0, 87

    # ── AUICGP, untagged CGP ─────────────────────────────────────────────────
    cspecialr a3, SCR_MTDC
    csetaddr  a3, a3, s0
    ccleartag gp, a3
    auicgp    a1, 1
    cgettag   t0, a1
    EXPECT_EQ t0, zero, 88
    cgetaddr  t0, a1
    li        t1, 2048
    add       t1, t1, s0
    EXPECT_EQ t0, t1, 89

    # ── AUICGP, full CGP ─────────────────────────────────────────────────────
    cspecialr gp, SCR_MTDC
    csetaddr  gp, gp, s0
    auicgp    a1, 0x7ffff
    cgettag   t0, a1
    EXPECT_EQI t0, 1, 91
    cgetaddr  t0, a1
    li        t1, 0x3FFFF800
    add       t1, t1, s0
    EXPECT_EQ t0, t1, 92

    # ── restore c3 and check it ──────────────────────────────────────────────
    clc       gp, sp, 0
    clc       a4, sp, 0
    cseqx     t0, gp, a4
    EXPECT_EQI t0, 1, 93

    CHECK_LIVENESS 251
    li        a0, 0
    j         .Lexit

    .balign 4
.Lunexpected:
    li        a0, 250
.Lexit:
    clc       gp, sp, 0
    cincaddrimm sp, sp, 16
    ret

# ── Code blocks, each run from its own PCC (see the header) ────────────────
    .option push
    .option norvc
    .balign 8
blk_a:                                      # 8-aligned
    auipcc    a1, 0xfffff
    auipcc    a2, 1
    jalr      zero, 0(a5)
    .balign 8
blk_b:
    auipcc    a1, 1
    auipcc    a2, 0xfffff
    jalr      zero, 0(a5)
    .balign 8
    .skip 6
blk_c:                                      # 6 mod 8
    auipcc    a1, 0xfffff
    auipcc    a2, 1
    jalr      zero, 0(a5)
    .balign 8
    .skip 6
blk_d:
    auipcc    a1, 1
    auipcc    a2, 0xfffff
    jalr      zero, 0(a5)
    .balign 8
blk_e:
    auipcc    a1, 0
    auipcc    a2, 0xfffff
    jalr      zero, 0(a5)
    .option pop
