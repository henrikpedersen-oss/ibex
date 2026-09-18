# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: wb_fetch_fifo_full — ibex_fetch_fifo all 3 slots occupied
# =============================================================================
# ibex_fetch_fifo has DEPTH = NUM_REQS + 1 = 3 (ibex_fetch_fifo.sv).
# The FIFO fills when the ID/EX stage is stalled for multiple cycles while the
# prefetch buffer keeps issuing instruction fetch requests.
#
# This test stalls the pipeline with a 32-cycle DIVU (unsigned divide) so that
# all three FIFO slots fill with the following sequential instructions.  A branch
# at the end exercises the FIFO-flush-then-redirect path (cp_pcc_bounds_squash
# covergroup path in ibex_if_stage).
#
#   Test 1: DIVU result 0xFFFFFFFF / 3 = 0x55555555 (unsigned)
#     Verifies that the 32-cycle stall completed without pipeline corruption.
#     A wrong result means instructions were skipped or an incorrect forward
#     value was consumed while the FIFO was full.
#
#   Test 2: second DIVU 100 / 7 = 14
#     Back-to-back stall: second FIFO-full cycle checks that the fill/drain
#     sequence leaves no stale data in any FIFO slot.
#
#   Tests 3-5: interrupt state unchanged (MIE=1, mcause=0, mip=0).
#
# Coverage: ibex_fetch_fifo fifo_valid_n=3 state, plus prefetch redirect.
# =============================================================================

.globl main
main:
    csrsi   mstatus, 8              # set mstatus.MIE

    # ── DIVU stall 1: fills all 3 fetch FIFO slots ──────────────────────────
    li      a0, 0xFFFFFFFF          # dividend (maximum unsigned value)
    li      a1, 3                   # divisor
    divu    a2, a0, a1              # ~32-cycle stall; IF fills FIFO slots 1,2,3
    nop                             # slot 1 during stall
    nop                             # slot 2 during stall
    nop                             # slot 3 (FIFO full)

    # ── Test 1: 0xFFFFFFFF / 3 = 0x55555555 (unsigned) ──────────────────────
    li      a1, 0x55555555
    bne     a2, a1, .Lfail_test1

    # ── DIVU stall 2: second fill/drain cycle ────────────────────────────────
    li      a0, 100
    li      a1, 7
    divu    a3, a0, a1              # 100 / 7 = 14
    nop
    nop
    nop

    # ── Test 2: 100 / 7 = 14 ─────────────────────────────────────────────────
    li      a1, 14
    bne     a3, a1, .Lfail_test2

    # Branch flushes the FIFO and redirects the prefetch (exercises redirect path)
    beq     zero, zero, .Lafter_branch
    li      a0, 99
    ret                             # unreachable

.Lafter_branch:
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
