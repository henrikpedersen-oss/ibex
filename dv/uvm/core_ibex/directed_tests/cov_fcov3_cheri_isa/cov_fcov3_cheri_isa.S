# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cov_fcov3_cheri_isa -- CSeal, CUnseal, CSetBounds, CSetHigh and CIncAddrImm operand corners
# =============================================================================
# Targets the cheriot_uarch_cg bins the fcov merge of regression 30527 (2026-10-10) left at 0,
# all hit by earlier regressions through cheriot_rand_operands' random operands only:
#   cheriot_cseal_cross1      {cs1 EX 0 / 1, cs2 tag 1, cs2 SE 0, cs2 address 7, seal_bound b2}
#   cheriot_cunseal_cross0    {cs1 tag 0, unsealed, GL 1; cs2 tag 1, sealed, US 0, GL 1}
#                             {cs1 tag 1, unsealed, GL 1; cs2 tag 1, sealed, US 1, GL 0}
#   cheriot_csetbounds_cross1 {tag 1, case b4,    len 8, E 1..14, cd tag 1}
#                             {tag 1, case b4|b2, len 3, E 1..14, cd tag 0}
#                             {tag 1, case b4|b2, len 4, E 24,    cd tag 0}
# and the three bins the merge of regression 14911 (2026-10-10, with this test) left at 0, again
# hit before by cheriot_rand_operands only:
#   cheriot_csethigh_cross0   {cd tag 0, otype 4, cperms 61 (0x3D)}
#   cheriot_cunseal_cross0    {cs1 tag 1, unsealed, GL 1; cs2 tag 0, sealed, US 0, GL 1}
#   cheriot_csetbounds_cross1 {tag 1, case b4|b2, len 7, E 0,     cd tag 0}
# Each block sweeps the neighbouring values too (cs2 address 3..7, requests 0..8, all 512
# CSetHigh (cotype, cperms) pairs), so those bins no longer depend on random operands either.
# And the three bins the merge of regression 26231 (2026-10-11) left at 0, hit before by
# cheriot_rand_operands only:
#   cheriot_cincaddrimm_cross {cs1 tag 0, case1, sealed, E 0, imm12 1..0x7FF}
#   cheriot_cseal_cross1      {cs1 EX 1, cs2 tag 0, cs2 SE 1, cs2 address >= 16, seal_bound b0}
#   cheriot_cunseal_cross0    {cs1 tag 1, sealed, GL 1; cs2 tag 1, sealed, US 0, GL 0}
# And the two cheriot_csetbounds_cross1 bins no regression has hit (combined merge, 2026-10-13):
#   {tag 1, case b2 alone, len 1, E 0, cd tag 0}: a request longer than a zero-length cs1
#   {tag 1, case b4 alone, len 0, E 0, cd tag 0}: an in-bounds request on a sealed cs1
# Here the sweeps cover the whole cross: all 792 cheriot_cseal_cross1 bins and all 128
# cheriot_cunseal_cross0 bins, each by exactly one instruction, and every case1 bin of
# cheriot_cincaddrimm_cross (tag x sealed x E 0 / 2 x the five imm12 bins; 36, the tagged imm 0
# pair being ignored).
#
# Expected values from CHERIoT-Sail (dv/cosim/cheriot-sail-model/src/cheri_insts.sail):
#   CSeal: permitted needs cs2 tagged, unsealed, SE, base <= cs2.address < top and an otype
#     valid for cs1 (1-7 executable, 9-15 otherwise); else cd's tag is cleared, never a trap.
#     cs2 = MTDC @ 0 bounded to [0, 2) (E = 0) then moved to address 3..7: still tagged, since
#     getCapBoundsBits decodes the same bounds anywhere in [0, 2^9); the memory root has no SE,
#     and the address is above the top (fcov seal_bound b2 alone). cd untagged for MTCC (EX)
#     and MTDC.
#   CUnseal: permitted needs cs2 tagged, unsealed and US, cs1 sealed and cs1.otype in cs2's
#     bounds; cd = cs1 unsealed with GL = cs1.GL & cs2.GL, tag cleared unless permitted, never a
#     trap. A sealed cs2 always fails: cd untagged, otype 0.
#       A cs2 = CSeal(MTDC, MScratchC @ 9) (data format: US 0; GL 1), cs1 = CClearTag(MTDC):
#         GL 1.
#       B cs2 = CSeal(MScratchC without GL, MScratchC @ 9) (perms 0xE00: US 1, GL 0),
#         cs1 = MTDC: GL 0.
#       C cs2 = CClearTag(CSeal(MTDC, MScratchC @ 9)) (untagged, still sealed: CClearTag keeps
#         the otype), cs1 = MTDC: GL 1.
#   CSetBounds (cheri_insts.sail:602-615): cd = setCapBounds(clearTagIfSealed(cs1), cs1.address,
#     rs2), tag cleared unless inCapBounds(cs1, cs1.address, rs2) (and always if cs1 is sealed);
#     base = cs1.address, length rs2 (exact for <= 8).
#       E = 2 source [0x80100000, 0x80100400) (setCapBounds: 1024 needs E = 2):
#         cursor 0x80100100 (inside, case b4): requests 0..8 all in bounds, tagged;
#         cursor 0x80100404 (above top, still representable: the E = 2 window is 2^11 bytes,
#         case b4|b2): tag 0.
#       E = 24 source [0x80000000, 0x90000000) (CSetBounds 0x10000000 saturates E to 24), cursor
#         0x91000000 (every address decodes the same bounds at E = 24, case b4|b2): tag 0.
#       E = 0 source [0x80100000, 0x80100010), cursor 0x80100100 (above top, inside the
#         2^9-byte window getCapBoundsBits decodes from B = 0, case b4|b2): tag 0.
#       E = 0 zero-length source [0x80100000, 0x80100000), cursor 0x80100100 (above top, same
#         window, still tagged): request 0 case b4|b2, requests 1..8 longer than cs1, case b2
#         alone; tag 0.
#       E = 0 source [0x80100000, 0x80100010), cursor 0x80100008, sealed at otype 9: requests
#         0..8 all in bounds (case b4 alone), tag 0 because cs1 is sealed.
#     The same shapes as cheriot_setbounds tests 8-20 and 46-49, with every request 0..8.
#   CSetHigh (cheri_insts.sail:289-296): cd = capBitsToCapability(false, rs2 @ cs1.address):
#     always untagged, CGetHigh returns rs2 (capToEncCap inverts the decode for every word).
#     rs2 = w << 22, w = 0..511, sets cperms [30:25] and cotype [24:22] to every pair, E = T =
#     B = 0. 0x7B000000 is cperms 0x3D (GL, mem-rw-cap: SL, LG; no LM) with cotype 4: perms
#     0x077, otype 12 (non-executable cotype 4 decodes to 8 | 4).
#   CIncAddrImm (cheri_insts.sail:547-556): cd = cs1 with address + imm; tag cleared if cs1 is
#     sealed or the bounds decoded from the new address differ (incCapAddr). Every result here
#     lies below cs1's base (fcov case1), so cd is untagged and its address is cs1.address + imm.
#       Tagged: MTDC bounded to [0xFFFFFF00, 2^32) (E = 0) or [0xFFFFFC00, 2^32) (E = 2), sealed
#         at otype 9 or not; cursor 0xFFFFFFFF plus 1 wraps to 0, cursor at the base minus 2048,
#         16 or 1 falls below it.
#       Untagged: [0x100, 0x110) (E = 0) or [0x1100, 0x1500) (E = 2) with the cursor moved to
#         0x20 (not representable, tag 0), sealed after the move or not: getCapBoundsBits
#         decodes from 0x20 with a_mid < B, so the base wraps to 0xFFFFFF00 / 0xFFFFF900 and
#         0x20 + 0, 0x7FF, -2048, -16 and -1 are all below it.
#   CSeal sweep: cs1 = MTCC (EX) or MTDC; cs2 = MScratchC (SE, US, U0, GL), without SE or not,
#     tag cleared or not, at address a = 0..16 with six bounds: [0x80000000, 0x90000000) (E = 24,
#     tagged at any address, so a is below the base: b0), [a-1, a-1) (b2), [a-1, a) (b3), [a, a)
#     (b1 | b3), [a-1, a+1) (inside) and [a, a+1) (b1). For a = 0 the three a-1 shapes are
#     skipped (cheriot_cseal_cross1 ignores them). cd is tagged only for the inside and b1
#     shapes, with cs2 tagged and SE and a an otype for cs1 (1..7 with EX, else 9..15). Only
#     cd's tag is read: a failed CSeal keeps cs2.address[3:0] as Sail's otype, which need not
#     be one the 3-bit RTL field can return.
#   CUnseal sweep over k = 0..127: cs1 = MTDC, GL k4, sealed (CSeal at 9) k5, tagged k6; cs2 =
#     MScratchC (bounds [0, 2^32), so 9 is in them), GL k0, US k1, sealed k2, tagged k3; read back
#     as k first. cd: otype 0, GL k4 & k0, tag k6 & k5 & k3 & ~k2 & k1.
#
# CHERIoT-Sail cosim on. Checks and failure codes (main returns 0 or the first failing code):
#   1-2     the CSeal authority: tagged, top 2
#   10-24   CSeal, cs2 address a = 3..7: 10 + 3 (a - 3) cs2 tagged, + 1 MTCC sealed tag 0,
#           + 2 MTDC sealed tag 0
#   30-32   CUnseal A's cs2: tag 1, CGetType 9, GL 1     33-35 A's cd: tag 0, type 0, GL 1
#   36-37   CUnseal B's cs2: tag 1, perms 0xE00          38-40 B's cd: tag 0, type 0, GL 0
#   41-43   CUnseal C's cs2: tag 0, CGetType 9, GL 1     44-46 C's cd: tag 0, type 0, GL 1
#   50-55   the CSetBounds sources: E = 2 tag / length, inside cursor tag, above-top cursor tag,
#           E = 24 tag / top
#   56-58   the E = 0 CSetBounds source: tag, length 16, above-top cursor tag
#   60-86   E = 2 inside, request n: 60 + 3n tag 1, + 1 base, + 2 length
#   90-116  E = 2 above top, request n: 90 + 3n tag 0, + 1 base, + 2 length
#   120-146 E = 24 above top, request n: 120 + 3n tag 0, + 1 base, + 2 length
#   150-176 E = 0 above top, request n: 150 + 3n tag 0, + 1 base, + 2 length
#   180     CSetHigh sweep: some w gave CGetHigh != rs2 or a tagged cd
#   181-182 CSetHigh 0x7B000000: CGetType 12, CGetPerm 0x077
#   190-197 CIncAddrImm, one code per cs1 (cs1 tag / base / sealed, or a cd tagged, at the wrong
#           address or not below the base): tagged E = 0 unsealed / sealed 190 / 191, E = 2
#           192 / 193; untagged E = 0 194 / 195, E = 2 196 / 197
#   200     CSeal sweep: some cs2 not as built (base, tag or SE)
#   201     CSeal sweep: some (cs1, cs2 tag, SE, address) gave cd tags other than Sail's
#   202     CUnseal sweep: some operand pair did not read back as k
#   203     CUnseal sweep: some cd tag, GL or otype other than Sail's
#   210-212 the zero-length CSetBounds source: tag, length 0, above-top cursor tag
#   220-246 zero-length source, request n: 220 + 3n tag 0, + 1 base, + 2 length
#   250 unexpected trap (MTCC points at a test-local vector)   251 liveness
#   260-263 the sealed CSetBounds source: tag, CGetType 9, cursor, length 16
#   270-296 sealed source, request n: 270 + 3n tag 0, + 1 base, + 2 length
# CHECK_LIVENESS: s1 must reach NCHK = 227 (the sweeps count one check per code).
#
# Register use: x0-x15 only. s1 = executed-check count (EXPECT_*), t2 is EXPECT_EQI's; a1 / a2
# sources, a3 / a4 results, a5 an expected address, t0 / t1 integers (in the CSetHigh sweep a4
# is the step and a5 the end). CIncAddrImm: a1 cs1's base, a2 the otype-9 authority, a5 cs1's
# cursor, t1 the mismatch OR. CSeal sweep: a5 = f (bit 2 cs1 EX, bit 1 cs2 tag, bit 0 cs2 SE),
# a0 the cs2 address, a2 the cs2 permission mask, t1 the six cd tags, s0 mismatches (bit 0
# cs2, bit 1 cd). CUnseal sweep: a5 = k, a2 the authority, s0 mismatches (bit 0 operands, bit 1
# cd).

