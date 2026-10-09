# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: debug_dm_pmp -- fetches, loads and stores in the Debug Module range in debug mode,
# with the PMP allowing and denying that range (RISC-V mode)
# =============================================================================
# REQ_DBG_05: PMP still applies in debug mode except to the Debug Module's own address range,
# which is always allowed (RISC-V Debug Specification A.2); every other address is PMP-checked as
# in M-mode.
#
# The bench has no debug module: DEBUG_MODE_HALT_ADDR is BOOT_ADDR, inside the program, and the
# DM range [0x1A110000, 0x1A111000) (compile_tb.py DM_ADDR / DM_ADDR_MASK) is plain memory in the
# memory agent. So the debug handler puts code there itself. One haltreq (rtl_test
# core_ibex_single_debug_pulse_test) starts one debug session, in which the handler:
#   1. stores dm_routine and a data word into the DM range, then fence.i;
#   2. calls the routine with mseccfg.MMWP = 0. No PMP region matches the DM range, so the M-mode
#      PMP check itself allows it. The routine runs from the DM range and loads, increments and
#      stores the data word there (code 20);
#   3. sets MMWP. A no-match M-mode access is now denied, so only the debug-mode exemption lets
#      the second call fetch, load and store in the DM range (codes 12, 21, 22). Any fault in the
#      DM range is a debug exception: code 95;
#   4. loads from the first address above the DM range: PMP-checked as in M-mode, so a load access
#      fault, i.e. a debug exception that updates no register (Debug Spec 4.1) (codes 30-34).
# Back in the program (M-mode, MMWP still 1): a load from, and a jump into, the DM range fault
# (load / instruction access fault, mtval = the address, mepc = the load / the target), so the
# exemption is confined to debug mode (codes 40-47).
#
# PMP region 0 (NAPOT, RWX, unlocked) covers [0x80000000, 0x90000000): program, data and the
# signature address, which keeps them accessible once MMWP is set. Spike is the cosim oracle: it
# exempts the same range in debug mode (processor_t::set_debug_module_range, set from DM_ADDR).
#
# Registers: the program uses x1-x15 only; the debug and trap handlers use x18-x26 and save
# nothing.
# Codes: 3 no debug request arrived; 10 dcsr.cause is not haltreq; 11 MMWP set before the
# session; 12 MMWP did not set (Smepmp); 20-22 the routine in the DM range; 30-34 the load above
# the DM range; 40-47 outside debug mode; 50 the session did not finish; 90 unexpected trap;
# 91 unexpected debug entry; 95 unexpected debug exception.

#include "cheriot_dv.h"

#define G_FLAG          0
#define G_STAGE         4
#define G_RESUME        8
#define G_TRAPS         12
#define G_MCAUSE        16
#define G_MTVAL         20
#define G_MEPC          24
#define G_DPC           28
#define G_SNAP_MCAUSE   32
#define G_SNAP_MTVAL    36
#define G_SNAP_MEPC     40
#define GLOBALS_SIZE    44

#define STG_SESSION     1
#define STG_ABOVE       2
#define STG_ABOVE_DONE  3

#define DM_BASE         0x1A110000
#define DM_ABOVE        0x1A111000  /* first address above the DM range */
#define DM_DATA         0x100       /* data word, after the routine */
#define DM_DATA_INIT    0x100
#define CSR_MSECCFG     0x747
#define MSECCFG_MMWP    0x2
#define MCAUSE_INSN_ACC 1
#define MCAUSE_LD_ACC   5

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
    la        t0, unexpected_trap
    sw        t0, G_RESUME(a5)
    li        t0, 0x21FFFFFF                # NAPOT [0x80000000, +256 MiB)
    csrw      pmpaddr0, t0
    li        t0, 0x1F                      # NAPOT | X | W | R, unlocked
    csrw      pmpcfg0, t0
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
    CHECK_EQI t0, STG_ABOVE_DONE, 50, t1

# Arm the trap handler (resume at \resume) and clear the trap record. Clobbers t0.
.macro ARM resume
    la        t0, \resume
    sw        t0, G_RESUME(a5)
    sw        zero, G_TRAPS(a5)
.endm

# One trap, mcause \cause, mtval = \mtval, mepc = \pc (registers). Codes \code .. \code+3.
# Clobbers t0, t1.
.macro EXPECT_TRAP cause, mtval, pc, code
    lw        t0, G_TRAPS(a5)
    CHECK_EQI t0, 1, \code, t1
    lw        t0, G_MCAUSE(a5)
    CHECK_EQI t0, \cause, \code+1, t1
    lw        t0, G_MTVAL(a5)
    CHECK_EQ  t0, \mtval, \code+2
    lw        t0, G_MEPC(a5)
    CHECK_EQ  t0, \pc, \code+3
.endm

    # ── outside debug mode the DM range is PMP-checked: MMWP, no region, denied ──
    ARM       n1r
    li        t2, DM_BASE
