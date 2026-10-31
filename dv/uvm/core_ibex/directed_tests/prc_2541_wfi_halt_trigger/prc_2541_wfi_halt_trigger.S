# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Test: prc_2541_wfi_halt_trigger -- a halt request that wakes the core from WFI, with an execute
#                                     trigger on the instruction after the WFI
#                                     (lowRISC/ibex PR #2541, the case added on 2026-10-30)
#
# The trigger compares the IF-stage PC. When a halt request wakes the core from WFI, the
# instruction after the WFI is already in IF, so its trigger "matches" although that instruction
# has not been attempted. PR #2541 reports dcsr.cause = HALTREQ (3) there, not TRIGGER (2); the
# trigger must still fire once the core resumes at that instruction. Our fork carries an earlier
# version of the PR that keeps the trigger first unless the core is stepping or flushing.
#
# rtl_test core_ibex_debug_wfi_test: after the riscv-dv set-up handshake (mstatus, mie,
# INITIALIZED) it sends a halt request each time the core sleeps, then expects IN_DEBUG_MODE and a
# dcsr signature with prv = the initial MPP (M here) and cause HALTREQ, then a dret.
# Trigger registers can only be written in debug mode (tdata1.dmode = 1), so the first sleep is
# used to set the trigger up:
#   1. wfi1: halt (cause HALTREQ, code 2); set an execute trigger on after_wfi2; dret.
#   2. wfi2: halt; the PR's claim: cause HALTREQ (code 3) and dpc = after_wfi2 (code 4); dret.
#   3. Resuming at after_wfi2, the trigger fires: cause TRIGGER (code 5), dpc = after_wfi2
#      (code 6); clear the trigger, dpc := done, dret.
#   4. done: phase must be 4 (code 7).
# Failure: TEST_FAIL with TESTNUM (gp) as above; 1 = a wfi was passed without the expected debug
#   entry; 8 = wrong phase after wfi1; 9 = unexpected debug entry; 0x100|code = unexpected trap.

#include "riscv_test.h"
#include "test_macros.h"

#define DBG_CAUSE_TRIGGER 2
#define DBG_CAUSE_HALTREQ 3
# The bench reads core status and CSR signatures at +signature_addr, 4 bytes above SIGNATURE_ADDR.
#define SIG_ADDR (SIGNATURE_ADDR + 4)

.macro SIG_CSR csr
  li   t0, SIG_ADDR
  li   t1, ((\csr) << 8) | WRITE_CSR
  sw   t1, 0(t0)
  csrr t1, \csr
  sw   t1, 0(t0)
.endm

.macro SIG_ST st
  li   t0, SIG_ADDR
  li   t1, ((\st) << 8) | CORE_STATUS
  sw   t1, 0(t0)
.endm

.macro SET_PHASE n
  la   t0, phase
  li   t1, \n
  sw   t1, 0(t0)
.endm

# DmHaltAddr is the start of .text.init and DmExceptionAddr 8 bytes later. The reset code of
# RVTEST_CODE_BEGIN starts at offset 0x80.
  .section .text.init
  .option push
  .option norvc
  j    debug_entry
  nop
  j    fail
  .option pop

RVTEST_RV32M
RVTEST_CODE_BEGIN

  # No interrupts: each wfi waits for the bench's halt request.
  csrw mie, zero
  csrci mstatus, MSTATUS_MIE
  li   t0, MSTATUS_MPP
  csrs mstatus, t0                 # MPP = M: the bench expects dcsr.prv = M
  SIG_CSR 0x300                    # mstatus
  SIG_CSR 0x304                    # mie
  SET_PHASE 1
  SIG_ST INITIALIZED

  li   TESTNUM, 1
  .balign 4
  .option push
  .option norvc
  wfi                              # wfi1
  li   TESTNUM, 8
  la   t0, phase
  lw   t0, 0(t0)
  li   t1, 2
  bne  t0, t1, fail
  li   TESTNUM, 1
  wfi                              # wfi2
after_wfi2:
  j    fail                        # reached only if no debug entry happened here
  .option pop

done:
  li   TESTNUM, 7
  la   t0, phase
  lw   t0, 0(t0)
  li   t1, 4
  bne  t0, t1, fail
  li   TESTNUM, 99
  j    pass

  TEST_PASSFAIL

.balign 4
mtvec_handler:
  ori  TESTNUM, TESTNUM, 0x100
  j    fail

debug_entry:
  csrw dscratch0, t0
  csrw dscratch1, t1
  la   t0, phase
  lw   t0, 0(t0)
  li   t1, 1
  beq  t0, t1, debug_wfi1
  li   t1, 2
  beq  t0, t1, debug_wfi2
  li   t1, 3
  beq  t0, t1, debug_trigger
  li   TESTNUM, 9
  j    fail

debug_wfi1:
  SIG_ST IN_DEBUG_MODE
  SIG_CSR 0x7b0                    # dcsr
  li   TESTNUM, 2
  csrr t0, dcsr
  srli t0, t0, 6
  andi t0, t0, 7
  li   t1, DBG_CAUSE_HALTREQ
  bne  t0, t1, fail
  # Execute trigger on after_wfi2 (tdata1 last, as the debug spec says).
  csrwi tselect, 0
  csrw tdata1, zero
  la   t0, after_wfi2
  csrw tdata2, t0
  csrwi tdata1, 5
  li   t0, 2
  j    debug_set_phase

debug_wfi2:
  SIG_ST IN_DEBUG_MODE
  SIG_CSR 0x7b0                    # dcsr
  li   TESTNUM, 3
  csrr t0, dcsr
  srli t0, t0, 6
  andi t0, t0, 7
  li   t1, DBG_CAUSE_HALTREQ
  bne  t0, t1, fail
  li   TESTNUM, 4
  csrr t0, dpc
  la   t1, after_wfi2
  bne  t0, t1, fail
  li   t0, 3
  j    debug_set_phase

debug_trigger:
  li   TESTNUM, 5
  csrr t0, dcsr
  srli t0, t0, 6
  andi t0, t0, 7
  li   t1, DBG_CAUSE_TRIGGER
  bne  t0, t1, fail
  li   TESTNUM, 6
  csrr t0, dpc
  la   t1, after_wfi2
  bne  t0, t1, fail
  csrw tdata1, zero
  la   t0, done
  csrw dpc, t0
  li   t0, 4

debug_set_phase:
  la   t1, phase
  sw   t0, 0(t1)
  csrr t0, dscratch0
  csrr t1, dscratch1
  dret

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
phase:
  .word 0
RVTEST_DATA_END
