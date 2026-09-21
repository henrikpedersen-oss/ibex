# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: juliet_cwe124_buf_underwrite — CWE-124 Buffer Underwrite (CHERIoT)
# =============================================================================
# CWE-124 (NIST Juliet Test Suite): Buffer Underwrite (write before start).
#
# In C without CHERIoT:
#   char buf[16];
#   *(buf - 4) = 0x42;   ← writes before the buffer start (underwrite)
#
# In CHERIoT:
#   A capability bounded to [base, top) has its tag cleared whenever the
#   cursor moves outside that range.  Moving the cursor before base
#   (cursor < base) is an out-of-bounds condition, and CHERIoT clears the
#   tag immediately in the CIncAddr instruction.  Any subsequent load/store
#   would raise a CHERI exception.  No software range-check is needed.
#
# This test simulates the CHERIoT side using MTDC (full-range data root) as
# the authority capability.  We narrow to a 16-byte buffer at 0x80080000,
# then attempt to move the cursor back by 4 bytes (before the buffer start).
#
#   Test 1 (tag = 1 after CSetBounds)
#     After csetaddr+csetbounds the derived cap is valid: cursor=base=0x80080000,
#     bounds=[0x80080000, 0x80080010), tag=1.  Verifies the setup is correct
#     before the underwrite attempt.
#
#   Test 2 (tag = 0 after CIncAddr(-4))
#     CIncAddr with a1=-4 (0xFFFFFFFC in two's complement) moves the cursor to
#     0x80080000 - 4 = 0x8007FFFC, which is BELOW the base.  CHERIoT hardware
#     clears the tag immediately.  Tag=0 means the underwrite is prevented.
#
#   Test 3 (cursor = 0x8007FFFC after CIncAddr(-4))
#     CGetAddr returns the cursor field regardless of tag state.  Verifying the
#     cursor is exactly 0x8007FFFC confirms that CIncAddr computed the correct
#     wrapped address and that the bounds check (not the arithmetic) is what
#     clears the tag.
#
#   Tests 4-6 (interrupt state — no interrupt expected)
#     Machine-mode interrupts are enabled at the start of the test.
#     Test 4: mstatus.MIE still = 1 (no spurious interrupt taken).
#     Test 5: mcause = 0 (no exception or interrupt recorded).
#     Test 6: mip = 0 (no interrupt inputs asserted).
#
# Verification:
#   Two independent layers catch a faulty DUT:
#
#   1. Cosim (Spike vs ibex RTL, per instruction step):
#      cgettag and cgetaddr write integer results to a0; Spike and RTL are
#      compared after every step.  If the tag is not cleared when the cursor
#      goes below base, or if the cursor arithmetic is wrong, Spike diverges
#      from the DUT immediately.
#
#   2. Self-check (bne/beq against expected values):
#      main() returns non-zero on any failure; the UVM testbench marks FAILED.
#
# Adapted from Juliet C Test Suite CWE124_Buffer_Underwrite (NIST/NSA).
# =============================================================================
#
# Instruction encodings (rd=a0=x10, cs1=ca0=x10, rs2=a1=x11 unless noted):
#
#   cspecialr ca0, mtdc   [funct7=0x01, rs2=29, rs1=x0, rd=x10]:
#     (0x01<<25)|(29<<20)|(0<<15)|(0<<12)|(10<<7)|0x5B
#     = 0x02000000|0x01D00000|0|0|0x500|0x5B = 0x03D0055B
#
#   csetaddr ca0, ca0, a1 [funct7=0x10, rs2=x11, rs1=x10, rd=x10]:
#     (0x10<<25)|(11<<20)|(10<<15)|(0<<12)|(10<<7)|0x5B
#     = 0x20000000|0x00B00000|0x00050000|0|0x500|0x5B = 0x20B5055B
#
#   csetbounds ca0, ca0, a1 [funct7=0x08, rs2=x11, rs1=x10, rd=x10]:
#     (0x08<<25)|(11<<20)|(10<<15)|(0<<12)|(10<<7)|0x5B
#     = 0x10000000|0x00B00000|0x00050000|0|0x500|0x5B = 0x10B5055B
#
#   cgettag a0, ca0 [funct7=0x7F, rs2=4, rs1=x10, rd=x10]:
#     (0x7F<<25)|(4<<20)|(10<<15)|(0<<12)|(10<<7)|0x5B
#     = 0xFE000000|0x00400000|0x00050000|0|0x500|0x5B = 0xFE45055B
#
#   cincaddr ca0, ca0, a1 [funct7=0x11, rs2=x11, rs1=x10, rd=x10]:
#     (0x11<<25)|(11<<20)|(10<<15)|(0<<12)|(10<<7)|0x5B
#     = 0x22000000|0x00B00000|0x00050000|0|0x500|0x5B = 0x22B5055B
#
#   cgetaddr a0, ca0 [funct7=0x7F, rs2=15, rs1=x10, rd=x10]:
#     (0x7F<<25)|(15<<20)|(10<<15)|(0<<12)|(10<<7)|0x5B
#     = 0xFE000000|0x00F00000|0x00050000|0|0x500|0x5B = 0xFEF5055B
#
# Tests:
#   1. cgettag after csetbounds(16) = 1  (bounded cap valid).
#   2. cgettag after cincaddr(-4) = 0   (cursor < base → tag cleared).
#   3. cgetaddr after cincaddr(-4) = 0x8007FFFC (cursor was set correctly).
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

    # ── Test 1: bounded cap is valid (tag = 1) ────────────────────────────────
    .word   0xFE45055B              # cgettag a0, ca0
    li      a1, 1
    bne     a0, a1, .Lfail_test1

    # ── Test 2: CIncAddr(-4) moves cursor before base → tag cleared ───────────
    # a1 = -4 = 0xFFFFFFFC in two's complement.
    # New cursor = 0x80080000 + 0xFFFFFFFC (mod 2^32) = 0x8007FFFC < base.
    # CHERIoT clears the tag because cursor < base (out of [base, top)).
    li      a1, -4
    .word   0x22B5055B              # cincaddr ca0, ca0, a1  (cursor → 0x8007FFFC)
    .word   0xFE45055B              # cgettag a0, ca0
    bne     a0, x0, .Lfail_test2   # tag must be 0

    # ── Test 3: cursor is 0x8007FFFC (underwrite address recorded) ───────────
    # Rebuild the whole chain first: a0 and ca0 are the SAME register, so the
    # cgettag in test 2 wrote an integer into it and cleared the tag. cgetaddr
    # then read a dead capability and returned 0 instead of the underwrite
    # address. The rebuild must include the CIncAddr(-4) too, because that is the
    # state this test is asserting about.
    .word   0x03D0055B              # cspecialr ca0, mtdc
    li      a1, 0x80080000
    .word   0x20B5055B              # csetaddr ca0, ca0, a1
    li      a1, 16
    .word   0x10B5055B              # csetbounds ca0, ca0, a1
    li      a1, -4
    .word   0x22B5055B              # cincaddr ca0, ca0, a1  (before base, clears tag)
    .word   0xFEF5055B              # cgetaddr a0, ca0
    lui     a2, 0x80080             # a2 = 0x80080000
    addi    a2, a2, -4              # a2 = 0x8007FFFC
    bne     a0, a2, .Lfail_test3

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
