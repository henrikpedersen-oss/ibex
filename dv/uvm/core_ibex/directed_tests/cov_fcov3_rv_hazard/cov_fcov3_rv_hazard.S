# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cov_fcov3_rv_hazard -- U-mode NMI, illegal / fence.i timing, X with IF empty, PMP faults
# =============================================================================
# RISC-V mode, Spike cosim on. Targets the uarch_cg bins (core_ibex_fcov_if.sv) the fcov merge
# of regression 30527 (2026-10-10) left at 0, all hit before only by random stimulus:
#   A  priv_mode_irq_cross {PRIV_LVL_U, nmi_external, mstatus.MIE 1}
#   B  exception_stall_instr_cross (0,0,CompressedIllegal,None,1,1,1)
#   C  exception_stall_instr_cross (0,1,FenceI,None,0,1,1)
#   D  pipe_cross {WFI, IF EmptyAndIdle, ID FullAndStalled, WB FullAndStalled}
# the ones the merge of regression 14911 (2026-10-10) left at 0, never targeted before:
#   B  exception_stall_instr_cross (0,0,Fence,None,1,1,1) (0,0,CSRIllegal,None,1,1,1)
#   C  exception_stall_instr_cross (0,0,Store,None,0,1,1)
# and the ones the merge of regression 26231 (2026-10-11) left at 0, hit in regression 14911 by
# random stimulus only (the WFI bin above among them: section D as first written missed it):
#   D  pipe_cross {UncompressedIllegal, IF EmptyAndIdle, ID FullAndStalled, WB FullAndStalled}
#      {FetchError, IF EmptyAndIdle, ID FullAndStalled, WB FullAndUnstalled}
#   E  exception_stall_instr_cross (0,1,EBreakExc,None,1,0,0) (0,1,FenceI,None,1,1,0)
#   F  interrupt_taken_instr_cross {nmi 1, unstalled_last 1, Fence}
#   G  exception_stall_instr_cross (1,0,EBreakDbg,None,0,1,1)
# (exception_stall_instr_cross = {pmp, err, category, stall, unstalled, irq pending, debug_req};
# its (1,0,EBreakDbg,None,0,0,0) is in cov_fcov2_rv_hazard section C, which has no
# +dbg_on_pmp_err_pct.)
#
# rtl_test core_ibex_stall_events_test (see its header and cov_fcov2_rv_hazard) with:
#   +gnt_trig_lo/hi = [TRIG, TRIG + 0xff]: T_DBG debug_req from the cycle after the access's
#     grant, T_NMI an NMI held from the second cycle after it until taken, T_FOFF fetch_enable_i
#     off from the second cycle after it for 40 cycles;
#   +dside_bus_err_lo/hi = [TRIG + T_ERR, TRIG + 0xff]: those accesses get a bus error;
#   +mem_mode_on_write = MEMMODE: memory-agent delays per section (M_FAST none, M_SLOW data
#     responses 4..12 cycles after the grant, M_SLOW10 and M_IFE below);
#   +irq_timer_on_wfi=1: irq_timer_i from the first wfi to the end, so mie.MTIE with mstatus.MIE
#     clear gives a pending, masked interrupt (uarch_cg.cp_irq_pending is |(mip & mie)), which
#     also makes every later wfi resume at once without a trap;
#   +dbg_on_pmp_err_pct=100: debug_req in the cycle a PMP-blocked data access reports its fault.
#     Section G's loads are the only data accesses here that PMP blocks.
#
# Why each section reaches its bin (RTL references: ibex_controller.sv, ibex_id_stage.sv):
#   A  An NMI is taken whatever mstatus.MIE is, and the bin wants it taken in U-mode with MIE set.
#      riscv-dv boots U-mode with MPIE = enable_interrupt & a random mstatus_mie
#      (riscv_privileged_common_seq.sv); every riscv-dv test of one seed draws the same boot, and
#      in regression 30527 every interrupt test that booted U-mode drew MIE 0. Here: mret to
#      U-mode with MPIE = 1 and mie = 0 (in U-mode every enabled M interrupt is taken, so only
#      the NMI is), then T_NMI from U-mode; the NMI handler checks MPP = U and MPIE = 1 and
#      returns to U-mode, which ecalls back.
#   B  As cov_fcov2_rv_hazard section B (M_SLOW, T_DBG, masked timer pending) with c.unimp: it
#      waits in ID on the outstanding access (stall Mem: any instruction waits on one) with
#      debug_req pending, and unstalls (None, unstalled 1) in the response cycle. Illegal
#      instruction trap, then the debug entry (FLUSH takes the exception first). The same with
#      csrrw to the read-only mvendorid (CSRIllegal: illegal_csr_insn, neither priv nor dbg),
#      the same trap and entry; and with fence (decoded as an ALU op, so stall_mem's
#      outstanding_memory_access is its only stall, ibex_id_stage.sv), no trap, the debug entry
#      once it has completed.
#   C  As cov_fcov2_rv_hazard section C (M_FAST, T_ERR_DBG, masked timer pending) with fence.i:
#      it is in its first ID cycle (unstalled 0) on the bus-error response, and with
#      BranchTargetALU its FIRST_CYCLE raises no stall (None). The load fault kills it. Then as
#      cov_fcov2_rv_hazard section A with a store: T_DBG on the access, whose response arrives
#      in the store's first ID cycle (M_FAST), so the store issues and is granted there (None,
#      after the access's own None cycle: unstalled 0) as debug_req rises. A store that enters
#      ID with debug_req already pending never enters (halt_if with id_wb_pending), which is why
#      random requests miss this bin.
#   D  IF EmptyAndIdle needs fetch_enable_i off (IF req_i low) with nothing fetched behind X in
#      ID, and X must enter ID before fetching stops (fetch_enable_i off holds halt_if): X enters
#      ID in the cycle after the grant of the T_FOFF load L just before it, and fetching is off
#      from the cycle after that. X is 32 bits -- wfi; the custom-0 word 0x0000000b, which the
#      decoder rejects (UncompressedIllegal); a nop in a word a locked no-permission NA4 entry
#      makes non-executable (FetchError: Ibex checks instruction PMP at the IF output,
#      ibex_core.sv pmp_req_addr[PMP_I] = pc_if, so that word is fetched like any other) -- so
#      unlike cov_fcov2_rv_hazard section E it cannot share a word with L: X's word must arrive
#      with no delay and the word behind it late. The icache (ibex_icache.sv) fetches whole 64-bit
#      lines into fill buffers, makes no new lookup while three are busy (lookup_throttle), and
#      releases one only when IF has taken all its words; so with no instruction-side delays and
#      IF stuck on one word, exactly the line of that word and the two after it are fetched. Each
#      attempt, all on one alignment:
#        .balign 8, nop, DIV  the DIV's line is released when it enters ID; ~37 cycles in ID, IF
#                             stuck on Q: Q's line and the two after it are fetched (M_SLOW10:
#                             no instruction-side delays)
#        Q   sw MEMMODE       line offset 0; granted at G_Q, its response (M_SLOW10: at least 10
#                             cycles after the grant) sets M_IFE: instruction responses 60..124
#                             cycles apart, data responses 3..10 cycles after the grant
#        Q1  sw               Q's line's second word: when it enters ID (G_Q + 1) the line is
#                             released and the fourth line is fetched at once (G_Q + 2..5); Q1
#                             then waits in ID for Q's response, IF stuck on the next word, so
#                             nothing more is fetched before M_IFE applies
#        PADS nops, L, X      L = lw T_FOFF
#      Every word up to Q + 7 (the end of the fourth line) arrives with no delay, every later one
#      at least 60 cycles after the one before. With PADS = 4, X is Q + 7: it enters ID at G_L + 1,
#      and from G_L + 2 IF is EmptyAndIdle, X waits in ID (FullAndStalled) for WB, where L waits
#      for its response (FullAndStalled, then FullAndUnstalled in the response cycle, 3..10 cycles
#      after G_L; fetching stays off for 40). The word behind X is requested about when Q + 3
#      enters ID; L is granted at most ~20 cycles after that (Q1's response, L's grant delay),
#      its response ~12 later. PADS = 0, 2, 6, 8 place X at the end of the line one or two before
#      or after, in case the fill buffers run a line shorter or further ahead than above; an
#      attempt whose X is not the last word fetched with no delay is a plain case. As first
#      written, this section timed a single wfi from a fetch-enable stop (one attempt per PADS
#      0..11) and missed the WFI bin in regression 26231: its attempts were not aligned alike (the
#      DIV alternated between line offsets 0 and 4 in pairs), so the last word fetched before the
#      stop moved with PADS, and, by the reasoning above, no attempt had its wfi on it.
#   E  As cov_fcov2_rv_hazard section B2 (M_SLOW, T_ERR: the instruction waits in ID on the
#      access, stall Mem, and unstalls in the bus-error response cycle, None and unstalled 1) with
#      ebreak and no interrupt pending (B2 has it only with the timer pending; dcsr.ebreakm is
#      clear, so it is EBreakExc), and with fence.i and the masked timer pending: with
#      BranchTargetALU fence.i (a jump) raises no Instr stall, so outstanding_memory_access is
#      its only stall (ibex_id_stage.sv stall_mem). The load fault kills both.
#   F  T_NMI on a good M_SLOW access with fence behind it: the fence waits in ID on the access
#      (Mem) with the NMI pending, which holds halt_if (handle_irq with id_wb_pending,
#      ibex_controller.sv DECODE) so nothing enters ID behind it. The fence completes in the
#      response cycle (None, unstalled), ID is empty in the next and the NMI is taken there
#      (DECODE -> IRQ_TAKEN) with the fence as the last category, just unstalled. The NMI
#      handler checks mepc = the instruction behind the fence.
#   G  A load from a word a locked no-permission entry covers (section D's d_nox0) makes no bus
#      request: it leaves ID on pmp_err_q (WAIT_GNT -> IDLE, ibex_load_store_unit.sv), and the
#      fault is reported in the next cycle, ebreak's first in ID (None, unstalled 0).
#      +dbg_on_pmp_err_pct=100 raises debug_req in exactly that cycle (one pending before ebreak
#      entered ID would have kept it out), dcsr.ebreakm (set through a T_DBG debug entry) makes
#      ebreak EBreakDbg, and the masked timer is pending. The load-fault trap is taken, then the
#      debug entry at the trap handler (FLUSH takes the exception first); ebreak never executes.
#
# Self-checks (TEST_PASS, else TEST_FAIL with the code in gp):
#   2/3   no timer interrupt at the first wfi / not exactly one   5  mip.MTIP not pending
#   6     a debug-handler command (DBG_CMD) was not served
#   10    trap with an unexpected mcause      11 trap where none was expected
#   20-22 timer interrupt: mcause / not expected / mepc
#   30    NMI: mcause      32 NMI: mstatus.MPP not U      33 NMI: mstatus.MPIE not 1
#   34    NMI (F): mepc not the instruction behind the fence
#   40    traps taken != expected             41 NMIs taken != expected
#   42    debug entries != expected           44 cases run != cases assembled
#   50    debug exception (none expected)     51 debug entry by ebreak (none executes)

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
#   s8 the NMI expected (0: section A's, from U-mode; 1: section F's, behind a fence)
#   s10 timer interrupts   s11 timer interrupt expected   tp cases run   a0 = TRIG
#   a1 = ok_buf   a3 debug handler command   t3/t4 the DIV's operands and the debug handler
#   (saved in dscratch0/1)   t5/t6 trap handlers   t0-t2 cases

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