#include "cheriot_dv.h"

    .option norelax

# CSetBounds(a2, \len): tag \tag, base a5, length \len. Codes \code .. \code + 2.
.macro SB_CHECK len, tag, code
    li        t0, \len
    csetbounds a3, a2, t0
    cgettag   t1, a3
    EXPECT_EQI t1, \tag, (\code)
    cgetbase  t1, a3
    EXPECT_EQ t1, a5, (\code + 1)
    cgetlen   t1, a3
    EXPECT_EQ t1, t0, (\code + 2)
.endm

# Requests 0..8 against a2.
.macro SB_SWEEP tag, code
  .irp n, 0, 1, 2, 3, 4, 5, 6, 7, 8
    SB_CHECK  \n, \tag, (\code + 3 * \n)
  .endr
.endm

# CSeal of MTCC and MTDC through a2 = a1 with its cursor at \a (above a1's top).
.macro SEAL_CHECK a
    li        t0, \a
    csetaddr  a2, a1, t0
    cgettag   t1, a2
    EXPECT_EQI t1, 1, (10 + 3 * (\a - 3))
    cspecialr a3, SCR_MTCC
    cseal     a4, a3, a2
    cgettag   t1, a4
    EXPECT_EQ t1, zero, (11 + 3 * (\a - 3))
    cspecialr a3, SCR_MTDC
    cseal     a4, a3, a2
    cgettag   t1, a4
    EXPECT_EQ t1, zero, (12 + 3 * (\a - 3))
