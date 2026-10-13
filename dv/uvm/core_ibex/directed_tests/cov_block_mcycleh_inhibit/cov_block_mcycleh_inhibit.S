# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cov_block_mcycleh_inhibit -- mcycleh written while mcycle is inhibited
# =============================================================================
# RISC-V mode (cheriot_enable_i Off). Cosim off, as for cov_expr_counter_inhibit: the Spike in
# this flow does not model mcountinhibit, so the program checks the counter itself.
#
# Block-coverage target (merged regression 30527 after UNR, 2026-10-10), ibex_counter.sv line 46
# in cs_registers_i.mcycle_counter_i:
#   counter_load[31:0] = counter_inc_i ? counter[31:0] + 32'd1 : counter[31:0];
# false part: a write to mcycleh while mcycle does not count. For mcycle counter_inc_i is
# ~mcountinhibit[0] (ibex_cs_registers.sv mhpmcounter_incr[0] = 1), so it needs mcountinhibit.CY
# set. counter_high_half_write writes mcycleh with CY clear only; wb_counter_inhibit sets CY but
# never writes mcycleh.
#
# Expected behaviour (RISC-V Privileged ISA: mcountinhibit.CY stops mcycle; on RV32 mcycleh is
# bits 63:32 of mcycle and a write to it leaves bits 31:0 alone):
#   - with CY set, two reads of mcycle with work in between return the same value;
#   - after csrw mcycleh, H: mcycleh reads H and mcycle (low half) still reads that value;
#   - with CY clear again mcycle counts (liveness: the freeze is not a dead counter).
# A second write to mcycleh with CY set, after a write of the low half, checks the low half is
# also held across the high-half write when it is not the value it had on inhibit.
#
# Failure: TEST_FAIL with TESTNUM (gp):
#   1  mcycle changed while CY was set           2  mcycleh did not read back H1
#   3  mcycle low half changed by the mcycleh write (or counted)
#   4  mcycle low half not L2 after csrw mcycle    5  mcycleh did not read back H2
#   6  mcycle low half changed by the second mcycleh write
#   7  mcycle did not count after CY was cleared   8  mcountinhibit.CY did not read back set
#   0x100 | code  an unexpected trap
#
# Proving it can fail (build-time switch, not in the testlist):
#   -DCOV_BLOCK_INJECT_FAIL  clears CY before check 1 -> mcycle counts -> TESTNUM 1

#include "riscv_test.h"
#include "test_macros.h"

#define H1 0x5A5A0001
#define H2 0x0000A5A5
#define L2 0xFFFFFFF0

.macro WORK
  addi  a5, a5, 1
  addi  a5, a5, 1
  addi  a5, a5, 1
  addi  a5, a5, 1
  addi  a5, a5, 1
  addi  a5, a5, 1
  addi  a5, a5, 1
  addi  a5, a5, 1
.endm

  .option norvc
  .option norelax

RVTEST_RV32M
RVTEST_CODE_BEGIN

  # ---- Inhibit mcycle ----
  csrsi mcountinhibit, 1
  li    TESTNUM, 8
  csrr  t0, mcountinhibit
  andi  t0, t0, 1
  beqz  t0, fail
#ifdef COV_BLOCK_INJECT_FAIL
  csrci mcountinhibit, 1
#endif

  li    TESTNUM, 1
  csrr  a0, mcycle
  WORK
  csrr  a1, mcycle
  bne   a0, a1, fail

  # ---- First mcycleh write while inhibited ----
  li    t0, H1
  csrw  mcycleh, t0
  li    TESTNUM, 2
  csrr  a2, mcycleh
  bne   a2, t0, fail
  li    TESTNUM, 3
  csrr  a3, mcycle
  bne   a3, a0, fail

  # ---- Low half written, then a second mcycleh write while inhibited ----
  li    t0, L2
  csrw  mcycle, t0
  li    TESTNUM, 4
  csrr  a3, mcycle
  bne   a3, t0, fail
  li    t1, H2
  csrw  mcycleh, t1
  li    TESTNUM, 5
  csrr  a2, mcycleh
  bne   a2, t1, fail
  li    TESTNUM, 6
  WORK
  csrr  a3, mcycle
  bne   a3, t0, fail

  # ---- Counting again ----
  csrci mcountinhibit, 1
  WORK
  li    TESTNUM, 7
  csrr  a4, mcycle
  beq   a4, t0, fail

  TEST_PASSFAIL

mtvec_handler:
  ori   TESTNUM, TESTNUM, 0x100
  j     fail

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
