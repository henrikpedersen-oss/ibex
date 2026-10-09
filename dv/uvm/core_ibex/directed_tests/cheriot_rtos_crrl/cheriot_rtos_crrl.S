# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_rtos_crrl — CRRL/CRAM and the allocator's exact-bounds recipe
# =============================================================================
# CRRL rd, rs1 (funct7=0x7F, rs2=0x08): the smallest length >= rs1 that can be
#   set exactly on a suitably aligned base.
# CRAM rd, rs1 (funct7=0x7F, rs2=0x09): the mask that aligns a base for that.
#
# The CHERIoT allocator sizes every object this way:
#   len  = CRRL(request);  base = base & CRAM(request);
#   CSetBoundsExact(cap@base, len)          -- must not need rounding
#
# Expected values come from the CHERIoT Sail model (cheri_cap_common.sail):
#   E    = exponent that setCapBounds(root, 0, len) picks: 0 for len < 512,
#          otherwise the bit count of len >> 9, plus one if T-B then exceeds
#          9 bits; any E > 14 saturates to 24 (cap_max_E).
#   CRAM = 0xFFFFFFFF << E
#   CRRL = (len + ~CRAM) & CRAM     (wraps to 0 when rounding reaches 2^32)
#
# Note CRAM is ALL ONES, not zero, when no alignment is needed: it is a mask to
# AND the base with.
#
# How each check can fail
# -----------------------
#   Tests 1-2   len=16:        CRRL=16,        CRAM=0xFFFFFFFF   (E=0)
#   Tests 3-4   len=511:       CRRL=511,       CRAM=0xFFFFFFFF   (largest E=0)
#   Tests 5-6   len=512:       CRRL=512,       CRAM=0xFFFFFFFE   (first E=1)
#               Fail if: the E=0/E=1 boundary is off by one.
#   Tests 7-8   len=513:       CRRL=514,       CRAM=0xFFFFFFFE
#               Fail if: rounding up is missing (CRRL returns len unchanged).
#   Tests 9-10  len=1023:      CRRL=1024,      CRAM=0xFFFFFFFC   (E=2)
#               The first try at E=1 rounds T-B up to 512, which overflows
#               9 bits, so E must be bumped. Fail if: that second path is
#               missing or selected wrongly.
#   Tests 11-12 len=0x12345:   CRRL=0x12400,   CRAM=0xFFFFFF00   (E=8)
#   Tests 13-14 len=0x400000:  CRRL=0x400000,  CRAM=0xFFFFC000   (E=14, the
#               largest unsaturated exponent)
#   Tests 15-16 len=0x800001:  CRRL=0x1000000, CRAM=0xFF000000   (E=15
#               saturates to 24). Fail if: the saturation threshold is wrong
#               or E=15 is used directly.
#   Tests 17-18 len=0xFFFFFFFF: CRRL=0 (2^32 wraps), CRAM=0xFF000000
#   Tests 19-20 len=0:         CRRL=0,         CRAM=0xFFFFFFFF
#   Test 21     The allocator recipe for request 0x12345 at 0x80001237:
#               CSetBoundsExact on base 0x80001237 & CRAM with length CRRL
#               keeps the tag.
#               Fails if: CRAM/CRRL disagree with what CSetBoundsExact needs.
#   Tests 22-23 ...giving base 0x80001200 and length 0x12400.
#   Test 24     The same CSetBoundsExact on the unaligned base 0x80001237 clears
#               the tag, so test 21 cannot pass vacuously.
#   Tests 25-27 interrupt state (no interrupt expected).
#
# Instruction encodings (opcode 0x5B):
#   crrl            a0, a1        = .word 0xFE85855B  (funct7=0x7F, rs2=0x08)
#   cram            a0, a1        = .word 0xFE95855B  (funct7=0x7F, rs2=0x09)
#   cspecialr       ca0, mtdc     = .word 0x03D0055B
#   csetaddr        ca0, ca0, a5  = .word 0x20F5055B  (funct7=0x10)
#   csetboundsexact ca0, ca0, a4  = .word 0x12E5055B  (funct7=0x09)
#   cgettag         t1, ca0       = .word 0xFE45035B
#   cgetbase        t1, ca0       = .word 0xFE25035B
#   cgetlen         t1, ca0       = .word 0xFE35035B

