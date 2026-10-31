# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Test: prc_2487_dret_sync_exc -- cpuctrlsts.sync_exc_seen after a debugger abandons a handler
#                                  (lowRISC/ibex PR #2487)
#
# Ibex sets cpuctrlsts.sync_exc_seen (bit 6) on every synchronous exception and clears it on
# mret; a synchronous exception while it is set is a double fault (cpuctrlsts.double_fault_seen,
# bit 7, and the double_fault_seen_o pulse). doc/03_reference/exception_interrupts.rst.
# PR #2487 also clears it on dret, for the case where a debugger halts inside a handler and
# resumes somewhere else, never returning through mret: without the change the next, unrelated
# exception is reported as a double fault.
#
# Sequence:
#   1. An illegal instruction traps. In the handler, sync_exc_seen must read 1 (documented, both
#      versions). The handler reports INITIALIZED and spins; the bench
#      (core_ibex_debug_halt_once_test) sends one halt request.
#   2. In debug mode: dcsr.cause = HALTREQ; dpc := resume (the handler is abandoned); dret.
#   3. At resume, the PR's claim: sync_exc_seen reads 0 (code 10). Without the PR it reads 1.
#   4. A benign ecall: its handler must see double_fault_seen = 0 (code 11), then returns.
#
# Failure: TEST_FAIL with TESTNUM (gp) =
#   1  the illegal instruction did not trap        2  sync_exc_seen not set in the handler
#   3  no halt request arrived                     4  wrong dcsr.cause in debug mode
#   10 sync_exc_seen still set after dret (no PR)  11 the later ecall was a double fault
#   12 ecall: wrong mcause                         13 ecall handler not reached / wrong phase
#   0x100|code an unexpected trap

#include "riscv_test.h"
#include "test_macros.h"

#define CSR_CPUCTRLSTS    0x7C0
#define SYNC_EXC_SEEN     0x40
#define DOUBLE_FAULT_SEEN 0x80
#define DBG_CAUSE_HALTREQ 3
# The bench reads core status at +signature_addr, 4 bytes above SIGNATURE_ADDR.
#define CORE_STATUS_ADDR (SIGNATURE_ADDR + 4)

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

  # phase (in .data): 1 waiting in the illegal-instruction handler, 2 after dret, 3 ecall taken
  la   t0, phase
  li   t1, 1
  sw   t1, 0(t0)
  li   TESTNUM, 1
  .option push
  .option norvc
  .word 0x00000000               # illegal instruction
  .option pop
  j    fail                      # the handler never returns here

resume:
  # ---- 3. the PR's claim ----
  li   TESTNUM, 10
  csrr t0, CSR_CPUCTRLSTS
  andi t0, t0, SYNC_EXC_SEEN
  bnez t0, fail

  # ---- 4. an unrelated exception must not be a double fault ----
  li   TESTNUM, 13
  ecall
  la   t0, phase
  lw   t0, 0(t0)
  li   t1, 3
  bne  t0, t1, fail

  li   TESTNUM, 99
  j    pass

  TEST_PASSFAIL

.balign 4
mtvec_handler:
  la   t0, phase
  lw   t0, 0(t0)
  li   t1, 1
  beq  t0, t1, handler_illegal
  li   t1, 2
  beq  t0, t1, handler_ecall
  ori  TESTNUM, TESTNUM, 0x100
  j    fail

handler_illegal:
  li   TESTNUM, 2
  csrr t0, CSR_CPUCTRLSTS
  andi t0, t0, SYNC_EXC_SEEN
  beqz t0, fail
  li   t0, CORE_STATUS_ADDR
  li   t1, (INITIALIZED << 8) | CORE_STATUS
  sw   t1, 0(t0)
  li   TESTNUM, 3
  li   t2, 100000
1:
  addi t2, t2, -1
  bnez t2, 1b
  j    fail

handler_ecall:
  li   TESTNUM, 11
  csrr t0, CSR_CPUCTRLSTS
  andi t0, t0, DOUBLE_FAULT_SEEN
  bnez t0, fail
  li   TESTNUM, 12
  csrr t0, mcause
  li   t1, CAUSE_MACHINE_ECALL
  bne  t0, t1, fail
  la   t0, phase
  li   t1, 3
  sw   t1, 0(t0)
  csrr t0, mepc
  addi t0, t0, 4
  csrw mepc, t0
  li   TESTNUM, 13
  mret

debug_entry:
  csrw dscratch0, t0
  csrw dscratch1, t1
  la   t0, phase
  lw   t0, 0(t0)
  li   t1, 1
  bne  t0, t1, fail
  li   TESTNUM, 4
  csrr t0, dcsr
  srli t0, t0, 6
  andi t0, t0, 7
  li   t1, DBG_CAUSE_HALTREQ
  bne  t0, t1, fail
  # Abandon the handler: resume elsewhere.
  la   t0, resume
  csrw dpc, t0
  la   t0, phase
  li   t1, 2
  sw   t1, 0(t0)
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
