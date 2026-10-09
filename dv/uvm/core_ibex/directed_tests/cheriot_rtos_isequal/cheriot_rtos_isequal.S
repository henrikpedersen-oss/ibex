# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_rtos_isequal — CSetEqualExact compares every field
# =============================================================================
# CSetEqualExact rd, cs1, cs2 (CSEQX, funct7=0x21; ibex_decoder.sv names the
# operator CIS_EQUAL): rd = 1 iff the tags and the complete in-memory representations of
# cs1 and cs2 are identical, address included (cheri_insts.sail, CSEQX).
#
# The RTOS uses exact equality to confirm that a capability came back from
# another compartment unchanged -- not narrowed, not moved, not untagged.
#
# Each negative case below differs from its reference in exactly ONE field, so
# a comparator that ignores that field passes the case and the test fails.
#
# How each check can fail
# -----------------------
#   Test 1  CSEQX(MTCC, CMove(MTCC)) = 1.
#   Test 2  CSEQX(c, c) with both operands the same register = 1.
#           Fail if: the comparator is broken outright or reads the wrong port.
#   Test 3  CSEQX(MTCC, MTDC) = 0 (different perms and address).
#   Test 4  Permissions only: CSEQX(MTCC, CAndPerm(MTCC, 0xFF)) = 0.
#           Fails if: cperms is not compared.
#   Test 5  Address only: CSEQX(MTCC, CIncAddrImm(MTCC, 4)) = 0.
#           Fails if: the integer half is not compared.
#   Test 6  Tag only: CSEQX(MTCC, CClearTag(MTCC)) = 0.
#           Fails if: the tag is not compared.
#   Test 7  Bounds only: CSEQX([0,256), [0,512)), same base, cursor and perms,
#           = 0. Fails if: top/exponent are not compared.
#   Test 8  CSEQX(MTCC, CAndPerm(MTCC, 0xFFF)) = 1.
#           Fails if: a no-op CAndPerm re-encodes the capability, or the
#           comparator looks at a field that is not architectural.
#   Tests 9-11  interrupt state (no interrupt expected).
#
# t0 is the only integer scratch register: aN and caN are the same register.
#
# Instruction encodings (opcode 0x5B; csetequalexact is funct7=0x21, rd, cs1, cs2):
#   cspecialr      ca0, mtcc     = .word 0x03C0055B
#   cmove          ca1, ca0      = .word 0xFEA505DB  (funct7=0x7F, rs2=0x0A)
#   csetequalexact t1, ca0, ca1  = .word 0x42B5035B
#   csetequalexact t1, ca0, ca0  = .word 0x42A5035B
#   cspecialr      ca2, mtdc     = .word 0x03D0065B
#   csetequalexact t1, ca0, ca2  = .word 0x42C5035B
#   candperm       ca3, ca0, t0  = .word 0x1A5506DB  (funct7=0x0D)
#   csetequalexact t1, ca0, ca3  = .word 0x42D5035B
#   cincaddrimm    ca3, ca0, 4   = .word 0x004516DB  (funct3=1)
#   ccleartag      ca3, ca0      = .word 0xFEB506DB  (funct7=0x7F, rs2=0x0B)
#   cspecialr      ca4, mtdc     = .word 0x03D0075B
#   csetbounds     ca4, ca4, t0  = .word 0x1057075B  (funct7=0x08)
#   cspecialr      ca5, mtdc     = .word 0x03D007DB
#   csetbounds     ca5, ca5, t0  = .word 0x105787DB
#   csetequalexact t1, ca4, ca5  = .word 0x42F7035B

    .text
    .globl main
main:
    csrsi   mstatus, 8              # set mstatus.MIE (bit 3)
    li      t2, 1

    # ── Tests 1-2: identical capabilities ─────────────────────────────────────
    .word   0x03C0055B              # cspecialr ca0, mtcc
    .word   0xFEA505DB              # cmove     ca1, ca0
    .word   0x42B5035B              # csetequalexact t1, ca0, ca1
    bne     t1, t2, .Lfail_test1
    .word   0x42A5035B              # csetequalexact t1, ca0, ca0
    bne     t1, t2, .Lfail_test2

    # ── Test 3: different roots ───────────────────────────────────────────────
    .word   0x03D0065B              # cspecialr ca2, mtdc
    .word   0x42C5035B              # csetequalexact t1, ca0, ca2
    bnez    t1, .Lfail_test3

    # ── Test 4: permissions differ ────────────────────────────────────────────
    li      t0, 0xFF                # clear EX (bit 8)
    .word   0x1A5506DB              # candperm ca3, ca0, t0
    .word   0x42D5035B              # csetequalexact t1, ca0, ca3
    bnez    t1, .Lfail_test4

    # ── Test 5: address differs ───────────────────────────────────────────────
    .word   0x004516DB              # cincaddrimm ca3, ca0, 4
    .word   0x42D5035B              # csetequalexact t1, ca0, ca3
    bnez    t1, .Lfail_test5

    # ── Test 6: tag differs ───────────────────────────────────────────────────
    .word   0xFEB506DB              # ccleartag ca3, ca0
    .word   0x42D5035B              # csetequalexact t1, ca0, ca3
    bnez    t1, .Lfail_test6

    # ── Test 7: bounds differ ─────────────────────────────────────────────────
    .word   0x03D0075B              # cspecialr  ca4, mtdc     (cursor 0)
    li      t0, 256
    .word   0x1057075B              # csetbounds ca4, ca4, t0  -> [0, 256)
    .word   0x03D007DB              # cspecialr  ca5, mtdc
    li      t0, 512
    .word   0x105787DB              # csetbounds ca5, ca5, t0  -> [0, 512)
    .word   0x42F7035B              # csetequalexact t1, ca4, ca5
    bnez    t1, .Lfail_test7

    # ── Test 8: a no-op CAndPerm leaves the capability identical ──────────────
    li      t0, 0xFFF
    .word   0x1A5506DB              # candperm ca3, ca0, t0
    .word   0x42D5035B              # csetequalexact t1, ca0, ca3
    bne     t1, t2, .Lfail_test8

    # ── Tests 9-11: interrupt state ───────────────────────────────────────────
    csrr    t1, mstatus
    andi    t1, t1, 8
    beqz    t1, .Lfail_test9
    csrr    t1, mcause
    bnez    t1, .Lfail_test10
    csrr    t1, mip
    bnez    t1, .Lfail_test11

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
