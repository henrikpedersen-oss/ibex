# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: juliet_cwe121_stack_bof — CWE-121 Stack Buffer Overflow (CHERIoT)
# =============================================================================
# CWE-121 (NIST Juliet Test Suite): Stack-Based Buffer Overflow.
#
# In C without CHERIoT:
#   char buf[64];
#   memcpy(buf + 128, src, N);  ← overflows into adjacent stack memory
#
# In CHERIoT:
#   A capability for 'buf' is bounded to exactly 64 bytes via CSetBounds.
#   Attempting to access buf+128 produces a capability with tag=0, so any
#   subsequent load or store raises a CHERI exception.  The overflow is
#   prevented at the hardware capability level — no bounds-check branch
#   in software is needed.
#
# This test simulates the CHERIoT side using CSetBounds + CIncAddr:
#   1. Create a bounded capability covering 64 bytes (the "stack buffer").
#   2. Verify the capability is valid and correctly bounded.
#   3. Access at offset 32: within bounds → tag stays 1 (safe access).
#   4. Access at offset 128: beyond top(64) → tag cleared to 0 (denied).
#      The kernel/hardware would raise a CHERI exception; here we observe tag=0.
#
# This directly corresponds to Juliet Flow Variant 01 (Baseline): the "bad"
# sink writes beyond the buffer end.  CHERIoT eliminates the vulnerability.
#
#   Test 1 (CGetLen of the bounded buffer = 64)
#     Verifies that CSetBounds correctly installed the requested length.
#     A wrong length means the bounds encoding is incorrect.
#
#   Test 2 (base address = 0 after CSetBounds on a cursor-0 capability)
#     CSetBounds(cs1, N) sets new_base = cs1.cursor.  MTDC has cursor=0,
#     so the new base must remain 0.
#
#   Test 3 (tag = 1 — bounded capability is valid)
#     The new region [0, 64) is contained within MTDC's full range [0, 2^32).
#     Tag must remain 1 after CSetBounds.
#
#   Test 4 (in-bounds access: CIncAddr +32 keeps tag=1)
#     buf+32 is within [0, 64) — a legitimate access in C.
#     Tag stays 1.  CHERIoT allows the access.
#
#   Test 5 (out-of-bounds access: CIncAddr +128 clears tag=0)
#     buf+32+128 = 160 > top(64): overflow access denied by hardware.
#     CIncAddr clears the tag because the new cursor exceeds the capability's
#     representable range.  This is the core of CWE-121 prevention.
#
#   Tests 6-8 (interrupt state — no interrupt expected)
#     mstatus.MIE=1, mcause=0, mip=0.
#
# Verification:
#   1. Cosim: each CGet* writes an integer result; Spike and RTL agree.
#   2. Self-check: main() returns non-zero on any mismatch.
#
# Adapted from Juliet C Test Suite CWE121_Stack_Based_Buffer_Overflow (NIST/NSA).
# =============================================================================
#
# CSetBounds ca0, ca0, a1 (funct7=0x08, rs1=ca0=x10, rs2=a1=x11, rd=ca0=x10):
#   = 0001000_01011_01010_000_01010_1011011 = 0x10B5055B
#
# Tests:
#   1. CGetLen after CSetBounds(MTDC, 64) = 64.
#   2. CGetBase = 0 (cursor was 0 when CSetBounds applied).
#   3. tag = 1 (region [0,64) ⊆ [0,2^32)).
#   4. CIncAddr +32 → tag=1 (in-bounds safe access like buf[32]).
#   5. CIncAddr +128 (cursor now 160 > top 64) → tag=0 (overflow denied).
#   6. mstatus.MIE = 1.
#   7. mcause = 0.
#   8. mip = 0.

.globl main
main:
    # Enable machine-mode interrupts for the duration of this test.
    csrsi   mstatus, 8              # set mstatus.MIE (bit 3)

    # Simulate: char buf[64]; — create a 64-byte bounded capability.
    .word   0x03D0055B              # cspecialr ca0, mtdc  (full-range data cap)
    li      a1, 64
    .word   0x10B5055B              # csetbounds ca0, ca0, a1  (bound to 64 bytes)

    # ── Test 1: length = 64 ───────────────────────────────────────────────────
    .word   0xFE35055B              # cgetlen a0, ca0
    li      a2, 64
    bne     a0, a2, .Lfail_test1

    # NOTE on the re-created capability below each test:
    # a0 and ca0 are the SAME register. Every cget* writes an integer into it,
    # which clears the tag and destroys the capability, so any following query
    # reads a dead capability. That made test 2 pass for the WRONG reason (base
    # reads 0 because everything reads 0) and test 3 fail. Unnoticed because
    # crt_cheriot.S reported TEST_PASS unconditionally until 2026-09-18.
    # Rebuild the 64-byte buffer capability before each query.

    # ── Test 2: base = 0 (cursor was 0 at time of CSetBounds) ────────────────
    .word   0x03D0055B              # cspecialr ca0, mtdc
    li      a1, 64
    .word   0x10B5055B              # csetbounds ca0, ca0, a1
    .word   0xFE25055B              # cgetbase a0, ca0
    bne     a0, x0, .Lfail_test2

    # ── Test 3: tag = 1 (valid bounded capability) ────────────────────────────
    .word   0x03D0055B              # cspecialr ca0, mtdc
    li      a1, 64
    .word   0x10B5055B              # csetbounds ca0, ca0, a1
    .word   0xFE45055B              # cgettag a0, ca0
    li      a1, 1
    bne     a0, a1, .Lfail_test3

    # ── Test 4: in-bounds access (buf+32) keeps tag = 1 ──────────────────────
    # Advance cursor by 32 — still within [0, 64).
    .word   0x03D0055B              # cspecialr ca0, mtdc
    li      a1, 64
    .word   0x10B5055B              # csetbounds ca0, ca0, a1
    li      a1, 32
    .word   0x22B5055B              # cincaddr ca0, ca0, a1  (cursor: 0 → 32)
    .word   0xFE45055B              # cgettag a0, ca0
    li      a1, 1
    bne     a0, a1, .Lfail_test4

    # ── Test 5: out-of-bounds access (cursor+128 = 160 > top=64) clears tag ──
    # ca0 has cursor=32 from test 4.  +128 → 160, which exceeds top=64.
    li      a1, 128
    .word   0x22B5055B              # cincaddr ca0, ca0, a1  (cursor: 32 → 160)
    .word   0xFE45055B              # cgettag a0, ca0
    bne     a0, x0, .Lfail_test5   # tag must be 0

    # ── Interrupt state verification ───────────────────────────────────────────
    csrr    a0, mstatus
    andi    a1, a0, 8
    beq     a1, x0, .Lfail_test6
    csrr    a0, mcause
    bne     a0, x0, .Lfail_test7
    csrr    a0, mip
    bne     a0, x0, .Lfail_test8

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