# CHECK n, len, expected_crrl, expected_cram: tests n (CRRL) and n+1 (CRAM).
.macro CHECK n, len, crrl_exp, cram_exp
    li      a1, \len
    .word   0xFE85855B              # crrl a0, a1
    li      a2, \crrl_exp
    bne     a0, a2, .Lfail_test\n
    .word   0xFE95855B              # cram a0, a1
    li      a2, \cram_exp
    bne     a0, a2, .Lfail_test\n\()_1
.endm

    .text
    .globl main
main:
    csrsi   mstatus, 8              # set mstatus.MIE (bit 3)

    CHECK   1,  16,         16,         0xFFFFFFFF
    CHECK   3,  511,        511,        0xFFFFFFFF
    CHECK   5,  512,        512,        0xFFFFFFFE
    CHECK   7,  513,        514,        0xFFFFFFFE
    CHECK   9,  1023,       1024,       0xFFFFFFFC
    CHECK   11, 0x12345,    0x12400,    0xFFFFFF00
    CHECK   13, 0x400000,   0x400000,   0xFFFFC000
    CHECK   15, 0x800001,   0x1000000,  0xFF000000
    CHECK   17, 0xFFFFFFFF, 0,          0xFF000000
    CHECK   19, 0,          0,          0xFFFFFFFF

    # ── Tests 21-23: the allocator's exact-bounds recipe ──────────────────────
    li      a1, 0x12345             # requested size
    .word   0xFE95855B              # cram a0, a1
    mv      a3, a0                  # a3 = alignment mask
    .word   0xFE85855B              # crrl a0, a1
    mv      a4, a0                  # a4 = representable length
    li      a5, 0x80001237
    and     a5, a5, a3              # a5 = aligned base
    .word   0x03D0055B              # cspecialr       ca0, mtdc
    .word   0x20F5055B              # csetaddr        ca0, ca0, a5
    .word   0x12E5055B              # csetboundsexact ca0, ca0, a4
    li      t2, 1
    .word   0xFE45035B              # cgettag  t1, ca0
    bne     t1, t2, .Lfail_test21
    .word   0xFE25035B              # cgetbase t1, ca0
    li      a2, 0x80001200
    bne     t1, a2, .Lfail_test22
    .word   0xFE35035B              # cgetlen  t1, ca0
    li      a2, 0x12400
    bne     t1, a2, .Lfail_test23

    # ── Test 24: without the CRAM alignment the same request is inexact ──────
    li      a5, 0x80001237
    .word   0x03D0055B              # cspecialr       ca0, mtdc
    .word   0x20F5055B              # csetaddr        ca0, ca0, a5
    .word   0x12E5055B              # csetboundsexact ca0, ca0, a4
    .word   0xFE45035B              # cgettag  t1, ca0
    bnez    t1, .Lfail_test24

    # ── Tests 25-27: interrupt state ──────────────────────────────────────────
    csrr    t1, mstatus
    andi    t1, t1, 8
    beqz    t1, .Lfail_test25
    csrr    t1, mcause
    bnez    t1, .Lfail_test26
    csrr    t1, mip
    bnez    t1, .Lfail_test27

    li      a0, 0
    ret

# Fail codes: test n of each CHECK pair returns n, test n+1 returns n+1.
.Lfail_test1:    li a0, 1;  ret
.Lfail_test1_1:  li a0, 2;  ret
.Lfail_test3:    li a0, 3;  ret
.Lfail_test3_1:  li a0, 4;  ret
.Lfail_test5:    li a0, 5;  ret
.Lfail_test5_1:  li a0, 6;  ret
.Lfail_test7:    li a0, 7;  ret
.Lfail_test7_1:  li a0, 8;  ret
.Lfail_test9:    li a0, 9;  ret
.Lfail_test9_1:  li a0, 10; ret
.Lfail_test11:   li a0, 11; ret
.Lfail_test11_1: li a0, 12; ret
.Lfail_test13:   li a0, 13; ret
.Lfail_test13_1: li a0, 14; ret
.Lfail_test15:   li a0, 15; ret
.Lfail_test15_1: li a0, 16; ret
.Lfail_test17:   li a0, 17; ret
.Lfail_test17_1: li a0, 18; ret
.Lfail_test19:   li a0, 19; ret
.Lfail_test19_1: li a0, 20; ret
.Lfail_test21:   li a0, 21; ret
.Lfail_test22:   li a0, 22; ret
.Lfail_test23:   li a0, 23; ret
.Lfail_test24:   li a0, 24; ret
.Lfail_test25:   li a0, 25; ret
.Lfail_test26:   li a0, 26; ret
.Lfail_test27:   li a0, 27; ret
