# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Load/store faults and slow accesses with each instruction category behind them, for the
# timing-dependent bins of uarch_cg: exception_stall_instr_cross (PMP fault, bus error or a plain
# access, crossed with the category and stall of the instruction in ID, a pending interrupt and a
# debug request), stall_cross, pipe_cross, pipe_flush_instr_cross, debug_entry_if_instr_cross,
# interrupt_taken_instr_cross and irq_wfi_cross. RISC-V mode, Spike cosim on.
#
# Runs under rtl_test core_ibex_stall_events_test, which raises the debug requests, NMIs, the timer
# interrupt and the fetch-enable drops at the pipeline events these bins need; see the testlist
# entry for its plusargs. The program requires three of them, and without them:
#   +dside_bus_err_lo/hi covering BUS_ERR_ADDR: the bus passes read uninitialised memory instead of
#         trapping. The first load's response carries bad integrity (the bench's alert check fails
#         on alert_major_bus; Ibex's internal NMI then reaches nmi_handler with an mcause that is
#         not CAUSE_NMI, gp 30), or the garbage reaches the jalr through the loaded address, gp 10.
#         Not gp 40/41: the trap-count checks come last.
#   +irq_timer_on_wfi=1: the first wfi sleeps for good with ID flushed, where no other trigger
#         fires, so the run ends in the simulation timeout, not in a fail code.
#   +dbg_req_on_write=DOORBELL: EBREAKM_REQ waits for a debug entry that never comes, gp 6 --
#         unless another trigger enters debug mode during the wait, which serves the request.
#
# Each case is
#     <set up: s0 = resume point, s3 = the access, s4 = the instruction under test>
#   2: <lw or sw of t0 at a0>          the access
#   3: <instruction under test>
#   1:
# and every case runs in three kinds of pass:
#   PMP   a0 = pmp_buf, a locked PMP entry with no permissions: the access faults (mcause 5 / 7).
#   BUS   a0 = BUS_ERR_ADDR, inside the d-side bus-error window: the access faults (mcause 5 / 7).
#   OK    a0 = ok_word: the access completes (after a random response delay) and the instruction
#         under test executes. Where it traps by itself the handler expects its own cause.
# The fetch-error cases put the access right before a word a locked PMP entry makes
# non-executable: a nop (CASE_FE, FetchError with no stall) or a load (CASE_FEL, FetchError with a
# Mem stall, exception_stall_instr_cross {pmp / err, FetchError, Mem}).
# In the fault passes the fault flushes the instruction under test, which never executes; the
# handler checks mcause, that mepc is the access (precise) and mtval its address, and resumes at s0.
# In the OK passes it checks the cause the instruction raises and that mepc is that instruction.
#
# The sweep (OK, PMP, BUS, PMP: the second PMP pass finds the code in the icache) runs with:
#   icache off, data-independent timing off and on (DIT: branches always stall a cycle);
#   icache on; with a masked pending timer interrupt (mie.MTIE = 1, mstatus.MIE = 0 -- the
#   interrupt is pending in uarch_cg.cp_irq_pending without halting IF), DIT off and on;
#   and with dcsr.ebreakm set (ebreak is EBreakDbg), without and with the masked interrupt.
#
# Debug: the halt and exception addresses (BOOT_ADDR + 0 / + 8) jump to dbg_entry and
# dbg_exception. dbg_entry counts entries, steps over an ebreak that entered debug mode (dcsr.cause
# 1, dcsr.ebreakm), applies a request from the program (a3: 1 sets dcsr.ebreakm, 2 clears it) and
# ends with `lw s10, 0(s9); dret`, so the dret waits in ID for the load (DRet stalls). In the fault
# passes s9 is the faulting target: that load faults in debug mode and must enter dbg_exception
# exactly once per entry (the debug exception address, no M-mode trap), never otherwise. The
# handler reads no program register but s9, and takes s9 = 0 (an entry during start-up, before
# the program has set it) as the OK target, so an entry at any point is harmless.
#
# Interrupts: the program first executes wfi with mie.MTIE and mstatus.MIE set and a store in
# flight; the bench raises irq_timer_i while the wfi is in ID and holds it to the end. Exactly one
# timer interrupt must be taken, with mepc after the wfi; the handler then clears mie.MTIE. A wfi
# with mie.MTIE set, mstatus.MIE clear and the timer pending must not sleep and not trap. An NMI
# (the bench raises one two cycles after a trap's FLUSH) is taken before the exception handler has
# done anything but read mcause/mepc; the NMI handler abandons that handler and resumes the case.
#
# Fail codes (gp):
#   2/3   no timer interrupt at the first wfi / not exactly one
#   5     mip.MTIP not pending where mie.MTIE is set (the bench did not hold irq_timer_i)
#   6     no debug entry within the doorbell timeout (+dbg_req_on_write missing or not served)
#   10-12 fault pass: mcause not 5/7 as the access / mepc not the access / mtval not its address
#   13-15 OK pass: mcause not the instruction's / mepc not the instruction / mtval of a fetch fault
#   20-22 timer interrupt: wrong mcause / outside the wfi handshake / mepc not after the wfi
#   30/31 NMI: wrong mcause / not taken at the exception handler's entry
#   40    expected-trap count differs from the static total (a case was skipped or repeated)
#   41    traps taken != traps expected
#   42/43 ebreak debug entries: not 4 expected / not 4 taken
#   44    debug exceptions != debug entries during fault passes
#   45/46 no debug entry beyond the 6 the program causes itself (2 doorbell, 4 ebreak) / none
#         beyond the 2 doorbell entries during a fault pass: the bench's triggers produced no entry
#         (core_ibex_stall_events_test::report_phase also reports a trigger that never fired)

