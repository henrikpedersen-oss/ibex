# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: juliet_cwe468_repr — CWE-468 incorrect pointer scaling, representability
# =============================================================================
# Companion to juliet_cwe468_ptr_scaling. That test asserts CIncAddr past the
# end of a buffer clears the tag; it does NOT, and the test is wrong to expect
# it. In CHERIoT the cursor may legitimately roam outside the bounds -- bounds
# are enforced at DEREFERENCE. CIncAddr only clears the tag when the result is
# UNREPRESENTABLE, which is a separate mechanism with its own threshold.
#
# This test covers that separate mechanism deliberately: a small-bounds
# capability moved a long way out loses its tag, because the compressed bounds
# encoding can no longer describe a cursor that far from its base.
#
# What this does NOT show is bounds enforcement; see juliet_cwe468_fault for
# that. The two mechanisms are easy to conflate and covering only one of them
# was how the original test came to assert the wrong thing.
#
#   Test 1: small-bounds cap, modest offset past the end -> tag STILL 1
#           (out of bounds but representable -- the point the original missed)
#   Test 2: same cap, very large offset                  -> tag 0 (unrepresentable)
#   Test 3: cursor of the in-bounds cap reads back correctly
#   Test 4: mstatus.MIE still set
#   Test 5: mcause = 0 (nothing here should trap -- CIncAddr never faults)
#   Test 6: mip = 0
#
# Encodings (rd = ca0, cs1 = ca0, rs2 = a1 unless noted):
#   cspecialr ca0, mtdc  = .word 0x03D0055B
#   csetaddr  ca0,ca0,a1 = .word 0x20B5055B
#   csetbounds ca0,ca0,a1= .word 0x10B5055B
#   cincaddr  ca0,ca0,a1 = .word 0x22B5055B
#   cgettag   a0, ca0    = .word 0xFE45055B
#   cgetaddr  a0, ca0    = .word 0xFEF5055B
#
# Returns 0 on success; 1-6 identify the failing check.

    .section .text
    .globl main

main:
    # Enable machine-mode interrupts for the duration of this test.
    csrsi   mstatus, 8              # set mstatus.MIE (bit 3)

    # ── Test 1: out of bounds but representable -> tag survives ──────────────
    # 2-element int32 array (8 bytes) at 0x80080000; wrong stride steps one element
    # too far -- out of bounds, but still representable.
    .word   0x03D0055B              # cspecialr ca0, mtdc
    li      a1, 0x80080000
    .word   0x20B5055B              # csetaddr ca0, ca0, a1
    li      a1, 8
    .word   0x10B5055B              # csetbounds ca0, ca0, a1   ([0x80080000,0x80080008))
    li      a1, 8
    .word   0x22B5055B              # cincaddr ca0, ca0, a1     (cursor -> 0x80080008)
    .word   0xFE45055B              # cgettag a0, ca0
    li      a1, 1
    bne     a0, a1, .Lfail_test1   # must still be tagged: OOB is not unrepresentable

    # ── Test 2: far out of bounds -> unrepresentable, tag cleared ────────────
    # Rebuild (a0 and ca0 are the same register: the cgettag above cleared the
    # tag) and move the cursor far enough that the compressed encoding cannot
    # describe it relative to an 8-byte base.
    .word   0x03D0055B              # cspecialr ca0, mtdc
    li      a1, 0x80080000
    .word   0x20B5055B              # csetaddr ca0, ca0, a1
    li      a1, 8
    .word   0x10B5055B              # csetbounds ca0, ca0, a1
    li      a1, 0x10000000          # a wildly wrong scale factor, far beyond the 8-byte array
    .word   0x22B5055B              # cincaddr ca0, ca0, a1
    .word   0xFE45055B              # cgettag a0, ca0
    bne     a0, x0, .Lfail_test2   # must be untagged: cursor is unrepresentable

    # ── Test 3: the in-bounds capability reports its cursor correctly ────────
    .word   0x03D0055B              # cspecialr ca0, mtdc
    li      a1, 0x80080000
    .word   0x20B5055B              # csetaddr ca0, ca0, a1
    li      a1, 8
    .word   0x10B5055B              # csetbounds ca0, ca0, a1
    li      a1, 4
    .word   0x22B5055B              # cincaddr ca0, ca0, a1     (cursor -> 0x80080004)
    .word   0xFEF5055B              # cgetaddr a0, ca0
    li      a2, 0x80080004
    bne     a0, a2, .Lfail_test3

    # ── Interrupt state verification ────────────────────────────────────────
    csrr    a0, mstatus
    andi    a1, a0, 8
    beq     a1, x0, .Lfail_test4
    csrr    a0, mcause
    bne     a0, x0, .Lfail_test5   # CIncAddr never traps, however far out
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
