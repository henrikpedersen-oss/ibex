# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_rtos_clc_csc — capabilities survive a trip through memory
# =============================================================================
# The CHERIoT RTOS keeps capabilities in memory all the time: the trusted stack
# holds sealed compartment capabilities, the allocator keeps bounded object
# capabilities in its headers, and every spilled register is a CSC/CLC pair.
# A capability loaded back must be bit-for-bit the one that was stored, and a
# slot overwritten with integer data must come back untagged.
#
# Memory is a two-slot buffer in .data. The authority is MTDC (perms 0x07F:
# LG and LM set, so CLC through it attenuates nothing and the loaded value can
# be compared exactly).
#
# How each check can fail
# -----------------------
#   Test 1  CSC MTCC, CLC it back: tag=1.
#           Fails if: CSC does not drive data_tag_o, the LSU drops data_tag_i,
#           or TRVK wrongly revokes a live capability.
#   Test 2  The loaded capability is CSetEqualExact to the stored one.
#           Fails if: either beat of the two-beat CLC/CSC is lost, swapped or
#           mis-merged, or CLC attenuates permissions it should not.
#   Test 3  A bounded, permission-reduced object capability (the allocator's
#           case) stored to the second slot comes back tagged...
#   Test 4  ...and CSetEqualExact to the original...
#   Test 5  ...with base 0x80001230...
#   Test 6  ...and length 64.
#           Tests 3-6 fail if the metadata word is corrupted in transit; a
#           root capability (as in tests 1-2) would hide errors in bounds
#           encoding because its B/T/E fields are the reset constants.
#   Test 7  SW to slot 0 clears its tag (the RTOS zeroing a freed object).
#           Fails if: the LSU drives data_tag_o=1 on an integer word store.
#   Test 8  The reloaded slot 0 carries the integer just written as its address.
#           Fails if: CLC returns stale data rather than the memory contents.
#   Test 9  Slot 1 is still tagged.
#           Fails if: the SW was issued to the wrong granule.
#   Tests 10-12  interrupt state (no interrupt expected).
#
# Register use: ca0 = authority for the buffer (never a destination after
# setup), ca2 = MTCC, ca3 = loaded capability, ca4 = object capability,
# t1 = result, t2 = 1.
#
# Instruction encodings (opcode 0x5B unless noted):
#   cspecialr      ca0, mtdc       = .word 0x03D0055B
#   csetaddr       ca0, ca0, t0    = .word 0x2055055B  (funct7=0x10)
#   cspecialr      ca2, mtcc       = .word 0x03C0065B
#   cspecialr      ca4, mtdc       = .word 0x03D0075B
#   csetaddr       ca4, ca4, a1    = .word 0x20B7075B
#   csetbounds     ca4, ca4, a1    = .word 0x10B7075B  (funct7=0x08)
#   candperm       ca4, ca4, a1    = .word 0x1AB7075B  (funct7=0x0D)
#   csc            ca2, 0(ca0)     = .word 0x00C53023  (STORE funct3=3)
#   csc            ca4, 8(ca0)     = .word 0x00E53423
#   clc            ca3, 0(ca0)     = .word 0x00053683  (LOAD funct3=3)
#   clc            ca3, 8(ca0)     = .word 0x00853683
#   cgettag        t1, ca3         = .word 0xFE46835B  (funct7=0x7F, rs2=0x04)
#   cgetbase       t1, ca3         = .word 0xFE26835B  (rs2=0x02)
#   cgetlen        t1, ca3         = .word 0xFE36835B  (rs2=0x03)
#   cgetaddr       t1, ca3         = .word 0xFEF6835B  (rs2=0x0F)
#   csetequalexact t1, ca3, ca2    = .word 0x42C6835B  (funct7=0x21)
#   csetequalexact t1, ca3, ca4    = .word 0x42E6835B

    .text
    .globl main
main:
    csrsi   mstatus, 8              # set mstatus.MIE (bit 3)

    la      t0, cap_slots
    .word   0x03D0055B              # cspecialr ca0, mtdc
    .word   0x2055055B              # csetaddr  ca0, ca0, t0   -> slot 0
    .word   0x03C0065B              # cspecialr ca2, mtcc      (tag=1)
    li      t2, 1

    # ── Tests 1-2: root capability round trip ─────────────────────────────────
    .word   0x00C53023              # csc     ca2, 0(ca0)
    .word   0x00053683              # clc     ca3, 0(ca0)
    .word   0xFE46835B              # cgettag t1, ca3
    bne     t1, t2, .Lfail_test1
    .word   0x42C6835B              # csetequalexact t1, ca3, ca2
    bne     t1, t2, .Lfail_test2

    # ── Tests 3-6: object capability round trip ───────────────────────────────
    .word   0x03D0075B              # cspecialr  ca4, mtdc
    li      a1, 0x80001230
    .word   0x20B7075B              # csetaddr   ca4, ca4, a1
    li      a1, 64
    .word   0x10B7075B              # csetbounds ca4, ca4, a1  -> [0x80001230, +64)
    li      a1, 0x6F                # GL LG SD LM LD MC: drops SL from MTDC's 0x07F
    .word   0x1AB7075B              # candperm   ca4, ca4, a1
    .word   0x00E53423              # csc     ca4, 8(ca0)
    .word   0x00853683              # clc     ca3, 8(ca0)
    .word   0xFE46835B              # cgettag t1, ca3
    bne     t1, t2, .Lfail_test3
    .word   0x42E6835B              # csetequalexact t1, ca3, ca4
    bne     t1, t2, .Lfail_test4
    .word   0xFE26835B              # cgetbase t1, ca3
    li      a1, 0x80001230
    bne     t1, a1, .Lfail_test5
    .word   0xFE36835B              # cgetlen  t1, ca3
    li      a1, 64
    bne     t1, a1, .Lfail_test6

    # ── Tests 7-9: an integer store revokes slot 0 only ───────────────────────
    li      a5, 0xCAFEF00D
    sw      a5, 0(a0)
    .word   0x00053683              # clc     ca3, 0(ca0)
    .word   0xFE46835B              # cgettag t1, ca3
    bnez    t1, .Lfail_test7
    .word   0xFEF6835B              # cgetaddr t1, ca3
    bne     t1, a5, .Lfail_test8
    .word   0x00853683              # clc     ca3, 8(ca0)
    .word   0xFE46835B              # cgettag t1, ca3
    bne     t1, t2, .Lfail_test9

    # ── Tests 10-12: interrupt state ──────────────────────────────────────────
    csrr    t1, mstatus
    andi    t1, t1, 8
    beqz    t1, .Lfail_test10
    csrr    t1, mcause
    bnez    t1, .Lfail_test11
    csrr    t1, mip
    bnez    t1, .Lfail_test12

    li      a0, 0
    ret

.Lfail_test1:  li a0, 1;  ret
.Lfail_test2:  li a0, 2;  ret
.Lfail_test3:  li a0, 3;  ret
.Lfail_test4:  li a0, 4;  ret
.Lfail_test5:  li a0, 5;  ret
.Lfail_test6:  li a0, 6;  ret
.Lfail_test7:  li a0, 7;  ret
.Lfail_test8:  li a0, 8;  ret
.Lfail_test9:  li a0, 9;  ret
.Lfail_test10: li a0, 10; ret
.Lfail_test11: li a0, 11; ret
.Lfail_test12: li a0, 12; ret

    .data
    .balign 8
cap_slots:                          # slot 0 at +0, slot 1 at +8
    .space  16
