# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cov_fcov2_cheri_isa -- address arithmetic on an untagged sealed capability whose
#       base decodes above its address; CGetBase at address 0xFFFFFFFF
# =============================================================================
# Targets the cheriot_uarch_cg bins no other source produced (fcov merge 2026-10-09 17:14):
#   cheriot_cauicgp_cross     {cs1 tag 0, case1, sealed, E = 0, imm20 = 0}
#   cheriot_cincaddrimm_cross {cs1 tag 0, case1, sealed, E = 0, imm12 = 0 / 0xFFF}
#   cheriot_cincaddr_cross    {cs1 tag 0, case1, sealed, E = 0, rs2 = 0 / 0xFFFFFFFF}
#   cheriot_cget_field_cross  {cs1 tag 1, cs1 address with no zero bit, CFIELD_BASE}
# and one the seed-4408 merge (2026-10-09 21:22) missed, which before only cheriot_rand_operands'
# random mem group had reached:
#   cheriot_csc_cross0        {cs1 tag 0, sealed, SD 0; cs2 GL 1}: CSC of the memory root (GL)
#                             through the same untagged sealed source (cperms 0: no SD)
# case1 is fcov_repr_cases(): the result's address below cs1's decoded base. With an increment of
# 0 that needs a base above the address itself, which for E = 0 happens only when the base's
# correction wraps it past 0: address < 2^9 and address[8:0] < B. A tagged capability never
# decodes like that (the ignore_bins inc0_tagbelow_*), so cs1 is untagged: CSetHigh builds it from
# an integer (the null capability with address 0x10) and the high word HI below, sealed
# (cotype 1) so the sealed bin is the one exercised.
#
# Expected values from CHERIoT-Sail (dv/cosim/cheriot-sail-model/src):
#   cheri_insts.sail CSetHigh: cd = capBitsToCapability(false, rs2 @ cs1.address), tag 0.
#   cheri_cap_common.sail: HI = 0x00422100 is cperms 0 (sealing format, no permissions),
#     cotype 1 (otype 9: 8 | cotype for a non-executable format), cE = 0, T = 0x110, B = 0x100.
#     getCapBoundsBits at address 0x10: a_mid = 0x010 < B, so the base region is one below the
#     address's: base = (0 - 0x200) | 0x100 = 0xFFFFFF00 (mod 2^32), above the address.
#   CIncAddr / CIncAddrImm / AUICGP (imm << 11): incCapAddr / setCapAddr change the address only;
#     the tag (already 0) stays 0, the high word is unchanged, nothing traps (a sealed source
#     only loses its tag).
#   CSetAddr(MTDC, 0xFFFFFFFF): MTDC is the memory root (base 0, top 2^32, E = 24), where every
#     address is representable: tagged, CGetBase 0.
#   cheri_insts.sail StoreCapImm: the first check is the authority's tag, so the CSC raises
#     CapEx_TagViolation (0x02) against cs1 (handle_cheri_reg_exception: mtval = cs1 << 5 | 0x02
#     = 0x182 for c12), mcause 28, MEPCC at the CSC, and writes nothing.
#
# Checks and failure codes (main returns 0 or the first failing code):
#   1-3   the CSetHigh source: CGetTag 0, CGetAddr 0x10, CGetBase 0xFFFFFF00
#   1x    AUICGP cd, 0 with c3 = that source: +0 tag 0, +1 address 0x10, +2 CGetHigh = HI
#   2x    CIncAddrImm 0      3x CIncAddrImm -1 (address 0xF)
#   4x    CIncAddr x0        5x CIncAddr 0xFFFFFFFF (address 0xF)
#   60/61 CSetAddr(MTDC, 0xFFFFFFFF): CGetTag 1, CGetBase 0
#   70-72 CSC c13 (MTDC), 0(c12 = the source): mcause 28, mtval 0x182, MEPCC.address = the CSC
#   73    that CSC did not trap
#   250   unexpected trap (MTCC points at a test-local vector)   251 liveness
#
# Register use: x0-x15 only. s1 = executed-check count, a5 holds cgp while c3 is the test source,
# a2 the source, a3 results, t0-t2 integers. A cget* result never goes into a live capability.

