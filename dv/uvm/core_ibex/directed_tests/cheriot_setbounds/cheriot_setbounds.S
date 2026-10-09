# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_setbounds — CSetBounds narrows a capability to a sub-region
# =============================================================================
# CSetBounds (funct7=0x08, R-type) derives a capability with:
#   new_base  = cs1.cursor  (current address)
#   new_top   = cs1.cursor + rs2  (rs2 = requested length)
#   new_tag   = 1 iff (cs1 was valid) AND (new_region ⊆ cs1 original bounds)
#
# The bounds use compressed (exponent-based) representation, so very small
# lengths are exact; larger ones are rounded up to the nearest representable
# value.  256 bytes (2^8) is exactly representable at exponent 0.
#
# CSetBoundsExact (funct7=0x09) would fail if rounding is needed; CSetBounds
# silently rounds up.  This test uses CSetBounds.
#
#   Test 1 (length after CSetBounds(MTDC, 256) = 256)
#     Start with MTDC (full range, length=0xFFFFFFFF).  After CSetBounds(256),
#     CGetLen should return exactly 256 (no rounding needed for power-of-two).
#     A failure means CSetBounds is not updating the bounds fields, or the
#     exponent calculation is wrong.
#
#   Test 2 (base after CSetBounds = 0)
#     The new base = cursor of MTDC at the time of CSetBounds = 0.
#     CGetBase should return 0.  A failure means the base derivation is wrong.
#
#   Test 3 (tag = 1 after in-range CSetBounds)
#     The new region [0, 256) is contained within the original MTDC bounds
#     [0, 2^32) → tag must remain 1.  A cleared tag means the bounds containment
#     check incorrectly rejected the derivation.
#
#   Test 4 (address (cursor) unchanged after CSetBounds)
#     CSetBounds sets base=cursor but does NOT change cursor.  CGetAddr must
#     still return 0.  A failure means CSetBounds is also moving the cursor,
#     which would break address-preserving derivation.
#
#   Tests 8-20 (cursor above top, request no longer than cs1: tag cleared)
#     CHERIoT-Sail CSetBounds (cheri_insts.sail): the result is
#     setCapBounds(cs1, cs1.address, rs2) with the tag cleared unless
#     inCapBounds(cs1, cs1.address, rs2), i.e. base <= address and
#     address + rs2 <= top. A tagged cs1 can have its cursor above top: for
#     E >= 1 the representable window (getCapBoundsBits) reaches 2^(9+E)
#     bytes past the base, and for E = 24 every address decodes to the same
#     bounds, so CSetAddr keeps the tag. The request is then out of bounds
#     however short it is, even 0. Expected values, from setCapBounds and
#     getCapBoundsBits:
#       ca2 = CSetBounds(MTDC @ 0x80100000, 1024): E = 2, [0x80100000, 0x80100400),
#             then CSetAddr 0x80100404 (top + 4): 8 tag 1, 9 top 0x80100400.
#       CSetBounds(ca2, 1) and CSetBounds(ca2, 7): tag 0 (10, 13), base
#             0x80100404 (11, 14), length 1 / 7 (12, 15).
#       ca4 = CSetBounds(MTDC @ 0x80000000, 0x10000000): E = 24,
#             [0x80000000, 0x90000000), then CSetAddr 0x91000000: 16 tag 1,
#             17 top 0x90000000.
#       CSetBounds(ca4, x0): 18 tag 0, 19 base 0x91000000, 20 length 0.
#   Tests 21-24 (cursor at top, request of 3: tag cleared)
#       ca2 with CSetAddr 0x80100400 (= top): 21 tag 1. CSetBounds(ca2, 3):
#       22 tag 0, 23 base 0x80100400, 24 length 3.
#   Tests 25-27 (E = 24 source, cursor above top, request 7: tag cleared)
#       CSetBounds(ca4, 7) (ca4 from tests 16-20): 25 tag 0, 26 base 0x91000000,
#       27 length 7. cheriot_csetbounds_cross1 bin {case b4|b2, len 7, E = 24}.
#   Tests 28-31 (sealed source, cursor inside, request 0: tag cleared)
#       Sail CSetBounds clears the tag of a sealed cs1 (clearTagIfSealed) and never
#       traps. ca2 = CSetBounds(MTDC @ 0x80100000, 1000): E = 1 (1000 > 511, 500 <= 511
#       after the shift; base 2-aligned, so exact), cursor moved to 0x80100064 (strictly
#       inside), sealed with MScratchC @ 9: 28 still tagged. CSetBounds(ca2, x0): 29 tag 0,
#       30 base 0x80100064, 31 length 0. cheriot_csetbounds_cross1 bin {tagged cs1,
#       case b4 alone, len 0, E in 1..14, cd untagged}: a tagged cs1 with its cursor
#       inside and a zero request loses the tag only by being sealed.
#   Tests 32-34 (E = 24 source, cursor above top, request 1: tag cleared)
#       CSetBounds(ca4, 1) (ca4 from tests 16-20, cursor 0x91000000): 32 tag 0, 33 base
#       0x91000000, 34 length 1. cheriot_csetbounds_cross1 bin {case b4|b2, len 1, E = 24}.
#   Tests 35-42 (E = 0 source of length 2, cursor above top, requests 3 and 7)
#       ca2 = CSetBounds(MTDC @ 0x80100000, 2): E = 0, [0x80100000, 0x80100002); CSetAddr
#       0x80100004 is representable (getCapBoundsBits gives the same bounds, 4 < 2^9): 35 tag 1,
#       36 top 0x80100002. CSetBounds(ca2, 3): 37 tag 0, 38 base 0x80100004, 39 length 3;
#       CSetBounds(ca2, 7): 40 tag 0, 41 base 0x80100004, 42 length 7. The request is longer
#       than cs1, so b4 is clear: cheriot_csetbounds_cross1 bins {case b2 alone, len 3 / 7,
#       E = 0, cd untagged}, which need a cs1 shorter than the request (fcov merge 2026-10-09).
#   Tests 43-45 (the same source, request 5)
#       CSetBounds(ca2, 5) (ca2 from tests 35-42, cursor 0x80100004): 43 tag 0, 44 base
#       0x80100004, 45 length 5. cheriot_csetbounds_cross1 bin {case b2 alone, len 5, E = 0,
#       cd untagged}.
#   Tests 46-49 (E = 2 source, cursor at top, request 2: tag cleared)
#       ca2 = CSetBounds(MTDC @ 0x80100000, 1024) again (E = 2), CSetAddr 0x80100400 (= top):
#       46 tag 1. CSetBounds(ca2, 2): 47 tag 0, 48 base 0x80100400, 49 length 2.
#       cheriot_csetbounds_cross1 bin {case b4|b3, len 2, E in 1..14, cd untagged}.
#   Tests 43-49 add the two bins of that cross the seed-4408 merge (2026-10-09 21:22) missed;
#   up to then only cheriot_rand_operands' random requests had reached them.
#
#   Tests 5-7 (interrupt state — no interrupt expected)
#     Machine-mode interrupts are enabled at the start of the test.
#     Test 5: mstatus.MIE still = 1.
#     Test 6: mcause = 0.
#     Test 7: mip = 0.
#
# Verification:
#   Two independent layers catch a faulty DUT:
#
#   1. Cosim (Spike vs ibex RTL, per instruction step):
#      cgetlen, cgetbase, cgettag, and cgetaddr all write to integer register
#      a0 → cosim verifies each result.  Wrong bounds after CSetBounds diverge
#      Spike from the DUT immediately.
#
#   2. Self-check (bne/beq against expected constants):
#      main() returns non-zero if any check fails → UVM testbench marks FAILED.
#
# Inspired by clang_purecap_array.c (array capability bounds) and
# clang_purecap_stack_cap.c (stack capability bounds) from CTSRD/Cambridge.
# CSetBounds is the fundamental instruction for enforcing spatial safety.
# =============================================================================
#
# CSetBounds encoding (funct7=0x08, rs1=ca0=x10, rs2=a1=x11, rd=ca0=x10):
#   funct7=0b0001000, rs2=0b01011, rs1=0b01010, funct3=000, rd=0b01010
#   = 0001000_01011_01010_000_01010_1011011 = 0x10B5055B
#
# Tests:
#   1. CGetLen after CSetBounds(MTDC, 256) = 256.
#   2. CGetBase after CSetBounds = 0 (new base = cursor = 0).
#   3. Tag = 1 (sub-region is inside original full-range bounds).
#   4. CGetAddr after CSetBounds = 0 (cursor unchanged).
#   8-20. CSetBounds from a cursor above top (E = 2 and E = 24 sources).
#   21-24. CSetBounds from a cursor at top (E = 2 source).
#   25-27. CSetBounds(7) from a cursor above top (E = 24 source).
#   28-31. CSetBounds(0) of a sealed E = 1 source, cursor inside.
#   32-34. CSetBounds(1) from a cursor above top (E = 24 source).
#   35-42. CSetBounds(3) and (7) from a cursor above the top of a length-2 E = 0 source.
#   43-45. CSetBounds(5) from the same source.
#   46-49. CSetBounds(2) from a cursor at top (E = 2 source).
#   5. mstatus.MIE = 1.
#   6. mcause = 0.
#   7. mip = 0.