#include "riscv_test.h"
#include "test_macros.h"

    .option norvc
    .option norelax

#define BUS_ERR_ADDR  0x80100000          /* +dside_bus_err_lo/hi must cover this word */
#define DOORBELL      0x80100100          /* +dbg_req_on_write=80100100 */
#define CAUSE_NMI     0x8000001f
#define CAUSE_TIMER   0x80000007
#define F_MASKED      2                   /* s7: masked pending timer interrupt in this pass */
#define F_EBREAKM     4                   /* s7: dcsr.ebreakm is set in this pass */

# Registers
#   s0 resume point   s1 traps taken     s2 traps expected  s3 the access  s4 the instruction
#   s5 the access's fault cause (5 / 7)  s6 pass kind (0 fault, 1 OK)       s7 flags (F_*)
#   s8 debug exceptions  s9 debug handler's load address  s10 its destination  s11 debug entries
#   a0 access target  a1 ok_buf  a2 cause of the instruction (OK pass)  a3 debug request
#   a4 ebreak debug entries  a5 expected ones  a6 timer interrupt expected  a7 timer interrupts
#   tp debug exceptions expected  t2 = 3  t0/t1 cases  t3/t4 debug handler  t5/t6 trap handlers

    .set NCASES, 0                        # cases in one sweep of run_cases
    .set NTRAP_OK, 0                      # of those, the ones that trap in an OK pass

# Shared set-up of a case. \cause: what the instruction raises when it executes (0 = nothing).
.macro CASE_HEAD cause
    .set NCASES, NCASES + 1
  .if \cause
    .set NTRAP_OK, NTRAP_OK + 1
  .endif
    la      s0, 1f
    li      a2, \cause
    la      t0, 1f                        # a code address: the OK-pass access stores it and
    beqz    s6, 4f                        # reads it back (jalr target, load address)
    sw      t0, 0(a0)
  .if \cause == 0
    addi    s2, s2, -1                    # OK pass and the instruction does not trap
  .endif
4:  addi    s2, s2, 1
.endm

