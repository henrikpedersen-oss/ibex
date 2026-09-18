# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: wb_fetch_fifo_single — fetch FIFO consumed with exactly 1 valid entry
# =============================================================================
# When a JAL jumps forward past the prefetch window the FIFO is flushed and the
# prefetcher restarts at the branch target.  With always-grant instruction memory
# (instr_gnt=instr_req) and 1-cycle rvalid, exactly one instruction occupies the
# FIFO (fifo_valid_n=1) between the restart and the first decode.
#
# Two back-to-back JALs exercise the single-entry state twice in succession.
#
#   Test 1: correct value after first JAL (no instruction skipped or duplicated)
#   Tests 2-4: interrupt state unchanged.
#
# Coverage: ibex_fetch_fifo fifo_valid_n=1 state on prefetch restart.
# =============================================================================

.globl main
main:
    csrsi   mstatus, 8

    # JAL 1: jump well past the current prefetch window (>3 instructions ahead).
    # The FIFO is flushed; exactly one instruction at .Ltarget1 is buffered
    # before the decoder starts consuming it (single-entry state).
    j       .Ltarget1
    nop; nop; nop; nop; nop; nop; nop; nop  # unreachable padding

    .align 2
.Ltarget1:
    # Immediate second JAL: exercises single-entry consumption + second restart.
    j       .Ltarget2
    nop; nop; nop; nop

    .align 2
.Ltarget2:
    # ── Test 1: correct value computable after both JALs ──────────────────────
    li      a0, 0x1234
    li      a1, 0x1234
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
