# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Test: prc_2521_bp_skid_trap -- a predicted-taken branch must not survive a trap redirect
#                                 (lowRISC/ibex PR #2521, issue #2520)
#
# With BranchPredictor = 1, ibex_if_stage.sv keeps a predicted-taken branch in a one-entry skid
# buffer while ID is not ready. The buffer's fill term has ~pc_set_i but its hold term does not,
# so an entry filled while the controller flushes for a trap survives the redirect and is
# executed as the first instruction of the trap handler (with the handler's privilege).
# PR #2521 adds ~pc_set_i to the hold term.
#
# Each case is a trapping instruction immediately followed by a backward (so predicted-taken)
# `beq zero, zero, back`. The handler sets s2 and returns past the trapping instruction, so the
# beq then really executes and jumps back, where s2 must be set. With the bug the stale beq runs
# first, as the handler's first instruction, and reaches `back` with s2 still 0 (or the cosim
# reports the extra instruction first).
#   case 1: ecall,              4-byte aligned
#   case 2: ecall,              2-byte offset (after a c.nop)
#   case 3: illegal (.word 0),  4-byte aligned
#   case 4: illegal (.word 0),  2-byte offset
# Needs BranchPredictor = 1 (IBEX_CONFIG=experimental-branch-predictor). RISC-V mode.
#
# Failure: TEST_FAIL with TESTNUM (gp) = the case number (the branch ran before the handler),
#   10 + case  wrong mcause in the handler,  20 + case  the beq fell through,
#   99 liveness (handler count != 4),  0x100 | case an unexpected trap.

#include "riscv_test.h"
#include "test_macros.h"

.macro TRAP_CASE n, trap_insn, offset
  li    TESTNUM, \n
  li    s2, 0
  j     3f
2:
  beqz  s2, fail                 # the branch ran before the handler
  j     4f
  .balign 4
3:
  .if \offset
  c.nop
  .endif
  \trap_insn
  beq   zero, zero, 2b           # backward: predicted taken
  li    TESTNUM, 20 + \n
  j     fail
4:
.endm

.macro ECALL_INSN
  ecall
.endm
.macro ILLEGAL_INSN
  .word 0x00000000
.endm

RVTEST_RV32M
RVTEST_CODE_BEGIN

  li    s3, 0                    # handler count
  .option push
  .option rvc
  TRAP_CASE 1, ECALL_INSN, 0
  TRAP_CASE 2, ECALL_INSN, 1
  TRAP_CASE 3, ILLEGAL_INSN, 0
  TRAP_CASE 4, ILLEGAL_INSN, 1
  .option pop

  li    TESTNUM, 99
  li    t0, 4
  bne   s3, t0, fail
  j     pass

  TEST_PASSFAIL

.balign 4
mtvec_handler:
  csrr  t0, mcause
  li    t1, CAUSE_MACHINE_ECALL
  beq   t0, t1, 1f
  li    t1, CAUSE_ILLEGAL_INSTRUCTION
  beq   t0, t1, 1f
  addi  TESTNUM, TESTNUM, 10
  j     fail
1:
  li    s2, 1
  addi  s3, s3, 1
  csrr  t0, mepc
  addi  t0, t0, 4
  csrw  mepc, t0
  mret

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