.macro CASE acc, cause, insn:vararg
    la      s3, 2f
    la      s4, 3f
    CASE_HEAD \cause
2:  \acc    t0, 0(a0)
3:  \insn
1:
.endm

# ebreak: with dcsr.ebreakm set it enters debug mode in an OK pass instead of trapping.
.macro CASE_EBREAK acc
    la      s3, 2f
    la      s4, 3f
    CASE_HEAD 3
    andi    t1, s7, F_EBREAKM
    beqz    s6, 5f
    beqz    t1, 5f
    addi    s2, s2, -1
    addi    a5, a5, 1
5:
2:  \acc    t0, 0(a0)
3:  ebreak
1:
.endm

# mret: in an OK pass it returns to the resume point in M-mode with MIE still clear.
.macro CASE_MRET acc
    li      t1, MSTATUS_MPP
    csrs    mstatus, t1
    li      t1, MSTATUS_MPIE
    csrc    mstatus, t1
    la      t1, 1f
    csrw    mepc, t1
    CASE acc=\acc, cause=0, insn=mret
.endm

# wfi: skipped in an OK pass without the masked pending interrupt (it would sleep for good).
.macro CASE_WFI acc
    andi    t1, s7, F_MASKED
    beqz    s6, 6f
    beqz    t1, 7f
6:
    CASE acc=\acc, cause=0, insn=wfi
7:
.endm

# Fetch error: the access is followed by a word a locked PMP entry makes non-executable.
.macro CASE_FE acc
    la      s3, fe_\acc
    la      s4, fe_\acc\()_nox
    CASE_HEAD CAUSE_FETCH_ACCESS
    j       fe_\acc
1:
.endm

# The same with a non-executable word that holds a load (fel_*): the PMP check is on the
# instruction's pc in IF (ibex_core.sv pmp_req_addr[PMP_I] = pc_if), so the fetch itself returns
# the word and ID decodes it, fetch error and all. lsu_req_dec is then set, the access is never
# made (instr_kill), and stall_mem holds (ibex_id_stage.sv) -- FetchError with a Mem stall, in
# the cycle the access's PMP fault or bus error is reported. A nop there (CASE_FE) is FetchError
# with no stall.
.macro CASE_FEL acc
    la      s3, fel_\acc
    la      s4, fel_\acc\()_nox
    CASE_HEAD CAUSE_FETCH_ACCESS
    j       fel_\acc
1:
.endm

.macro ALL_CASES acc
    CASE \acc, 0, add    t1, t0, t0       # ALU, depends on the access (load hazard)
    CASE \acc, 0, add    t1, t2, t2       # ALU, independent
    CASE \acc, 0, mul    t1, t0, t2       # Mul
    CASE \acc, 0, mul    t1, t2, t2
    CASE \acc, 0, div    t1, t0, t2       # Div
    CASE \acc, 0, div    t1, t2, t2
    CASE \acc, 0, beq    t0, t2, 1f       # Branch
    CASE \acc, 0, beq    t2, t2, 1f
    CASE \acc, 0, jalr   x0, 0(s0)        # Jump (to the resume point)
    CASE \acc, 0, jalr   x0, 0(t0)        # Jump through the loaded address (load hazard)
    CASE \acc, 0, jal    x0, 1f
    CASE \acc, 0, lw     t1, 0(t0)        # Load (address from the access)
    CASE \acc, 0, lw     t1, 4(a1)        # Load, independent, readable
    CASE \acc, 0, sw     t0, 4(a1)        # Store
    CASE \acc, 0, csrw   mscratch, t0     # CSR access
    CASE \acc, 0, csrr   t1, mscratch
    CASE \acc, 0, fence
    CASE \acc, 0, fence.i
    CASE \acc, CAUSE_MACHINE_ECALL, ecall
    CASE_EBREAK \acc
    CASE_MRET \acc
    CASE_WFI \acc
    CASE \acc, CAUSE_ILLEGAL_INSTRUCTION, .word 0x00000000    # c.unimp: compressed illegal
    CASE \acc, CAUSE_ILLEGAL_INSTRUCTION, .word 0x0000000b    # custom-0: uncompressed illegal
    CASE \acc, CAUSE_ILLEGAL_INSTRUCTION, csrrw t1, CSR_MVENDORID, t0  # write to a read-only CSR
    CASE \acc, CAUSE_ILLEGAL_INSTRUCTION, csrr t1, CSR_DCSR    # dcsr outside debug mode
    CASE_FE \acc
    CASE_FEL \acc
