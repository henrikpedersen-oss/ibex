# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cov_fcov4_rv_hazard -- ebreak / wfi / fence with irq and debug_req, dret with IF empty,
#                              an NMI taken right after dret
# =============================================================================
# RISC-V mode, Spike cosim on. Targets the uarch_cg bins (core_ibex_fcov_if.sv) the combined
# coverage of regression 2026-10-18 20:47 left at 0, the UNR-excluded view's last 7 covergroup
# holes but the CHERI one (cov_fcov4_cheri_hazard):
#   A  exception_stall_instr_cross (0,0,EBreakDbg,None,1,1,1) (0,0,WFI,None,1,1,1)
#   B  exception_stall_instr_cross (0,1,EBreakExc,None,0,1,1) (0,1,Fence,None,0,0,1)
#   C  pipe_cross {PrivIllegal, IF EmptyAndIdle, ID FullAndStalled, WB FullAndUnstalled}
#   D  interrupt_taken_instr_cross {nmi 1, unstalled_last 0, DRet}
# (exception_stall_instr_cross = {pmp, err, category, stall, unstalled, irq pending, debug_req}.)
#
# rtl_test core_ibex_stall_events_test with the windows of cov_fcov2_rv_hazard
# (directed_testlist_cov_fcov4.yaml): T_DBG debug_req from the cycle after the access's grant,
# T_NMI an NMI from the second cycle after it, held until taken, T_FOFF fetch_enable_i off from the
# second cycle after it for 40 cycles, T_ERR a bus error; +mem_mode_on_write the memory-agent
# delays per section; +irq_timer_on_wfi=1 irq_timer_i from the first wfi to the end, so mie.MTIE
# with mstatus.MIE clear is a pending, masked interrupt (cp_irq_pending is |(mip & mie)).
#
# Why each section reaches its bin (RTL references: ibex_controller.sv, ibex_id_stage.sv):
#   A  As cov_fcov2_rv_hazard section B (M_SLOW, T_DBG): the instruction behind the access waits
#      in ID on it (stall Mem: outstanding_memory_access stalls any instruction) with debug_req
#      pending, and unstalls (None, unstalled 1) in the response cycle; here with the masked timer
#      pending too. ebreak with dcsr.ebreakm set (EBreakDbg): its FLUSH honours the ebreak over
#      the pending debug_req, and that entry serves the request. wfi: no trap; the debug entry
#      after it (the pending timer would wake it at once).
#   B  As cov_fcov3_rv_hazard section C (M_FAST, T_ERR_DBG: the error response arrives in the
#      instruction's first ID cycle, None and unstalled 0, with debug_req from the cycle after the
#      grant). ebreak with dcsr.ebreakm clear (EBreakExc) and the masked timer pending; fence
#      (decoded as an ALU op, no stall of its own) with mie.MTIE clear, so nothing is pending. The
#      load fault kills both; its trap, then the debug entry (FLUSH takes the exception first).
#   C  cov_fcov3_rv_hazard section D (IF_EMPTY: X enters ID behind a T_FOFF load L with nothing
#      fetched behind it, IF EmptyAndIdle from the second cycle after L's grant, X stalled while
#      L waits in WB) with X = dret outside debug mode, which ibex_id_stage.sv categorises
#      PrivIllegal (illegal_dret_insn). An illegal X raises special_req, so retain_id keeps it in
#      DECODE (FullAndStalled) also in L's response cycle, when WB is FullAndUnstalled: the bin.
#      The same five alignments (PADS 0..8) as there.
#   D  A debug entry (doorbell) whose handler, command 3, makes an access to TRIG + T_NMI: the NMI
#      is raised in debug mode, where handle_irq masks it (~debug_mode_q). dret leaves ID through
#      FLUSH, its last cycle in ID (category DRet, stall None in FLUSH and in the DECODE before:
#      unstalled 0). In the next cycle, DECODE with ID empty and debug_mode_q clear, the NMI is
#      taken (DECODE -> IRQ_TAKEN): fcov_interrupt_taken with DRet as the last category. The NMI
#      handler returns to the interrupted code (the command's wait loop).
#
# Self-checks (TEST_PASS, else TEST_FAIL with the code in gp):
#   2/3   no timer interrupt at the first wfi / not exactly one   5  mip.MTIP not pending
#   6     a debug-handler command was not served
#   10    trap with an unexpected mcause      11 trap where none was expected
#   20-22 timer interrupt: mcause / not expected / mepc
#   30    NMI: mcause      31 NMI where none was expected
#   40    traps taken != expected             41 NMIs taken != expected
#   42    debug entries != expected           43 ebreak debug entries != expected
#   44    cases run != cases assembled
#   50    debug exception (none expected)

