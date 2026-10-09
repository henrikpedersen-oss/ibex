# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cov_fcov2_rv_hazard -- timing-exact debug requests, NMIs and fetch-enable drops
# =============================================================================
# RISC-V mode, Spike cosim on. Targets the uarch_cg bins (core_ibex_fcov_if.sv) that need an
# event in one particular cycle of the instruction behind a data access, which pmp_fault_hazard
# reaches only when random delays line up (fcov merge 2026-10-09 17:14):
#   exception_stall_instr_cross {pmp, err, category, stall, unstalled, irq pending, debug_req}
#     A  (0,0,Mul,None,0,1,1) (0,0,Load,None,0,1,1)
#     B  (0,0,EBreakExc,None,1,0,1) (0,0,ECall,None,1,0,1) (0,0,FetchError,None,1,1,1)
#     B2 (0,1,EBreakExc,None,1,1,0) (0,1,EBreakExc,None,1,1,1) (0,1,ECall,None,1,1,0)
#     C  (0,1,EBreakDbg,None,0,0,1) (0,1,EBreakDbg,None,0,1,0) (0,1,EBreakDbg,None,1,0,0)
#        (0,1,EBreakDbg,None,1,1,0) (0,1,UncompressedIllegal,None,0,0,0)
#        (0,1,UncompressedIllegal,None,1,1,0) (0,1,CSRIllegal,None,1,1,0)
#        (0,1,FetchError,None,0,1,1) (0,0,EBreakDbg,None,1,0,1) (0,0,MRet,None,1,1,1)
#   interrupt_taken_instr_cross {nmi = 1, unstalled_last = 0, last category}
#     D  EBreakDbg, WFI, FetchError, PrivIllegal
#   pipe_cross {category, IF EmptyAndIdle, ID FullAndStalled, WB state}
#     E  EBreakDbg x WB FullAndStalled / FullAndUnstalled / Empty,
#        CompressedIllegal x FullAndStalled / FullAndUnstalled, EBreakExc x all three
#
# rtl_test core_ibex_stall_events_test (see its header) with:
#   +gnt_trig_lo/hi = [TRIG, TRIG + 0xff]: the program picks the action by the offset it accesses
#     T_DBG debug_req from the cycle after the grant, T_NMI an NMI held from the second cycle
#     after it until taken, T_FOFF fetch_enable_i off from the second cycle after it (40 cycles);
#   +dside_bus_err_lo/hi = [TRIG + T_ERR, TRIG + 0xff]: those accesses get a bus error;
#   +mem_mode_on_write = MEMMODE: the program sets the data-side response delay per section
#     (M_FAST none, M_SLOW 4..12, M_SLOW3 3..10 cycles) with no instruction-side delays, and for
#     section E (M_PIPE) instruction-side responses 40..84 cycles apart;
#   +dbg_req_on_write = DOORBELL (dcsr.ebreakm requests and the sled debug requests);
#   +irq_timer_on_wfi=1: irq_timer_i from the first wfi to the end, so mie.MTIE with mstatus.MIE
#     clear gives a pending, masked interrupt (uarch_cg.cp_irq_pending is |(mip & mie));
#   +enable_bad_intg_on_uninit_access=0: TRIG is not part of the image (random data, good
#     integrity); +disable_fetch_enable_seq=1: no other fetch-enable drops.
#
# Why each section reaches its bins (RTL references: ibex_controller.sv, ibex_id_stage.sv):
#   A  An instruction that enters ID while debug_req is already pending does not enter at all
#      (halt_if with id_wb_pending), so debug_req must rise in the cycle a Mul or Load is in its
#      only ID cycle. Two ways: a doorbell store followed by a sled of 64 single-cycle MULs (or
#      loads), so whichever cycle the request lands in has one in ID; and T_DBG on the access just
#      before one (M_FAST, so the access's response does not stall it). Masked timer pending.
#   B  T_DBG on a slow (M_SLOW) access: the next instruction waits in ID on the outstanding
#      access (Mem) with debug_req pending, and in the response cycle it is unstalled (None, 1).
#   B2 As C below with M_SLOW and the timer pending, while dcsr.ebreakm is still clear, so that
#      ebreak is EBreakExc.
#   C  T_ERR: the access faults; M_FAST puts the next instruction's first ID cycle on the error
#      response (unstalled 0), M_SLOW makes it wait first (unstalled 1). dcsr.ebreakm = 1 makes
#      ebreak EBreakDbg. Every irq / debug combination. Then three single cases: a fetch error
#      behind a faulting T_ERR_DBG access with M_FAST (the non-executable word is inline, so it
#      is fetched while the access waits on the store before it, as \insn in CASE); ebreak
#      (EBreakDbg) unstalling on a good T_DBG access, whose debug request the ebreak's own
#      debug entry then serves (FLUSH honours the ebreak over a pending debug_req); mret, with
#      mepc = the resume point, MPP = M and MPIE = 0, unstalling with the timer pending and a
#      T_DBG request, which FLUSH takes as DBG_TAKEN_IF at the mret target (dpc = mepc).
#   D  T_ERR_NMI, M_SLOW: the NMI is pending while the instruction waits in ID. The load
#      fault's FLUSH (exceptions from WB beat the instruction's own) leaves ID empty, and in the
#      next cycle the NMI is taken (ID empty, PipeEmptyOnIrq) with the flushed instruction as the
#      last category, never just unstalled (None in DECODE before FLUSH and in FLUSH). mepc is
#      the exception handler's first instruction, which never ran.
#   E  IF EmptyAndIdle needs fetch_enable_i off (IF req_i low) with nothing fetched behind X in
#      ID. X must already be in ID when fetching stops: with fetch_enable_i off the controller
#      holds halt_if (ibex_controller.sv ~instr_exec_i), so nothing enters ID. And the icache
#      prefetches ahead whenever req_i is high, so "nothing behind X" can only come from slow
#      instruction-side responses: M_PIPE spaces them 40..84 cycles apart. [c.lw a2, T_FOFF(a0) ;
#      X] share one 32-bit word, so X is in IF as soon as the c.lw is in ID and enters ID in the
#      cycle after the c.lw's grant (G + 1), with the word behind it at least 40 cycles after
#      theirs. From G + 2 fetching is off: IF EmptyAndIdle, ID FullAndStalled (halt_if), and
#      WB holds the c.lw waiting on its M_PIPE (3..10 cycle) response: FullAndStalled, then
#      FullAndUnstalled in the response cycle, then for ebreak into debug mode (which FLUSH
#      keeps in ID for DBG_TAKEN_ID) Empty. The latest such cycle is about 26 cycles after the
#      word arrived (data-side grant delay up to 10, response up to 10 more).
#
# Self-checks (TEST_PASS, else TEST_FAIL with the code in gp):
#   2/3   no timer interrupt at the first wfi / not exactly one   5  mip.MTIP not pending
#   6     a dcsr.ebreakm request was not served
#   10    trap with an unexpected mcause      11 trap where none was expected
#   20-22 timer interrupt: mcause / not expected / mepc
#   30/31 NMI: mcause / mepc not the exception handler's first instruction
#   40    traps taken != expected             41 NMIs taken != expected
#   42    debug entries != expected           43 ebreak debug entries != expected
#   44    cases run != cases assembled
#   45    a sled's debug entry did not happen within the sled
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
#define T_ERR_NMI     0xa0
#define DOORBELL      0x80100100          /* +dbg_req_on_write=80100100 */
#define MEMMODE       0x80100104          /* +mem_mode_on_write=80100104 */
#define M_FAST        0x101               /* no data- or instruction-side delays */
#define M_SLOW        0x104               /* data responses 4..12 cycles after the grant */
#define M_SLOW3       0x103               /* data responses 3..10 cycles after the grant */
#define M_PIPE        0x280003            /* M_SLOW3, instruction responses 40..84 cycles apart */
#define CAUSE_NMI     0x8000001f
#define CAUSE_TIMER   0x80000007