.endm

.macro PASS_OK flags
    la      a0, ok_word
    li      s6, 1
    li      s7, \flags
    addi    s9, a1, 8
    jal     ra, run_cases
.endm

# Fault passes: s9 is set to the faulting target first, so a debug entry at any point sees either
# the previous pass's (OK) target or this one, and counts its own expectation from s9 (dbg_entry).
.macro PASS_PMP flags
    la      a0, pmp_buf
    li      s6, 0
    li      s7, \flags
    mv      s9, a0
    jal     ra, run_cases
.endm

.macro PASS_BUS flags
    li      a0, BUS_ERR_ADDR
    li      s6, 0
    li      s7, \flags
    mv      s9, a0
    jal     ra, run_cases
.endm

.macro SWEEP flags
    PASS_OK  \flags
    PASS_PMP \flags
    PASS_BUS \flags
    PASS_PMP \flags
.endm

# Set (1) or clear (2) dcsr.ebreakm: ring the doorbell and wait for the debug handler to take it.
.macro EBREAKM_REQ cmd
    li      a3, \cmd
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

#----------------------------------------------------------------------------------------------
# Debug halt / exception addresses: DEBUG_MODE_HALT_ADDR = BOOT_ADDR, _EXCEPTION_ADDR = + 8.
    .section .text.init
    j       dbg_entry
    nop
    j       dbg_exception

#----------------------------------------------------------------------------------------------
    .text

# One sweep of every case, first behind a lw (fault cause 5), then behind a sw (7).
run_cases:
    li      s5, CAUSE_LOAD_ACCESS
    ALL_CASES lw
    li      s5, CAUSE_STORE_ACCESS
    ALL_CASES sw
    ret

# The fetch-error cases' access and the non-executable word after it, each word in its own
# 64-bit icache line: PMP entries 1 and 2 (NA4, locked, no permissions) cover the _nox words.
    .balign 16
    nop
fe_lw:
    lw      t0, 0(a0)
fe_lw_nox:
    nop
    .balign 16
    nop
fe_sw:
    sw      t0, 0(a0)
fe_sw_nox:
    nop
# CASE_FEL: as above, PMP entries 3 and 4. The load reads a1, never the access's t0, so it has
# no load hazard on it: its stall is Mem alone.
    .balign 16
    nop
fel_lw:
    lw      t0, 0(a0)
fel_lw_nox:
    lw      t1, 4(a1)
    .balign 16
    nop
fel_sw:
    sw      t0, 0(a0)
fel_sw_nox:
    lw      t1, 4(a1)

# mtvec (vectored, as Ibex forces): exceptions at +0, the machine timer at +0x1c, NMIs at +0x7c.
# The first three words only read: an NMI taken there abandons them (nmi_handler).
    .balign 256
mtvec_table:
    csrr    t5, mcause
    csrr    t6, mepc
    j       exc_handler
    .org    mtvec_table + 0x1c
    j       timer_handler
    .org    mtvec_table + 0x7c
    j       nmi_handler

exc_handler:
    bnez    s6, 2f
    # Fault pass: the access faulted (load / store access fault), precisely.
    li      gp, 10
    bne     t5, s5, fail
    li      gp, 11
    bne     t6, s3, fail
    csrr    t6, mtval
    li      gp, 12
    bne     t6, a0, fail
    j       9f
