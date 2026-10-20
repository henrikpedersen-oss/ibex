# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: debug_triggers_all -- every debug trigger of the build is programmed and fires
# (RISC-V mode)
# =============================================================================
# The earlgrey configuration has four triggers (DbgHwBreakNum = 4, tselect 0-3); every other test
# leaves tselect at 0, so triggers 1-3 were never written, read or matched. N =
# IBEX_DBG_HW_BREAK_NUM, the build's DbgHwBreakNum (compile_test.py), so the test checks the
# triggers the core it runs on has.
#
# One haltreq (rtl_test core_ibex_single_debug_pulse_test) starts the first debug session. In it,
# for each trigger k < N: tselect := k reads k; tdata1 and tdata2 read their reset values; tdata2
# := the address of target k and tdata1 := execute on. Then every tdata2 is read back (the
# triggers keep separate values), and a write of 0xFF to tselect reads N-1. After dret the program
# runs targets 0 .. N-1 in order. Each trigger fires before its target executes: debug mode with
# dcsr.cause = trigger and dpc = the target; the handler checks both, turns that trigger off
# (otherwise dret would fire it again) and returns. The program then counts N hits.
#
# Expected behaviour (not taken from the RTL):
#   - Ibex manual cs_registers.rst (tselect, tdata1, tdata2) and debug.rst: tselect resets to 0
#     and selects the trigger the tdata registers access; "Writing a value larger than or equal
#     to the number of supported triggers will write the highest valid index". tdata1 reads
#     0x28001048 (type 2, dmode 1, action 1 = enter debug mode, m 1, u 1) with execute (bit 2) 0
#     at reset; execute is the one writable bit. tdata2 is the match address, reset 0.
#   - RISC-V Debug Specification 0.13.2: a trigger with action 1 enters debug mode before the
#     matching instruction executes (timing 0): dcsr.cause = 2 (trigger), dpc = its address.
#   All writes are made in debug mode (dmode = 1), so the M-mode tselect question (draft ticket,
#   status/rtl_tickets.md) does not arise.
#
# Cosim off: Spike's trigger module is not configured with the build's trigger count; every value
# is checked here.
#
# Registers: the program uses x1-x15 only; the debug handlers use x18-x25 and save nothing.
# Codes (a0): 3 no debug request arrived; 10 first entry's dcsr.cause is not haltreq;
#   30+k tselect != k after selecting it; 40+k tdata1 not at reset; 50+k tdata2 not 0;
#   60+k tdata1 does not read execute after enabling; 70+k tdata2 of trigger k changed by
#   another trigger's write; 79 tselect not clamped to N-1; 80 a later entry's cause is not
#   trigger; 81 dpc is not the next target; 82 tdata1 still has execute after disabling;
#   83 more trigger entries than triggers; 20 the first session did not finish; 22 fewer than N
#   trigger hits; 90 unexpected trap; 95 debug exception.
#
# Proving it can fail (build-time switch, not in the testlist):
#   -DDEBUG_TRIGGERS_INJECT_FAIL  leaves the last trigger disabled -> 22

#include "cheriot_dv.h"

#ifndef IBEX_DBG_HW_BREAK_NUM
#error "IBEX_DBG_HW_BREAK_NUM (DbgHwBreakNum) is set by compile_test.py"
#endif
#define NTRIG           IBEX_DBG_HW_BREAK_NUM

#define G_FLAG          0
#define G_STAGE         4
#define G_HITS          8
#define GLOBALS_SIZE    12

#define STG_SESSION     1
#define STG_ARMED       2

#define DCSR_CAUSE_TRIGGER  2
#define DCSR_CAUSE_HALTREQ  3
#define TDATA1_RESET    0x28001048
#define TDATA1_EXECUTE  0x4

    .option norvc

    DV_VECTORS debug_entry, debug_exception
_start:
    j         main

    .text
main:
    la        t0, trap_handler
    csrw      mtvec, t0
    li        s1, SIG_ADDR_VAL
    la        a5, globals
    li        t0, 0x1800                    # MPP = M: the bench reads the boot privilege from this
    csrs      mstatus, t0
    SIG_CSR   0x300
    SIG_CSR   0x304
    SIG_STATUS ST_INITIALIZED

    li        s0, 400000
wait_start:
    lw        t0, G_FLAG(a5)
    bnez      t0, wait_done
    addi      s0, s0, -1
    bnez      s0, wait_start
    li        a0, 3                         # no debug request arrived
    j         test_end