#include "riscv_test.h"
#include "test_macros.h"

    .option norvc
    .option norelax

#define TRIG          0x80100000          /* +gnt_trig_lo/hi = 80100000 / 801000ff */
#define T_DBG         0x10
#define T_NMI         0x20
#define T_FOFF        0x40
#define T_ERR         0x80                /* +dside_bus_err_lo/hi = 80100080 / 801000ff */
#define T_ERR_DBG     0x90
#define DOORBELL      0x80100100          /* +dbg_req_on_write=80100100 */
#define MEMMODE       0x80100104          /* +mem_mode_on_write=80100104 */
#define M_FAST        0x101               /* no data- or instruction-side delays */
#define M_SLOW        0x104               /* data responses 4..12 cycles after the grant */
#define M_SLOW10      0x10a               /* data responses 10..24 cycles after the grant */
#define M_IFE         0x3c0003            /* data 3..10, instruction responses 60..124 apart */
#define CAUSE_NMI     0x8000001f
#define CAUSE_TIMER   0x80000007

# Registers
#   s0 resume point   s1 traps taken   s2 traps expected   s3 NMIs taken   s4 NMIs expected
#   s5 debug entries  s6 the trap cause expected next (0: none)   s7 debug entries expected
#   s8 ebreak debug entries   s9 ebreak debug entries expected   s10 timer interrupts
#   s11 timer interrupt expected   tp cases run   a0 = TRIG   a1 = ok_buf   a3 debug command
#   t3/t4 the DIV's operands and the debug handler (saved in dscratch0/1)   t5/t6 trap handlers
#   t0-t2 cases

    .set NCASES, 0

# Set the memory agents' timing (+mem_mode_on_write). The bench applies it after this store's
# response; the load and nops after it keep any access of the next case out of the change-over.
.macro MEM_MODE v
    li      t0, MEMMODE
    li      t1, \v
    sw      t1, 0(t0)
    lw      t1, 0(a1)
    .rept 8
    nop
    .endr
.endm

# Debug handler command (1: set dcsr.ebreakm, 2: clear it, 3: raise an NMI from debug mode)
# through a doorbell debug request.
.macro DBG_CMD cmd
    li      a3, \cmd
    addi    s7, s7, 1
    li      t0, DOORBELL
    sw      zero, 0(t0)
    li      t1, 200000
8:  beqz    a3, 9f
    addi    t1, t1, -1
    bnez    t1, 8b
    li      gp, 6
    j       fail
9:
.endm

.macro MASKED_IRQ_ON
    li      t0, MIP_MTIP
    csrs    mie, t0
    csrr    t1, mip
    and     t1, t1, t0
    li      gp, 5
    beqz    t1, fail
.endm

.macro MASKED_IRQ_OFF
    li      t0, MIP_MTIP
    csrc    mie, t0
.endm

# Book-keeping shared by every case: resume point 1f, the trap / NMI / debug entries expected.
#   cause: trap cause (0 none)  nmi: NMIs expected  dbg: haltreq entries
#   ebk: 1 = an ebreak enters debug mode (dcsr.ebreakm)
.macro EXPECT cause, nmi, dbg, ebk
    .set NCASES, NCASES + 1
    addi    tp, tp, 1
    la      s0, 1f
    li      s6, \cause
  .if \cause
    addi    s2, s2, 1
  .endif
    addi    s4, s4, \nmi
    addi    s7, s7, \dbg + \ebk
    addi    s9, s9, \ebk
.endm