2:  # OK pass: the instruction under test trapped by itself.
    li      gp, 13
    bne     t5, a2, fail
    li      gp, 14
    bne     t6, s4, fail
    li      t5, CAUSE_FETCH_ACCESS
    bne     a2, t5, 9f
    csrr    t6, mtval
    li      gp, 15
    bne     t6, s4, fail
9:  addi    s1, s1, 1
    csrw    mepc, s0
    mret

timer_handler:
    csrr    t5, mcause
    li      t6, CAUSE_TIMER
    li      gp, 20
    bne     t5, t6, fail
    li      gp, 21
    beqz    a6, fail
    csrr    t5, mepc
    la      t6, wfi_resume
    li      gp, 22
    bne     t5, t6, fail
    li      t5, MIP_MTIP
    csrc    mie, t5                       # irq_timer_i stays high from now on
    li      a6, 0
    addi    a7, a7, 1
    mret

nmi_handler:
    csrr    t5, mcause
    li      t6, CAUSE_NMI
    li      gp, 30
    bne     t5, t6, fail
    csrr    t5, mepc
    la      t6, mtvec_table
    bltu    t5, t6, 1f
    addi    t6, t6, 12
    bltu    t5, t6, 2f                    # at mtvec_table + 0 .. + 8
1:  la      t6, exc_handler
    li      gp, 31
    bltu    t5, t6, fail
    addi    t6, t6, 8
    bgeu    t5, t6, fail                  # nor at exc_handler + 0 / + 4
2:  addi    s1, s1, 1                     # the abandoned trap was the case's
    csrw    mepc, s0
    mret

dbg_entry:
    csrw    CSR_DSCRATCH0, t3
    csrw    CSR_DSCRATCH1, t4
    addi    s11, s11, 1
    csrr    t3, CSR_DCSR
    srli    t4, t3, 6
    andi    t4, t4, 7
    li      t3, 1
    bne     t4, t3, 1f
    csrr    t4, CSR_DPC                   # entered by ebreak (dcsr.ebreakm): resume after it
    addi    t4, t4, 4
    csrw    CSR_DPC, t4
    addi    a4, a4, 1
1:  li      t4, DCSR_EBREAKM
    li      t3, 1
    bne     a3, t3, 2f
    csrs    CSR_DCSR, t4
2:  li      t3, 2
    bne     a3, t3, 3f
    csrc    CSR_DCSR, t4
3:  li      a3, 0
    # The handler uses no program register: an entry during start-up, before the program has set
    # s9 (zero from INIT_XREG), loads the OK target instead of address 0 (uninitialised memory,
    # whose response carries bad integrity).
    bnez    s9, 4f
    la      s9, ok_buf + 8
4:  la      t3, ok_buf + 8
    beq     s9, t3, 5f
    addi    tp, tp, 1                     # the load below faults
5:  csrr    t3, CSR_DSCRATCH0
    csrr    t4, CSR_DSCRATCH1
    lw      s10, 0(s9)
    dret

dbg_exception:
    addi    s8, s8, 1
    dret