# Registers
#   s0 resume point   s1 traps taken   s2 traps expected   s3 NMIs taken   s4 NMIs expected
#   s5 debug entries  s6 the trap cause expected next (0: none)   s7 debug entries expected
#   s8 ebreak debug entries   s9 ebreak debug entries expected   s10 timer interrupts
#   s11 timer interrupt expected   tp cases run   a0 = TRIG   a1 = ok_buf   a3 debug command
#   t3/t4 debug handler (saved in dscratch0/1)   t5/t6 trap handlers   t0-t2, a2 cases

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

# Debug handler command (1: set dcsr.ebreakm, 2: clear it) through a doorbell debug request.
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
#   cause: trap cause (0 none)  nmi: 1 = the NMI takes over that trap  dbg: haltreq entries
#   ebk: 1 = an ebreak enters debug mode (dcsr.ebreakm)
.macro EXPECT cause, nmi, dbg, ebk
    .set NCASES, NCASES + 1
    addi    tp, tp, 1
    la      s0, 1f
    li      s6, \cause
  .if \nmi
    addi    s4, s4, 1
  .elseif \cause
    addi    s2, s2, 1
  .endif
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

# Fetch-error case: the access is the last word executable before a locked no-permission word
# (fe_*); its debug / NMI / error behaviour as CASE.
.macro CASE_FE blk, cause, nmi, dbg
    EXPECT  \cause, \nmi, \dbg, 0
    sw      zero, 8(a1)
    j       \blk
