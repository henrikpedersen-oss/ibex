# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Test: prc_2044_mtvec_direct -- the mtvec MODE field (lowRISC/ibex PR #2044)
#
# PR #2044 makes mtvec.MODE writable: 0 (direct) and 1 (vectored) are kept, the reserved
# values 2 and 3 become 0. The RISC-V privileged spec makes MODE WARL with 0 = Direct,
# 1 = Vectored, >= 2 reserved. Ibex's manual (cs_registers.rst, mtvec) says MODE is fixed to
# vectored and BASE is 256-byte aligned.
#
# Checks 1-4 hold with and without the PR. Check 5 is the PR's claim (direct mode can be
# selected); it fails on RTL without the PR, which reads MODE back as 1.
#
# Runs in RISC-V mode. Failure: TEST_FAIL with TESTNUM (gp) =
#   1  write BASE|1 does not read back as BASE|1
#   2  write BASE|2 reads back a reserved MODE (2 or 3)
#   3  write BASE|3 reads back a reserved MODE (2 or 3)
#   4  write of all-ones to BASE[7:2] is not ignored (BASE not 256-byte aligned)
#   5  write BASE|0 does not read back MODE = 0 (direct mode not supported)
#   0x100|code  unexpected trap while check `code` was in progress

#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32M
RVTEST_CODE_BEGIN

  la    s0, trap_vector          # 256-byte aligned BASE (RVTEST_CODE_BEGIN .balign 256)

  # 1: vectored
  li    TESTNUM, 1
  ori   t0, s0, 1
  csrw  mtvec, t0
  csrr  t1, mtvec
  bne   t1, t0, fail

  # 2: reserved MODE 2 must not stick
  li    TESTNUM, 2
  ori   t0, s0, 2
  csrw  mtvec, t0
  csrr  t1, mtvec
  andi  t1, t1, 2
  bnez  t1, fail

  # 3: reserved MODE 3 must not stick
  li    TESTNUM, 3
  ori   t0, s0, 3
  csrw  mtvec, t0
  csrr  t1, mtvec
  andi  t1, t1, 2
  bnez  t1, fail

  # 4: BASE[7:2] ignored
  li    TESTNUM, 4
  ori   t0, s0, 0xFD             # BASE[7:2] all ones, MODE 1
  csrw  mtvec, t0
  csrr  t1, mtvec
  andi  t1, t1, 0xFC
  bnez  t1, fail

  # 5: direct mode (the PR's feature)
  li    TESTNUM, 5
  csrw  mtvec, s0                # MODE 0
  csrr  t1, mtvec
  ori   t0, s0, 1
  csrw  mtvec, t0                # back to the handler, vectored
  bne   t1, s0, fail

  li    TESTNUM, 99
  j     pass

  TEST_PASSFAIL

.balign 256
mtvec_handler:
  ori   TESTNUM, TESTNUM, 0x100
  j     fail

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
