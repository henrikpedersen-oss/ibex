# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_rtos_subset — CTestSubset operand order, bounds, perms, tag
# =============================================================================
# CTestSubset rd, cs1, cs2 (funct7=0x20). Per the CHERIoT Sail model
# (cheri_insts.sail) rd = 1 iff
#     cs1.tag == cs2.tag
#     and cs2.base >= cs1.base and cs2.top <= cs1.top
#     and cs2.perms is a subset of cs1.perms
# i.e. "is cs2 a subset of cs1". The operand order is the reverse of the usual
# RISC-V comparison convention; the Sail comment says so explicitly, and
# ibex_cheriot_ex.sv (CIS_SUBSET) implements the same order.
#
# check_pointer() in the RTOS uses this to confirm that a capability handed in
# by another compartment lies inside the region it is supposed to refer to.
#
# How each check can fail
# -----------------------
#   Test 1  CTestSubset(full, [0,256)) = 1.
#   Test 2  CTestSubset([0,256), full) = 0.
#           Tests 1+2 fail together if the operands are swapped. Test 2 alone
#           fails if the top comparison is missing.
#   Test 3  CTestSubset(c, c) with both operands the same register = 1.
#   Test 4  CTestSubset(MTCC, CAndPerm(MTCC, 0xFF)) = 1 (fewer perms is a subset).
#   Test 5  CTestSubset(CAndPerm(MTCC, 0xFF), MTCC) = 0.
#           Fails if: permissions are not compared (bounds are identical here,
#           so only the permission check can produce 0).
#   Test 6  CTestSubset([0x100,0x200), [0,256)) = 0.
#           Fails if: the base comparison is missing (cs2's top 0x100 is inside
#           cs1, only its base is below).
#   Test 7  CTestSubset([0,256), [0x80,0x100)) = 1: a strict interior subset of
#           a bounded capability, not just of a root.
#   Test 8  CTestSubset(full tagged, [0,256) untagged) = 0.
#           Fails if: the tags are not compared.
#   Test 9  CTestSubset(full untagged, [0,256) untagged) = 1.
#           Equal tags, even both clear, satisfy the tag condition.
#           Fails if: the implementation additionally requires tag=1.
#   Tests 10-12  interrupt state (no interrupt expected).
#
# t0 is the only integer scratch register: aN and caN are the same register,
# so an integer write to a1-a5 would destroy the capability held there.
#
# Instruction encodings (opcode 0x5B; ctestsubset is funct7=0x20, rd, cs1, cs2):
#   cspecialr   ca0, mtdc       = .word 0x03D0055B
#   csetbounds  ca0, ca0, t0    = .word 0x1055055B  (funct7=0x08)
#   cspecialr   ca1, mtdc       = .word 0x03D005DB
#   ctestsubset t1, ca1, ca0    = .word 0x40A5835B
#   ctestsubset t1, ca0, ca1    = .word 0x40B5035B
#   ctestsubset t1, ca0, ca0    = .word 0x40A5035B
#   cspecialr   ca2, mtcc       = .word 0x03C0065B
#   candperm    ca3, ca2, t0    = .word 0x1A5606DB  (funct7=0x0D)
#   ctestsubset t1, ca2, ca3    = .word 0x40D6035B
#   ctestsubset t1, ca3, ca2    = .word 0x40C6835B
#   cspecialr   ca4, mtdc       = .word 0x03D0075B
#   csetaddr    ca4, ca4, t0    = .word 0x2057075B  (funct7=0x10)
#   csetbounds  ca4, ca4, t0    = .word 0x1057075B
#   ctestsubset t1, ca4, ca0    = .word 0x40A7035B
#   cspecialr   ca5, mtdc       = .word 0x03D007DB
#   csetaddr    ca5, ca5, t0    = .word 0x205787DB
#   csetbounds  ca5, ca5, t0    = .word 0x105787DB
#   ctestsubset t1, ca0, ca5    = .word 0x40F5035B
#   ccleartag   ca5, ca0        = .word 0xFEB507DB  (funct7=0x7F, rs2=0x0B)
#   ctestsubset t1, ca1, ca5    = .word 0x40F5835B
#   ccleartag   ca4, ca1        = .word 0xFEB5875B
#   ctestsubset t1, ca4, ca5    = .word 0x40F7035B

    .text
    .globl main
main:
    csrsi   mstatus, 8              # set mstatus.MIE (bit 3)
    li      t2, 1

    .word   0x03D0055B              # cspecialr  ca0, mtdc     (cursor 0)
    li      t0, 256
    .word   0x1055055B              # csetbounds ca0, ca0, t0  -> [0, 256)
    .word   0x03D005DB              # cspecialr  ca1, mtdc     -> [0, 2^32)

    # ── Tests 1-3: bounds, operand order, self ────────────────────────────────
    .word   0x40A5835B              # ctestsubset t1, ca1, ca0
    bne     t1, t2, .Lfail_test1
    .word   0x40B5035B              # ctestsubset t1, ca0, ca1
    bnez    t1, .Lfail_test2
    .word   0x40A5035B              # ctestsubset t1, ca0, ca0
    bne     t1, t2, .Lfail_test3

    # ── Tests 4-5: permissions ────────────────────────────────────────────────
    .word   0x03C0065B              # cspecialr ca2, mtcc      (perms 0x1EB)
    li      t0, 0xFF                # clear EX (bit 8)
    .word   0x1A5606DB              # candperm  ca3, ca2, t0
    .word   0x40D6035B              # ctestsubset t1, ca2, ca3
    bne     t1, t2, .Lfail_test4
    .word   0x40C6835B              # ctestsubset t1, ca3, ca2
    bnez    t1, .Lfail_test5

    # ── Test 6: cs2 base below cs1 base ───────────────────────────────────────
    .word   0x03D0075B              # cspecialr  ca4, mtdc
    li      t0, 0x100
    .word   0x2057075B              # csetaddr   ca4, ca4, t0
    .word   0x1057075B              # csetbounds ca4, ca4, t0  -> [0x100, 0x200)
    .word   0x40A7035B              # ctestsubset t1, ca4, ca0
    bnez    t1, .Lfail_test6

    # ── Test 7: strict interior subset of a bounded capability ────────────────
    .word   0x03D007DB              # cspecialr  ca5, mtdc
    li      t0, 0x80
    .word   0x205787DB              # csetaddr   ca5, ca5, t0
    .word   0x105787DB              # csetbounds ca5, ca5, t0  -> [0x80, 0x100)
    .word   0x40F5035B              # ctestsubset t1, ca0, ca5
    bne     t1, t2, .Lfail_test7

    # ── Tests 8-9: tag equality ───────────────────────────────────────────────
    .word   0xFEB507DB              # ccleartag ca5, ca0       -> [0, 256), untagged
    .word   0x40F5835B              # ctestsubset t1, ca1, ca5
    bnez    t1, .Lfail_test8
    .word   0xFEB5875B              # ccleartag ca4, ca1       -> full, untagged
    .word   0x40F7035B              # ctestsubset t1, ca4, ca5
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