.endm

# cd \cd: tag 0, otype 0, GL \gl. Codes \code .. \code + 2.
.macro UNSEAL_FAILED cd, gl, code
    cgettag   t1, \cd
    EXPECT_EQ t1, zero, (\code)
    cgettype  t1, \cd
    EXPECT_EQ t1, zero, (\code + 1)
    cgetperm  t1, \cd
    andi      t1, t1, 1                     # GL is perms bit 0
    EXPECT_EQI t1, \gl, (\code + 2)
.endm

# a3 := MTDC bounded to [\base, \base + \len) with its cursor at a5 = \cursor, then sealed through
# a2 (otype 9) if \sealed; a1 := \base.
.macro INC_BUILD base, len, cursor, sealed
    cspecialr a3, SCR_MTDC
    li        a1, \base
    csetaddr  a3, a3, a1
    li        t0, \len
    csetbounds a3, a3, t0
    li        a5, \cursor
    csetaddr  a3, a3, a5
  .if \sealed
    cseal     a3, a3, a2
  .endif
.endm

# a3: tag \tag, base a1, sealed \sealed. Mismatches are ORed into t1.
.macro INC_CS1 tag, sealed
    cgettag   t0, a3
    xori      t0, t0, \tag
    or        t1, t1, t0
    cgetbase  t0, a3
    xor       t0, t0, a1
    or        t1, t1, t0
    cgettype  t0, a3
    snez      t0, t0
    xori      t0, t0, \sealed
    or        t1, t1, t0