n1: lw        a1, DM_DATA(t2)
    li        a0, 40
    j         test_end
n1r: li       t2, DM_BASE + DM_DATA
    la        a2, n1
    EXPECT_TRAP MCAUSE_LD_ACC, t2, a2, 40

    ARM       n2r
    li        t2, DM_BASE
n2: jalr      ra, 0(t2)
    li        a0, 44
    j         test_end
n2r: li       t2, DM_BASE
    EXPECT_TRAP MCAUSE_INSN_ACC, t2, t2, 44

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
    csrr      s4, CSR_MSECCFG
    andi      s4, s4, MSECCFG_MMWP
    CHECK_EQI s4, 0, 11, s5

    # ── 1. the routine and its data word into the DM range ───────────────────
    li        s6, DM_BASE
    la        s7, dm_routine
    la        s8, dm_routine_end
2:  lw        s9, 0(s7)
    sw        s9, 0(s6)
    addi      s7, s7, 4
    addi      s6, s6, 4
    bltu      s7, s8, 2b
    li        s6, DM_BASE
    li        s9, DM_DATA_INIT
    sw        s9, DM_DATA(s6)
    fence.i

    # ── 2. MMWP = 0: the PMP check allows the DM range ───────────────────────
    jalr      s10, 0(s6)
    CHECK_EQI s9, DM_DATA_INIT + 1, 20, s4

    # ── 3. MMWP = 1: the PMP check denies it, debug mode exempts it ──────────
    csrsi     CSR_MSECCFG, MSECCFG_MMWP
    csrr      s4, CSR_MSECCFG
    andi      s4, s4, MSECCFG_MMWP
    CHECK_EQI s4, MSECCFG_MMWP, 12, s5
    jalr      s10, 0(s6)
    CHECK_EQI s9, DM_DATA_INIT + 2, 21, s4
    lw        s9, DM_DATA(s6)
    CHECK_EQI s9, DM_DATA_INIT + 2, 22, s4

    # ── 4. above the DM range debug mode is PMP-checked as M-mode ────────────
    csrr      s4, mcause
    sw        s4, G_SNAP_MCAUSE(s2)
    csrr      s4, mtval
    sw        s4, G_SNAP_MTVAL(s2)
    csrr      s4, mepc
    sw        s4, G_SNAP_MEPC(s2)
    csrr      s4, dpc
    sw        s4, G_DPC(s2)
    li        s3, STG_ABOVE
    sw        s3, G_STAGE(s2)
    li        s6, DM_ABOVE
    lw        s9, 0(s6)                     # load access fault: to debug_exception
    li        a0, 30
    j         test_end
dbg_above_back:
    li        s3, STG_ABOVE_DONE
    sw        s3, G_STAGE(s2)
    csrr      s4, mcause
    lw        s5, G_SNAP_MCAUSE(s2)
    CHECK_EQ  s4, s5, 31
    csrr      s4, mtval
    lw        s5, G_SNAP_MTVAL(s2)
    CHECK_EQ  s4, s5, 32
    csrr      s4, mepc
    lw        s5, G_SNAP_MEPC(s2)
    CHECK_EQ  s4, s5, 33
    csrr      s4, dpc
    lw        s5, G_DPC(s2)
    CHECK_EQ  s4, s5, 34
    # Outlast the 75-cycle request pulse, so one request is one entry.
    li        s4, 100
3:  addi      s4, s4, -1
    bnez      s4, 3b
    li        s3, 1
    sw        s3, G_FLAG(s2)
    dret

# ---- Debug exception address --------------------------------------------------------------------
    .balign 4
debug_exception:
    la        s2, globals
    lw        s3, G_STAGE(s2)
    li        s4, STG_ABOVE
    beq       s3, s4, dbg_above_back
    li        a0, 95                        # e.g. an access to the DM range faulted
    j         test_end

# Copied to DM_BASE. s6 = DM_BASE; returns through s10, the new data word in s9.
    .balign 4
dm_routine:
    lw        s9, DM_DATA(s6)
    addi      s9, s9, 1
    sw        s9, DM_DATA(s6)
    jalr      x0, 0(s10)
dm_routine_end:

# ---- Trap handler: record, resume at G_RESUME ---------------------------------------------------
    .balign 256
trap_handler:
    la        s2, globals
    lw        s3, G_TRAPS(s2)
    addi      s3, s3, 1
    sw        s3, G_TRAPS(s2)
    li        s4, 4
    bltu      s3, s4, 1f
    li        a0, 90
    j         test_end
1:  csrr      s3, mcause
    sw        s3, G_MCAUSE(s2)
    csrr      s3, mtval
    sw        s3, G_MTVAL(s2)
    csrr      s3, mepc
    sw        s3, G_MEPC(s2)
    lw        s3, G_RESUME(s2)
    csrw      mepc, s3
    mret

    .data
    .balign 8
globals:
    .fill GLOBALS_SIZE / 4, 4, 0
