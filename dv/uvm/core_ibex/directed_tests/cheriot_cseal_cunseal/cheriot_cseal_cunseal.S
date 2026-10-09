# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_cseal_cunseal — CSeal/CUnseal round-trip on an executable cap
# =============================================================================
# CSeal (funct7=0x0b) and CUnseal (funct7=0x0c) are two-source instructions:
# cd <-- cs1 with cd.otype set from (CSeal) / cleared to (CUnseal) an
# authority provided by cs2 (ibex_cheriot_ex.sv). Sealing requires a
# dedicated "sealing capability" as cs2 -- one with Permit_Seal (SE) for
# CSeal / Permit_Unseal (US) for CUnseal, unsealed itself, tagged, and whose
# ADDRESS (not otype field) both lies within its own bounds AND encodes the
# new/expected otype value.
#
# MScratchC resets to ROOT_CAP_TS (ibex_cheriot_pkg.sv), the dedicated
# Sealing Root: cperms=CPERMS_TS expands (cheriot_expand_perms) to perm=0xE01
# (SE=1, US=1, U0=1, GL=1, all else 0) -- already verified by
# cheriot_mscratchc_seal. No other reset SCR has SE or US set.
#
# For an EXECUTABLE cs1 (MTCC, perm.EX=1), ibex_cheriot_ex.sv's
# chk_cs2_bad_type check requires cs2.address in [1,7] with bits[31:3]==0 --
# exactly the OTYPE_SENTRY_* range (1=forward, EX-only sentry). Using
# MScratchC's cursor (set via CSetAddr to 1) as cs2 avoids the more
# complicated non-executable path (whose otype range [9,15] is represented
# via an implicit 4th bit reconstructed at CGetType time from the sealed
# cap's own EX permission, not stored directly -- see
# ibex_cheriot_pkg.sv's cheriot_decode_otype).
#
#   Test 1 (tag = 1 after CSeal: cs2 checks all passed)
#   Test 2 (CGetType = 1 after CSeal: matches OTYPE_SENTRY_II_FWD)
#   Test 3 (original MTCC (cs1) untouched: still tag = 1 -- CSeal writes cd,
#           a separate register, not cs1 itself)
#   Test 4 (tag = 1 after CUnseal: cs2 checks all passed)
#   Test 5 (CGetType = 0 (OTYPE_UNSEALED) after CUnseal)
#   Test 6 (permissions preserved through the seal/unseal round trip)
#   Tests 10-24 (CUnseal with an untagged authority: cd always untagged)
#     CHERIoT-Sail CUnseal (cheri_insts.sail): permitted = cs2.tag &
#     sealed(cs1) & unsealed(cs2) & otype in cs2's bounds & cs2.US; cd =
#     unseal(cs1) (otype 0) with GL = cs1.GL & cs2.GL, tag cleared unless
#     permitted. CUnseal never traps. cs2 here is MTDC without GL (0x07E),
#     sealed with otype 9 (10 tag 1, 11 CGetType 9, 12 GL 0 before the
#     CClearTag), then untagged: sealed, US = 0 (data format), GL = 0. With
#     it as cs2, each cs1 below gives tag 0, CGetType 0 and GL 0:
#       13-15  cs1 = an integer (untagged, unsealed, GL = 0)
#       16-18  cs1 = cs2 itself (untagged, sealed, GL = 0)
#       19-21  cs1 = CClearTag(CSeal(MTDC, 9)) (untagged, sealed, GL = 1)
#       22-24  cs1 = MTDC (tagged, unsealed, GL = 1)
#   Tests 25-52 (CUnseal with the other sealed authorities, cs1 unsealed: cd
#     always untagged, unsealed, GL = cs1.GL & cs2.GL). Preconditions: 25
#     MTDC without GL sealed with otype 9 is tagged (cs2 B: tagged, sealed,
#     US = 0, GL = 0); 26-28 MScratchC without GL sealed with otype 9 is
#     tagged, CGetType 9, perms 0xE00 (cs2 E: tagged, sealed, US = 1, GL = 0).
#       29-31  cs2 E,            cs1 = CClearTag(MTDC) (untagged, GL = 1)
#       32-34  cs2 CClearTag(E), cs1 = an integer
#       35-37  cs2 B,            cs1 = an integer
#       38-40  cs2 B,            cs1 = CClearTag(MTDC)
#       41-43  cs2 B,            cs1 = MTDC without GL (tagged, GL = 0)
#       44-46  cs2 as 13-24,     cs1 = MTDC without GL
#       47-49  cs2 as 13-24,     cs1 = CClearTag(MTDC)
#       50-52  cs2 CClearTag(CSeal(MTDC, 9)) (untagged, sealed, US = 0,
#              GL = 1), cs1 = CClearTag(MTDC): cd GL = 1
#   Tests 53-54 (CSeal of MTCC with an untagged authority: cd untagged)
#     53 CSetBoundsExact(MScratchC @ 6, 1) is tagged; 54 CSeal(MTCC,
#     CClearTag of it) is untagged (the authority has SE and its address is
#     its base, but no tag).
#   Tests 55-58 (CUnseal of a tagged, unsealed, global cs1 with a tagged sealed
#     authority without US and GL: cheriot_cunseal_cross0 bin {cs1 tag 1, unsealed,
#     GL 1; cs2 tag 1, sealed, US 0, GL 0}). 55 MTDC without GL sealed with otype 9 is
#     tagged (as 25); 56-58 CUnseal(MTDC, it): cd untagged (cs1 is not sealed),
#     unsealed, GL = 1 & 0 = 0.
#   Tests 59-61 (CSeal of MTCC (EX) with authorities that cannot seal; Sail CSeal:
#     permitted needs cs2 tagged, unsealed, SE, base <= cs2.address < top and an
#     otype valid for cs1 (1-7 for an executable cs1), else cd's tag is cleared;
#     never a trap). cheriot_cseal_cross1 bins:
#       59  cs2 = CClearTag(MScratchC @ 13): untagged, SE, address 13 strictly inside
#           [0, 2^32) (seal_bound 0): cd untagged
#       60  cs2 = MTDC @ 0 bounded to [0, 2) then moved to address 4: still tagged
#           (representable at E = 0)
#       61  CSeal(MTCC, that cs2): tagged, no SE, address 4 above top (seal_bound
#           b2): cd untagged
#   Tests 62-68 (CUnseal of an unsealed global cs1 with an untagged sealed authority that
#     has US but not GL: cheriot_cunseal_cross0 bins {cs1 tag 0 / 1, unsealed, GL 1; cs2
#     tag 0, sealed, US 1, GL 0}, the two the seed-4408 merge (2026-10-09 21:22) missed;
#     32-34 cross the same cs2 with an integer cs1 only). 62 MScratchC without GL sealed
#     with otype 9 is tagged (cs2 E of 26-28), then CClearTag. cs1 = CClearTag(MTDC):
#     63-65; cs1 = MTDC: 66-68. cd untagged (cs2 untagged, cs1 not sealed), unsealed,
#     GL = 1 & 0 = 0.
#   Tests 7-9 (interrupt state — no interrupt expected)
#
# Verification: cosim (per-instruction Spike/RTL register compare) plus the
# self-check below (independent of cosim).
#
# Instruction encodings (opcode=0x5B for CHERIoT):
#   cspecialr ca0, mtcc       = .word 0x03C0055B  (rd=a0, SCR=28=MTCC)
#   cgetperm  t0, ca0         = .word 0xFE0502DB  (rs2=0x00, rs1=a0, rd=t0)
#   cspecialr ca2, mscratchc  = .word 0x03E0065B  (rd=a2, SCR=30=MSCRATCHC)
#   csetaddr  ca2,ca2,a1      = .word 0x20B6065B  (funct7=0x10, cs1=a2, rs2=a1, rd=a2)
#   cseal     ca3,ca0,ca2     = .word 0x16C506DB  (funct7=0x0b, cs1=a0, rs2=a2, rd=a3)
#   cgettag   a5, ca3         = .word 0xFE4687DB  (rs2=0x04, rs1=a3, rd=a5)
#   cgettype  a5, ca3         = .word 0xFE1687DB  (rs2=0x01, rs1=a3, rd=a5)
#   cgettag   a5, ca0         = .word 0xFE4507DB  (rs2=0x04, rs1=a0, rd=a5)
#   cunseal   ca4,ca3,ca2     = .word 0x18C6875B  (funct7=0x0c, cs1=a3, rs2=a2, rd=a4)
#   cgettag   a5, ca4         = .word 0xFE4707DB  (rs2=0x04, rs1=a4, rd=a5)
#   cgettype  a5, ca4         = .word 0xFE1707DB  (rs2=0x01, rs1=a4, rd=a5)
#   cgetperm  a5, ca4         = .word 0xFE0707DB  (rs2=0x00, rs1=a4, rd=a5)

