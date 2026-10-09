# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_rtos_gettop — CGetTop returns the decoded, saturated top
# =============================================================================
# CGetTop rd, cs1 (funct7=0x7F, rs2=0x18) returns the exclusive top of cs1's
# bounds. The RTOS uses it to size what is left of an allocation
# (top - address) and to check that a pointer is inside its object.
#
# Top is 33 bits wide (a full-range capability has top = 2^32). Per the CHERIoT
# Sail model (cheri_insts.sail, CGetTop) the result SATURATES:
#   rd = (top > 0xFFFFFFFF) ? 0xFFFFFFFF : top
# It does not wrap to 0. ibex_cheriot_ex.sv implements the same saturation
# (CFIELD_TOP: top33[32] ? 32'hffff_ffff : top33[31:0]).
#
# How each check can fail
# -----------------------
#   Test 1  CGetTop(MTDC) = 0xFFFFFFFF.
#           Fails if: top33 is truncated instead of saturated (returns 0).
#   Test 2  CGetTop(CSetBounds(MTDC@0, 512)) = 512.
#   Test 3  CGetTop(CSetBounds(MTDC@0, 1024)) = 1024.
#           Fail if: top is not decoded from T and E (E=1 and E=2 here).
#   Test 4  Base 0x80001000, length 0x100: top = 0x80001100.
#           Fails if: top is returned relative to the base, or the upper
#           address bits used to rebuild it are wrong.
#   Test 5  Moving the cursor within bounds (+0xF0) leaves top unchanged.
#           Fails if: the top decode takes its upper bits from the cursor
#           without the correction term.
#   Test 6  An untagged capability still reports its top.
#           Fails if: CGetTop gates the result on the tag (the Sail model
#           decodes regardless of tag).
#   Test 7  Base 0x80001000, length 513: top = 0x80001202 (length rounded up
#           to 514 at E=1).
#           Fails if: CGetTop returns the requested top, not the encoded one.
#   Tests 8-10  interrupt state (no interrupt expected).
#
# Instruction encodings (opcode 0x5B):
#   cspecialr   ca0, mtdc      = .word 0x03D0055B
#   csetaddr    ca0, ca0, t0   = .word 0x2055055B  (funct7=0x10)
#   csetbounds  ca0, ca0, t0   = .word 0x1055055B  (funct7=0x08)
#   cincaddrimm ca0, ca0, 0xF0 = .word 0x0F05155B  (funct3=1)
#   ccleartag   ca0, ca0       = .word 0xFEB5055B  (funct7=0x7F, rs2=0x0B)
#   cgettop     t1, ca0        = .word 0xFF85035B  (funct7=0x7F, rs2=0x18)

    .text
    .globl main
main:
    csrsi   mstatus, 8              # set mstatus.MIE (bit 3)

    # ── Test 1: full range saturates ──────────────────────────────────────────
    .word   0x03D0055B              # cspecialr ca0, mtdc
    .word   0xFF85035B              # cgettop   t1, ca0
    li      a2, 0xFFFFFFFF
    bne     t1, a2, .Lfail_test1

    # ── Test 2: [0, 512) ──────────────────────────────────────────────────────
    .word   0x03D0055B              # cspecialr  ca0, mtdc     (cursor 0)
    li      t0, 512
    .word   0x1055055B              # csetbounds ca0, ca0, t0
    .word   0xFF85035B              # cgettop    t1, ca0
    li      a2, 512
    bne     t1, a2, .Lfail_test2

    # ── Test 3: [0, 1024) ─────────────────────────────────────────────────────
    .word   0x03D0055B              # cspecialr  ca0, mtdc
    li      t0, 1024
    .word   0x1055055B              # csetbounds ca0, ca0, t0
    .word   0xFF85035B              # cgettop    t1, ca0
    li      a2, 1024
    bne     t1, a2, .Lfail_test3

    # ── Test 4: non-zero base ─────────────────────────────────────────────────
    .word   0x03D0055B              # cspecialr  ca0, mtdc
    li      t0, 0x80001000
    .word   0x2055055B              # csetaddr   ca0, ca0, t0
    li      t0, 0x100
    .word   0x1055055B              # csetbounds ca0, ca0, t0  -> [0x80001000, 0x80001100)
    .word   0xFF85035B              # cgettop    t1, ca0
    li      a2, 0x80001100
    bne     t1, a2, .Lfail_test4

    # ── Test 5: cursor moves, top does not ────────────────────────────────────
    .word   0x0F05155B              # cincaddrimm ca0, ca0, 0xF0 -> cursor 0x800010F0
    .word   0xFF85035B              # cgettop     t1, ca0
    bne     t1, a2, .Lfail_test5

    # ── Test 6: untagged capability still decodes ─────────────────────────────
    .word   0xFEB5055B              # ccleartag ca0, ca0
    .word   0xFF85035B              # cgettop   t1, ca0
    bne     t1, a2, .Lfail_test6

    # ── Test 7: rounded-up length ─────────────────────────────────────────────
    .word   0x03D0055B              # cspecialr  ca0, mtdc
    li      t0, 0x80001000
    .word   0x2055055B              # csetaddr   ca0, ca0, t0
    li      t0, 513
    .word   0x1055055B              # csetbounds ca0, ca0, t0  -> [0x80001000, 0x80001202)
    .word   0xFF85035B              # cgettop    t1, ca0
    li      a2, 0x80001202
    bne     t1, a2, .Lfail_test7

    # ── Tests 8-10: interrupt state ───────────────────────────────────────────
    csrr    t1, mstatus
    andi    t1, t1, 8
    beqz    t1, .Lfail_test8
    csrr    t1, mcause
    bnez    t1, .Lfail_test9
    csrr    t1, mip
    bnez    t1, .Lfail_test10

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
