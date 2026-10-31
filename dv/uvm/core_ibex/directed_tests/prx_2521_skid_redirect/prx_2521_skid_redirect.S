# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# With static branch prediction enabled, put a backward jump immediately after
# a U-mode ECALL.  The jump can occupy the predictor skid buffer while the
# older ECALL redirects.  It must be discarded: otherwise it runs before the
# M-mode handler and reaches stale_target with elevated privilege.

#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32M
RVTEST_CODE_BEGIN
  la   t0, mtvec_handler
  csrw mtvec, t0

  li   TESTNUM, 1
  la   t0, user_entry
  csrw mepc, t0
  li   t0, MSTATUS_MPP
  csrc mstatus, t0
  mret
  j fail

.balign 4096
user_region:
stale_target:
  li   TESTNUM, 2
  j    fail

user_entry:
  ecall
  j    stale_target

user_resume:
#ifdef PRX_INJECT_FAIL
  li   TESTNUM, 3
  j    fail
#else
  j    pass
#endif

.balign 256
mtvec_handler:
  csrr t0, mcause
  li   t1, CAUSE_USER_ECALL
  bne  t0, t1, fail
  la   t0, user_resume
  csrw mepc, t0
  mret

  TEST_PASSFAIL
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