# Debug handler command (1: set dcsr.ebreakm, 2: clear it) through a T_DBG debug entry.
.macro DBG_CMD cmd
    li      a3, \cmd
    addi    s7, s7, 1
    lw      t0, T_DBG(a0)
    li      t1, 200000
8:  beqz    a3, 9f
    addi    t1, t1, -1
    bnez    t1, 8b
    li      gp, 6
    j       fail
9:
.endm

# Book-keeping shared by every case: resume point 1f, the trap cause and debug entries expected.
.macro EXPECT cause, dbg
    .set NCASES, NCASES + 1
    addi    tp, tp, 1
    la      s0, 1f
    li      s6, \cause
  .if \cause
    addi    s2, s2, 1
  .endif
    addi    s7, s7, \dbg
.endm

# The access to TRIG + \off, then \insn. The store before it leaves the access waiting on it in
# ID, by which time \insn has been fetched: \insn is in ID the cycle after the access's grant.
.macro CASE off, cause, dbg, insn:vararg
    EXPECT  \cause, \dbg
    sw      zero, 8(a1)
    lw      t0, (\off)(a0)
    \insn
1:
.endm

# As CASE with c.unimp (0x0000, CompressedIllegal) behind the access, then a c.nop that is never
# reached and keeps the resume point word-aligned.
.macro CASE_CUNIMP off, cause, dbg
    EXPECT  \cause, \dbg
    sw      zero, 8(a1)
    lw      t0, (\off)(a0)
    .hword  0x0000
    .hword  0x0001
