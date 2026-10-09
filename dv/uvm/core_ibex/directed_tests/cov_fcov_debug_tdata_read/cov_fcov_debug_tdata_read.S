# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cov_fcov_debug_tdata_read -- read-only accesses to the trigger CSRs in debug mode
# (RISC-V mode)
# =============================================================================
# Targets uarch_cg.csr_read_only_debug_cross {CSR_TDATA1, debug mode} and {CSR_TDATA2, debug
# mode}: a csrr (csrrs rd, csr, x0) of tdata1 / tdata2 while the core is in debug mode. riscv-dv's
# debug ROM only writes them, and the regression of 2026-10-09 never read them in debug mode.
#
# One haltreq (rtl_test core_ibex_single_debug_pulse_test) starts one debug session, in which the
# handler reads tselect, tdata1 and tdata2, writes tdata2 and reads it back, restores it, and
# returns with dret. Back in the program (M-mode) tdata2 is read once more.
#
# Expected values (ibex_cs_registers.sv gen_trigger_regs, the Debug Specification 0.13.2 5.2):
#   tselect = 0 at reset.
#   tdata1  = 0x28001048 for trigger 0 at reset: type 2 (address/data match, [31:28]), dmode 1
#             ([27], only debug mode may write it), action 1 ([15:12], enter debug mode), m 1
#             ([6]), u 1 ([3]), execute 0 ([2], the trigger is disabled), all else 0.
#   tdata2  = 0 at reset; in debug mode a write of TDATA2_PATTERN reads back unchanged (a plain
#             32-bit match value). With execute = 0 the value never matches.
# Spike is the cosim oracle (as in debug_dm_pmp, which also runs one haltreq session); every
# value read here goes through it as a register write.
#
# Registers: the program uses x1-x15 only; the debug handlers use x18-x25 and save nothing.
# Codes: 3 no debug request arrived; 10 dcsr.cause is not haltreq; 11 tselect; 12 tdata1; 13
# tdata2 at reset; 14 tdata2 after the write; 15 tdata2 after the restore; 20 the session did not
# finish; 21 tdata2 outside debug mode; 90 unexpected trap; 91 unexpected debug entry; 95
# unexpected debug exception.

#include "cheriot_dv.h"

#define G_FLAG          0
#define G_STAGE         4
#define GLOBALS_SIZE    8

#define STG_SESSION     1
#define STG_DONE        2

#define TDATA1_RESET    0x28001048
#define TDATA2_PATTERN  0x5A5AA5A4

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
    CHECK_EQI t0, STG_DONE, 20, t1
    csrr      t0, tdata2                    # outside debug mode: readable, still 0
    CHECK_EQI t0, 0, 21, t1
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
    beqz      s3, 1f
    li        a0, 91
    j         test_end
1:  li        s3, STG_SESSION
    sw        s3, G_STAGE(s2)
    csrr      s4, dcsr
    srli      s4, s4, 6
    andi      s4, s4, 7
    CHECK_EQI s4, 3, 10, s5                 # dcsr.cause = haltreq

    # ── read-only accesses in debug mode ─────────────────────────────────────
    csrr      s4, tselect
    CHECK_EQI s4, 0, 11, s5
    csrr      s4, tdata1
    CHECK_EQI s4, TDATA1_RESET, 12, s5
    csrr      s4, tdata2
    CHECK_EQI s4, 0, 13, s5

    # ── tdata2 is writable in debug mode; read it back, then restore it ─────
    li        s6, TDATA2_PATTERN
    csrw      tdata2, s6
    csrr      s4, tdata2
    CHECK_EQ  s4, s6, 14
    csrw      tdata2, zero
    csrr      s4, tdata2
    CHECK_EQI s4, 0, 15, s5

    # Outlast the 75-cycle request pulse, so one request is one entry.
    li        s4, 100
2:  addi      s4, s4, -1
    bnez      s4, 2b
    li        s3, STG_DONE
    sw        s3, G_STAGE(s2)
    li        s3, 1
    sw        s3, G_FLAG(s2)
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
    .balign 8
globals:
    .fill GLOBALS_SIZE / 4, 4, 0
