# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Test: prc_2495_mml_off_exec -- MML write suppression for entries that create no rule
#                                 (lowRISC/ibex PR #2495, issue #2491)
#
# Smepmp (mseccfg.MML = 1, RLB = 0): "Adding a rule with executable privileges that either is
# M-mode-only or a locked Shared-Region is not possible and such pmpcfg writes are ignored."
# Ibex suppresses such writes in ibex_cs_registers.sv (pmp_cfg_wr_suppress, is_mml_m_exec_cfg),
# looking at L and {R,W,X} only. PR #2495 says an entry with A = OFF, or A = TOR with an empty
# range, creates no rule, so its write must not be suppressed.
#
# Sequence (M-mode, MMWP = 0), set-up as in cov_fcov_pmp_mml_locked_wr:
#   1. MML = 0: region 0 := NAPOT [0x80000000, 0x80010000), L|X|R (an M-mode RX rule over the
#      program; under MML no-match execution is denied). pmpaddr4 = pmpaddr5 = 0x20004000
#      (so a TOR entry 5 has an empty range), pmpaddr6 = NAPOT 16 bytes at 0x80020000.
#   2. MML := 1.
#   3. Control (both readings agree): pmpcfg1 byte 2 (entry 6) := L|NAPOT|X (0x9C), a real
#      M-mode-only execute rule: must be ignored, pmpcfg1 reads 0 (code 10).
#   4. The PR's case 1: entry 4 := L|OFF|X (0x84): the PR expects the write to take effect,
#      pmpcfg1 reads 0x84 (code 11). Without the PR it is ignored.
#   5. The PR's case 3: entry 5 := L|TOR|X (0x8C) with pmpaddr4 == pmpaddr5 (empty range): the
#      PR expects it to take effect (code 12).
# The Spike cosim is on: whatever Spike does with steps 4-5 shows as a match or a mismatch of the
# pmpcfg1 read-back, so this test also tells which reading the reference model follows.
#
# Failure: TEST_FAIL with TESTNUM (gp) =
#   1-3 set-up read-backs wrong   10 control write took effect   11 OFF write ignored
#   12 empty-TOR write ignored     0x100|code unexpected trap

#include "riscv_test.h"
#include "test_macros.h"

#define CSR_MSECCFG   0x747
#define MSECCFG_MML   0x1
#define CODE_NAPOT    0x20001FFF  /* NAPOT [0x80000000, 0x80010000): 64 KiB */
#define CFG0_LXR      0x9D        /* L | NAPOT | X | R */
#define TOR_ADDR      0x20004000  /* 0x80010000 >> 2 */
#define NAPOT16_ADDR  0x20008001  /* NAPOT 16 bytes at 0x80020000 */

RVTEST_RV32M
RVTEST_CODE_BEGIN

  # ---- 1. set-up with MML = 0 ----
  li    TESTNUM, 1
  li    t0, CODE_NAPOT
  csrw  pmpaddr0, t0
  li    t0, CFG0_LXR
  csrw  pmpcfg0, t0
  csrr  t1, pmpcfg0
  bne   t1, t0, fail
  li    TESTNUM, 2
  csrw  pmpcfg1, zero
  li    t0, TOR_ADDR
  csrw  pmpaddr4, t0
  csrw  pmpaddr5, t0
  li    t0, NAPOT16_ADDR
  csrw  pmpaddr6, t0
  csrr  t1, pmpaddr5
  li    t0, TOR_ADDR
  bne   t1, t0, fail

  # ---- 2. MML ----
  li    TESTNUM, 3
  csrsi CSR_MSECCFG, MSECCFG_MML
  csrr  t1, CSR_MSECCFG
  li    t0, MSECCFG_MML
  bne   t1, t0, fail

  # ---- 3. control: a real locked M-mode execute rule is refused ----
  li    TESTNUM, 10
  li    t0, 0x9C << 16
  csrw  pmpcfg1, t0
  csrr  t1, pmpcfg1
  bnez  t1, fail

  # ---- 4. A = OFF: no rule, the PR lets the write through ----
  li    TESTNUM, 11
  li    t0, 0x84
  csrw  pmpcfg1, t0
  csrr  t1, pmpcfg1
  bne   t1, t0, fail

  # ---- 5. A = TOR with an empty range: no rule, the PR lets it through ----
  li    TESTNUM, 12
  li    t0, (0x8C << 8) | 0x84
  csrw  pmpcfg1, t0
  csrr  t1, pmpcfg1
  bne   t1, t0, fail

  li    TESTNUM, 99
  j     pass

  TEST_PASSFAIL

# Any trap fails.
.balign 4
.global mtvec_handler
mtvec_handler:
  ori   TESTNUM, TESTNUM, 0x100
  j     fail

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
