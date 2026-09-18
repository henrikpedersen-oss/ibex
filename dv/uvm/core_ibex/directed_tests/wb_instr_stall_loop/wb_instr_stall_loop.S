# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: wb_instr_stall_loop — sustained pipeline stall via DIVU loop
# =============================================================================
# Exercises the prolonged fetch-stall-during-execute scenario (analogous to
# instr_gnt_i=0 for many cycles) by chaining four ~32-cycle DIVU operations.
# The total stall spans ~128 cycles, keeping the fetch FIFO at or near maximum
# depth for an extended period and stressing the prefetch buffer state machine.
#
#   Test 1: sum of four quotients = 700/7 + 800/8 + 900/9 + 600/6 = 400
#     Each DIVU stalls ~32 cycles.  Wrong sum means a pipeline hazard caused
#     an incorrect forward or the FIFO fed a stale instruction.
#
#   Tests 2-4: interrupt state unchanged.
#
# Coverage: ibex_fetch_fifo sustained FIFO-full state; prefetch_buffer stall
# across multiple instruction-fetch stall boundaries.
# =============================================================================

.globl main
main:
    csrsi   mstatus, 8

    # ── Stall 1: 700 / 7 = 100 ───────────────────────────────────────────────
    li      a0, 700
    li      a1, 7
    divu    a2, a0, a1
    nop; nop; nop

    # ── Stall 2: 800 / 8 = 100 ───────────────────────────────────────────────
    li      a0, 800
    li      a1, 8
    divu    a3, a0, a1
    nop; nop; nop

    # ── Stall 3: 900 / 9 = 100 ───────────────────────────────────────────────
    li      a0, 900
    li      a1, 9
    divu    a4, a0, a1
    nop; nop; nop

    # ── Stall 4: 600 / 6 = 100 ───────────────────────────────────────────────
    li      a0, 600
    li      a1, 6
    divu    a5, a0, a1
    nop; nop; nop

    # ── Test 1: sum = 400 ─────────────────────────────────────────────────────
    add     a0, a2, a3
    add     a0, a0, a4
    add     a0, a0, a5
    li      a1, 400
    bne     a0, a1, .Lfail_test1

    # ── Tests 2-4: interrupt state ────────────────────────────────────────────
    csrr    a0, mstatus
    andi    a1, a0, 8
    beq     a1, x0, .Lfail_test2
    csrr    a0, mcause
    bne     a0, x0, .Lfail_test3
    csrr    a0, mip
    bne     a0, x0, .Lfail_test4

    li      a0, 0
    ret

.Lfail_test1: li a0, 1; ret
.Lfail_test2: li a0, 2; ret
.Lfail_test3: li a0, 3; ret
.Lfail_test4: li a0, 4; ret
