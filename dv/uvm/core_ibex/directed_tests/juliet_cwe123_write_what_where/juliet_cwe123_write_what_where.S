# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: juliet_cwe123_write_what_where — CWE-123 Write-What-Where (CHERIoT)
# =============================================================================
# CWE-123 (NIST Juliet Test Suite): Write-What-Where Condition.
#
# In C without CHERIoT:
#   // Attacker controls both the write target address and the written value.
#   // Classic primitive for arbitrary code/data corruption.
#   *(attacker_controlled_ptr) = attacker_controlled_value;
#
# In CHERIoT:
#   CSetAddr sets the cursor of a capability to an arbitrary address.
#   If that address falls OUTSIDE the capability's current [base, top) bounds,
#   the tag is immediately cleared.  A tag=0 capability cannot authorise any
#   store — the write-what-where primitive is neutralised before the store
#   instruction even executes.
#
#   Even if an attacker can manipulate the integer address fed to CSetAddr,
#   the capability they receive has tag=0 and is useless as a write primitive
#   unless the address is within the original allocation's bounds.
#
#   Test 1 (tag = 1 on bounded capability — baseline)
#     MTDC-derived capability narrowed to [0x80080000, 0x80080010).
#     Before any attacker-controlled redirect, the capability is valid (tag=1).
#     This tests that the setup is correct.
#
#   Test 2 (tag = 0 after CSetAddr(0x80090000) — target outside bounds)
#     0x80090000 is outside [0x80080000, 0x80080010).
#     CSetAddr sets the cursor to 0x80090000, which is > top=0x80080010.
#     CHERIoT clears the tag immediately — the write-what-where primitive
#     is stopped.  The attacker cannot corrupt address 0x80090000 through
#     this capability.
#
#   Test 3 (cgetaddr = 0x80090000 after CSetAddr — address was placed)
#     CGetAddr returns the cursor regardless of tag state.  Verifying the
#     cursor is 0x80090000 confirms that CSetAddr did set the address (the
#     tag-clear is a separate protection, not an address suppression).
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
#      cgettag and cgetaddr write integer results; Spike and RTL agree.
#      If CSetAddr to an out-of-bounds address fails to clear the tag,
#      the cosim diverges immediately.
#
#   2. Self-check (bne against expected values):
#      main() returns non-zero on any failure; UVM marks FAILED.
#
# Adapted from Juliet C Test Suite CWE123_Write_What_Where_Condition (NIST/NSA).
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
#   cgetaddr a0, ca0 [funct7=0x7F, rs2=15, rs1=x10, rd=x10]:
#     (0x7F<<25)|(15<<20)|(10<<15)|(0<<12)|(10<<7)|0x5B = 0xFEF5055B
#
# Tests:
#   1. cgettag on bounded cap = 1                 (baseline — allocation valid).
#   2. cgettag after csetaddr(0x80090000) = 0     (target outside bounds → denied).
#   3. cgetaddr after csetaddr(0x80090000) = 0x80090000 (address set, tag=0).
#   4. mstatus.MIE = 1.
#   5. mcause = 0.
#   6. mip = 0.

.globl main
main:
    # Enable machine-mode interrupts for the duration of this test.
    csrsi   mstatus, 8              # set mstatus.MIE (bit 3)

    # Derive a bounded 16-byte capability at 0x80080000 from MTDC.
    # This represents the legitimate allocation that an attacker is trying to
    # escape using a CSetAddr to an arbitrary write target.
    .word   0x03D0055B              # cspecialr ca0, mtdc  (full-range data cap)
    li      a1, 0x80080000
    .word   0x20B5055B              # csetaddr ca0, ca0, a1  (cursor → 0x80080000)
    li      a1, 16
    .word   0x10B5055B              # csetbounds ca0, ca0, a1  ([0x80080000, 0x80080010))

    # ── Test 1: bounded cap is valid (tag = 1) ────────────────────────────────
    .word   0xFE45055B              # cgettag a0, ca0
    li      a1, 1
    bne     a0, a1, .Lfail_test1

    # ── Test 2: CSetAddr to out-of-bounds target → tag cleared ────────────────
    # Attacker-controlled target 0x80090000 is outside [0x80080000, 0x80080010).
    # CSetAddr sets cursor to 0x80090000 (> top=0x80080010) → tag=0.
    # The write-what-where primitive is neutralised: tag=0 means no store.
    li      a1, 0x80090000
    .word   0x20B5055B              # csetaddr ca0, ca0, a1  (cursor → 0x80090000)
    .word   0xFE45055B              # cgettag a0, ca0
    bne     a0, x0, .Lfail_test2   # tag must be 0 (write target denied)

    # ── Test 3: cgetaddr = 0x80090000 (address was placed, tag is protection) ─
    # Confirm CSetAddr did place the address; the tag-clear is the defence,
    # not a suppression of the address computation itself.
    # Rebuild the whole chain first: a0 and ca0 are the SAME register, so the
    # cgettag in test 2 wrote an integer into it and cleared the tag. cgetaddr
    # then read a dead capability and returned 0 instead of the placed address.
    # The rebuild must go through the out-of-bounds CSetAddr too, because that is
    # the state this test is asserting about.
    .word   0x03D0055B              # cspecialr ca0, mtdc
    li      a1, 0x80080000
    .word   0x20B5055B              # csetaddr ca0, ca0, a1
    li      a1, 16
    .word   0x10B5055B              # csetbounds ca0, ca0, a1
    li      a1, 0x80090000
    .word   0x20B5055B              # csetaddr ca0, ca0, a1  (out of bounds, clears tag)
    .word   0xFEF5055B              # cgetaddr a0, ca0
    li      a2, 0x80090000
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