1:
.endm

# As CASE with T_NMI: the NMI section F expects (s8 = 1), taken right after \insn leaves ID.
.macro CASE_NMI insn:vararg
    EXPECT  0, 0
    addi    s4, s4, 1
    sw      zero, 8(a1)
    lw      t0, T_NMI(a0)
    \insn
1:
.endm

# As CASE with a load from d_nox0 (locked, no permissions), which PMP blocks: \insn is in its
# first ID cycle when the fault is reported.
.macro CASE_PMP cause, dbg, insn:vararg
    EXPECT  \cause, \dbg
    la      t1, d_nox0
    sw      zero, 8(a1)
    lw      t0, 0(t1)
    \insn
1:
.endm

# Section D attempt (see D above): \pads nops between Q1 and L, then X = \insn. Runs in
# M_SLOW10 and leaves it set for the next attempt.
.macro IF_EMPTY pads, cause, insn:vararg
    EXPECT  \cause, 0
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

# Resumes at s0 in M-mode with mstatus.MIE kept clear (MPP = M, MPIE = 0): section A's ecall
# comes from U-mode with MIE set.
exc_handler:
    csrr    t5, mcause
    li      gp, 11
    beqz    s6, fail
    li      gp, 10
    bne     t5, s6, fail
    addi    s1, s1, 1
    li      s6, 0
    li      t5, MSTATUS_MPP
    csrs    mstatus, t5
    li      t5, MSTATUS_MPIE
    csrc    mstatus, t5
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

