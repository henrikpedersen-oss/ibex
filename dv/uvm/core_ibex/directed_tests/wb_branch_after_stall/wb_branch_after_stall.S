# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: wb_branch_after_stall — data-dependent branch immediately after DIVU
# =============================================================================
# A branch whose condition depends on a DIVU result cannot be resolved until the
# divide completes (~32 cycles).  This exercises the path where ibex_controller
# issues a branch_req after a prolonged EX-stage stall, stressing the interaction
# between the multi-cycle multiply-divide unit and the branch prediction logic.
#
#   Test 1: taken branch on DIVU result (100 / 3 = 33)
#     Verifies the branch is resolved correctly after the stall.  A wrong taken/
#     not-taken decision means the forwarded DIVU result was corrupted.
#
#   Test 2: not-taken branch on a different DIVU result (200 / 7 = 28)
#     Checks the not-taken path after a stall.  Confirms the branch predictor
#     did not speculatively commit the fall-through path before DIVU completed.
#
#   Tests 3-5: interrupt state unchanged.
#
# Coverage: ibex_controller branch_req from WB stage after MUL/DIV stall.
# =============================================================================

.globl main
main:
    csrsi   mstatus, 8

    # ── Stall + taken branch ──────────────────────────────────────────────────
    li      a0, 100
    li      a1, 3
    divu    a2, a0, a1               # a2 = 33 after ~32-cycle stall

    # Branch resolves only after DIVU writeback
    li      a3, 33
    beq     a2, a3, .Ltaken1        # taken: 100/3 = 33
    li      a0, 1
    ret                              # not taken path: fail test 1

.Ltaken1:
    # ── Test 1: DIVU result correct and branch taken ──────────────────────────
    bne     a2, a3, .Lfail_test1    # a2 must equal 33

    # ── Stall + not-taken branch ──────────────────────────────────────────────
    li      a0, 200
    li      a1, 7
    divu    a4, a0, a1               # a4 = 28

    li      a5, 99
    beq     a4, a5, .Lbad2          # 28 != 99: not taken
    j       .Lgood2
.Lbad2:
    li      a0, 2; ret
.Lgood2:
    # ── Test 2: not-taken correctly resolved ──────────────────────────────────
    li      a5, 28
    bne     a4, a5, .Lfail_test2

    # ── Tests 3-5: interrupt state ────────────────────────────────────────────
    csrr    a0, mstatus
    andi    a1, a0, 8
    beq     a1, x0, .Lfail_test3
    csrr    a0, mcause
    bne     a0, x0, .Lfail_test4
    csrr    a0, mip
    bne     a0, x0, .Lfail_test5

    li      a0, 0
    ret

.Lfail_test1: li a0, 1; ret
.Lfail_test2: li a0, 2; ret
.Lfail_test3: li a0, 3; ret
.Lfail_test4: li a0, 4; ret
.Lfail_test5: li a0, 5; ret