.endm

# CIncAddrImm(a3, \imm): tag 0, address a5 + \imm, below a3's base a1 (fcov case1). Mismatches are
# ORed into t1.
.macro INC_BELOW imm
    cincaddrimm a4, a3, \imm
    cgettag   t0, a4
    or        t1, t1, t0
    cgetaddr  t0, a4
    addi      t2, a5, \imm
    xor       t2, t2, t0
    or        t1, t1, t2
    sltu      t0, t0, a1
    xori      t0, t0, 1
    or        t1, t1, t0
.endm

# Tagged a3 over [\base, 2^32): cursor top - 1 plus 1 (wraps to 0), cursor at the base minus 2048,
# 16 and 1. Code \code.
.macro INC_TAGGED base, len, sealed, code
    li        t1, 0
    INC_BUILD \base, \len, 0xFFFFFFFF, \sealed
    INC_CS1   1, \sealed
    INC_BELOW 1
    INC_BUILD \base, \len, \base, \sealed
    INC_CS1   1, \sealed
    INC_BELOW -2048
    INC_BELOW -16
    INC_BELOW -1
    EXPECT_EQ t1, zero, \code
.endm

# Untagged a3: [\base, \base + \len) with its cursor moved to 0x20, below the base, so the bounds
# decode from 0x20 with the base wrapped to \expbase; plus 0, 0x7FF, -2048, -16 and -1. Code \code.
.macro INC_UNTAGGED base, len, expbase, sealed, code
    li        t1, 0
    INC_BUILD \base, \len, 0x20, \sealed
    li        a1, \expbase
    INC_CS1   0, \sealed
    INC_BELOW 0
    INC_BELOW 0x7FF
    INC_BELOW -2048
    INC_BELOW -16
    INC_BELOW -1
    EXPECT_EQ t1, zero, \code