# Section A (s8 = 0): taken in U-mode with MIE set (Ibex keeps the interrupted MPP/MPIE in its
# NMI stack and restores them on mret); returns to the interrupted U-mode code.
# Section F (s8 = 1): taken in the cycle after the fence left ID, so mepc is the instruction
# behind it (the resume point); returns there.
nmi_handler:
    csrr    t5, mcause
    li      t6, CAUSE_NMI
    li      gp, 30
    bne     t5, t6, fail
    bnez    s8, nmi_fence
    csrr    t5, mstatus
    li      t6, MSTATUS_MPP
    and     t6, t5, t6
    li      gp, 32
    bnez    t6, fail
    li      t6, MSTATUS_MPIE
    and     t6, t5, t6
    li      gp, 33
    beqz    t6, fail
    addi    s3, s3, 1
    mret

nmi_fence:
    csrr    t5, mepc
    li      gp, 34
    bne     t5, s0, fail
    addi    s3, s3, 1
    mret

# Counts the entry and applies a DBG_CMD command (a3). No ebreak executes in this test, so an
# entry by ebreak (dcsr.cause 1) fails.
dbg_entry:
    csrw    CSR_DSCRATCH0, t3
    csrw    CSR_DSCRATCH1, t4
    addi    s5, s5, 1
    csrr    t3, CSR_DCSR
    srli    t4, t3, 6
    andi    t4, t4, 7
    li      t3, 1
    beq     t4, t3, dbg_ebreak
    li      t4, DCSR_EBREAKM
    bne     a3, t3, 2f
    csrs    CSR_DCSR, t4
