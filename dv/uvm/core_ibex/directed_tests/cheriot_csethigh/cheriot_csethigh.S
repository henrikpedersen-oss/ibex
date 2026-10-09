# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_csethigh -- CSetHigh from every kind of source, every metadata format
# =============================================================================
# Expected values come from CHERIoT-Sail (dv/cosim/cheriot-sail-model/src):
#   cheri_insts.sail:289-296  CSetHigh(cd, cs1, rs2):
#       capLow = capToBits(cs1)[31:0]                   (= cs1.address)
#       cd     = capBitsToCapability(false, rs2 @ capLow)
#     so cd's tag is always 0; its address is cs1.address; every other field is the
#     decode of rs2. cs1's tag, seal and bounds play no part, and nothing traps.
#   cheri_cap_common.sail:109-117  high-word layout: [31] reserved, [30:25] cperms,
#       [24:22] cotype, [21:18] cE, [17:9] T, [8:0] B.
#   cheri_cap_common.sail:244-329  decode: cperms[5] = GL; cperms[4:0] selects one of
#       six formats (mem-rw-cap 11xxx, mem-ro-cap 101xx, mem-wo-cap 10000, mem-data
#       100xx, executable 01xxx, sealing 00xxx); otype = (exe or cotype = 0 ? 0 : 8) |
#       cotype; E = 24 if cE = 0xF else cE.
#   cheri_cap_common.sail:399-422  getCapBoundsBits: base and top are rebuilt from
#       B, T, E *and the address*, so the same rs2 decodes to different bounds for
#       different cs1 cursors.
#   cheri_cap_common.sail:345-389  capToEncCap is the exact inverse of the decode for
#       every 32-bit rs2 (including the reserved bit), so CGetHigh(CSetHigh(c, x)) = x
#       (cheri_insts.sail:271-275 CGetHigh).
#   CGetPerm/Type/Base/Top/Len/Tag/Addr: cheri_insts.sail:234-354; CGetTop and CGetLen
#       saturate at 0xFFFFFFFF.
# The fixed-pattern values (section 8) were computed by transcribing exactly those Sail
# functions; each row below gives rs2 and the fields Sail decodes from it at address
# A = 0x80001234 (cs1 is the integer A, a null capability with that address):
#   rs2         perms otype E   base       top        len
#   0x00000000  0x000  0    0   0x80001200 0x80001200 0          (sealing format, nothing)
#   0xFFFFFFFF  0x07F 15   24   0xFF000000 0xFFFFFFFF 0xFFFFFFFF (reserved bit set)
#   0xFE3E0000  0x07F  0   24   0          0xFFFFFFFF 0xFFFFFFFF (memory root + reserved)
#   0x1ECD4A5A  0x1EA  3    3   0x800002D0 0x80000528 0x258      (executable, SR LM LG)
#   0x60008030  0x045  0    0   0x80001230 0x80001240 0x10       (mem-wo-cap, GL)
#   0x254A00F0  0x020 13    2   0x80000BC0 0x80000C00 0x40       (mem-data, LD only)
#   0x6E3BFE00  0x06B  0   14   0x80000000 0x807FC000 0x7FC000   (mem-ro-cap, GL LM LG)
#   0x4E411834  0xE01  9    0   0x80001234 0x8000128C 0x58       (sealing, GL U0 SE US)
#   0x7E010100  0x07F  0    0   0x80001100 0x80001280 0x180      (T < B: top in next region)
#   0x49000000  0x801 12    0   0x80001200 0x80001200 0          (sealing, GL U0; cotype 4)
#   0x7F400000  0x07F 13    0   0x80001200 0x80001200 0          (memory root perms; cotype 5)
#   0x49C00000  0x801 15    0   0x80001200 0x80001200 0          (sealing, GL U0; cotype 7)
#   0x10800000  0x160  2    0   0x80001200 0x80001200 0          (executable, none; cotype 2)
#   0x72800000  0x067 10    0   0x80001200 0x80001200 0          (mem-rw-cap, GL LG; cotype 2)
#   0x45800000  0x401 14    0   0x80001200 0x80001200 0          (sealing, GL SE; cotype 6)
#   0x73C00000  0x067 15    0   0x80001200 0x80001200 0          (mem-rw-cap, GL LG; cotype 7)
#   0x29800000  0x060 14    0   0x80001200 0x80001200 0          (mem-ro-cap, none; cotype 6)
#
# Row 0x72800000 is cperms 0x39 with cotype 2, and the last two cperms 0x22 with cotype 6 and
# cperms 0x39 with cotype 7: the (cotype, cperms) pairs of cheriot_uarch_cg.
# cheriot_csethigh_cross0 (untagged result, 512 bins) that no other source produced (fcov
# merges 2026-10-09 morning and 17:14). Row 0x29800000 is cperms 0x14 (20) with cotype 6, the pair
# the seed-4408 merge (2026-10-09 21:22) missed: until then only cheriot_rand_operands' random
# CSetHigh words had produced it.
#
# Bounded sources (sections 2-4): obj is 1024-aligned. CSetBounds(MTDC@obj, 1001) is
# inexact: E = 1, length 1002 (setCapBounds rounds the odd top up); B = 0, T = 501.
# Decoded at other cursors (getCapBoundsBits): obj+100 -> base obj, len 1002;
# obj+0x10000 and obj+0x10300 -> base obj+0x10000 (the bounds follow the cursor's
# 1024-byte region); obj-2 -> base obj-0x400 (a_mid >= B puts the cursor in the
# region below). CSetBoundsExact(MTDC@obj, 256) is exact (E = 0) and stays tagged.
#
# Checks and failure codes (main returns 0 or the first failing code)
#   Each CSetHigh result is checked for: +0 CGetHigh = rs2 exactly, +1 CGetTag = 0,
#   +2 CGetAddr = cs1.address, +3 CGetPerm, +4 CGetType, +5 CGetBase, +6 CGetTop,
#   +7 CGetLen (codes 10n+k for sub-test n; a "-" means not checked there):
#   1x  tagged unsealed root (MTDC), rs2 = CGetHigh(MTDC); 18: CSEQX with
#       CClearTag(MTDC) = 1 (identical apart from the tag); 19: in-place cd = cs1
#   2x  tagged source, rs2 = high word of the inexact obj capability, cursor obj+100;
#       28: CSEQX with CClearTag(CIncAddrImm(objcap, 100)) = 1
#   3x  same rs2, cursor obj+0x10000 (+30..37) and obj+0x10300 (38: base) and
#       obj-2 (39: base obj-0x400)
#   4x  untagged sources: CClearTag(MTDC@obj+100) (40-47) and the integer obj+100
#       (48: CSEQX equal to the 2x result, 49: tag 0)
#   5x  sealed source: CSeal(objcap@obj+100, otype 9); no trap, otype 0 from rs2,
#       address from cs1 (50-57); 58: cs1 still sealed and tagged afterwards
#   6x  rs2 = high word of that sealed capability, on an unsealed cs1: CGetType 9,
#       bounds of objcap (60-67);
#       68: rs2 from cra (the backward sentry crt's `call main` made): same otype as cra
#   7x  exact source: CSetBoundsExact(MTDC@obj, 256) tagged (79), CSetHigh of its own
#       high word gives base obj, len 256, tag 0 (70-77)
#   8x-16x, 18x-24x, 26x  the fixed rs2 patterns of the table above, in that order, at
#        cs1 = A (26x, not 25x: 250 and 251 are taken)
#   17x  CSEQX distinguishes the reserved bit: CSetHigh(A, 0xFE3E0000) differs from
#        CSetHigh(A, 0x7E3E0000) (170) and CGetHigh tells them apart (171, 172)
#   250  unexpected trap (MTCC points at a test-local vector for the whole test)
#   251  liveness: fewer checks executed than assembled
#
# Register use: x0-x15 only. s1 = executed-check count, t0/t1/t2/s0 integer scratch,
# ca0-ca5 capabilities (a cget* result never goes into a live capability register:
# aN and caN are the same register). ra, sp and gp are not touched.

