# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: wb_counter_inhibit — mcountinhibit.CY stops/resumes mcycle counter
# =============================================================================
# CSR 0x320 (mcountinhibit) controls whether performance counters increment.
# Bit 0 (CY) inhibits mcycle; bit 2 (IR) inhibits minstret.
#
# ibex_cs_registers.sv: mcountinhibit_d feeds directly into the counter enable
# logic.  Writing 1 to bit 0 halts mcycle on the next clock edge.
#
#   Test 1: mcycle increments during normal execution (delta >= 3 after 3 NOPs)
#   Test 2: mcycle frozen while mcountinhibit.CY=1 (delta = 0 across 4 NOPs)
#   Test 3: mcycle resumes after mcountinhibit cleared (delta >= 3 after 3 NOPs)
#   Tests 4-6: interrupt state unchanged.
#
# CSR 0x320 = mcountinhibit.  The bit 1 is hardwired to 0 (ibex_cs_registers.sv:
# mcountinhibit_d = {upper, 1'b0, csr_wdata_int[0]}).
# =============================================================================

.globl main
main:
    csrsi   mstatus, 8

    # ── Test 1: mcycle increments normally ───────────────────────────────────
    csrr    a0, mcycle
    nop
    nop
    nop
    csrr    a1, mcycle
    sub     a2, a1, a0              # delta should be >= 3
    li      a3, 3
    bltu    a2, a3, .Lfail_test1   # fail if counter didn't advance

    # ── Inhibit CY (bit 0) ───────────────────────────────────────────────────
    li      a0, 1
    csrw    0x320, a0               # mcountinhibit.CY = 1

    # ── Test 2: mcycle frozen ─────────────────────────────────────────────────
    csrr    a4, mcycle              # baseline (inhibit just took effect)
    nop
    nop
    nop
    nop
    csrr    a5, mcycle              # should still equal a4
    bne     a4, a5, .Lfail_test2

    # ── Clear inhibit ─────────────────────────────────────────────────────────
    csrw    0x320, x0               # mcountinhibit = 0 (CY resumes)

    # ── Test 3: mcycle resumes ────────────────────────────────────────────────
    csrr    a0, mcycle
    nop
    nop
    nop
    csrr    a1, mcycle
    sub     a2, a1, a0
    bltu    a2, a3, .Lfail_test3   # a3 still = 3

    # ── Tests 4-6: interrupt state ────────────────────────────────────────────
    csrr    a0, mstatus
    andi    a1, a0, 8
    beq     a1, x0, .Lfail_test4
    csrr    a0, mcause
    bne     a0, x0, .Lfail_test5
    csrr    a0, mip
    bne     a0, x0, .Lfail_test6

    li      a0, 0
    ret

.Lfail_test1: li a0, 1; ret
.Lfail_test2: li a0, 2; ret
.Lfail_test3: li a0, 3; ret
.Lfail_test4: li a0, 4; ret
.Lfail_test5: li a0, 5; ret
.Lfail_test6: li a0, 6; ret