2:  li      t3, 2
    bne     a3, t3, 3f
    csrc    CSR_DCSR, t4
3:  li      a3, 0
    csrr    t3, CSR_DSCRATCH0
    csrr    t4, CSR_DSCRATCH1
    dret

dbg_ebreak:
    li      gp, 51
    j       fail

dbg_exception:
    li      gp, 50
    j       fail

#----------------------------------------------------------------------------------------------
RVTEST_RV32M
RVTEST_CODE_BEGIN

  la      t0, mtvec_table
  csrw    mtvec, t0
  # PMP. Entries 0-4: section D's d_nox0/2/4/6/8, NA4, locked, no permissions (fetch errors;
  # section G loads from d_nox0). Entry 5: all memory, NAPOT, RWX, unlocked (M-mode is
  # unrestricted elsewhere; it lets section A's U-mode code fetch and access TRIG). This replaces
  # INIT_PMP's (riscv_test.h) entry 0 over all memory.
  la      t0, d_nox0
  srli    t0, t0, 2
  csrw    pmpaddr0, t0
  la      t0, d_nox2
  srli    t0, t0, 2
  csrw    pmpaddr1, t0
  la      t0, d_nox4
  srli    t0, t0, 2
  csrw    pmpaddr2, t0
  la      t0, d_nox6
  srli    t0, t0, 2
  csrw    pmpaddr3, t0
  la      t0, d_nox8
  srli    t0, t0, 2
  csrw    pmpaddr4, t0
  li      t0, -1
  csrw    pmpaddr5, t0
  li      t0, (0x1F << 8) | 0x90
  csrw    pmpcfg1, t0
  li      t0, (0x90 << 24) | (0x90 << 16) | (0x90 << 8) | 0x90
  csrw    pmpcfg0, t0

  li      s1, 0
  li      s2, 0
  li      s3, 0
  li      s4, 0
  li      s5, 0
  li      s6, 0
  li      s7, 0
  li      s8, 0
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

  # ---- A: an NMI taken in U-mode with mstatus.MIE = 1 ----
  MEM_MODE M_FAST
  MASKED_IRQ_OFF                          # mie = 0: in U-mode only the NMI may be taken
  EXPECT  CAUSE_USER_ECALL, 0
  addi    s4, s4, 1
  la      t0, a_umode
  csrw    mepc, t0
  li      t0, MSTATUS_MPP
  csrc    mstatus, t0                     # MPP = U
  li      t0, MSTATUS_MPIE
  csrs    mstatus, t0                     # MIE = 1 after the mret
  mret
a_umode:
  lw      t1, T_NMI(a0)                   # the NMI from the second cycle after the grant
  .rept 16
  nop
  .endr
  ecall
