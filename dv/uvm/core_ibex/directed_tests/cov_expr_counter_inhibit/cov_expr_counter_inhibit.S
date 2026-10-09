# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cov_expr_counter_inhibit -- minstret and mhpmcounter10 frozen by mcountinhibit
# =============================================================================
# RISC-V mode (cheriot_enable_i Off). Cosim off: the Spike in this flow does not inhibit
# minstret (see counter_high_half_write), so the program checks the counts itself.
#
# Expression-coverage targets (merged regression after UNR, 2026-10-09), ibex_cs_registers.sv:
#   `instr_ret_spec_i & ~mcountinhibit[2] ? minstret_next : minstret_raw`, row
#     instr_ret_spec = 1, mcountinhibit[2] = 1: instructions retire while minstret is inhibited.
#   gen_cntrs[7].gen_compressed_instr_cnt (mhpmcounter10, compressed instructions retired),
#     `instr_ret_compressed_spec_i & ~mcountinhibit[Cnt]`, row 1/1: compressed instructions
#     retire while mhpmcounter10 is inhibited.
# Nothing in the regression set mcountinhibit.IR or bit 10 (wb_counter_inhibit sets CY only).
#
# Expected behaviour (RISC-V Privileged ISA, mcountinhibit; Ibex
# doc/03_reference/performance_counters.rst: mhpmcounter10 counts retired compressed
# instructions):
#   - inhibited: minstret and mhpmcounter10 do not change, whatever retires;
#   - counting: between two csrr of minstret with N instructions in between, minstret grows by
#     N + 1 (the first csrr retires too; the same rule mcounteren_test checks for instret), and
#     mhpmcounter10 grows by the number of compressed instructions retired in between.
# Counting is checked before and after the inhibited stretch, so the freeze is not a counter that
# never counts.
#
# Failure: TEST_FAIL with TESTNUM (gp):
#   1/2  before: minstret delta not 18 / mhpmcounter10 delta not 8
#   3/4  inhibited: minstret changed / mhpmcounter10 changed
#   5/6  after: minstret delta not 18 / mhpmcounter10 delta not 8
#   7    mcountinhibit read back without bits 2 and 10
#   0x100 | code  an unexpected trap

#include "riscv_test.h"
#include "test_macros.h"

#define INHIBIT_IR_C  ((1 << 2) | (1 << 10))

# 8 compressed and 8 uncompressed instructions between two csrr pairs (16 instructions, 8 of them
# compressed); minstret delta = 16 + 2 (csrr minstret, csrr mhpmcounter10 before them).
.macro BODY
  .option push
  .option rvc
  c.addi a5, 1
  c.addi a5, 1
  c.addi a5, 1
  c.addi a5, 1
  c.addi a5, 1
  c.addi a5, 1
  c.addi a5, 1
  c.addi a5, 1
  .option norvc
  addi  a5, a5, 1
  addi  a5, a5, 1
  addi  a5, a5, 1
  addi  a5, a5, 1
  addi  a5, a5, 1
  addi  a5, a5, 1
  addi  a5, a5, 1
  addi  a5, a5, 1
  .option pop
.endm

# a0/a1 := minstret, mhpmcounter10 before BODY; a2/a3 := after.
.macro MEASURE
  csrr  a0, minstret
  csrr  a1, mhpmcounter10
  BODY
  csrr  a2, minstret
  csrr  a3, mhpmcounter10
.endm

  .option norvc
  .option norelax

RVTEST_RV32M
RVTEST_CODE_BEGIN

  csrw  mcountinhibit, zero

  # ---- Counting ----
  MEASURE
  li    TESTNUM, 1
  sub   t0, a2, a0
  li    t1, 18
  bne   t0, t1, fail
  li    TESTNUM, 2
  sub   t0, a3, a1
  li    t1, 8
  bne   t0, t1, fail

  # ---- Inhibited: IR and counter 10 ----
  li    t0, INHIBIT_IR_C
  csrw  mcountinhibit, t0
  li    TESTNUM, 7
  csrr  t1, mcountinhibit
  and   t1, t1, t0
  bne   t1, t0, fail
  MEASURE
  li    TESTNUM, 3
  bne   a2, a0, fail
  li    TESTNUM, 4
  bne   a3, a1, fail
  csrw  mcountinhibit, zero

  # ---- Counting again ----
  MEASURE
  li    TESTNUM, 5
  sub   t0, a2, a0
  li    t1, 18
  bne   t0, t1, fail
  li    TESTNUM, 6
  sub   t0, a3, a1
  li    t1, 8
  bne   t0, t1, fail

  TEST_PASSFAIL

mtvec_handler:
  ori   TESTNUM, TESTNUM, 0x100
  j     fail

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
