# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: wb_prefetch_branch — branch while a prefetch is outstanding
# =============================================================================
# When the first JAL fires, ibex_prefetch_buffer flushes the FIFO and issues a
# new fetch request to the branch target.  If the very next instruction at the
# branch target is also a branch (before rvalid returns), the prefetcher handles
# a "branch_req while outstanding" scenario.
#
# With always-grant + 1-cycle rvalid this creates: JAL → target fetch in-flight
# → target instruction arrives → second JAL fires → second fetch in-flight →
# second target arrives.  All three transitions exercise prefetch_branch timing.
#
#   Test 1: value correctly computed after three branch hops.
#   Test 2: data-dependent not-taken branch (verifies branch resolve path).
#   Tests 3-5: interrupt state unchanged.
#
# Coverage: ibex_prefetch_buffer prefetch_branch signal during in-flight fetch.
# =============================================================================

.globl main
main:
    csrsi   mstatus, 8

    # Hop 1: unconditional forward jump
    j       .Lhop1

.Lhop1:
    # Hop 2: another immediate unconditional jump (branch during in-flight fetch)
    j       .Lhop2

.Lhop2:
    # Hop 3: data-independent arithmetic, then conditional branch
    li      a0, 7
    li      a1, 3
    add     a2, a0, a1               # 7 + 3 = 10
    bne     a2, a0, .Lhop3          # a2 != a0 (10 != 7) — taken
    li      a0, 99
    ret                              # unreachable

.Lhop3:
    # ── Test 1: arithmetic survived all branches ──────────────────────────────
    li      a3, 10
    bne     a2, a3, .Lfail_test1

    # ── Test 2: not-taken branch (verifies branch-not-taken redirect path) ────
    li      a4, 5
    beq     a4, a3, .Lbad           # 5 != 10, not taken
    j       .Lgood
.Lbad:
    li      a0, 2; ret
.Lgood:

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
.Lfail_test3: li a0, 3; ret
.Lfail_test4: li a0, 4; ret
.Lfail_test5: li a0, 5; ret