1:
.endm

# Fetch-error case with the non-executable word \nox inline (a locked no-permission NA4 entry):
# as CASE, the access waits in ID on the store before it, by which time \nox has been fetched.
.macro CASE_FE_IN nox, off, cause, nmi, dbg
    EXPECT  \cause, \nmi, \dbg, 0
    sw      zero, 8(a1)
    lw      t0, (\off)(a0)
\nox:
    nop
1:
.endm

# mret behind the access, returning to the resume point in M-mode with interrupts still masked
# (MPIE = 0), so that the masked timer stays pending.
.macro CASE_MRET off, cause, nmi, dbg
    EXPECT  \cause, \nmi, \dbg, 0
    csrw    mepc, s0
    li      t0, MSTATUS_MPP
    csrs    mstatus, t0
    li      t0, MSTATUS_MPIE
    csrc    mstatus, t0
    sw      zero, 8(a1)
    lw      t0, (\off)(a0)
    mret
1:
.endm

# Section E: [c.lw a2, T_FOFF(a0) ; \insn] in one 32-bit word (see E above). fetch_enable_i drops
# from the second cycle after the c.lw's grant, \insn having entered ID in the first.
.macro CASE_PIPE cause, ebk, insn:vararg
    EXPECT  \cause, 0, 0, \ebk
    .balign 4
    .option push
    .option rvc
    c.lw    a2, T_FOFF(a0)
    \insn
    .option pop
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

# Taken in the first DECODE cycle after a load fault's FLUSH: mepc is the exception handler's
# first instruction, which has not run. The trap it replaces is abandoned.
nmi_handler:
    csrr    t5, mcause
    li      t6, CAUSE_NMI
    li      gp, 30
    bne     t5, t6, fail
    csrr    t5, mepc
    la      t6, mtvec_table
    li      gp, 31
    bne     t5, t6, fail
    addi    s3, s3, 1
    li      s6, 0
    csrw    mepc, s0
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
3:  li      a3, 0
    csrr    t3, CSR_DSCRATCH0
    csrr    t4, CSR_DSCRATCH1
    dret

dbg_exception:
    li      gp, 50
    j       fail

# Fetch-error blocks: the access, then a word that a locked no-permission NA4 entry makes
# non-executable (PMP entries 0 and 1). The two words share a 64-bit line, so the instruction
# behind the access is fetched with it.
    .balign 8
fe_dbg:
    lw      t0, T_DBG(a0)
fe_dbg_nox:
    nop
    .balign 8
fe_nmi:
    lw      t0, T_ERR_NMI(a0)
fe_nmi_nox:
    nop

