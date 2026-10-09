# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cov_fcov2_cheri_hazard -- a CHERI instruction behind a data access, timing-exact
# =============================================================================
# CHERIoT mode: boots in RISC-V mode and the bench raises cheriot_enable_i
# (+cheriot_enable_on_write=80200000). Cosim off (CHERIoT-Sail has no debug mode and no bus
# errors); self-checking. Targets the InstrCategoryCheri bins of uarch_cg that pmp_fault_hazard
# (RISC-V mode) cannot reach and the random CHERIoT streams reach only by chance (fcov merge
# 2026-10-09 17:14), {pmp, err, category, stall, unstalled, irq pending, debug_req}:
#   exception_stall_instr_cross
#     A  (0,0,Cheri,None,0,1,1)
#     B  (0,0,Cheri,None,1,0,1) (0,0,Cheri,None,1,1,1) (0,0,Cheri,LdHz,0,0,1)
#        (0,0,Cheri,LdHz,0,1,1) (0,0,Cheri,Mem,0,0,1) (0,0,Cheri,Mem,0,1,1)
#     C  (0,1,Cheri,None,0,0,1) (0,1,Cheri,None,0,1,0) (0,1,Cheri,None,0,1,1)
#        (0,1,Cheri,None,1,0,1) (0,1,Cheri,None,1,1,0) (0,1,Cheri,None,1,1,1)
#        (0,1,Cheri,LdHz,0,0,1) (0,1,Cheri,LdHz,0,1,0) (0,1,Cheri,LdHz,0,1,1)
#   debug_entry_if_instr_cross (seen, unstalled_last = 1, Cheri)   (section B)
# The PMP bins (pmp = 1) with Cheri are ignore_bins: data PMP errors are gated off in CHERIoT
# mode (core_ibex_fcov_if.sv pmp_cheri_ignore).
#
# rtl_test core_ibex_stall_events_test (see its header and cov_fcov2_rv_hazard, which uses the
# same arrangement in RISC-V mode):
#   +gnt_trig_lo/hi = [TRIG, TRIG + 0xff]; offset T_DBG: debug_req from the cycle after the
#     access's grant, i.e. the first ID cycle of the CHERI instruction behind it;
#   +dside_bus_err_lo/hi = [TRIG + T_ERR, TRIG + 0xff]: bus error (load access fault, mcause 5);
#   +mem_mode_on_write = MEMMODE: M_FAST no data-side delay (the error / data arrives in the CHERI
#     instruction's first ID cycle: unstalled 0), M_SLOW data 4..12 cycles after the grant (it
#     waits in ID first: Mem, or LdHz when it reads the loaded register; unstalled 1 after);
#     no instruction-side delays either way;
#   +dbg_req_on_write = DOORBELL (section A's sled); +irq_timer_on_wfi=1 (masked pending timer).
#
# Sections:
#   A  M_FAST, timer pending: a doorbell debug request lands in a sled of 64 CIncAddrImm, each
#      unstalled in its one ID cycle; and T_DBG on the access right before one.
#   B  M_SLOW, timer pending / not: T_DBG on an access followed by an independent CHERI op
#      (Mem while it waits, None unstalled 1 in the response cycle, then the debug entry from an
#      empty ID with it as last category) or one reading the loaded register (LdHz).
#   C  M_FAST and M_SLOW, timer pending / not, debug / not: T_ERR, the same two CHERI ops.
#
# Failure codes (TEST_END_A0, a0): 1 setup, 2 no timer interrupt at the first wfi, 5 mip.MTIP
# not pending, 10 trap with an unexpected mcause, 11 trap where none was expected, 40 traps taken
# != expected, 42 debug entries != expected, 44 cases run != assembled, 45 the sled's debug entry
# not within the sled, 50 debug exception.

#include "cheriot_dv.h"

#define TRIG          0x80100000          /* +gnt_trig_lo/hi = 80100000 / 801000ff */
#define T_DBG         0x10
#define T_ERR         0x80                /* +dside_bus_err_lo/hi = 80100080 / 801000ff */
#define T_ERR_DBG     0x90
#define DOORBELL      0x80100100          /* +dbg_req_on_write=80100100 */
#define MEMMODE       0x80100104          /* +mem_mode_on_write=80100104 */
#define M_FAST        0x101
#define M_SLOW        0x104
#define CAUSE_TIMER   0x80000007
#define MIP_MTIP      0x80

# Registers (x0-x15 only)
#   s0 resume point (integer)  s1 traps taken  gp traps expected  tp cases run
#   a0 capability at TRIG  a1 capability at ok_buf  a3 the trap cause expected next (0: none)
#   a4 debug entries  a5 debug entries expected  t2 / a2 the CHERI ops' results
#   t0, t1 scratch (the trap handler uses them)

    .option norvc
    .option norelax

    .set NCASES, 0

# cd := MTDC with its cursor at the constant address \addr. \tmp must differ from \cd.
.macro DCAP_ABS cd, addr, tmp
    cspecialr \cd, SCR_MTDC
    li        \tmp, \addr
    csetaddr  \cd, \cd, \tmp
.endm

# Store \v to the +mem_mode_on_write address; the load and nops after it keep the next case's
# access out of the change-over.
.macro MEM_MODE v
    DCAP_ABS  t0, MEMMODE, t1
    li        t1, \v
    sw        t1, 0(t0)
    lw        t1, 0(a1)
    .rept 8
    nop
    .endr
.endm