.endm

# CSeal sweep, cs2 a1 built with base t0: CAndPerm a2, tag cleared unless f (a5) bit 1. s0 bit 0
# is set unless its base is t0 and {tag, SE} is f[1:0]; cd's tag goes to t1 bit 0.
.macro SEAL_CS2
    candperm  a1, a1, a2
    andi      t2, a5, 2
    bnez      t2, 7f
    ccleartag a1, a1
7:
    cgetbase  t2, a1
    xor       t0, t0, t2
    snez      t0, t0
    or        s0, s0, t0
    cgetperm  t0, a1
    srli      t0, t0, 10
    andi      t0, t0, 1                     # SE
    cgettag   t2, a1
    slli      t2, t2, 1
    or        t0, t0, t2
    andi      t2, a5, 3
    xor       t0, t0, t2
    snez      t0, t0
    or        s0, s0, t0
    cseal     a4, a3, a1
    cgettag   t0, a4
    or        t1, t1, t0
.endm

# cs2 := MScratchC bounded to [a0 + \off, a0 + \off + \len) (E = 0), cursor a0. Skipped for
# a0 = 0 when \off is -1: those three positions need base -1, and cheriot_cseal_cross1 ignores
# them for address 0.
.macro SEAL_POS off, len
    slli      t1, t1, 1
  .if \off
    beqz      a0, 8f
  .endif
    cspecialr a1, SCR_MSCRATCHC
    addi      t0, a0, \off
    csetaddr  a1, a1, t0
    li        t2, \len
    csetbounds a1, a1, t2
    csetaddr  a1, a1, a0
    SEAL_CS2
8:
.endm

# cs2 := MScratchC bounded to [0x80000000, 0x90000000) (E = 24), cursor a0: still tagged (E = 24
# represents every address) and below the base.
.macro SEAL_BELOW
    slli      t1, t1, 1
    cspecialr a1, SCR_MSCRATCHC
    li        t0, 0x80000000
    csetaddr  a1, a1, t0
    li        t2, 0x10000000
    csetbounds a1, a1, t2
    csetaddr  a1, a1, a0
    SEAL_CS2
.endm

    .text
    .globl main
