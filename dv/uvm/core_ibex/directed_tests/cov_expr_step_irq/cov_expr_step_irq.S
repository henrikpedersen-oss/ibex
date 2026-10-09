# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cov_expr_step_irq -- a single step with an enabled interrupt pending
# =============================================================================
# RISC-V mode (cheriot_enable_i Off), Spike cosim on. rtl_test core_ibex_stall_events_test:
#   +irq_timer_on_wfi=1        raises irq_timer_i when the program's wfi is in ID and holds it;
#   +dbg_req_on_write=DOORBELL raises debug_req_i (until debug mode) on a store to DOORBELL.
#
# Expression-coverage target (merged regression after UNR, 2026-10-09):
#   ibex_core.sv (RVFI capture for the cosim)
#     `captured_taken <= (id_stage_i.controller_i.ctrl_fsm_cs == DBG_TAKEN_IF) & debug_req_i`,
#     row DBG_TAKEN_IF = 1, debug_req_i = 0: the interrupt state is first captured in the cycle
#     the controller enters debug mode for a reason other than debug_req_i. Here that is the end
#     of a single step whose stepped instruction is `csrsi mstatus, MIE` with the timer interrupt
#     pending (masked by the step: dcsr.stepie = 0). The CSR write is a pipeline flush, so the
#     instruction stays in ID through FLUSH and ID first empties in DBG_TAKEN_IF, the first cycle
#     with an enabled interrupt and an empty ID. (Had MIE been set before the step, the capture
#     would happen in DECODE as soon as the stepped instruction left ID.) No regression test
#     single-steps with an interrupt becoming enabled.
#
# Expected behaviour (RISC-V Debug Spec 0.13.2, dcsr.step / stepie; Privileged ISA):
#   - with dcsr.step = 1 and stepie = 0, dret (to dpc = step_target, set by the handler) executes
#     exactly one instruction with interrupts disabled, then re-enters debug mode with
#     dcsr.cause = 4 (step) and dpc = the next instruction (step_next);
#   - after the next dret with step = 0, the pending timer interrupt (mie.MTIE, and mstatus.MIE
#     set by the stepped instruction) is taken at once: mcause = 0x80000007, mepc = step_next;
#   - exactly two debug entries (haltreq, cause 3; step, cause 4) and one timer interrupt.
# Ibex hardwires dcsr.stepie to 0 and takes no interrupt while dcsr.step is set outside debug mode
# (ibex_controller.sv handle_irq). The cosim Spike has no stepie: processor_t::step() takes a
# pending interrupt before it enters debug mode for a completed step, so without the matching
# spike_cosim.cc change (hide pending interrupts from Spike while it single-steps) it enters the
# timer handler and then debug mode there: "Synchronous trap was expected at ISS PC: 80000000"
# at the step's debug entry (seeds 28607/28608, 2026-10-09). Any other cosim mismatch points at
# the RVFI interrupt capture; re-run with +disable_cosim=1 to see the program's own checks.
#
# Failure: TEST_FAIL with TESTNUM (gp):
#   1  mip.MTIP not pending after the wfi (the bench did not raise irq_timer_i)
#   2  no debug entry for the doorbell (timeout)      3  debug entries != 2
#   11 dpc at the step entry is not step_next
#   4  last dcsr.cause not 4 (step)                   5  timer interrupts != 1
#   6  timer mepc != dpc of the step entry            7  timer mcause wrong
#   8  an exception (mtvec + 0)      9  unexpected dcsr.cause      10  debug exception

#include "riscv_test.h"
#include "test_macros.h"

#define DOORBELL      0x80100100          /* +dbg_req_on_write=80100100 */
#define CAUSE_TIMER   0x80000007

# Registers: s9 debug entries, s10 last dcsr.cause, s11 dpc at the step entry, a6 timer interrupts,
#   s8 the timer interrupt's mepc, s7 its mcause. t3/t4 are the debug handler's (via dscratch).

  .option norvc
  .option norelax

# Debug halt / exception addresses: DEBUG_MODE_HALT_ADDR = BOOT_ADDR, _EXCEPTION_ADDR = + 8.
  .section .text.init
  j     dbg_entry
  nop
  j     dbg_exception

  .text
  .balign 256
mtvec_table:
  li    TESTNUM, 8
  j     fail
  .org  mtvec_table + 0x1c
  j     timer_handler

timer_handler:
  csrr  s7, mcause
  csrr  s8, mepc
  addi  a6, a6, 1
  li    t5, MIP_MTIP
  csrc  mie, t5                     # irq_timer_i stays high from now on
  mret

dbg_entry:
  csrw  CSR_DSCRATCH0, t3
  csrw  CSR_DSCRATCH1, t4
  addi  s9, s9, 1
  csrr  t3, CSR_DCSR
  srli  t4, t3, 6
  andi  t4, t4, 7
  mv    s10, t4
  li    t3, 3
  bne   t4, t3, 1f
  # haltreq: arm a single step of the instruction at step_target.
  csrsi CSR_DCSR, DCSR_STEP
  la    t3, step_target
  csrw  CSR_DPC, t3
  j     9f
1:li    t3, 4
  bne   t4, t3, 8f
  # step: disarm, remember where the hart resumes.
  csrci CSR_DCSR, DCSR_STEP
  csrr  s11, CSR_DPC
  j     9f
8:li    TESTNUM, 9
  j     fail
9:csrr  t3, CSR_DSCRATCH0
  csrr  t4, CSR_DSCRATCH1
  dret

dbg_exception:
  li    TESTNUM, 10
  j     fail

RVTEST_RV32M
RVTEST_CODE_BEGIN

  la    t0, mtvec_table
  csrw  mtvec, t0
  li    s9, 0
  li    a6, 0

  # Timer pending and enabled in mie, masked by mstatus.MIE: the wfi wakes without a trap.
  li    t0, MIP_MTIP
  csrs  mie, t0
  csrci mstatus, MSTATUS_MIE
  wfi
  li    TESTNUM, 1
  csrr  t1, mip
  and   t1, t1, t0
  beqz  t1, fail

  # Doorbell: the haltreq session arms the step and resumes at step_target; the stepped
  # instruction enables interrupts; the step session disarms; then the timer interrupt.
  li    TESTNUM, 2
  li    t0, DOORBELL
  sw    zero, 0(t0)
  li    t2, 200000
2:addi  t2, t2, -1
  bnez  t2, 2b
  j     fail                        # the debug handler never redirected to step_target

step_target:
  csrsi mstatus, MSTATUS_MIE        # the stepped instruction
step_next:
  nop                               # the timer interrupt is taken here (mepc = step_next)
  nop
  nop
  nop
  csrci mstatus, MSTATUS_MIE
  li    TESTNUM, 11
  la    t1, step_next
  bne   s11, t1, fail
  li    TESTNUM, 3
  li    t1, 2
  bne   s9, t1, fail
  li    TESTNUM, 4
  li    t1, 4
  bne   s10, t1, fail
  li    TESTNUM, 5
  li    t1, 1
  bne   a6, t1, fail
  li    TESTNUM, 6
  bne   s8, s11, fail
  li    TESTNUM, 7
  li    t1, CAUSE_TIMER
  bne   s7, t1, fail

  li    TESTNUM, 1
  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