#include "cheriot_dv.h"

    .option norelax

# Checks every field of capability \cd against expected values. \hi, \addr, \base are
# registers (\hi is the rs2 that made \cd); \perms, \otype, \top, \len immediates, or
# relative: \top and \len are immediates; \base is a register. Clobbers t0, t2.
.macro FIELDS cd, hi, addr, perms, otype, base, top, len, n
    cgethigh  t0, \cd
    EXPECT_EQ t0, \hi, (\n * 10 + 0)
    cgettag   t0, \cd
    EXPECT_EQ t0, zero, (\n * 10 + 1)
    cgetaddr  t0, \cd
    EXPECT_EQ t0, \addr, (\n * 10 + 2)
    cgetperm  t0, \cd
    EXPECT_EQI t0, \perms, (\n * 10 + 3)
    cgettype  t0, \cd
    EXPECT_EQI t0, \otype, (\n * 10 + 4)
    cgetbase  t0, \cd
    EXPECT_EQ t0, \base, (\n * 10 + 5)
    cgettop   t0, \cd
    EXPECT_EQ t0, \top, (\n * 10 + 6)
    cgetlen   t0, \cd
    EXPECT_EQI t0, \len, (\n * 10 + 7)
.endm

# Fixed-pattern case: cs1 = integer A (a5), rs2 = \hi; all fields absolute.
.macro PATTERN hi, perms, otype, base, top, len, n
    li        s0, \hi
    csethigh  a1, a5, s0
    li        t1, \base
    li        a4, \top
    FIELDS    a1, s0, a5, \perms, \otype, t1, a4, \len, \n