# The access to TRIG + \off, then \insn. The store before it leaves the access waiting on it in
# ID, by which time \insn has been fetched: \insn is in ID the cycle after the access's grant.
.macro CASE off, cause, nmi, dbg, ebk, insn:vararg
    EXPECT  \cause, \nmi, \dbg, \ebk
    sw      zero, 8(a1)
    lw      t0, (\off)(a0)
    \insn
1:
.endm

# Section C attempt (cov_fcov3_rv_hazard section D): \pads nops between Q1 and L, then X = \insn.
# Runs in M_SLOW10 and leaves it set for the next attempt.
.macro IF_EMPTY pads, cause, insn:vararg
    EXPECT  \cause, 0, 0, 0
    li      t1, M_IFE
    li      t2, MEMMODE
    li      t3, 1000
    li      t4, 3
    .balign 8
    nop
    div     t3, t3, t4                      # line offset 4
    sw      t1, 0(t2)                       # Q, line offset 0
    sw      zero, 8(a1)                     # Q1
  .rept \pads
    nop
  .endr
    lw      t0, T_FOFF(a0)                  # L
    \insn                                   # X
1:
    MEM_MODE M_SLOW10
.endm

# Section D: an NMI raised from debug mode (command 3), taken right after the handler's dret.
.macro NMI_AFTER_DRET
    EXPECT  0, 1, 0, 0
    DBG_CMD 3
1:
.endm

#----------------------------------------------------------------------------------------------
# Debug halt / exception addresses: DEBUG_MODE_HALT_ADDR = BOOT_ADDR, _EXCEPTION_ADDR = + 8.
    .section .text.init
    j       dbg_entry
    nop
    j       dbg_exception

#----------------------------------------------------------------------------------------------
    .text

# mtvec (vectored, as Ibex forces): exceptions at +0, the machine timer at +0x1c, NMIs at +0x7c.
    .balign 256
mtvec_table:
    j       exc_handler
    .org    mtvec_table + 0x1c
    j       timer_handler
    .org    mtvec_table + 0x7c
    j       nmi_handler

exc_handler:
    csrr    t5, mcause
    li      gp, 11
    beqz    s6, fail
    li      gp, 10
    bne     t5, s6, fail
    addi    s1, s1, 1
    li      s6, 0
    csrw    mepc, s0
    mret

timer_handler:
    csrr    t5, mcause
    li      t6, CAUSE_TIMER
    li      gp, 20
    bne     t5, t6, fail
    li      gp, 21
    beqz    s11, fail
    csrr    t5, mepc
    la      t6, wfi_resume
    li      gp, 22
    bne     t5, t6, fail
    li      t5, MIP_MTIP
    csrc    mie, t5                       # irq_timer_i stays high from now on
    li      s11, 0
    addi    s10, s10, 1
    mret

# Section D: taken in the DECODE cycle after the debug handler's dret, so mepc is where the core
# was when it entered debug mode (the command's wait loop); returns there.
nmi_handler:
    csrr    t5, mcause
    li      t6, CAUSE_NMI
    li      gp, 30
    bne     t5, t6, fail
    addi    s3, s3, 1
    li      gp, 31
    bgt     s3, s4, fail
    mret

dbg_entry:
    csrw    CSR_DSCRATCH0, t3
    csrw    CSR_DSCRATCH1, t4
    addi    s5, s5, 1
    csrr    t3, CSR_DCSR
    srli    t4, t3, 6
    andi    t4, t4, 7
    li      t3, 1
    bne     t4, t3, 1f
    csrw    CSR_DPC, s0                   # entered by ebreak (dcsr.ebreakm): resume the case
    addi    s8, s8, 1
1:  li      t4, DCSR_EBREAKM
    li      t3, 1
    bne     a3, t3, 2f
    csrs    CSR_DCSR, t4
2:  li      t3, 2
    bne     a3, t3, 3f
    csrc    CSR_DCSR, t4
3:  li      t3, 3
    bne     a3, t3, 4f
    sw      zero, T_NMI(a0)               # the NMI from the second cycle after the grant
    lw      t3, 0(a1)                     # after the store's response: the NMI is pending
    .rept 8                               # (and masked) well before the dret below
    nop
    .endr