main:
    li        s1, 0
    SET_VEC   .Lunexpected, t0, t1

    # ── 1x-2x: CSeal through a tagged authority without SE, cursor above its top ──
    cspecialr a1, SCR_MTDC
    csetaddr  a1, a1, zero
    li        t0, 2
    csetbounds a1, a1, t0                   # [0, 2), E = 0
    cgettag   t1, a1
    EXPECT_EQI t1, 1, 1
    cgettop   t1, a1
    EXPECT_EQI t1, 2, 2
  .irp a, 3, 4, 5, 6, 7
    SEAL_CHECK \a
  .endr

    # ── 30-35: CUnseal A ─────────────────────────────────────────────────────
    cspecialr a2, SCR_MSCRATCHC
    li        t0, 9
    csetaddr  a2, a2, t0                    # the sealing authority at otype 9
    cspecialr a1, SCR_MTDC
    cseal     a1, a1, a2                    # cs2: tagged, sealed (9), US 0, GL 1
    cgettag   t1, a1
    EXPECT_EQI t1, 1, 30
    cgettype  t1, a1
    EXPECT_EQI t1, 9, 31
    cgetperm  t1, a1
    andi      t1, t1, 1
    EXPECT_EQI t1, 1, 32
    cspecialr a3, SCR_MTDC
    ccleartag a3, a3                        # cs1: untagged, unsealed, GL 1
    cunseal   a4, a3, a1
    UNSEAL_FAILED a4, 1, 33

    # ── 36-40: CUnseal B ─────────────────────────────────────────────────────
    cspecialr a1, SCR_MSCRATCHC
    li        t0, 0xFFE
    candperm  a1, a1, t0                    # sealing root without GL: perms 0xE00
    cseal     a1, a1, a2                    # cs2: tagged, sealed (9), US 1, GL 0
    cgettag   t1, a1
    EXPECT_EQI t1, 1, 36
    cgetperm  t1, a1
    EXPECT_EQI t1, 0xE00, 37
    cspecialr a3, SCR_MTDC                  # cs1: tagged, unsealed, GL 1
    cunseal   a4, a3, a1
    UNSEAL_FAILED a4, 0, 38

    # ── 41-46: CUnseal C ─────────────────────────────────────────────────────
    cspecialr a1, SCR_MTDC
    cseal     a1, a1, a2                    # a2 is still MScratchC @ 9
    ccleartag a1, a1                        # cs2: untagged, sealed (9), US 0, GL 1
    cgettag   t1, a1
    EXPECT_EQ t1, zero, 41
    cgettype  t1, a1
    EXPECT_EQI t1, 9, 42
    cgetperm  t1, a1
    andi      t1, t1, 1
    EXPECT_EQI t1, 1, 43
    cspecialr a3, SCR_MTDC                  # cs1: tagged, unsealed, GL 1
    cunseal   a4, a3, a1
    UNSEAL_FAILED a4, 1, 44

    # ── 50-53, 60-116: CSetBounds on an E = 2 source ─────────────────────────
    cspecialr a1, SCR_MTDC
    li        t0, 0x80100000
    csetaddr  a1, a1, t0
    li        t0, 1024
    csetbounds a1, a1, t0                   # [0x80100000, 0x80100400), E = 2
    cgettag   t1, a1
    EXPECT_EQI t1, 1, 50
    cgetlen   t1, a1
    EXPECT_EQI t1, 1024, 51
    li        a5, 0x80100100
    csetaddr  a2, a1, a5                    # cursor inside
    cgettag   t1, a2
    EXPECT_EQI t1, 1, 52
    SB_SWEEP  1, 60
    li        a5, 0x80100404
    csetaddr  a2, a1, a5                    # cursor top + 4
    cgettag   t1, a2
    EXPECT_EQI t1, 1, 53
    SB_SWEEP  0, 90

    # ── 54-55, 120-146: CSetBounds on an E = 24 source, cursor above top ─────
    cspecialr a1, SCR_MTDC
    li        t0, 0x80000000
    csetaddr  a1, a1, t0
    li        t0, 0x10000000
    csetbounds a1, a1, t0                   # [0x80000000, 0x90000000), E = 24
    li        a5, 0x91000000
    csetaddr  a2, a1, a5
    cgettag   t1, a2
    EXPECT_EQI t1, 1, 54
    cgettop   t1, a2
    EXPECT_EQI t1, 0x90000000, 55
    SB_SWEEP  0, 120

    # ── 56-58, 150-176: CSetBounds on an E = 0 source, cursor above top ──────
    cspecialr a1, SCR_MTDC
    li        t0, 0x80100000
    csetaddr  a1, a1, t0
    li        t0, 16
    csetbounds a1, a1, t0                   # [0x80100000, 0x80100010), E = 0
    cgettag   t1, a1
    EXPECT_EQI t1, 1, 56
    cgetlen   t1, a1
    EXPECT_EQI t1, 16, 57
    li        a5, 0x80100100
    csetaddr  a2, a1, a5                    # cursor top + 0xF0
    cgettag   t1, a2
    EXPECT_EQI t1, 1, 58
    SB_SWEEP  0, 150

    # ── 210-212, 220-246: CSetBounds on a zero-length E = 0 source, cursor above top ─
    cspecialr a1, SCR_MTDC
    li        t0, 0x80100000
    csetaddr  a1, a1, t0
    csetbounds a1, a1, zero                 # [0x80100000, 0x80100000), E = 0
    cgettag   t1, a1
    EXPECT_EQI t1, 1, 210
    cgetlen   t1, a1
    EXPECT_EQ t1, zero, 211
    li        a5, 0x80100100
    csetaddr  a2, a1, a5                    # cursor top + 0x100
    cgettag   t1, a2
    EXPECT_EQI t1, 1, 212
    SB_SWEEP  0, 220

    # ── 260-263, 270-296: CSetBounds on a sealed E = 0 source, cursor inside ──
    cspecialr a2, SCR_MSCRATCHC
    li        t0, 9
    csetaddr  a2, a2, t0                    # the sealing authority at otype 9
    cspecialr a1, SCR_MTDC
    li        t0, 0x80100000
    csetaddr  a1, a1, t0
    li        t0, 16
    csetbounds a1, a1, t0                   # [0x80100000, 0x80100010), E = 0
    li        a5, 0x80100008
    csetaddr  a1, a1, a5                    # cursor inside
    cseal     a2, a1, a2
    cgettag   t1, a2
    EXPECT_EQI t1, 1, 260
    cgettype  t1, a2
    EXPECT_EQI t1, 9, 261
    cgetaddr  t1, a2
    EXPECT_EQ t1, a5, 262
    cgetlen   t1, a2
    EXPECT_EQI t1, 16, 263
    SB_SWEEP  0, 270

    # ── 180-182: CSetHigh over every (cotype, cperms) pair ───────────────────
    cspecialr a1, SCR_MTDC
    li        t0, 0                         # rs2 = w << 22
    li        t1, 0                         # OR of (CGetHigh ^ rs2) and every CGetTag
    li        a4, 1 << 22
    li        a5, 1 << 31                   # w = 512
