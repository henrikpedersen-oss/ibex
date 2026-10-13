# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cov_fcov3_cheri_irq -- an interrupt or NMI taken right behind a CHERI instruction
# =============================================================================
# CHERIoT mode: boots in RISC-V mode and the bench raises cheriot_enable_i
# (+cheriot_enable_on_write=80200000). Cosim off (as cov_fcov2_cheri_hazard); self-checking.
# Targets uarch_cg.interrupt_taken_instr_cross {nmi 0, unstalled_last, InstrCategoryCheri}, both
# unstalled_last values, which only cheriot_irq_cheri's random interrupts reached
# (fcov merge of regression 30527, 2026-10-10: both 0), and {nmi 1, unstalled_last 0,
# InstrCategoryCheri}, which nothing reached (merge of regression 14911, 2026-10-10: 0; no
# CHERIoT test raises an NMI with a CHERI instruction in ID).
#
# Why random interrupts rarely reach it: an interrupt is taken only with ID empty
# (ibex_controller.sv, !stall && !id_wb_pending), and the bin needs the cycle before that to hold
# a CHERI instruction, i.e. the interrupt must rise while one is in ID, so that halt_if keeps the
# next instruction out while it completes. cheriot_irq_cheri runs with random instruction-side
# delays, so ID is mostly empty when its interrupts arrive (seed 30528: the candperm before a
# timer interrupt retired 26 cycles before the handler; the category in between was None). An
# interrupt that is pending, or unmasked by a CSR write (every mie/mstatus write flushes,
# ibex_id_stage.sv csr_pipe_flush), is taken behind a flush instead.
#
# rtl_test core_ibex_stall_events_test with:
#   +gnt_trig_lo/hi = [TRIG, TRIG + 0xff]; offset T_IRQ (0x08): irq_external_i from the second
#     cycle after the access's grant, held until the core takes an interrupt; offset T_NMI
#     (0x20): the same with irq_nm_i;
#   +mem_mode_on_write = MEMMODE: M_FAST no delays on either side, M_SLOW data responses 4..12
#     cycles after the grant, no instruction-side delays.
# mie.MEIE and mstatus.MIE are set for S0 and S1, so the interrupt is taken as soon as ID
# empties; both are clear for S2 (an NMI is taken whatever they are, ibex_controller.sv
# handle_irq). In CHERIoT mode the NMI also traps to MTCC (ibex_if_stage.sv EXC_PC_IRQ), and its
# mret restores MEPCC and mstatus from the NMI stack (ibex_cs_registers.sv).
#
# Cases (the store before the access leaves it waiting in ID, by which time what follows has
# been fetched, so the instruction after it is in ID from the cycle after its grant, G + 1):
#   S0  M_FAST: the access, then a sled of CIncAddrImm. The response arrives at G + 1, so no
#       sled op stalls; the interrupt rises at G + 2 with the second op in ID, which completes
#       (halt_if), and is taken at G + 3: last category Cheri, unstalled_last 0.
#   S1  M_SLOW: the access, then CIncAddr reading the loaded register: LdHz in ID until the
#       response, at least 4 cycles after G; the interrupt rises at G + 2 while it waits, it
#       completes in the response cycle (None after LdHz: unstalled) and the interrupt is taken
#       in the next: last category Cheri, unstalled_last 1.
#   S2  As S0 with T_NMI: the NMI rises at G + 2 with the second op in ID; handle_irq includes
#       irq_nm, and DECODE takes it only with ID empty (!id_wb_pending) as in S0, so it is taken
#       at G + 3: nmi 1, last category Cheri, unstalled_last 0.
#
# Failure codes (TEST_END_A0, a0): 1 setup, 10 trap other than the interrupt the case expects
# (external interrupt or NMI), 40 interrupts taken != expected (checked after every case),
# 44 cases run != assembled.

#include "cheriot_dv.h"