.macro MASKED_IRQ_ON
    li        t0, MIP_MTIP
    csrs      mie, t0
    csrr      t1, mip
    and       t1, t1, t0
    bnez      t1, 1f
    li        a0, 5
    j         test_end
1:
.endm

.macro MASKED_IRQ_OFF
    li        t0, MIP_MTIP
    csrc      mie, t0
.endm

# The access to TRIG + \off, then \insn. The store before it leaves the access waiting on it in
# ID, by which time \insn is fetched: \insn is in ID the cycle after the access's grant.
#   cause: trap expected (0 none)  dbg: debug entries expected
.macro CASE off, cause, dbg, insn:vararg
    .set NCASES, NCASES + 1
    addi      tp, tp, 1
    LA_FAR    s0, .Lres\@, t1
    li        a3, \cause
  .if \cause
    addi      gp, gp, 1
  .endif
    addi      a5, a5, \dbg
    sw        zero, 8(a1)
    lw        t0, \off(a0)
    \insn
.Lres\@:
.endm

# The two CHERI ops: independent of the access, and reading its destination (load hazard).
#define OP_INDEP cincaddrimm t2, a1, 4
#define OP_DEP   cincaddr a2, a1, t0

    DV_VECTORS debug_entry_v, debug_exception_v
_start:
    ENABLE_CHERIOT_VIA_TRIGGER
    j         main
debug_entry_v:
    j         debug_entry
debug_exception_v:
    j         debug_exception

    .text
main:
    SET_VEC   trap_handler, t1, t0
    DCAP_ABS  a0, TRIG, t0
    DCAP_FAR  a1, ok_buf, t0
    cgettag   t0, a1
    beqz      t0, setup_fail
    li        s1, 0
    li        gp, 0
    li        tp, 0
    li        a3, 0
    li        a4, 0
    li        a5, 0

    # The timer interrupt the bench raises at this wfi and then holds (+irq_timer_on_wfi).
    li        t2, 1
    li        t0, MIP_MTIP
    csrs      mie, t0
    csrsi     mstatus, 8
    sw        t0, 12(a1)
    wfi
    csrci     mstatus, 8
    beqz      t2, 1f
    li        a0, 2
    j         test_end
1:

    # ---- A: unstalled CHERI op as debug_req rises, timer pending ----
    MEM_MODE  M_FAST
    MASKED_IRQ_ON
    mv        t2, a4
    addi      a5, a5, 1
    DCAP_ABS  t0, DOORBELL, t1
    sw        zero, 0(t0)
    .rept 64
    cincaddrimm a2, a1, 4
    .endr
    bne       t2, a4, 2f
    li        a0, 45
    j         test_end
2:
    CASE      T_DBG, 0, 1, OP_INDEP
    MASKED_IRQ_OFF

    # ---- B: debug_req pending while the CHERI op waits on the access ----
    MEM_MODE  M_SLOW
    CASE      T_DBG, 0, 1, OP_INDEP
    CASE      T_DBG, 0, 1, OP_DEP
    MASKED_IRQ_ON
    CASE      T_DBG, 0, 1, OP_INDEP
    CASE      T_DBG, 0, 1, OP_DEP
    MASKED_IRQ_OFF

    # ---- C: bus error with the CHERI op in ID ----
.macro ERR_SET
    CASE      T_ERR,     MCAUSE_LOAD_ACC, 0, OP_INDEP
    CASE      T_ERR_DBG, MCAUSE_LOAD_ACC, 1, OP_INDEP
    CASE      T_ERR,     MCAUSE_LOAD_ACC, 0, OP_DEP
    CASE      T_ERR_DBG, MCAUSE_LOAD_ACC, 1, OP_DEP
.endm
    MEM_MODE  M_FAST
    ERR_SET
    MASKED_IRQ_ON
    ERR_SET
    MASKED_IRQ_OFF
    MEM_MODE  M_SLOW
    ERR_SET
    MASKED_IRQ_ON
    ERR_SET
    MASKED_IRQ_OFF
    MEM_MODE  0

    # ---- Totals ----
    beq       s1, gp, 3f
    li        a0, 40
    j         test_end
3:  beq       a4, a5, 4f
    li        a0, 42
    j         test_end
4:  li        t0, NCASES
    beq       tp, t0, 5f
    li        a0, 44
    j         test_end
5:  li        a0, 0
    j         test_end

setup_fail:
    li        a0, 1
test_end:
    SIG_INIT
    TEST_END_A0

# ---- Traps (CHERIoT: every trap at MTCC). The first wfi's timer interrupt returns to MEPCC
# with mie.MTIE cleared (irq_timer_i stays high); an exception must be the one expected, and
# resumes at s0 through an MTCC-derived MEPCC. Uses t0, t1 (and t2 for the timer flag).
    .balign 4
trap_handler:
    csrr      t0, mcause
    li        t1, CAUSE_TIMER
    bne       t0, t1, 1f
    li        t0, MIP_MTIP
    csrc      mie, t0
    li        t2, 0
    mret
1:  bnez      a3, 2f
    li        a0, 11
    j         test_end
2:  beq       t0, a3, 3f
    li        a0, 10
    j         test_end
3:  addi      s1, s1, 1
    li        a3, 0
    cspecialr t1, SCR_MTCC
    csetaddr  t1, t1, s0
    cspecialw SCR_MEPCC, t1
    mret

# ---- Debug: count the entry and return (no register but a4 is touched) ----
    .balign 4
debug_entry:
    addi      a4, a4, 1
    dret

debug_exception:
    li        a0, 50
    j         test_end

    .data
    .balign 16
ok_buf:
    .fill 4, 4, 0
