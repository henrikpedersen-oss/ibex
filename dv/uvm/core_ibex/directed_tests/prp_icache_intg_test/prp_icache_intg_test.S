# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Program for prp_icache_intg_test (lowRISC/ibex#2536). Upstream runs the PR's
# core_ibex_icache_intg_test on a riscv-dv random program; directed tests here
# need a program of their own, so this one gives the bench what the test needs:
# the ICache on (cpuctrlsts.icache_enable) and a loop that runs from the cache
# long enough for the bench to corrupt one tag or data read on a cache lookup.
#
# The bench (core_ibex_prp_icache_intg_test) flips one bit of a tag or data way
# read and checks the minor alert of the main core and of the lockstep shadow
# core. A corrupted read is an ECC error: the cache treats it as a miss and
# refetches, so the program must still compute the right result.
#
# Failure: TEST_FAIL with TESTNUM (gp) 2 = the ICache did not switch on,
# 3 = wrong loop result. The bench fails the test if the program ends before
# the corruption check completed.

#include "riscv_test.h"
#include "test_macros.h"

#define CSR_CPUCTRLSTS   0x7c0
#define ICACHE_ENABLE    0x1
#define LOOP_COUNT       3000

RVTEST_RV32M
RVTEST_CODE_BEGIN

  li   TESTNUM, 2
  csrsi CSR_CPUCTRLSTS, ICACHE_ENABLE
  csrr t0, CSR_CPUCTRLSTS
  andi t0, t0, ICACHE_ENABLE
  beqz t0, fail
  fence.i

  li   TESTNUM, 3
  li   t3, 0                       # sum of 3 per pass
  li   t4, LOOP_COUNT
1:
  addi t3, t3, 3
  slli t6, t3, 1
  sub  t6, t6, t3
  bne  t6, t3, fail
  addi t4, t4, -1
  bnez t4, 1b

  li   t0, 3 * LOOP_COUNT
  bne  t3, t0, fail
  j    pass

  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