wait_done:
    lw        t0, G_STAGE(a5)
    CHECK_EQI t0, STG_ARMED, 20, t1

    # ── the targets: each trigger fires once, before its target executes ───
    .irp k, 0, 1, 2, 3, 4, 5, 6, 7
    .if \k < NTRIG
    .globl trig_target_\k
trig_target_\k:
    nop
    .endif
    .endr

    lw        t0, G_HITS(a5)
    CHECK_EQI t0, NTRIG, 22, t1
    li        a0, 0
    j         test_end
unexpected_trap:
    li        a0, 90
test_end:
    TEST_END_A0

# ---- Debug halt address ------------------------------------------------------------------------
    .balign 4
debug_entry:
    la        s2, globals
    lw        s3, G_STAGE(s2)
    bnez      s3, trigger_entry

    # ── first entry: the haltreq ─────────────────────────────────────────────
    li        s3, STG_SESSION
    sw        s3, G_STAGE(s2)
    csrr      s4, dcsr
    srli      s4, s4, 6
    andi      s4, s4, 7
    CHECK_EQI s4, DCSR_CAUSE_HALTREQ, 10, s5

    la        s6, targets
    li        s7, 0                         # k
arm_loop:
    csrw      tselect, s7
    csrr      s4, tselect
    addi      a0, s7, 30
    bne       s4, s7, test_end
    csrr      s4, tdata1
    li        s5, TDATA1_RESET
    addi      a0, s7, 40
    bne       s4, s5, test_end
    csrr      s4, tdata2
    addi      a0, s7, 50
    bnez      s4, test_end
    slli      s8, s7, 2
    add       s8, s8, s6
    lw        s8, 0(s8)                     # target k
    csrw      tdata2, s8
#ifdef DEBUG_TRIGGERS_INJECT_FAIL
    li        s9, NTRIG - 1
    beq       s7, s9, 2f                    # the last trigger stays off
#endif
    li        s5, TDATA1_RESET | TDATA1_EXECUTE
    csrw      tdata1, s5
    csrr      s4, tdata1
    addi      a0, s7, 60
    bne       s4, s5, test_end
2:  addi      s7, s7, 1
    li        s5, NTRIG
    blt       s7, s5, arm_loop

    # Every trigger kept its own match address.
    li        s7, 0
check_loop:
    csrw      tselect, s7
    csrr      s4, tdata2
    slli      s8, s7, 2
    add       s8, s8, s6
    lw        s8, 0(s8)
    addi      a0, s7, 70
    bne       s4, s8, test_end
    addi      s7, s7, 1
    li        s5, NTRIG
    blt       s7, s5, check_loop

    # A tselect beyond the last trigger writes the last index (Ibex manual).
    li        s4, 0xFF
    csrw      tselect, s4
    csrr      s4, tselect
    CHECK_EQI s4, NTRIG - 1, 79, s5

    # Outlast the 75-cycle request pulse, so one request is one entry.
    li        s4, 100
3:  addi      s4, s4, -1
    bnez      s4, 3b
    li        s3, STG_ARMED
    sw        s3, G_STAGE(s2)
    li        s3, 1
    sw        s3, G_FLAG(s2)
    dret

    # ── later entries: trigger k fired at target k ───────────────────────────
trigger_entry:
    csrr      s4, dcsr
    srli      s4, s4, 6
    andi      s4, s4, 7
    CHECK_EQI s4, DCSR_CAUSE_TRIGGER, 80, s5
    lw        s7, G_HITS(s2)                # k: the triggers fire in target order
    li        s5, NTRIG
    blt       s7, s5, 4f
    li        a0, 83
    j         test_end
4:  la        s6, targets
    slli      s8, s7, 2
    add       s8, s8, s6
    lw        s8, 0(s8)
    csrr      s4, dpc
    CHECK_EQ  s4, s8, 81
    csrw      tselect, s7                   # turn trigger k off, or dret fires it again
    li        s5, TDATA1_RESET
    csrw      tdata1, s5
    csrr      s4, tdata1
    CHECK_EQ  s4, s5, 82
    addi      s7, s7, 1
    sw        s7, G_HITS(s2)
    dret

# ---- Debug exception address --------------------------------------------------------------------
    .balign 4
debug_exception:
    li        a0, 95
    j         test_end

# ---- Trap handler: nothing may trap -------------------------------------------------------------
    .balign 256
trap_handler:
    j         unexpected_trap

    .data
    .balign 4
targets:
    .irp k, 0, 1, 2, 3, 4, 5, 6, 7
    .if \k < NTRIG
    .word     trig_target_\k
    .endif
    .endr
    .balign 8
globals:
    .fill GLOBALS_SIZE / 4, 4, 0
