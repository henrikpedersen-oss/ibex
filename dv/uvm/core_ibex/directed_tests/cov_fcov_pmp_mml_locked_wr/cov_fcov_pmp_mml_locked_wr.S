# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# With mseccfg.MML = 1 and RLB = 0, writes that would turn a locked, non-executable PMP entry
# into an executable one are ignored. Targets core_ibex_pmp_fcov_if pmp_region_cg
# .pmp_wr_exec_region with rlb = 0: every (locked non-executable source, executable target) pair,
# deterministically. On 2026-10-09 the random riscv_epmp_* tests had left {MML_RM -> MML_XU,
# MML_XRU, MML_XWRU, MML_XM_XU, MML_XM, MML_XRM_XU} and {MML_WRM -> MML_XWRU} unhit.
#
# The cross samples the current entry ({MML, L, X, W, R}) against the write data of a CSR write to
# the entry's pmpcfg register, whether or not the write takes effect; it is what a locked entry
# being asked for execute permission looks like.
#
# Sequence (M-mode throughout, MMWP = 0):
#   1. With MML = 0: region 0 := NAPOT [0x80000000, 0x80010000), L | X | R (the program; under
#      MML this is an M-mode-only RX rule, without which M-mode could not fetch: Smepmp, no-match
#      execution is denied). Regions 4-7 (pmpcfg1) := L, L|R, L|W|R, L|X|W|R with A = OFF, which
#      under MML are MML_L, MML_RM, MML_WRM and MML_RM_RU. Both read back (codes 2, 3).
#   2. mseccfg.MML := 1; mseccfg reads 1 (MML only; RLB stays 0) (code 4).
#   3. pmpcfg1 := each executable MML config in all four bytes: XU 0x04, XRU 0x05, XWRU 0x07,
#      XM_XU 0x82, XM 0x84, XRM 0x85, XRM_XU 0x86. All four entries are locked and RLB = 0, so
#      every write is ignored (Privileged Spec 3.7.1 lock; ibex_cs_registers.sv pmp_cfg_locked):
#      pmpcfg1 reads back unchanged after each (codes 10-16). For the locked-M-exec targets the
#      Smepmp rule (ibex pmp_cfg_wr_suppress) would suppress the write too.
# The signature address (0x8ffffff8) matches no entry: M-mode loads/stores there stay allowed
# with MML = 1 and MMWP = 0. Spike is the cosim oracle and implements Smepmp.
# Codes in TESTNUM (gp): 1 mseccfg not 0 at reset; 2-4 setup; 10-16 a write changed pmpcfg1;
# TESTNUM | 0x100 an unexpected trap.

#include "riscv_test.h"
#include "test_macros.h"

#define CSR_MSECCFG   0x747
#define MSECCFG_MML   0x1
#define CODE_NAPOT    0x20001FFF  /* NAPOT [0x80000000, 0x80010000): 64 KiB */
#define CFG0_LXR      0x9D        /* L | NAPOT | X | R */
#define CFG1_LOCKED   0x87838180  /* region 7..4: L|X|W|R, L|W|R, L|R, L; A = OFF */

# pmpcfg1 := \cfg in every byte; it must read back as CFG1_LOCKED (s2). Code \code.
.macro WR_EXEC cfg, code
  li    TESTNUM, \code
  li    t0, (\cfg) * 0x01010101
  csrw  pmpcfg1, t0
  csrr  t1, pmpcfg1
  bne   t1, s2, fail
.endm

RVTEST_RV32M
RVTEST_CODE_BEGIN

  # ---- 1. lock the configuration, MML = 0, RLB = 0 ----
  li    TESTNUM, 1
  csrr  t0, CSR_MSECCFG
  bnez  t0, fail
  li    TESTNUM, 2
  li    t0, CODE_NAPOT
  csrw  pmpaddr0, t0
  li    t0, CFG0_LXR
  csrw  pmpcfg0, t0
  csrr  t1, pmpcfg0
  bne   t1, t0, fail
  li    TESTNUM, 3
  li    s2, CFG1_LOCKED
  csrw  pmpcfg1, s2
  csrr  t1, pmpcfg1
  bne   t1, s2, fail

  # ---- 2. MML ----
  li    TESTNUM, 4
  csrsi CSR_MSECCFG, MSECCFG_MML
  csrr  t1, CSR_MSECCFG
  li    t0, MSECCFG_MML
  bne   t1, t0, fail

  # ---- 3. attempts to make the locked entries executable ----
  WR_EXEC 0x04, 10            # MML_XU
  WR_EXEC 0x05, 11            # MML_XRU
  WR_EXEC 0x07, 12            # MML_XWRU
  WR_EXEC 0x82, 13            # MML_XM_XU
  WR_EXEC 0x84, 14            # MML_XM
  WR_EXEC 0x85, 15            # MML_XRM
  WR_EXEC 0x86, 16            # MML_XRM_XU

  j     pass

  TEST_PASSFAIL

# Any trap fails: RVTEST_FAIL only stores to the signature address, which no entry matches.
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