#include "cheriot_dv.h"

    .option norelax

#define HI 0x00422100

# Checks result \cd: tag 0, address \addr (register), high word HI. Clobbers t0, t2.
.macro RESULT cd, addr, n
    cgettag   t0, \cd
    EXPECT_EQ t0, zero, (\n * 10 + 0)
    cgetaddr  t0, \cd
    EXPECT_EQ t0, \addr, (\n * 10 + 1)
    cgethigh  t0, \cd
    EXPECT_EQI t0, HI, (\n * 10 + 2)
.endm

    .text
    .globl main
main:
    li        s1, 0
    SET_VEC   .Lunexpected, t0, t1

    # ── The source: untagged, sealed, E = 0, base above its address ──────────
    li        a2, 0x10                      # null capability with address 0x10
    li        t0, HI
    csethigh  a2, a2, t0
    cgettag   t0, a2
    EXPECT_EQ t0, zero, 1
    cgetaddr  t0, a2
    EXPECT_EQI t0, 0x10, 2
    cgetbase  t0, a2
    EXPECT_EQI t0, 0xFFFFFF00, 3
    li        t1, 0x10                      # expected address, increment 0
    li        t2, 0xF                       # expected address, increment -1 (EXPECT_EQI uses t2:
    mv        a4, t2                        # keep it in a4)

    # ── 1x: AUICGP cd, 0 with c3 = the source ────────────────────────────────
    cmove     a5, gp
    cmove     gp, a2
    auicgp    a3, 0
    cmove     gp, a5
    RESULT    a3, t1, 1

    # ── 2x / 3x: CIncAddrImm 0 and -1 ────────────────────────────────────────
    cincaddrimm a3, a2, 0
    RESULT    a3, t1, 2
    cincaddrimm a3, a2, -1
    RESULT    a3, a4, 3

    # ── 4x / 5x: CIncAddr x0 and 0xFFFFFFFF ──────────────────────────────────
    cincaddr  a3, a2, zero
    RESULT    a3, t1, 4
    li        a1, -1
    cincaddr  a3, a2, a1
    RESULT    a3, a4, 5

    # ── 60/61: CGetBase of a tagged capability at address 0xFFFFFFFF ─────────
    cspecialr a3, SCR_MTDC
    li        t0, -1
    csetaddr  a3, a3, t0
    cgettag   t0, a3
    EXPECT_EQI t0, 1, 60
    cgetbase  t0, a3
    EXPECT_EQ t0, zero, 61

    # ── 7x: CSC of a global capability through the source (untagged, sealed, no SD) ──
    cspecialr a3, SCR_MTDC                  # cs2: the memory root, GL = 1
    SET_VEC   .Lcsc_trap, a4, t0
.Lcsc_insn:
    csc       a3, a2, 0                     # must trap: CapEx_TagViolation against ca2
    li        a0, 73                        # fell through: no trap
    j         .Lexit

    .balign 4
.Lcsc_trap:                                 # PCC = MTCC (has SR); MEPCC = the CSC
    csrr      t0, mcause
    EXPECT_EQI t0, 28, 70                   # CHERI exception
    csrr      t0, mtval
    EXPECT_EQI t0, ((12 << 5) | 0x02), 71   # cs1 = c12, capcause TagViolation
    cspecialr a4, SCR_MEPCC
    cgetaddr  t0, a4
    LA_FAR    a1, .Lcsc_insn, a4
    EXPECT_EQ t0, a1, 72
    RESUME    .Lcsc_resume, a4, t0          # mret past the CSC, MIE restored
.Lcsc_resume:
    SET_VEC   .Lunexpected, a4, t0

    CHECK_LIVENESS 251
    li        a0, 0
    j         .Lexit

    .balign 4
.Lunexpected:
    li        a0, 250
.Lexit:
    ret
