# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: ibex_mhartid -- mhartid reads hart_id_i; writing it is illegal
# =============================================================================
# Expected behaviour (not taken from the RTL):
#   - doc/02_user/integration.rst: hart_id_i is the hart ID, read through mhartid.
#   - RISC-V Privileged ISA, mhartid: read-only; "Attempts to write a read-only register raise
#     an illegal-instruction exception".
#
# EXPECTED_HART_ID is the value core_ibex_tb_top.sv drives on hart_id_i (+hart_id=<hex>,
# default 0). ibex_mhartid_ones builds with -DEXPECTED_HART_ID=0xFFFFFFFF and runs with
# +hart_id=FFFFFFFF; that entry has the cosim off, as Spike's mhartid is always 0, so the
# checks below are the only ones on the value.
#
# Failure: the testbench sees TEST_FAIL; TESTNUM (gp) holds the code of the failing check.
#   1  mhartid != EXPECTED_HART_ID
#   2  csrw mhartid took no illegal-instruction exception
#   3  mhartid changed after the write
#   0x100 | code  any other trap while check `code` was in progress

#include "riscv_test.h"
#include "test_macros.h"

# riscv_test.h's reset code parks every hart but 0 (RISCV_MULTICORE_DISABLE: csrr a0, mhartid;
# 1: bnez a0, 1b). ibex_mhartid_ones runs with hart_id_i = 0xFFFFFFFF, so the parked core never
# reached the test and hit the wall-clock timeout (2026-10-08). RVTEST_CODE_BEGIN expands the macro
# where it is used, so an empty definition here keeps every hart running.
#undef RISCV_MULTICORE_DISABLE
#define RISCV_MULTICORE_DISABLE

#ifndef EXPECTED_HART_ID
#define EXPECTED_HART_ID 0
#endif

RVTEST_RV32M
RVTEST_CODE_BEGIN

  li    TESTNUM, 1
  csrr  a0, mhartid
  li    t1, EXPECTED_HART_ID
  bne   a0, t1, fail

  # s1 is set by the handler when the write traps as expected.
  li    TESTNUM, 2
  li    s1, 0
  li    t2, 0x5A5A5A5A
  csrw  mhartid, t2
  beqz  s1, fail

  li    TESTNUM, 3
  csrr  a0, mhartid
  bne   a0, t1, fail

  TEST_PASSFAIL

# RVTEST_CODE_BEGIN's trap_vector jumps here (t5, t6 are free).
mtvec_handler:
  li    t5, 2
  bne   TESTNUM, t5, 1f
  csrr  t5, mcause
  li    t6, CAUSE_ILLEGAL_INSTRUCTION
  bne   t5, t6, 1f
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
