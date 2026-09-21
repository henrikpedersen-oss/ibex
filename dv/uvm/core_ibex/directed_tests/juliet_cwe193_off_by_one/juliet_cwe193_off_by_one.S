# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: juliet_cwe193_off_by_one — CWE-193 Off-by-One Error (CHERIoT)
# =============================================================================
# CWE-193 (NIST Juliet Test Suite): Off-by-One Error.
#
# In C without CHERIoT:
#   char buf[16];
#   for (int i = 0; i <= 16; i++) buf[i] = 0;  ← writes one past the end
#
# In CHERIoT:
#   CHERI bounds are half-open intervals [base, top).  The cursor value equal
#   to 'top' is OUTSIDE the valid range — it is the first address past the end.
#   When CIncAddr moves the cursor to exactly the top address, the tag is
#   cleared immediately.  The "i == 16" iteration is blocked in hardware.
#
# This test creates a 16-byte buffer capability at 0x80080000 and probes the
# boundary precisely:
#
#   Test 1 (tag = 1 after CSetBounds(16))
#     After csetaddr+csetbounds, cursor=0x80080000=base, top=0x80080010.
#     The cursor is at the first byte of the buffer (in-bounds) → tag=1.
#     This is the baseline: the allocation is valid.
#
#   Test 2 (tag = 0 after CIncAddr(+16) — cursor exactly at top)
#     CIncAddr(+16) moves the cursor to 0x80080000+16 = 0x80080010 = top.
#     CHERI bounds exclude top, so cursor=top is out-of-bounds → tag=0.
#     This is the off-by-one access: one step past the end is denied.
#
#   Test 3 (tag = 1 after fresh CSetBounds(16)+CIncAddr(+15))
#     A fresh 16-byte cap starting at 0x80080000 is derived.  CIncAddr(+15)
#     gives cursor=0x8008000F = top-1, which IS within [base, top) → tag=1.
#     This confirms that the last valid byte (index 15) is accessible, and
#     only the element at index 16 (= top) is denied.
#
#   Tests 4-6 (interrupt state — no interrupt expected)
#     Machine-mode interrupts are enabled at the start of the test.
#     Test 4: mstatus.MIE still = 1.
#     Test 5: mcause = 0.
#     Test 6: mip = 0.
#
# Verification:
#   Two independent layers catch a faulty DUT:
#
#   1. Cosim (Spike vs ibex RTL, per instruction step):
#      cgettag writes to a0; Spike and RTL are compared after every step.
#      If the tag is not cleared at cursor=top, or is wrongly cleared at
#      cursor=top-1, Spike and the DUT diverge immediately.
#
#   2. Self-check (bne against expected 0 or 1):
#      main() returns non-zero on any failure; UVM marks FAILED.
#
# Adapted from Juliet C Test Suite CWE193_Off_by_One_Error (NIST/NSA).
# =============================================================================
#
# Instruction encodings (rd=a0=x10, cs1=ca0=x10, rs2=a1=x11 unless noted):
#
#   cspecialr ca0, mtdc   [funct7=0x01, rs2=29, rs1=x0, rd=x10]:
#     (0x01<<25)|(29<<20)|(0<<15)|(0<<12)|(10<<7)|0x5B = 0x03D0055B
#
#   csetaddr ca0, ca0, a1 [funct7=0x10, rs2=x11, rs1=x10, rd=x10]:
#     (0x10<<25)|(11<<20)|(10<<15)|(0<<12)|(10<<7)|0x5B = 0x20B5055B
#
#   csetbounds ca0, ca0, a1 [funct7=0x08, rs2=x11, rs1=x10, rd=x10]:
#     (0x08<<25)|(11<<20)|(10<<15)|(0<<12)|(10<<7)|0x5B = 0x10B5055B
#
#   cgettag a0, ca0 [funct7=0x7F, rs2=4, rs1=x10, rd=x10]:
#     (0x7F<<25)|(4<<20)|(10<<15)|(0<<12)|(10<<7)|0x5B = 0xFE45055B
#
#   cincaddr ca0, ca0, a1 [funct7=0x11, rs2=x11, rs1=x10, rd=x10]:
#     (0x11<<25)|(11<<20)|(10<<15)|(0<<12)|(10<<7)|0x5B = 0x22B5055B
#
# Tests:
#   1. cgettag after csetbounds(16) = 1     (cursor at base, valid).
#   2. cgettag after cincaddr(+16) = 0      (cursor at top, OOB — off-by-one).
#   3. cgettag after fresh cap + cincaddr(+15) = 1 (top-1 is still valid).
#   4. mstatus.MIE = 1.
#   5. mcause = 0.
#   6. mip = 0.

.globl main
main:
    # Enable machine-mode interrupts for the duration of this test.
    csrsi   mstatus, 8              # set mstatus.MIE (bit 3)

    # Derive a bounded 16-byte capability at 0x80080000 from MTDC.
    .word   0x03D0055B              # cspecialr ca0, mtdc  (full-range data cap)
    li      a1, 0x80080000
    .word   0x20B5055B              # csetaddr ca0, ca0, a1  (cursor → 0x80080000)
    li      a1, 16
    .word   0x10B5055B              # csetbounds ca0, ca0, a1  ([0x80080000, 0x80080010))

    # ── Test 1: bounded cap valid (cursor=base is in-bounds) ─────────────────
    .word   0xFE45055B              # cgettag a0, ca0
    li      a1, 1
    bne     a0, a1, .Lfail_test1

    # ── Test 2: CIncAddr(+16) → cursor = top → tag cleared (off-by-one) ──────
    # cursor = 0x80080000 + 16 = 0x80080010 = top.
    # [base, top) excludes top: cursor=top is out-of-bounds → tag=0.
    li      a1, 16
    .word   0x22B5055B              # cincaddr ca0, ca0, a1  (cursor → top)
    .word   0xFE45055B              # cgettag a0, ca0
    bne     a0, x0, .Lfail_test2   # tag must be 0

    # ── Test 3: fresh cap + CIncAddr(+15) → cursor = top-1 → tag=1 ──────────
    # Rederive the 16-byte capability and advance to the LAST valid byte.
    .word   0x03D0055B              # cspecialr ca0, mtdc
    li      a1, 0x80080000
    .word   0x20B5055B              # csetaddr ca0, ca0, a1
    li      a1, 16
    .word   0x10B5055B              # csetbounds ca0, ca0, a1
    li      a1, 15
    .word   0x22B5055B              # cincaddr ca0, ca0, a1  (cursor → 0x8008000F)
    .word   0xFE45055B              # cgettag a0, ca0
    li      a1, 1
    bne     a0, a1, .Lfail_test3   # top-1 is in-bounds: tag must be 1

    # ── Interrupt state verification (no interrupt expected) ───────────────────
    csrr    a0, mstatus
    andi    a1, a0, 8
    beq     a1, x0, .Lfail_test4
    csrr    a0, mcause
    bne     a0, x0, .Lfail_test5
    csrr    a0, mip
    bne     a0, x0, .Lfail_test6

    li      a0, 0
    ret

.Lfail_test1: li a0, 1; ret
.Lfail_test2: li a0, 2; ret
.Lfail_test3: li a0, 3; ret
.Lfail_test4: li a0, 4; ret
.Lfail_test5: li a0, 5; ret
.Lfail_test6: li a0, 6; ret
