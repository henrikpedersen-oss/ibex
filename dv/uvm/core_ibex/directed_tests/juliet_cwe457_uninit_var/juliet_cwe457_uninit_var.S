# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: juliet_cwe457_uninit_var — CWE-457 Uninitialized Variable (CHERIoT)
# =============================================================================
# CWE-457 (NIST Juliet Test Suite): Use of Uninitialized Variable.
#
# In C without CHERIoT:
#   void *ptr;          // uninitialised — holds garbage
#   *ptr = 42;          // undefined behaviour; may hit any address
#
# In CHERIoT:
#   Uninitialized capability registers contain the null capability (tag=0,
#   address=0).  In hardware, x0 is hardwired to the null capability.
#   Any load or store through a tag=0 capability raises a CHERI exception;
#   the uninitialized dereference is blocked unconditionally.
#
#   An initialized capability (e.g., loaded from MTDC via cspecialr) has
#   tag=1 and can be used for memory accesses.
#
#   Test 1 (cgettag on x0 = 0 — null capability has no tag)
#     x0 represents an uninitialized/null pointer in CHERIoT.  CGetTag must
#     return 0.  Any non-zero result would mean the null capability is being
#     misrepresented as a valid pointer — a critical safety failure.
#
#   Test 2 (cgettag on MTDC = 1 — initialized root has valid tag)
#     After cspecialr loads MTDC into ca0, the tag must be 1.  This contrasts
#     with Test 1: explicit initialization produces a usable capability.
#     A failure here means cspecialr is returning an invalid capability.
#
#   Test 3 (cgetaddr on x0 = 0 — null capability has address zero)
#     The integer address of the null capability must be 0.  This confirms
#     that x0 is the zero/null address, not an arbitrary garbage value.
#     Catching a non-zero address from x0 would indicate a severe register-
#     file reset failure.
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
#      cgettag and cgetaddr write integer results to a0; Spike and RTL are
#      compared after every step.  If x0 ever has a non-zero tag or address,
#      the cosim diverges immediately.
#
#   2. Self-check (bne against expected 0 or 1):
#      main() returns non-zero on any failure; UVM marks FAILED.
#
# Adapted from Juliet C Test Suite CWE457_Use_of_Uninitialized_Variable (NIST/NSA).
# =============================================================================
#
# Instruction encodings:
#
#   cgettag a0, x0 [funct7=0x7F, rs2=4, rs1=x0=00000, rd=x10=01010]:
#     (0x7F<<25)|(4<<20)|(0<<15)|(0<<12)|(10<<7)|0x5B
#     = 0xFE000000|0x00400000|0|0|0x500|0x5B = 0xFE40055B
#
#   cspecialr ca0, mtdc [funct7=0x01, rs2=29, rs1=x0, rd=x10]:
#     (0x01<<25)|(29<<20)|(0<<15)|(0<<12)|(10<<7)|0x5B = 0x03D0055B
#
#   cgettag a0, ca0 [funct7=0x7F, rs2=4, rs1=x10, rd=x10]:
#     (0x7F<<25)|(4<<20)|(10<<15)|(0<<12)|(10<<7)|0x5B
#     = 0xFE000000|0x00400000|0x00050000|0|0x500|0x5B = 0xFE45055B
#
#   cgetaddr a0, x0 [funct7=0x7F, rs2=15, rs1=x0=00000, rd=x10=01010]:
#     (0x7F<<25)|(15<<20)|(0<<15)|(0<<12)|(10<<7)|0x5B
#     = 0xFE000000|0x00F00000|0|0|0x500|0x5B = 0xFEF0055B
#
# Tests:
#   1. cgettag on x0 (null cap) = 0   (uninitialized → no valid tag).
#   2. cgettag on MTDC = 1            (initialized root cap → valid).
#   3. cgetaddr on x0 = 0             (null address is zero).
#   4. mstatus.MIE = 1.
#   5. mcause = 0.
#   6. mip = 0.

.globl main
main:
    # Enable machine-mode interrupts for the duration of this test.
    csrsi   mstatus, 8              # set mstatus.MIE (bit 3)

    # ── Test 1: null cap (x0) has tag = 0 (simulates uninitialised pointer) ──
    # x0 is the hardware null/zero capability: tag=0, address=0.
    # Any pointer derived from this (or left uninitialised) cannot be used
    # for loads or stores — CHERIoT blocks the access at hardware level.
    .word   0xFE40055B              # cgettag a0, x0  (rd=x10, rs1=x0)
    bne     a0, x0, .Lfail_test1   # tag must be 0

    # ── Test 2: MTDC (explicit initialisation) has tag = 1 ────────────────────
    .word   0x03D0055B              # cspecialr ca0, mtdc  (load root data cap)
    .word   0xFE45055B              # cgettag a0, ca0
    li      a1, 1
    bne     a0, a1, .Lfail_test2   # initialized cap must have tag=1

    # ── Test 3: null cap (x0) address = 0 ────────────────────────────────────
    .word   0xFEF0055B              # cgetaddr a0, x0  (rd=x10, rs1=x0)
    bne     a0, x0, .Lfail_test3   # null address must be zero

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