.Lhigh_loop:
    csethigh  a3, a1, t0
    cgethigh  t2, a3
    xor       t2, t2, t0
    or        t1, t1, t2
    cgettag   t2, a3
    or        t1, t1, t2
    add       t0, t0, a4
    bne       t0, a5, .Lhigh_loop
    EXPECT_EQ t1, zero, 180
    li        t0, 0x7B000000                # cperms 0x3D, cotype 4
    csethigh  a3, a1, t0
    cgettype  t1, a3
    EXPECT_EQI t1, 12, 181
    cgetperm  t1, a3
    EXPECT_EQI t1, 0x77, 182

    # ── 190-197: CIncAddrImm to below cs1's base, tag x sealed x E 0 / 2 x imm ─
    cspecialr a2, SCR_MSCRATCHC
    li        t0, 9
    csetaddr  a2, a2, t0                    # the sealing authority at otype 9
    INC_TAGGED   0xFFFFFF00, 0x100, 0, 190  # E = 0
    INC_TAGGED   0xFFFFFF00, 0x100, 1, 191
    INC_TAGGED   0xFFFFFC00, 0x400, 0, 192  # E = 2
    INC_TAGGED   0xFFFFFC00, 0x400, 1, 193
    INC_UNTAGGED 0x100, 0x10, 0xFFFFFF00, 0, 194   # E = 0
    INC_UNTAGGED 0x100, 0x10, 0xFFFFFF00, 1, 195
    INC_UNTAGGED 0x1100, 0x400, 0xFFFFF900, 0, 196 # E = 2
    INC_UNTAGGED 0x1100, 0x400, 0xFFFFF900, 1, 197

    # ── 200-201: CSeal over cs1 EX x cs2 tag x SE x address 0..16 x bound position ─
    li        a5, 0                         # f: bit 2 cs1 EX, bit 1 cs2 tag, bit 0 cs2 SE
    li        s0, 0
.Lseal_f:
    cspecialr a3, SCR_MTDC
    andi      t0, a5, 4
    beqz      t0, 1f
    cspecialr a3, SCR_MTCC
1:  li        a2, 0xFFF
    andi      t0, a5, 1
    bnez      t0, 1f
    li        a2, 0xBFF                     # all but SE
1:  li        a0, 0                         # cs2 address
.Lseal_a:
    li        t1, 0                         # cd tags, one bit per position, at-base in bit 0
    SEAL_BELOW                              # [0x80000000, 0x90000000): b0
    SEAL_POS  -1, 0                         # [a - 1, a - 1): b2
    SEAL_POS  -1, 1                         # [a - 1, a):     b3
    SEAL_POS  0, 0                          # [a, a):         b1 | b3
    SEAL_POS  -1, 2                         # [a - 1, a + 1): inside
    SEAL_POS  0, 1                          # [a, a + 1):     b1
    # Sail: inside and at-base seal (tag 1) iff cs2 is tagged with SE and a is an otype for cs1
    andi      t0, a5, 4
    addi      t2, a0, -1
    bnez      t0, 1f
    addi      t2, a0, -9