#----------------------------------------------------------------------------------------------
RVTEST_RV32M
RVTEST_CODE_BEGIN

  la      t0, mtvec_table
  csrw    mtvec, t0

  # PMP. Entries 0/1/2: fe_dbg_nox / fe_nmi_nox / fe_errdbg_nox, NA4, locked, no permissions.
  # Entry 3: all memory, NAPOT, RWX (unlocked: M-mode is unrestricted elsewhere).
  la      t0, fe_dbg_nox
  srli    t0, t0, 2
  csrw    pmpaddr0, t0
  la      t0, fe_nmi_nox
  srli    t0, t0, 2
  csrw    pmpaddr1, t0
  la      t0, fe_errdbg_nox
  srli    t0, t0, 2
  csrw    pmpaddr2, t0
  li      t0, -1
  csrw    pmpaddr3, t0
  li      t0, (0x1F << 24) | (0x90 << 16) | (0x90 << 8) | 0x90
  csrw    pmpcfg0, t0

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
  li      t2, 3

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

  # ---- A: Mul / Load with no stall in their one ID cycle as debug_req rises, timer pending ----
  MEM_MODE M_FAST
  MASKED_IRQ_ON
  # Doorbell then a sled: the request lands somewhere in it.
  mv      t2, s5
  addi    s7, s7, 1
  li      t0, DOORBELL
  sw      zero, 0(t0)
  .rept 64
  mul     t1, s10, s10
  .endr
  li      gp, 45
  beq     t2, s5, fail
  mv      t2, s5
  addi    s7, s7, 1
  li      t0, DOORBELL
  sw      zero, 0(t0)
  .rept 64
  lw      t1, 0(a1)
  .endr
  li      gp, 45
  beq     t2, s5, fail
  # T_DBG on the access just before the instruction.
  CASE    T_DBG, 0, 0, 1, 0, mul t1, s10, s10
  CASE    T_DBG, 0, 0, 1, 0, lw t1, 4(a1)
  MASKED_IRQ_OFF

  # ---- B: the instruction unstalls on a slow access's response with debug_req pending ----
  MEM_MODE M_SLOW
  CASE    T_DBG, CAUSE_BREAKPOINT, 0, 1, 0, ebreak
  CASE    T_DBG, CAUSE_MACHINE_ECALL, 0, 1, 0, ecall
  MASKED_IRQ_ON
  CASE_FE fe_dbg, CAUSE_FETCH_ACCESS, 0, 1
  CASE    T_DBG, CAUSE_BREAKPOINT, 0, 1, 0, ebreak
  CASE    T_DBG, CAUSE_MACHINE_ECALL, 0, 1, 0, ecall
  MASKED_IRQ_OFF
  CASE_FE fe_dbg, CAUSE_FETCH_ACCESS, 0, 1

  # ---- B2: ebreak (EBreakExc) and ecall unstall on a faulting slow access, timer pending ----
  MASKED_IRQ_ON
  CASE    T_ERR,     CAUSE_LOAD_ACCESS, 0, 0, 0, ebreak
  CASE    T_ERR_DBG, CAUSE_LOAD_ACCESS, 0, 1, 0, ebreak
  CASE    T_ERR,     CAUSE_LOAD_ACCESS, 0, 0, 0, ecall
  MASKED_IRQ_OFF

  # ---- C: bus error with the instruction in ID: every response timing, irq and debug ----
  DBG_CMD 1                               # dcsr.ebreakm: ebreak is EBreakDbg
.macro ERR_SET
  CASE    T_ERR,         CAUSE_LOAD_ACCESS, 0, 0, 0, ebreak
  CASE    T_ERR_DBG, CAUSE_LOAD_ACCESS, 0, 1, 0, ebreak
  CASE    T_ERR,         CAUSE_LOAD_ACCESS, 0, 0, 0, .word 0x0000000b
  CASE    T_ERR_DBG, CAUSE_LOAD_ACCESS, 0, 1, 0, .word 0x0000000b
  CASE    T_ERR,         CAUSE_LOAD_ACCESS, 0, 0, 0, csrrw t1, CSR_MVENDORID, t0
  CASE    T_ERR_DBG, CAUSE_LOAD_ACCESS, 0, 1, 0, csrrw t1, CSR_MVENDORID, t0
.endm
  MEM_MODE M_FAST
  ERR_SET
  MASKED_IRQ_ON
  ERR_SET
  # A fetch error in its first ID cycle on the error response: (0,1,FetchError,None,0,1,1)
  CASE_FE_IN fe_errdbg_nox, T_ERR_DBG, CAUSE_LOAD_ACCESS, 0, 1
  MASKED_IRQ_OFF
  MEM_MODE M_SLOW
  ERR_SET
  MASKED_IRQ_ON
  ERR_SET
  # mret unstalling with the timer pending and debug_req: (0,0,MRet,None,1,1,1)
  CASE_MRET T_DBG, 0, 0, 1
  MASKED_IRQ_OFF
  # ebreak into debug mode unstalling with debug_req, no fault: (0,0,EBreakDbg,None,1,0,1). The
  # request is served by the ebreak's debug entry, so it adds no entry of its own.
  CASE    T_DBG, 0, 0, 0, 1, ebreak

  # ---- D: NMI pending while the instruction waits on a faulting access (ebreakm still set) ----
  CASE    T_ERR_NMI, CAUSE_LOAD_ACCESS, 1, 0, 0, ebreak
  CASE    T_ERR_NMI, CAUSE_LOAD_ACCESS, 1, 0, 0, wfi
  CASE    T_ERR_NMI, CAUSE_LOAD_ACCESS, 1, 0, 0, csrr t1, CSR_DCSR
  CASE_FE fe_nmi, CAUSE_LOAD_ACCESS, 1, 0

  # ---- E: IF empty and idle behind X in ID, each WB state ----
  MEM_MODE M_PIPE
  CASE_PIPE 0, 1, c.ebreak                # EBreakDbg: WB FullAndStalled, FullAndUnstalled, Empty
  CASE_PIPE CAUSE_ILLEGAL_INSTRUCTION, 0, .hword 0x0000  # c.unimp: CompressedIllegal
  DBG_CMD 2                               # ebreak is EBreakExc again
  CASE_PIPE CAUSE_BREAKPOINT, 0, c.ebreak
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
