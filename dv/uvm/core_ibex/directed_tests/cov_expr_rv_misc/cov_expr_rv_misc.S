# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cov_expr_rv_misc -- rori / bexti with shamt[5] set are illegal
# =============================================================================
# RISC-V mode (cheriot_enable_i Off), Spike cosim on.
#
# Expression-coverage target (merged regression after UNR, 2026-10-09):
#   ibex_decoder.sv OP-IMM funct3 101 (instr[26] = 0),
#   `(RV32B != RV32BNone) ? (instr[26:25] != 2'b00) : 1'b1` (rori / bexti), row
#   instr[26:25] != 0: rori and bexti with instr[25] = 1 (shamt 33). riscv-dv never emits the
#   reserved shift amounts; ibex_decode_holes covers them for srli/srai only.
#
# Expected behaviour (not taken from the RTL): RV32I/Zbb/Zbs -- an immediate shift or bit index
# with shamt[5] = 1 is reserved on RV32; Ibex raises an illegal instruction exception with
# mtval = the instruction (doc/03_reference/cs_registers.rst, mtval) and rd is not written.
#   rori a2, a0, 33 = 0x62155613; bexti a2, a0, 33 = 0x4A155613 (binutils 2.35 disassembles
#   both as such).
#
# Failure: TEST_FAIL with TESTNUM (gp):
#   1  rori shamt 33 did not trap, or wrote a2      2  same for bexti
#   0x100 | code  an unexpected trap (wrong mcause or mtval, or outside checks 1-2)

#include "riscv_test.h"
#include "test_macros.h"

#define POISON         0x0BADF00D

# One illegal encoding: the handler sets s1 when it sees mcause 2 with mtval = \enc (in s3).
.macro ILLEGAL_CHECK code, enc
  li    TESTNUM, \code
  li    s1, 0
  li    s3, \enc
  li    a2, POISON
  .word \enc
  beqz  s1, fail
  li    t1, POISON
  bne   a2, t1, fail
.endm

  .option norvc
  .option norelax

RVTEST_RV32M
RVTEST_CODE_BEGIN

  li    a0, 0x12345678
  ILLEGAL_CHECK 1, 0x62155613       # rori a2, a0, 33
  ILLEGAL_CHECK 2, 0x4A155613       # bexti a2, a0, 33

  TEST_PASSFAIL

# RVTEST_CODE_BEGIN's trap_vector jumps here (t5, t6 are free): only checks 1-2 may trap.
mtvec_handler:
  li    t5, 1
  blt   TESTNUM, t5, 1f
  li    t5, 2
  bgt   TESTNUM, t5, 1f
  csrr  t5, mcause
  li    t6, CAUSE_ILLEGAL_INSTRUCTION
  bne   t5, t6, 1f
  csrr  t5, mtval
  bne   t5, s3, 1f
  li    s1, 1
  csrr  t5, mepc
  addi  t5, t5, 4
  csrw  mepc, t5
  mret
1:
  ori   TESTNUM, TESTNUM, 0x100
  j     fail

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