.endm

    .text
    .globl main
main:
    li        s1, 0
    SET_VEC   .Lunexpected, t0, t1

    # ── 1x: tagged unsealed root, its own high word ──────────────────────────
    cspecialr a0, SCR_MTDC                  # ca0 = memory root, address 0
    cgethigh  s0, a0
    csethigh  a1, a0, s0
    li        t1, 0                         # base 0, address 0
    li        a4, 0xFFFFFFFF                # top (saturated)
    FIELDS    a1, s0, t1, 0x07F, 0, t1, a4, 0xFFFFFFFF, 1
    ccleartag a2, a0
    cseqx     t0, a1, a2
    EXPECT_EQI t0, 1, 18
    cmove     a2, a0
    csethigh  a2, a2, s0                    # cd = cs1
    cgettag   t0, a2
    EXPECT_EQ t0, zero, 19

    # ── 2x: inexact bounded source, cursor obj+100 ───────────────────────────
    DCAP_FAR  a2, obj, t1                   # ca2 = MTDC @ obj
    li        t0, 1001
    csetbounds a2, a2, t0                   # objcap: E = 1, [obj, obj+1002), tagged
    cgethigh  s0, a2                        # s0 = its high word (rs2 for 2x-6x)
    DCAP_FAR  a0, obj + 100, t1             # ca0 = MTDC @ obj+100 (tagged root)
    csethigh  a1, a0, s0
    LA_FAR    t1, obj, t0                   # t1 = obj
    addi      a4, t1, 100                   # a4 = obj+100 (integer)
    li        t0, 1002
    add       a3, t1, t0                    # a3 = obj+1002 = top
    FIELDS    a1, s0, a4, 0x07F, 0, t1, a3, 1002, 2
    cincaddrimm a3, a2, 100
    ccleartag a3, a3
    cseqx     t0, a1, a3
    EXPECT_EQI t0, 1, 28

    # ── 3x: the same rs2 decoded at other cursors ────────────────────────────
    DCAP_FAR  a0, obj + 0x10000, t1
    csethigh  a1, a0, s0
    LA_FAR    t1, obj + 0x10000, t0         # expected base = cursor
    li        t0, 1002
    add       a3, t1, t0
    FIELDS    a1, s0, t1, 0x07F, 0, t1, a3, 1002, 3
    DCAP_FAR  a0, obj + 0x10300, t1
    csethigh  a1, a0, s0
    cgetbase  t0, a1
    LA_FAR    t1, obj + 0x10000, t2
    EXPECT_EQ t0, t1, 38
    DCAP_FAR  a0, obj - 2, t1
    csethigh  a1, a0, s0
    cgetbase  t0, a1
    LA_FAR    t1, obj - 0x400, t2
    EXPECT_EQ t0, t1, 39

    # ── 4x: untagged sources ─────────────────────────────────────────────────
    DCAP_FAR  a0, obj + 100, t1
    ccleartag a0, a0                        # untagged, root metadata, cursor obj+100
    csethigh  a1, a0, s0
    LA_FAR    t1, obj, t0
    addi      a4, t1, 100
    li        t0, 1002
    add       a3, t1, t0
    FIELDS    a1, s0, a4, 0x07F, 0, t1, a3, 1002, 4
    mv        a0, a4                        # ca0 = integer obj+100 (null capability)
    csethigh  a3, a0, s0
    cseqx     t0, a3, a1
    EXPECT_EQI t0, 1, 48
    cgettag   t0, a3
    EXPECT_EQ t0, zero, 49

    # ── 5x: sealed source ────────────────────────────────────────────────────
    cincaddrimm a0, a2, 100                 # objcap @ obj+100 (ca2 is still objcap)
    cspecialr a3, SCR_MSCRATCHC             # sealing root
    li        t0, 9
    csetaddr  a3, a3, t0
    cseal     a0, a0, a3                    # ca0 = objcap sealed with otype 9
    csethigh  a1, a0, s0                    # must not trap
    LA_FAR    t1, obj, t0
    addi      a4, t1, 100
    li        t0, 1002
    add       a3, t1, t0
    FIELDS    a1, s0, a4, 0x07F, 0, t1, a3, 1002, 5
    cgettype  t0, a0
    cgettag   t1, a0
    add       t0, t0, t1                    # 9 + 1 if cs1 is untouched
    EXPECT_EQI t0, 10, 58

    # ── 6x: rs2 carrying an otype ────────────────────────────────────────────
    cgethigh  s0, a0                        # high word of the otype-9 sealed capability
    DCAP_FAR  a2, obj + 100, t1             # unsealed tagged cs1
    csethigh  a1, a2, s0
    LA_FAR    t1, obj, t0
    addi      a4, t1, 100
    li        t0, 1002
    add       a3, t1, t0
    FIELDS    a1, s0, a4, 0x07F, 9, t1, a3, 1002, 6
    cgethigh  s0, ra                        # cra: the sentry crt's `call main` wrote
    csethigh  a1, a2, s0
    cgettype  t0, a1
    cgettype  t1, ra
    EXPECT_EQ t0, t1, 68

    # ── 7x: exact source ─────────────────────────────────────────────────────
    DCAP_FAR  a2, obj, t1
    li        t0, 256
    csetboundsexact a2, a2, t0
    cgettag   t0, a2
    EXPECT_EQI t0, 1, 79
    cgethigh  s0, a2
    csethigh  a1, a2, s0                    # cd from its own high word
    LA_FAR    t1, obj, t0
    addi      a3, t1, 256
    FIELDS    a1, s0, t1, 0x07F, 0, t1, a3, 256, 7

    # ── 8x-16x: fixed patterns at cs1 = integer A ────────────────────────────
    li        a5, 0x80001234
    PATTERN   0x00000000, 0x000,  0, 0x80001200, 0x80001200, 0x00000000,  8
    PATTERN   0xFFFFFFFF, 0x07F, 15, 0xFF000000, 0xFFFFFFFF, 0xFFFFFFFF,  9
    PATTERN   0xFE3E0000, 0x07F,  0, 0x00000000, 0xFFFFFFFF, 0xFFFFFFFF, 10
    PATTERN   0x1ECD4A5A, 0x1EA,  3, 0x800002D0, 0x80000528, 0x00000258, 11
    PATTERN   0x60008030, 0x045,  0, 0x80001230, 0x80001240, 0x00000010, 12
    PATTERN   0x254A00F0, 0x020, 13, 0x80000BC0, 0x80000C00, 0x00000040, 13
    PATTERN   0x6E3BFE00, 0x06B,  0, 0x80000000, 0x807FC000, 0x007FC000, 14
    PATTERN   0x4E411834, 0xE01,  9, 0x80001234, 0x8000128C, 0x00000058, 15
    PATTERN   0x7E010100, 0x07F,  0, 0x80001100, 0x80001280, 0x00000180, 16
    # (cotype, cperms) pairs no other source here produces
    PATTERN   0x49000000, 0x801, 12, 0x80001200, 0x80001200, 0x00000000, 18
    PATTERN   0x7F400000, 0x07F, 13, 0x80001200, 0x80001200, 0x00000000, 19
    PATTERN   0x49C00000, 0x801, 15, 0x80001200, 0x80001200, 0x00000000, 20
    PATTERN   0x10800000, 0x160,  2, 0x80001200, 0x80001200, 0x00000000, 21
    PATTERN   0x72800000, 0x067, 10, 0x80001200, 0x80001200, 0x00000000, 22
    PATTERN   0x45800000, 0x401, 14, 0x80001200, 0x80001200, 0x00000000, 23
    PATTERN   0x73C00000, 0x067, 15, 0x80001200, 0x80001200, 0x00000000, 24
    PATTERN   0x29800000, 0x060, 14, 0x80001200, 0x80001200, 0x00000000, 26

    # ── 17x: the reserved bit is part of the capability ──────────────────────
    li        s0, 0xFE3E0000
    csethigh  a1, a5, s0
    li        s0, 0x7E3E0000
    csethigh  a2, a5, s0
    cseqx     t0, a1, a2
    EXPECT_EQ t0, zero, 170
    cgethigh  t0, a1
    li        t1, 0xFE3E0000
    EXPECT_EQ t0, t1, 171
    cgethigh  t0, a2
    EXPECT_EQ t0, s0, 172

    CHECK_LIVENESS 251
    li        a0, 0
    j         .Lexit

    .balign 4
.Lunexpected:
    li        a0, 250
.Lexit:
    ret

    .data
    .balign 1024
obj:
    .space  1024
