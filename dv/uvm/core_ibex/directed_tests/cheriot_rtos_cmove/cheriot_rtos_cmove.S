# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_rtos_cmove — CMove copies a capability register exactly
# =============================================================================
# CMove (funct7=0x7F, rs2=0x0A) copies cs1 to cd with every field intact: tag,
# permissions, bounds, otype and address. The RTOS uses it for every pointer
# hand-off (compartment call arguments, saving the return capability, moving
# the stack capability), so a CMove that drops, forges or alters any field
# breaks capability propagation everywhere.
#
# The source is deliberately NOT a root capability. Copying MTCC or MTDC would
# let a CMove that returns a root constant, or that loses the bounds fields,
# pass: their B/T/E fields and permissions are the reset values. Here the
# source is MTDC narrowed to [0x80001230, +64), cursor +8, perms reduced.
#
# How each check can fail
# -----------------------
#   Test 1  Precondition: the source's permissions really differ from MTDC's
#           0x07F. Fails if CAndPerm did not narrow (not a CMove bug, but the
#           remaining checks would be weaker).
#   Test 2  The copy is tagged.         Fails if: CMove drops the tag.
#   Test 3  Same permissions as source. Fails if: perms not copied.
#   Test 4  Base = 0x80001230.          Fails if: bounds fields not copied.
#   Test 5  Length = 64.                Same.
#   Test 6  Address = 0x80001238.       Fails if: the integer half not copied.
#   Test 7  CSetEqualExact(copy, source) = 1.
#           Fails if: any encoded bit differs, including otype and reserved bits.
#   Test 8  CMove of an untagged capability gives an untagged copy.
#           Fails if: CMove sets the tag, forging a capability.
#   Test 9  CMove of MTCC keeps perms 0x1EB (execute root).
#           Fails if: CMove re-encodes permissions differently for the
#           executable format.
#   Tests 10-12  interrupt state (no interrupt expected).
#
# Getters write their integer result to t1 or s0, never to a register holding a
# capability that is still needed: aN and caN are the same register, and an
# integer write clears the capability.
#
# Instruction encodings (opcode 0x5B):
#   cspecialr   ca0, mtdc       = .word 0x03D0055B
#   csetaddr    ca0, ca0, a1    = .word 0x20B5055B  (funct7=0x10)
#   csetbounds  ca0, ca0, a1    = .word 0x10B5055B  (funct7=0x08)
#   cincaddrimm ca0, ca0, 8     = .word 0x0085155B  (funct3=1)
#   candperm    ca0, ca0, a1    = .word 0x1AB5055B  (funct7=0x0D)
#   cgetperm    s0, ca0         = .word 0xFE05045B  (funct7=0x7F, rs2=0x00)
#   cmove       ca1, ca0        = .word 0xFEA505DB  (funct7=0x7F, rs2=0x0A)
#   cgettag     t1, ca1         = .word 0xFE45835B  (rs2=0x04)
#   cgetperm    t1, ca1         = .word 0xFE05835B
#   cgetbase    t1, ca1         = .word 0xFE25835B  (rs2=0x02)
#   cgetlen     t1, ca1         = .word 0xFE35835B  (rs2=0x03)
#   cgetaddr    t1, ca1         = .word 0xFEF5835B  (rs2=0x0F)
#   csetequalexact t1, ca1, ca0 = .word 0x42A5835B  (funct7=0x21)
#   ccleartag   ca2, ca0        = .word 0xFEB5065B  (rs2=0x0B)
#   cmove       ca3, ca2        = .word 0xFEA606DB
#   cgettag     t1, ca3         = .word 0xFE46835B
#   cspecialr   ca4, mtcc       = .word 0x03C0075B
#   cmove       ca5, ca4        = .word 0xFEA707DB
#   cgetperm    t1, ca5         = .word 0xFE07835B

    .text
    .globl main
main:
    csrsi   mstatus, 8              # set mstatus.MIE (bit 3)

    # ── Build a non-root source capability in ca0 ─────────────────────────────
    .word   0x03D0055B              # cspecialr   ca0, mtdc
    li      a1, 0x80001230
    .word   0x20B5055B              # csetaddr    ca0, ca0, a1
    li      a1, 64
    .word   0x10B5055B              # csetbounds  ca0, ca0, a1   -> [0x80001230, +64)
    .word   0x0085155B              # cincaddrimm ca0, ca0, 8    -> cursor 0x80001238
    li      a1, 0x25                # GL SD LD: no capability load/store
    .word   0x1AB5055B              # candperm    ca0, ca0, a1

    # ── Test 1: the source is attenuated ──────────────────────────────────────
    .word   0xFE05045B              # cgetperm s0, ca0
    li      a1, 0x07F
    beq     s0, a1, .Lfail_test1

    .word   0xFEA505DB              # cmove ca1, ca0

    # ── Tests 2-7: every field of the copy ────────────────────────────────────
    li      t2, 1
    .word   0xFE45835B              # cgettag  t1, ca1
    bne     t1, t2, .Lfail_test2
    .word   0xFE05835B              # cgetperm t1, ca1
    bne     t1, s0, .Lfail_test3
    .word   0xFE25835B              # cgetbase t1, ca1
    li      a2, 0x80001230
    bne     t1, a2, .Lfail_test4
    .word   0xFE35835B              # cgetlen  t1, ca1
    li      a2, 64
    bne     t1, a2, .Lfail_test5
    .word   0xFEF5835B              # cgetaddr t1, ca1
    li      a2, 0x80001238
    bne     t1, a2, .Lfail_test6
    .word   0x42A5835B              # csetequalexact t1, ca1, ca0
    bne     t1, t2, .Lfail_test7

    # ── Test 8: an untagged source stays untagged ─────────────────────────────
    .word   0xFEB5065B              # ccleartag ca2, ca0
    .word   0xFEA606DB              # cmove     ca3, ca2
    .word   0xFE46835B              # cgettag   t1, ca3
    bnez    t1, .Lfail_test8

    # ── Test 9: copy of the execute root keeps its permissions ────────────────
    .word   0x03C0075B              # cspecialr ca4, mtcc
    .word   0xFEA707DB              # cmove     ca5, ca4
    .word   0xFE07835B              # cgetperm  t1, ca5
    li      a2, 0x1EB
    bne     t1, a2, .Lfail_test9

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