#define TRIG          0x80100000          /* +gnt_trig_lo/hi = 80100000 / 801000ff */
#define T_IRQ         0x08
#define T_NMI         0x20
#define MEMMODE       0x80100104          /* +mem_mode_on_write=80100104 */
#define M_FAST        0x101
#define M_SLOW        0x104
#define CAUSE_EXT     0x8000000b
#define CAUSE_NMI     0x8000001f
#define MIE_MEIE      0x800

# Registers (x0-x15 only)
#   s1 interrupts taken  gp interrupts expected  tp cases run  a3 the mcause the case expects
#   a0 capability at TRIG  a1 capability at ok_buf  t2 / a2 the CHERI ops' results
#   t0, t1 scratch (case code)   a4 the trap handler's only register

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

# Every case expects exactly one interrupt, of mcause \cause, raised by the access to TRIG + \off;
# the count is checked once the case is over.
.macro CASE_BEGIN off, cause
    .set NCASES, NCASES + 1
    addi      tp, tp, 1
    addi      gp, gp, 1
    li        a3, \cause
    sw        zero, 8(a1)
    lw        t0, \off(a0)
.endm

.macro CASE_END
    .rept 8
    nop
    .endr
    beq       s1, gp, 1f
    li        a0, 40
    j         test_end
1:
.endm

    DV_VECTORS debug_entry_v, debug_exception_v
_start:
    ENABLE_CHERIOT_VIA_TRIGGER
    j         main
debug_entry_v:
    j         test_fail_dbg
debug_exception_v:
    j         test_fail_dbg

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

    li        t0, MIE_MEIE
    csrs      mie, t0
    csrsi     mstatus, 8

    # ---- S0: an unstalled CHERI op in ID as the interrupt rises (unstalled_last 0) ----
    MEM_MODE  M_FAST
    CASE_BEGIN T_IRQ, CAUSE_EXT
    .rept 16
    cincaddrimm t2, a1, 4
    .endr
    CASE_END
    CASE_BEGIN T_IRQ, CAUSE_EXT
    .rept 16
    cincaddrimm t2, a1, 4
    .endr
    CASE_END

    # ---- S1: a CHERI op unstalling from LdHz after the interrupt rose (unstalled_last 1) ----
    MEM_MODE  M_SLOW
    CASE_BEGIN T_IRQ, CAUSE_EXT
    cincaddr  a2, a1, t0
    CASE_END
    CASE_BEGIN T_IRQ, CAUSE_EXT
    cincaddr  a2, a1, t0
    CASE_END

    csrci     mstatus, 8
    li        t0, MIE_MEIE
    csrc      mie, t0

    # ---- S2: an unstalled CHERI op in ID as an NMI rises (nmi 1, unstalled_last 0) ----
    MEM_MODE  M_FAST
    CASE_BEGIN T_NMI, CAUSE_NMI
    .rept 16
    cincaddrimm t2, a1, 4
    .endr
    CASE_END
    CASE_BEGIN T_NMI, CAUSE_NMI
    .rept 16
    cincaddrimm t2, a1, 4
    .endr
    CASE_END
    MEM_MODE  0

    # ---- Totals ----
    li        t0, NCASES
    beq       tp, t0, 5f
    li        a0, 44
    j         test_end
5:  li        a0, 0
    j         test_end

setup_fail:
    li        a0, 1
    j         test_end
test_fail_dbg:
    li        a0, 50
test_end:
    SIG_INIT
    TEST_END_A0

# ---- Traps (CHERIoT: every trap at MTCC, the NMI's too). Only the interrupt the case expects
# (mcause a3) is; the bench drops it once taken, so mret (MIE restored from MPIE; after the NMI,
# MEPCC and mstatus from the NMI stack) resumes at the interrupted point. Writes a4 only, which
# no case touches.
    .balign 4
trap_handler:
    csrr      a4, mcause
    bne       a4, a3, 1f
    addi      s1, s1, 1
    mret
1:  li        a0, 10
    j         test_end

    .data
    .balign 16
ok_buf:
    .fill 4, 4, 0