1:

  # ---- B: c.unimp unstalls on a slow access's response, debug_req and the timer pending ----
  MEM_MODE M_SLOW
  MASKED_IRQ_ON
  CASE_CUNIMP T_DBG, CAUSE_ILLEGAL_INSTRUCTION, 1
  CASE_CUNIMP T_DBG, CAUSE_ILLEGAL_INSTRUCTION, 1
  # (0,0,CSRIllegal,None,1,1,1) and (0,0,Fence,None,1,1,1)
  CASE    T_DBG, CAUSE_ILLEGAL_INSTRUCTION, 1, csrrw t1, CSR_MVENDORID, t0
  CASE    T_DBG, CAUSE_ILLEGAL_INSTRUCTION, 1, csrrw t1, CSR_MVENDORID, t0
  CASE    T_DBG, 0, 1, fence
  CASE    T_DBG, 0, 1, fence
  MASKED_IRQ_OFF

  # ---- C: fence.i in its first ID cycle on a bus error, debug_req and the timer pending ----
  MEM_MODE M_FAST
  MASKED_IRQ_ON
  CASE    T_ERR_DBG, CAUSE_LOAD_ACCESS, 1, fence.i
  CASE    T_ERR_DBG, CAUSE_LOAD_ACCESS, 1, fence.i
  # A store in its one ID cycle as debug_req rises: (0,0,Store,None,0,1,1)
  CASE    T_DBG, 0, 1, sw t1, 4(a1)
  CASE    T_DBG, 0, 1, sw t1, 4(a1)
  MASKED_IRQ_OFF

  # ---- D: X in ID behind a waiting load with IF empty and idle ----
  MEM_MODE M_SLOW10
  MASKED_IRQ_ON                           # every wfi below resumes at once
  # {WFI, EmptyAndIdle, FullAndStalled, FullAndStalled}
  .irp pads, 0, 2, 4, 6, 8
  IF_EMPTY \pads, 0, wfi
  .endr
  # {UncompressedIllegal, EmptyAndIdle, FullAndStalled, FullAndStalled}
  .irp pads, 0, 2, 4, 6, 8
  IF_EMPTY \pads, CAUSE_ILLEGAL_INSTRUCTION, .word 0x0000000b
  .endr
  # {FetchError, EmptyAndIdle, FullAndStalled, FullAndUnstalled}: X is a locked no-permission word
  IF_EMPTY 0, CAUSE_FETCH_ACCESS, d_nox0: nop
  IF_EMPTY 2, CAUSE_FETCH_ACCESS, d_nox2: nop
  IF_EMPTY 4, CAUSE_FETCH_ACCESS, d_nox4: nop
  IF_EMPTY 6, CAUSE_FETCH_ACCESS, d_nox6: nop
  IF_EMPTY 8, CAUSE_FETCH_ACCESS, d_nox8: nop
  MASKED_IRQ_OFF

  # ---- E: a bus error unstalls ebreak (no interrupt) and fence.i (timer pending) ----
  MEM_MODE M_SLOW
  # (0,1,EBreakExc,None,1,0,0)
  CASE    T_ERR, CAUSE_LOAD_ACCESS, 0, ebreak
  CASE    T_ERR, CAUSE_LOAD_ACCESS, 0, ebreak
  # (0,1,FenceI,None,1,1,0)
  MASKED_IRQ_ON
  CASE    T_ERR, CAUSE_LOAD_ACCESS, 0, fence.i
  CASE    T_ERR, CAUSE_LOAD_ACCESS, 0, fence.i
  MASKED_IRQ_OFF

  # ---- F: an NMI taken right after fence unstalls on a slow access: {1, 1, Fence} ----
  li      s8, 1
  CASE_NMI fence
  CASE_NMI fence

  # ---- G: a PMP fault reported with ebreak (EBreakDbg) in ID, debug_req, the timer pending ----
  DBG_CMD 1                               # dcsr.ebreakm: ebreak is EBreakDbg
  MASKED_IRQ_ON
  # (1,0,EBreakDbg,None,0,1,1): +dbg_on_pmp_err_pct=100 raises debug_req at the report
  CASE_PMP CAUSE_LOAD_ACCESS, 1, ebreak
  CASE_PMP CAUSE_LOAD_ACCESS, 1, ebreak
  MASKED_IRQ_OFF
  DBG_CMD 2
  MEM_MODE 0

  # ---- Totals ----
  li      gp, 40
  bne     s1, s2, fail
  li      gp, 41
  bne     s3, s4, fail
  li      gp, 42
  bne     s5, s7, fail
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