#include "cheriot_dv.h"

# cd untagged (code \c_tag), unsealed (\c_type) and without GL (\c_gl). Uses a5.
.macro EXPECT_UNTAGGED_LOCAL cd, c_tag, c_type, c_gl
    cgettag a5, \cd
    bnez    a5, .Lfail_test\c_tag
    cgettype a5, \cd
    bnez    a5, .Lfail_test\c_type
    cgetperm a5, \cd
    andi    a5, a5, 1               # GL is perms bit 0
    bnez    a5, .Lfail_test\c_gl
.endm

# As EXPECT_UNTAGGED_LOCAL with cd.GL == \gl. Uses a5 and t1.
.macro EXPECT_UNSEAL_FAILED cd, gl, c_tag, c_type, c_gl
    cgettag a5, \cd
    bnez    a5, .Lfail_test\c_tag
    cgettype a5, \cd
    bnez    a5, .Lfail_test\c_type
    cgetperm a5, \cd
    andi    a5, a5, 1
    li      t1, \gl
    bne     a5, t1, .Lfail_test\c_gl
.endm

.globl main
main:
    csrsi   mstatus, 8              # set mstatus.MIE (bit 3)

    # a0 = MTCC (execute root: perms=0x1EB (EX=1,GL=1,...), tag=1, unsealed)
    .word   0x03C0055B              # cspecialr ca0, mtcc
    .word   0xFE0502DB              # cgetperm t0, ca0   -> save original perms

    # a2 = MScratchC (sealing root: perms=0xE01 (SE=1,US=1), tag=1, unsealed),
    # cursor set to 1 (OTYPE_SENTRY_II_FWD) -- both the sealing authority AND
    # the otype value to seal with.
    .word   0x03E0065B              # cspecialr ca2, mscratchc
    li      a1, 1
    .word   0x20B6065B              # csetaddr ca2, ca2, a1

    # Seal a0 (MTCC) into a3 using a2 as the sealing authority.
    .word   0x16C506DB              # cseal ca3, ca0, ca2

    # ── Test 1: tag = 1 (all CSeal permission/bound checks passed) ───────────
    .word   0xFE4687DB              # cgettag a5, ca3
    # Hold the constant in t1, NOT a4: a4 is x14 is ca4, the CUnseal destination
    # below. `cunseal ca4, ca3, ca2` overwrites x14 with the unsealed cursor
    # (0x80000200), so test 4 would compare tag=1 against that address and fail
    # for register aliasing rather than a real CUnseal defect.
    li      t1, 1
    bne     a5, t1, .Lfail_test1

    # ── Test 2: otype = 1 (OTYPE_SENTRY_II_FWD) ───────────────────────────────
    .word   0xFE1687DB              # cgettype a5, ca3
    bne     a5, t1, .Lfail_test2    # t1 still holds 1

    # ── Test 3: original a0 (cs1) untouched by CSeal -- still tag = 1 ────────
    .word   0xFE4507DB              # cgettag a5, ca0
    bne     a5, t1, .Lfail_test3

    # Unseal a3 back using the same sealing authority (a2 also has US=1).
    .word   0x18C6875B              # cunseal ca4, ca3, ca2

    # ── Test 4: tag = 1 (all CUnseal permission/bound checks passed) ─────────
    .word   0xFE4707DB              # cgettag a5, ca4
    bne     a5, t1, .Lfail_test4

    # ── Test 5: otype = 0 (OTYPE_UNSEALED) ────────────────────────────────────
    .word   0xFE1707DB              # cgettype a5, ca4
    bnez    a5, .Lfail_test5

    # ── Test 6: permissions preserved through the round trip ────────────────
    .word   0xFE0707DB              # cgetperm a5, ca4
    bne     a5, t0, .Lfail_test6

    # ── Tests 10-12: cs2 = local data capability sealed with otype 9 ─────────
    cspecialr a1, SCR_MTDC
    li      t2, 0xFFE
    candperm a1, a1, t2             # clear GL: perms 0x07E
    li      t2, 9
    csetaddr a2, a2, t2             # sealing authority at otype 9
    cseal   a1, a1, a2
    cgettag a5, a1
    bne     a5, t1, .Lfail_test10   # t1 still holds 1
    cgettype a5, a1
    bne     a5, t2, .Lfail_test11
    cgetperm a5, a1
    andi    a5, a5, 1
    bnez    a5, .Lfail_test12
    ccleartag a1, a1                # cs2: untagged, sealed, US = 0, GL = 0

    # ── Tests 13-24: CUnseal through that cs2 ────────────────────────────────
    li      a3, 0x1234              # an integer: untagged, unsealed, GL = 0
    cunseal a4, a3, a1
    EXPECT_UNTAGGED_LOCAL a4, 13, 14, 15
    cmove   a3, a1                  # untagged, sealed, GL = 0
    cunseal a4, a3, a1
    EXPECT_UNTAGGED_LOCAL a4, 16, 17, 18
    cspecialr a3, SCR_MTDC
    cseal   a3, a3, a2
    ccleartag a3, a3                # untagged, sealed (otype 9), GL = 1
    cunseal a4, a3, a1
    EXPECT_UNTAGGED_LOCAL a4, 19, 20, 21
    cspecialr a3, SCR_MTDC          # tagged, unsealed, GL = 1
    cunseal a4, a3, a1
    EXPECT_UNTAGGED_LOCAL a4, 22, 23, 24

    # ── Tests 25-52: the other cs2 states with an unsealed cs1 ───────────────
    # a1 is still cs2 = untagged, sealed, US = 0, GL = 0, and a2 the authority at otype 9.
    li      t2, 0xFFE               # candperm mask: clear GL
    cspecialr a0, SCR_MTDC
    candperm a0, a0, t2
    cseal   a0, a0, a2              # a0: tagged, sealed, US = 0, GL = 0
    cgettag a5, a0
    li      t1, 1
    bne     a5, t1, .Lfail_test25
    cspecialr t0, SCR_MSCRATCHC
    candperm t0, t0, t2
    cseal   t0, t0, a2              # t0: tagged, sealed, US = 1, GL = 0
    cgettag a5, t0
    bne     a5, t1, .Lfail_test26
    cgettype a5, t0
    li      t1, 9
    bne     a5, t1, .Lfail_test27
    cgetperm a5, t0
    li      t1, 0xE00               # SE, US, U0 of the sealing root, without GL
    bne     a5, t1, .Lfail_test28

    # cs2 tagged and sealed (US = 1, GL = 0), cs1 untagged, unsealed, GL = 1
    cspecialr a3, SCR_MTDC
    ccleartag a3, a3
    cunseal a4, a3, t0
    EXPECT_UNSEAL_FAILED a4, 0, 29, 30, 31
    # cs2 untagged, sealed, US = 1, GL = 0; cs1 an integer
    ccleartag t0, t0
    li      a3, 0x1234
    cunseal a4, a3, t0
    EXPECT_UNSEAL_FAILED a4, 0, 32, 33, 34
    # cs2 tagged, sealed, US = 0, GL = 0; cs1 an integer, then untagged GL = 1, then
    # tagged without GL
    cunseal a4, a3, a0
    EXPECT_UNSEAL_FAILED a4, 0, 35, 36, 37
    cspecialr a3, SCR_MTDC
    ccleartag a3, a3
    cunseal a4, a3, a0
    EXPECT_UNSEAL_FAILED a4, 0, 38, 39, 40
    cspecialr a3, SCR_MTDC
    candperm a3, a3, t2
    cunseal a4, a3, a0
    EXPECT_UNSEAL_FAILED a4, 0, 41, 42, 43
    # cs2 untagged, sealed, US = 0, GL = 0 (a1); cs1 tagged without GL, then untagged GL = 1
    cunseal a4, a3, a1
    EXPECT_UNSEAL_FAILED a4, 0, 44, 45, 46
    cspecialr a3, SCR_MTDC
    ccleartag a3, a3
    cunseal a4, a3, a1
    EXPECT_UNSEAL_FAILED a4, 0, 47, 48, 49
    # cs2 untagged, sealed, US = 0, GL = 1; cs1 untagged, GL = 1: cd keeps GL = 1
    cspecialr t0, SCR_MTDC
    cseal   t0, t0, a2
    ccleartag t0, t0
    cunseal a4, a3, t0
    EXPECT_UNSEAL_FAILED a4, 1, 50, 51, 52

    # ── Tests 53-54: CSeal of MTCC with an untagged authority at its base ─────
    cspecialr t0, SCR_MSCRATCHC
    li      t2, 6
    csetaddr t0, t0, t2
    li      t2, 1
    csetboundsexact t0, t0, t2      # [6, 7): SE, address 6 at the base
    cgettag a5, t0
    li      t1, 1
    bne     a5, t1, .Lfail_test53
    ccleartag t0, t0
    cspecialr a3, SCR_MTCC
    cseal   a4, a3, t0
    cgettag a5, a4
    bnez    a5, .Lfail_test54

    # ── Tests 55-58: tagged unsealed global cs1, tagged sealed cs2 (US 0, GL 0) ─
    # a2 is still the sealing authority at otype 9 (MScratchC @ 9).
    li      t2, 0xFFE               # candperm mask: clear GL
    cspecialr a0, SCR_MTDC
    candperm a0, a0, t2
    cseal   a0, a0, a2              # a0: tagged, sealed (otype 9), US = 0, GL = 0
    cgettag a5, a0
    li      t1, 1
    bne     a5, t1, .Lfail_test55
    cspecialr a3, SCR_MTDC          # tagged, unsealed, GL = 1
    cunseal a4, a3, a0
    EXPECT_UNSEAL_FAILED a4, 0, 56, 57, 58

    # ── Tests 59-61: CSeal of MTCC through authorities that cannot seal ──────
    cspecialr t0, SCR_MSCRATCHC
    li      t2, 13
    csetaddr t0, t0, t2
    ccleartag t0, t0                # untagged, SE, address 13 inside [0, 2^32)
    cspecialr a3, SCR_MTCC
    cseal   a4, a3, t0
    cgettag a5, a4
    bnez    a5, .Lfail_test59
    cspecialr t0, SCR_MTDC
    csetaddr t0, t0, zero
    li      t2, 2
    csetbounds t0, t0, t2           # [0, 2), E = 0
    li      t2, 4
    csetaddr t0, t0, t2             # address 4: above top, representable
    cgettag a5, t0
    li      t1, 1
    bne     a5, t1, .Lfail_test60
    cseal   a4, a3, t0              # a3 is still MTCC
    cgettag a5, a4
    bnez    a5, .Lfail_test61

    # ── Tests 62-68: untagged sealed cs2 with US (GL 0), unsealed global cs1 ─
    # a2 is still the sealing authority at otype 9 (MScratchC @ 9).
    li      t2, 0xFFE               # candperm mask: clear GL
    cspecialr t0, SCR_MSCRATCHC
    candperm t0, t0, t2
    cseal   t0, t0, a2              # t0: tagged, sealed (otype 9), US = 1, GL = 0
    cgettag a5, t0
    li      t1, 1
    bne     a5, t1, .Lfail_test62
    ccleartag t0, t0                # cs2: untagged, sealed, US = 1, GL = 0
    cspecialr a3, SCR_MTDC
    ccleartag a3, a3                # cs1: untagged, unsealed, GL = 1
    cunseal a4, a3, t0
    EXPECT_UNSEAL_FAILED a4, 0, 63, 64, 65
    cspecialr a3, SCR_MTDC          # cs1: tagged, unsealed, GL = 1
    cunseal a4, a3, t0
    EXPECT_UNSEAL_FAILED a4, 0, 66, 67, 68

    # ── Interrupt state verification ───────────────────────────────────────────
    csrr    a0, mstatus
    andi    a1, a0, 8
    beq     a1, x0, .Lfail_test7
    csrr    a0, mcause
    bne     a0, x0, .Lfail_test8
    csrr    a0, mip
    bne     a0, x0, .Lfail_test9

    li      a0, 0
    ret

.Lfail_test1: li a0, 1; ret
.Lfail_test2: li a0, 2; ret
.Lfail_test3: li a0, 3; ret
.Lfail_test4: li a0, 4; ret
.Lfail_test5: li a0, 5; ret
.Lfail_test6: li a0, 6; ret
.Lfail_test7: li a0, 7; ret
.Lfail_test8: li a0, 8; ret
.Lfail_test9: li a0, 9; ret
.Lfail_test10: li a0, 10; ret
.Lfail_test11: li a0, 11; ret
.Lfail_test12: li a0, 12; ret
.Lfail_test13: li a0, 13; ret
.Lfail_test14: li a0, 14; ret
.Lfail_test15: li a0, 15; ret
.Lfail_test16: li a0, 16; ret
.Lfail_test17: li a0, 17; ret
.Lfail_test18: li a0, 18; ret
.Lfail_test19: li a0, 19; ret
.Lfail_test20: li a0, 20; ret
.Lfail_test21: li a0, 21; ret
.Lfail_test22: li a0, 22; ret
.Lfail_test23: li a0, 23; ret
.Lfail_test24: li a0, 24; ret
.irp n, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68
.Lfail_test\n: li a0, \n; ret
.endr
