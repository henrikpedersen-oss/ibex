# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: juliet_cwe190_int_overflow — CWE-190 Integer Overflow (CHERIoT)
# =============================================================================
# CWE-190 (NIST Juliet Test Suite): Integer Overflow or Wraparound.
#
# In C without CHERIoT (bad):
#   char buf[64];
#   size_t index = (size_t)0x7FFFFFFF;  ← large value (could come from untrusted input)
#   buf[index] = 'A';                   ← integer "overflow" as array index → OOB write
#
# Integer overflow in a size or index calculation is a classic way to bypass
# software bounds checks (the check tests a signed result that appears in-range,
# but the unsigned access exceeds the buffer).
#
# In CHERIoT, the array index calculation is done via CIncAddr.  If the resulting
# cursor exceeds the capability's top, the tag is cleared — regardless of whether
# the overflow appears positive or negative in two's complement arithmetic.
# There is no need for a software "if (index < size)" check; the hardware
# enforces it unconditionally.
#
# This test demonstrates CHERIoT protection against two types of overflows:
#
#   (a) Large positive index (0x7FFFFFFF): clearly out of range.
#       CIncAddr(buf_cap, 0x7FFFFFFF) → cursor = 0x7FFFFFFF > top(64) → tag=0.
#
#   (b) Safe small index (32): within range.
#       CIncAddr(buf_cap, 32) → cursor = 32 < top(64) → tag=1.
#
#   Test 1 (CGetLen of bounded buffer = 64)
#   Test 2 (safe index: CIncAddr +32 → tag=1)
#   Test 3 (overflow index: CIncAddr +0x7FFFFFFF on fresh cap → tag=0)
#   Tests 4-6 (interrupt state — no interrupt expected)
#
# Adapted from Juliet CWE190_Integer_Overflow (NIST/NSA).
# =============================================================================
#
# li a1, 0x7FFFFFFF uses lui + addi (or li pseudo), which is fine in RV32.
#
# Tests:
#   1. CGetLen = 64 after CSetBounds(MTDC, 64).
#   2. CIncAddr +32 → tag=1 (safe access, no overflow).
#   3. CIncAddr +0x7FFFFFFF (fresh cap, cursor=0+0x7FFFFFFF > top=64) → tag=0.
#   4. mstatus.MIE = 1.
#   5. mcause = 0.
#   6. mip = 0.

.globl main
main:
    csrsi   mstatus, 8              # set mstatus.MIE (bit 3)

    # Create a 64-byte bounded capability (simulates a stack/heap buffer).
    .word   0x03D0055B              # cspecialr ca0, mtdc
    li      a1, 64
    .word   0x10B5055B              # csetbounds ca0, ca0, a1

    # ── Test 1: length = 64 (correct bounds set) ───────────────────────────────
    .word   0xFE35055B              # cgetlen a0, ca0
    li      a2, 64
    bne     a0, a2, .Lfail_test1

    # ── Test 2: safe index 32 → tag=1 (in-bounds access) ────────────────────
    # Rebuild the capability first: a0 and ca0 are the SAME register, so the
    # cgetlen above wrote an integer into it and cleared the tag. The cincaddr
    # below would otherwise operate on a dead capability and cgettag return 0.
    # Unnoticed because crt_cheriot.S reported TEST_PASS unconditionally until
    # 2026-09-18.
    .word   0x03D0055B              # cspecialr ca0, mtdc
    li      a1, 64
    .word   0x10B5055B              # csetbounds ca0, ca0, a1
    li      a1, 32
    .word   0x22B5055B              # cincaddr ca0, ca0, a1  (cursor: 0 → 32)
    .word   0xFE45055B              # cgettag a0, ca0
    li      a1, 1
    bne     a0, a1, .Lfail_test2

    # ── Test 3: integer overflow index 0x7FFFFFFF → tag=0 ─────────────────────
    # Reload a fresh bounded cap for the overflow test.
    .word   0x03D0055B              # cspecialr ca0, mtdc
    li      a1, 64
    .word   0x10B5055B              # csetbounds ca0, ca0, a1
    # Simulate overflowed index: 0x7FFFFFFF >> 64 (way outside allocation).
    li      a1, 0x7FFFFFFF
    .word   0x22B5055B              # cincaddr ca0, ca0, a1  (cursor: 0 → 0x7FFFFFFF)
    .word   0xFE45055B              # cgettag a0, ca0
    bne     a0, x0, .Lfail_test3   # tag must be 0: overflow index denied

    # ── Interrupt state verification ───────────────────────────────────────────
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