#include "cheriot_dv.h"

.globl main
main:
    # Enable machine-mode interrupts for the duration of this test.
    csrsi   mstatus, 8              # set mstatus.MIE (bit 3)

    # Load MTDC (full range, base=0, cursor=0, length=0xFFFFFFFF, tag=1).
    .word   0x03D0055B              # cspecialr ca0, mtdc

    # Narrow to 256 bytes (base=cursor=0, length=256).
    li      a1, 256
    .word   0x10B5055B              # csetbounds ca0, ca0, a1
    # Save result to ca1 before cget* checks — each cget* with rd=a0=x10 writes
    # an integer to x10, which clears ca0's capability tag in the same register.
    .word   0xFEA505DB              # cmove ca1, ca0  (rd=x11=a1, rs1=x10=ca0)

    # ── Test 1: length = 256 after CSetBounds ─────────────────────────────────
    .word   0xFE35855B              # cgetlen a0, ca1  (cs1=x11, rd=x10)
    li      a2, 256
    bne     a0, a2, .Lfail_test1

    # ── Test 2: base = 0 (cursor was 0 when CSetBounds was applied) ───────────
    .word   0xFE25855B              # cgetbase a0, ca1
    bne     a0, x0, .Lfail_test2

    # ── Test 3: tag = 1 ([0,256) ⊆ [0,2^32) → derivation is legal) ───────────
    .word   0xFE45855B              # cgettag a0, ca1
    # Compare against a2, NOT a1: a1 is x11 is ca1, the register holding the saved
    # capability every cget* above reads. `li a1, 1` writes a bare integer there and
    # strips the tag, so test 4's cgetaddr would see a null capability with cursor 1
    # instead of the derived one, and fail for that reason rather than a real defect.
    li      a2, 1
    bne     a0, a2, .Lfail_test3

    # ── Test 4: cursor unchanged = 0 ──────────────────────────────────────────
    .word   0xFEF5855B              # cgetaddr a0, ca1
    bne     a0, x0, .Lfail_test4

    # ── Tests 8-15: E = 2 source, cursor 4 bytes above its top ────────────────
    cspecialr a2, SCR_MTDC
    li      t0, 0x80100000
    csetaddr a2, a2, t0
    li      t0, 1024
    csetbounds a2, a2, t0           # [0x80100000, 0x80100400), E = 2
    li      t0, 0x80100404
    csetaddr a2, a2, t0             # top + 4: representable, tag kept
    cgettag a0, a2
    li      t1, 1
    bne     a0, t1, .Lfail_test8
    cgettop a0, a2
    li      t1, 0x80100400
    bne     a0, t1, .Lfail_test9
    li      t2, 0x80100404          # expected base of both results
    li      t0, 1
    csetbounds a3, a2, t0
    cgettag a0, a3
    bnez    a0, .Lfail_test10
    cgetbase a0, a3
    bne     a0, t2, .Lfail_test11
    cgetlen a0, a3
    bne     a0, t0, .Lfail_test12
    li      t0, 7
    csetbounds a3, a2, t0
    cgettag a0, a3
    bnez    a0, .Lfail_test13
    cgetbase a0, a3
    bne     a0, t2, .Lfail_test14
    cgetlen a0, a3
    bne     a0, t0, .Lfail_test15

    # ── Tests 16-20: E = 24 source, cursor above its top, zero-length request ─
    cspecialr a4, SCR_MTDC
    li      t0, 0x80000000
    csetaddr a4, a4, t0
    li      t0, 0x10000000
    csetbounds a4, a4, t0           # [0x80000000, 0x90000000), E = 24
    li      t2, 0x91000000
    csetaddr a4, a4, t2             # E = 24: every address keeps the bounds
    cgettag a0, a4
    li      t1, 1
    bne     a0, t1, .Lfail_test16
    cgettop a0, a4
    li      t1, 0x90000000
    bne     a0, t1, .Lfail_test17
    csetbounds a5, a4, zero
    cgettag a0, a5
    bnez    a0, .Lfail_test18
    cgetbase a0, a5
    bne     a0, t2, .Lfail_test19
    cgetlen a0, a5
    bnez    a0, .Lfail_test20

    # ── Tests 21-24: E = 2 source, cursor exactly at its top ──────────────────
    li      t2, 0x80100400
    csetaddr a2, a2, t2             # ca2 from tests 8-15, cursor = top
    cgettag a0, a2
    li      t1, 1
    bne     a0, t1, .Lfail_test21
    li      t0, 3
    csetbounds a3, a2, t0
    cgettag a0, a3
    bnez    a0, .Lfail_test22
    cgetbase a0, a3
    bne     a0, t2, .Lfail_test23
    cgetlen a0, a3
    bne     a0, t0, .Lfail_test24

    # ── Tests 25-27: E = 24 source, cursor above its top, request 7 ──────────
    li      t0, 7
    csetbounds a5, a4, t0           # ca4 from tests 16-20, cursor 0x91000000
    cgettag a0, a5
    bnez    a0, .Lfail_test25
    cgetbase a0, a5
    li      t2, 0x91000000
    bne     a0, t2, .Lfail_test26
    cgetlen a0, a5
    bne     a0, t0, .Lfail_test27

    # ── Tests 28-31: sealed E = 1 source, cursor inside, zero-length request ─
    cspecialr a2, SCR_MTDC
    li      t0, 0x80100000
    csetaddr a2, a2, t0
    li      t0, 1000
    csetbounds a2, a2, t0           # [0x80100000, 0x801003E8), E = 1
    cincaddrimm a2, a2, 100         # cursor 0x80100064: base < cursor < top
    cspecialr a3, SCR_MSCRATCHC     # sealing root
    li      t0, 9
    csetaddr a3, a3, t0
    cseal   a2, a2, a3              # sealed with otype 9, tagged
    cgettag a0, a2
    li      t1, 1
    bne     a0, t1, .Lfail_test28
    csetbounds a3, a2, zero
    cgettag a0, a3
    bnez    a0, .Lfail_test29
    cgetbase a0, a3
    li      t2, 0x80100064
    bne     a0, t2, .Lfail_test30
    cgetlen a0, a3
    bnez    a0, .Lfail_test31

    # ── Tests 32-34: E = 24 source, cursor above its top, request 1 ──────────
    li      t0, 1
    csetbounds a5, a4, t0           # ca4 from tests 16-20, cursor 0x91000000
    cgettag a0, a5
    bnez    a0, .Lfail_test32
    cgetbase a0, a5
    li      t2, 0x91000000
    bne     a0, t2, .Lfail_test33
    cgetlen a0, a5
    bne     a0, t0, .Lfail_test34

    # ── Tests 35-42: E = 0 source of length 2, cursor above top, requests 3, 7
    cspecialr a2, SCR_MTDC
    li      t0, 0x80100000
    csetaddr a2, a2, t0
    li      t0, 2
    csetbounds a2, a2, t0           # [0x80100000, 0x80100002), E = 0
    li      t2, 0x80100004
    csetaddr a2, a2, t2             # top + 2: representable, tag kept
    cgettag a0, a2
    li      t1, 1
    bne     a0, t1, .Lfail_test35
    cgettop a0, a2
    li      t1, 0x80100002
    bne     a0, t1, .Lfail_test36
    li      t0, 3
    csetbounds a3, a2, t0
    cgettag a0, a3
    bnez    a0, .Lfail_test37
    cgetbase a0, a3
    bne     a0, t2, .Lfail_test38
    cgetlen a0, a3
    bne     a0, t0, .Lfail_test39
    li      t0, 7
    csetbounds a3, a2, t0
    cgettag a0, a3
    bnez    a0, .Lfail_test40
    cgetbase a0, a3
    bne     a0, t2, .Lfail_test41
    cgetlen a0, a3
    bne     a0, t0, .Lfail_test42

    # ── Tests 43-45: the same length-2 E = 0 source above its top, request 5 ─
    li      t0, 5
    csetbounds a3, a2, t0           # ca2 from tests 35-42, cursor 0x80100004 (t2)
    cgettag a0, a3
    bnez    a0, .Lfail_test43
    cgetbase a0, a3
    bne     a0, t2, .Lfail_test44
    cgetlen a0, a3
    bne     a0, t0, .Lfail_test45

    # ── Tests 46-49: E = 2 source, cursor exactly at its top, request 2 ──────
    cspecialr a2, SCR_MTDC
    li      t0, 0x80100000
    csetaddr a2, a2, t0
    li      t0, 1024
    csetbounds a2, a2, t0           # [0x80100000, 0x80100400), E = 2
    li      t2, 0x80100400
    csetaddr a2, a2, t2             # cursor = top
    cgettag a0, a2
    li      t1, 1
    bne     a0, t1, .Lfail_test46
    li      t0, 2
    csetbounds a3, a2, t0
    cgettag a0, a3
    bnez    a0, .Lfail_test47
    cgetbase a0, a3
    bne     a0, t2, .Lfail_test48
    cgetlen a0, a3
    bne     a0, t0, .Lfail_test49

    # ── Interrupt state verification ───────────────────────────────────────────
    csrr    a0, mstatus
    andi    a1, a0, 8
    beq     a1, x0, .Lfail_test5
    csrr    a0, mcause
    bne     a0, x0, .Lfail_test6
    csrr    a0, mip
    bne     a0, x0, .Lfail_test7

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
.Lfail_test25: li a0, 25; ret
.Lfail_test26: li a0, 26; ret
.Lfail_test27: li a0, 27; ret
.Lfail_test28: li a0, 28; ret
.Lfail_test29: li a0, 29; ret
.Lfail_test30: li a0, 30; ret
.Lfail_test31: li a0, 31; ret
.Lfail_test32: li a0, 32; ret
.Lfail_test33: li a0, 33; ret
.Lfail_test34: li a0, 34; ret
.Lfail_test35: li a0, 35; ret
.Lfail_test36: li a0, 36; ret
.Lfail_test37: li a0, 37; ret
.Lfail_test38: li a0, 38; ret
.Lfail_test39: li a0, 39; ret
.Lfail_test40: li a0, 40; ret
.Lfail_test41: li a0, 41; ret
.Lfail_test42: li a0, 42; ret
.Lfail_test43: li a0, 43; ret
.Lfail_test44: li a0, 44; ret
.Lfail_test45: li a0, 45; ret
.Lfail_test46: li a0, 46; ret
.Lfail_test47: li a0, 47; ret
.Lfail_test48: li a0, 48; ret
.Lfail_test49: li a0, 49; ret
