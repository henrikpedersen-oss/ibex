# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: prc_2555_dbg_illegal_scr -- an unimplemented SCR accessed in debug mode traps
#                                   (lowRISC/ibex PR #2555)
# =============================================================================
# In CHERIoT mode Ibex turns off the CHERIoT checks in debug mode, and with them the trap for an
# unimplemented SCR: ibex_cheriot_ex.sv masks cheriot_wb_err_d with ~debug_mode_i, so CSpecialRW
# of SCR 0 in debug mode does nothing and raises nothing. A CSR access to an unimplemented CSR
# does raise an illegal-instruction exception in debug mode (which goes to the debug exception
# address). PR #2555 makes the SCR case trap too, and documents the rest.
#
# Sequence (core_ibex_debug_halt_once_test sends one halt request after INITIALIZED; CHERIoT
# mode via +cheriot_enable_on_write; cosim off: CHERIoT-Sail has no debug mode):
#   main waits; debug_entry counts the entry, then executes CSpecialR cd, SCR 0. With the PR
#   that traps to the debug exception address, which counts it and resumes; without the PR the
#   instruction completes silently. dret; main checks the counts.
# Result (a0): 0 pass; 1 no debug entry; 2 the SCR 0 access did not trap in debug mode;
#              3 more than one debug exception; 250 an unexpected trap outside debug mode.

#include "cheriot_dv.h"

# CSpecialRW cd, scr, c0 (a read), raw: SCR 0 has no assembler name.
#define CSPECIALR_RAW(cd, scr) .word (0x01<<25)|((scr)<<20)|((cd)<<7)|0x5b
#define F_ENTRIES 0
#define F_DBGEXC  4

    .option norvc
    .option norelax

    DV_VECTORS debug_entry, debug_exception
_start:
    ENABLE_CHERIOT_VIA_TRIGGER
    j         main

    .text
main:
    SET_VEC   unexpected, t1, t0
    SIG_INIT
    DCAP_FAR  a5, flags, t0
    sw        zero, F_ENTRIES(a5)
    sw        zero, F_DBGEXC(a5)
    SIG_STATUS ST_INITIALIZED

    li        s0, 400000
1:
    lw        t0, F_ENTRIES(a5)
    bnez      t0, 2f
    addi      s0, s0, -1
    bnez      s0, 1b
    li        a0, 1
    j         test_end
2:
    lw        t0, F_DBGEXC(a5)
    li        a0, 2
    beqz      t0, test_end
    li        t1, 1
    li        a0, 3
    bne       t0, t1, test_end
    li        a0, 0
test_end:
    TEST_END_A0

    .balign 4
unexpected:
    li        a0, 250
    j         test_end

# ---- debug mode -------------------------------------------------------------------------------
    .balign 4
debug_entry:
    cspecialrw t0, SCR_DSCRATCHC0, t0
    cspecialrw t1, SCR_DSCRATCHC1, t1
    DCAP_FAR  t1, flags, t0
    lw        t0, F_ENTRIES(t1)
    addi      t0, t0, 1
    sw        t0, F_ENTRIES(t1)
    CSPECIALR_RAW(5, 0)                     # CSpecialR t0, SCR 0: no such SCR
dbg_resume:
    cspecialrw t0, SCR_DSCRATCHC0, t0
    cspecialrw t1, SCR_DSCRATCHC1, t1
    dret

    .balign 4
debug_exception:
    lw        t0, F_DBGEXC(t1)
    addi      t0, t0, 1
    sw        t0, F_DBGEXC(t1)
    j         dbg_resume

    .data
    .balign 8
flags:
    .fill 4, 4, 0