1:  sltiu     t2, t2, 7                     # EX: 1..7, else 9..15
    andi      t0, a5, 3
    xori      t0, t0, 3
    seqz      t0, t0
    and       t2, t2, t0
    slli      t0, t2, 1
    or        t2, t2, t0                    # 0b11 or 0
    xor       t1, t1, t2
    snez      t1, t1
    slli      t1, t1, 1
    or        s0, s0, t1
    addi      a0, a0, 1
    li        t0, 17
    bne       a0, t0, .Lseal_a
    addi      a5, a5, 1
    li        t0, 8
    bne       a5, t0, .Lseal_f
    andi      t0, s0, 1
    EXPECT_EQ t0, zero, 200
    andi      t0, s0, 2
    EXPECT_EQ t0, zero, 201

    # ── 202-203: CUnseal over all 128 (cs1 tag, sealed, GL, cs2 tag, sealed, US, GL) ─
    cspecialr a2, SCR_MSCRATCHC
    li        t0, 9
    csetaddr  a2, a2, t0                    # the sealing authority at otype 9
    li        a5, 0                         # k, bits 6..0 in the order above
    li        s0, 0
.Lunseal_loop:
    li        t0, 0xFFF                     # cs1 := MTDC, GL from k4, sealed k5, tagged k6
    andi      t1, a5, 0x10
    bnez      t1, 1f
    xori      t0, t0, 1
1:  cspecialr a3, SCR_MTDC
    candperm  a3, a3, t0
    andi      t1, a5, 0x20
    beqz      t1, 1f
    cseal     a3, a3, a2
1:  andi      t1, a5, 0x40
    bnez      t1, 1f
    ccleartag a3, a3
1:  li        t0, 0xFFF                     # cs2 := MScratchC, GL k0, US k1, sealed k2, tag k3
    andi      t1, a5, 1
    bnez      t1, 1f
    xori      t0, t0, 1
1:  andi      t1, a5, 2
    bnez      t1, 1f
    xori      t0, t0, 0x200
1:  cspecialr a1, SCR_MSCRATCHC
    candperm  a1, a1, t0
    andi      t1, a5, 4
    beqz      t1, 1f
    cseal     a1, a1, a2
1:  andi      t1, a5, 8
    bnez      t1, 1f
    ccleartag a1, a1
1:  cgettag   t0, a3                        # the operands as read back must spell k
    cgettype  t1, a3
    snez      t1, t1
    slli      t0, t0, 1
    or        t0, t0, t1
    cgetperm  t1, a3
    andi      t1, t1, 1
    slli      t0, t0, 1
    or        t0, t0, t1
    cgettag   t1, a1
    slli      t0, t0, 1
    or        t0, t0, t1
    cgettype  t1, a1
    snez      t1, t1
    slli      t0, t0, 1
    or        t0, t0, t1
    cgetperm  t1, a1
    srli      t1, t1, 9
    andi      t1, t1, 1
    slli      t0, t0, 1
    or        t0, t0, t1
    cgetperm  t1, a1
    andi      t1, t1, 1
    slli      t0, t0, 1
    or        t0, t0, t1
    xor       t0, t0, a5
    snez      t0, t0
    or        s0, s0, t0
    cunseal   a4, a3, a1
    cgettag   t0, a4                        # {cd tag, GL} | type << 2
    slli      t0, t0, 1
    cgetperm  t1, a4
    andi      t1, t1, 1
    or        t0, t0, t1
    cgettype  t1, a4
    slli      t1, t1, 2
    or        t0, t0, t1
    andi      t1, a5, 0x6E                  # Sail: tag = k6 & k5 & k3 & ~k2 & k1
    xori      t1, t1, 0x6A
    seqz      t1, t1
    slli      t1, t1, 1
    srli      t2, a5, 4                     # GL = k4 & k0, type 0
    and       t2, t2, a5
    andi      t2, t2, 1
    or        t1, t1, t2
    xor       t0, t0, t1
    snez      t0, t0
    slli      t0, t0, 1
    or        s0, s0, t0
    addi      a5, a5, 1
    li        t0, 128
    bne       a5, t0, .Lunseal_loop
    andi      t0, s0, 1
    EXPECT_EQ t0, zero, 202
    andi      t0, s0, 2
    EXPECT_EQ t0, zero, 203

    CHECK_LIVENESS 251
    li        a0, 0
    j         .Lexit

    .balign 4
.Lunexpected:
    li        a0, 250
.Lexit:
    ret