#----------------------------------------------------------------------------------------------
RVTEST_RV32M
RVTEST_CODE_BEGIN

  la      t0, mtvec_table
  csrw    mtvec, t0

  # PMP. Entry 0: pmp_buf (32 bytes), NAPOT, locked, no permissions. Entries 1-4: fe_lw_nox /
  # fe_sw_nox / fel_lw_nox / fel_sw_nox, NA4, locked, no permissions (not executable). Entry 5:
  # all memory, NAPOT, RWX.
  li      t0, -1
  csrw    pmpaddr5, t0
  la      t0, fe_lw_nox
  srli    t0, t0, 2
  csrw    pmpaddr1, t0
  la      t0, fe_sw_nox
  srli    t0, t0, 2
  csrw    pmpaddr2, t0
  la      t0, fel_lw_nox
  srli    t0, t0, 2
  csrw    pmpaddr3, t0
  la      t0, fel_sw_nox
  srli    t0, t0, 2
  csrw    pmpaddr4, t0
  la      t0, pmp_buf
  srli    t0, t0, 2
  ori     t0, t0, 0x3                     # NAPOT 32 bytes: ...011
  csrw    pmpaddr0, t0
  li      t0, (0x1F << 8) | 0x90
  csrw    pmpcfg1, t0
  li      t0, (0x90 << 24) | (0x90 << 16) | (0x90 << 8) | 0x98
  csrw    pmpcfg0, t0

  li      s1, 0
  li      s2, 0
  li      s7, 0
  li      s8, 0
  li      s11, 0
  li      tp, 0
  li      a3, 0
  li      a4, 0
  li      a5, 0
  li      a7, 0
  li      t2, 3
  la      a1, ok_buf
  addi    s9, a1, 8

  # Timer interrupt that arrives while the wfi is in ID (irq_wfi_cross, mstatus.MIE = 1).
  li      a6, 1
  li      t0, MIP_MTIP
  csrs    mie, t0
  csrsi   mstatus, MSTATUS_MIE
  sw      t0, 12(a1)                      # in flight: the wfi waits in DECODE for its response
  wfi
wfi_resume:
  csrci   mstatus, MSTATUS_MIE
  li      gp, 2
  bnez    a6, fail
  li      gp, 3
  li      t0, 1
  bne     a7, t0, fail

  # wfi with the timer pending and enabled in mie but mstatus.MIE clear (irq_wfi_cross,
  # mstatus.MIE = 0): resumes at once, no trap.
  MASKED_IRQ_ON
  wfi
  MASKED_IRQ_OFF

  # Icache off, DIT off then on.
  SWEEP   0
  csrsi   0x7c0, 2
  SWEEP   0
  csrci   0x7c0, 2

  # Icache on.
  csrsi   0x7c0, 1
  SWEEP   0
  MASKED_IRQ_ON
  SWEEP   F_MASKED
  csrsi   0x7c0, 2
  SWEEP   F_MASKED
  csrci   0x7c0, 2
  MASKED_IRQ_OFF

  # dcsr.ebreakm set: ebreak is EBreakDbg.
  EBREAKM_REQ 1
  SWEEP   F_EBREAKM
  MASKED_IRQ_ON
  SWEEP   F_EBREAKM | F_MASKED
  MASKED_IRQ_OFF
  EBREAKM_REQ 2
  csrci   0x7c0, 1

  # 7 sweeps; each has three fault passes (every case traps) and one OK pass (NTRAP_OK trap, less
  # the two ebreaks in the two sweeps with dcsr.ebreakm: those enter debug mode).
  li      t0, 7 * 3 * NCASES + 7 * NTRAP_OK - 2 * 2
  li      gp, 40
  bne     s2, t0, fail
  li      gp, 41
  bne     s1, s2, fail
  li      t0, 2 * 2
  li      gp, 42
  bne     a5, t0, fail
  li      gp, 43
  bne     a4, a5, fail
  li      gp, 44
  bne     s8, tp, fail
  # Debug entries the program causes itself: the two doorbell entries (EBREAKM_REQ, each after a
  # PMP pass, so s9 = pmp_buf and the handler's load faults: tp counts them) and the four ebreak
  # entries (OK passes, s9 = ok_buf + 8). Only entries above these came from the bench's triggers.
  li      t0, 2 + 2 * 2
  li      gp, 45
  bgeu    t0, s11, fail
  li      t0, 2
  li      gp, 46
  bgeu    t0, tp, fail
  j       pass

  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
  .balign 32
pmp_buf:
  .zero 32
ok_buf:
  .zero 16
ok_word:
  .zero 4
RVTEST_DATA_END
