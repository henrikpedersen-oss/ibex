# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: juliet_cwe123_write_what_where — CWE-123 Write-What-Where (CHERIoT)
# =============================================================================
# CWE-123 (NIST Juliet Test Suite): Write-What-Where Condition.
#
#   // Attacker controls both the write target address and the written value.
#   *(attacker_controlled_ptr) = attacker_controlled_value;
#
# In CHERIoT an attacker who can steer the address fed to CSetAddr still only
# holds a capability derived from the original allocation. CHERIoT-Sail
# (cheri_insts.sail CSetAddr -> setCapAddr, cheri_cap_common.sail) clears the
# tag iff the new address is not REPRESENTABLE: the bounds, decoded again with
# the new address, must equal the old ones. For exponent E the representable
# window is [base, base + 2^(9+E)). It is NOT an [base, top) check -- a cursor
# may leave the bounds and keep its tag (the store would then fault at
# dereference, see juliet_cwe131_fault); only a cursor far enough away to be
# unrepresentable loses it here. RTL: ibex_cheriot_pkg.sv cheriot_set_address,
# valid cleared iff (newptr - base) >> (9+E) != 0.
#
# The allocation is a 16-byte capability at 0x80080000 (E = 0, so the window
# is [0x80080000, 0x80080200)). The attacker's target 0x80090000 is 0x10000
# above base, far outside the window: the tag is cleared, and the capability
# can no longer authorise any store. No memory is accessed by this test, so
# the fixed address (the bottom of the stack/TLS area) is never touched.
#
# Integer results go to t0, never a0: aN and caN are the same register, so a
# result written to a0 would replace the capability under test with an integer.
#
#   Test 1  The 16-byte bounded capability is valid: CGetTag = 1.
#   Test 7  Control: CSetAddr(base + 0x100) -- outside [base, top) but inside
#           the representable window -- keeps tag = 1. Fails if CSetAddr
#           clears the tag on a bounds check instead of a representability
#           check, and shows test 2's tag 0 is not "CSetAddr always clears".
#   Test 2  CSetAddr(0x80090000) on the same capability: CGetTag = 0.
#           Fails if an unrepresentable address keeps its tag.
#   Test 3  CGetAddr = 0x80090000: the address is still placed; only the tag
#           is cleared.
#   Tests 4-6  mstatus.MIE = 1, mcause = 0, mip = 0 (no interrupt taken).
#
# Returns 0 on success, else the failing test number (1-7).
#
# Encodings (Sail encdec, opcode 0x5B; cross-checked against
# cheriot_perm_lc_sc.S):
#   cspecialr  ca0, mtdc     = .word 0x03D0055B  (CSpecialRW, SCR 29)
#   csetaddr   ca0, ca0, a1  = .word 0x20B5055B  (funct7=0x10)
#   csetbounds ca0, ca0, a1  = .word 0x10B5055B  (funct7=0x08)
#   cgettag    t0, ca0       = .word 0xFE4502DB  (funct7=0x7F, rs2=0x04)
#   cgetaddr   t0, ca0       = .word 0xFEF502DB  (rs2=0x0F)
# =============================================================================

.globl main
main:
    # Enable machine-mode interrupts for the duration of this test.
    csrsi   mstatus, 8              # set mstatus.MIE (bit 3)

    # The legitimate allocation: [0x80080000, 0x80080010), derived from MTDC.
    .word   0x03D0055B              # cspecialr ca0, mtdc  (full-range data cap)
    li      a1, 0x80080000
    .word   0x20B5055B              # csetaddr ca0, ca0, a1  (cursor -> 0x80080000)
    li      a1, 16
    .word   0x10B5055B              # csetbounds ca0, ca0, a1

    # ── Test 1: bounded cap is valid (tag = 1) ────────────────────────────────
    .word   0xFE4502DB              # cgettag t0, ca0 (t0: keep ca0 intact)
    li      t1, 1
    bne     t0, t1, .Lfail_test1

    # ── Test 7: out of bounds but representable -> tag kept ───────────────────
    li      a1, 0x80080100          # base + 0x100: > top, < base + 2^9
    .word   0x20B5055B              # csetaddr ca0, ca0, a1
    .word   0xFE4502DB              # cgettag t0, ca0
    bne     t0, t1, .Lfail_test7    # t1 = 1

    # ── Test 2: attacker-controlled target, unrepresentable -> tag cleared ────
    li      a1, 0x80090000          # base + 0x10000
    .word   0x20B5055B              # csetaddr ca0, ca0, a1
    .word   0xFE4502DB              # cgettag t0, ca0
    bnez    t0, .Lfail_test2        # tag must be 0

    # ── Test 3: the address was placed; the tag is the defence ────────────────
    .word   0xFEF502DB              # cgetaddr t0, ca0
    li      t1, 0x80090000
    bne     t0, t1, .Lfail_test3

    # ── Interrupt state verification (no interrupt expected) ───────────────────
    csrr    t0, mstatus
    andi    t0, t0, 8
    beqz    t0, .Lfail_test4
    csrr    t0, mcause
    bnez    t0, .Lfail_test5
    csrr    t0, mip
    bnez    t0, .Lfail_test6

    li      a0, 0
    ret

.Lfail_test1: li a0, 1; ret
.Lfail_test2: li a0, 2; ret
.Lfail_test3: li a0, 3; ret
.Lfail_test4: li a0, 4; ret
.Lfail_test5: li a0, 5; ret
.Lfail_test6: li a0, 6; ret
.Lfail_test7: li a0, 7; ret