4:  li      a3, 0
    csrr    t3, CSR_DSCRATCH0
    csrr    t4, CSR_DSCRATCH1
    dret

dbg_exception:
    li      gp, 50
    j       fail

#----------------------------------------------------------------------------------------------
RVTEST_RV32M
RVTEST_CODE_BEGIN

  la      t0, mtvec_table
  csrw    mtvec, t0

  li      s1, 0
  li      s2, 0
  li      s3, 0
  li      s4, 0
  li      s5, 0
  li      s6, 0
  li      s7, 0
  li      s8, 0
  li      s9, 0
  li      s10, 0
  li      tp, 0
  li      a3, 0
  li      a0, TRIG
  la      a1, ok_buf

  # The timer interrupt the bench raises at this wfi and then holds (+irq_timer_on_wfi).
  li      s11, 1
  li      t0, MIP_MTIP
  csrs    mie, t0
  csrsi   mstatus, MSTATUS_MIE
  sw      t0, 12(a1)
  wfi
wfi_resume:
  csrci   mstatus, MSTATUS_MIE
  li      gp, 2
  bnez    s11, fail
  li      gp, 3
  li      t0, 1
  bne     s10, t0, fail
  MASKED_IRQ_OFF

  # ---- B: bus error in the instruction's first ID cycle, debug_req; dcsr.ebreakm still clear ----
  MEM_MODE M_FAST
  # (0,1,EBreakExc,None,0,1,1): the masked timer pending
  MASKED_IRQ_ON
  CASE    T_ERR_DBG, CAUSE_LOAD_ACCESS, 0, 1, 0, ebreak
  CASE    T_ERR_DBG, CAUSE_LOAD_ACCESS, 0, 1, 0, ebreak
  # (0,1,Fence,None,0,0,1): nothing pending
  MASKED_IRQ_OFF
  CASE    T_ERR_DBG, CAUSE_LOAD_ACCESS, 0, 1, 0, fence
  CASE    T_ERR_DBG, CAUSE_LOAD_ACCESS, 0, 1, 0, fence

  # ---- A: ebreak (EBreakDbg) and wfi unstall on a slow access, debug_req and the timer ----
  MEM_MODE M_SLOW
  MASKED_IRQ_ON
  # (0,0,WFI,None,1,1,1): the pending timer wakes the wfi at once; the debug entry follows
  CASE    T_DBG, 0, 0, 1, 0, wfi
  CASE    T_DBG, 0, 0, 1, 0, wfi
  MASKED_IRQ_OFF
  DBG_CMD 1                               # dcsr.ebreakm: ebreak is EBreakDbg
  MASKED_IRQ_ON
  # (0,0,EBreakDbg,None,1,1,1): the ebreak's own entry serves the request
  CASE    T_DBG, 0, 0, 0, 1, ebreak
  CASE    T_DBG, 0, 0, 0, 1, ebreak
  MASKED_IRQ_OFF
  DBG_CMD 2

  # ---- C: dret (PrivIllegal outside debug mode) in ID behind a waiting load, IF empty ----
  MEM_MODE M_SLOW10
  # {PrivIllegal, EmptyAndIdle, FullAndStalled, FullAndUnstalled}
  .irp pads, 0, 2, 4, 6, 8
  IF_EMPTY \pads, CAUSE_ILLEGAL_INSTRUCTION, dret
  .endr

  # ---- D: an NMI raised in debug mode is taken right after dret: {1, 0, DRet} ----
  MEM_MODE M_FAST
  NMI_AFTER_DRET
  NMI_AFTER_DRET
  MEM_MODE 0

  # ---- Totals ----
  li      gp, 40
  bne     s1, s2, fail
  li      gp, 41
  bne     s3, s4, fail
  li      gp, 42
  bne     s5, s7, fail
  li      gp, 43
  bne     s8, s9, fail
  li      gp, 44
  li      t0, NCASES
  bne     tp, t0, fail
  j       pass

  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
  .balign 16
ok_buf:
  .zero 16
RVTEST_DATA_END
