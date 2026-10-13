# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cov_fcov_pmp_region_mml1 -- every PMP region, every MML permission, every access
# =============================================================================
# RISC-V mode (cheriot_enable_i Off, the riscv-tests default), Spike cosim on, PMPNumRegions 16,
# PMPGranularity 0 (ibex_configs.yaml "opentitan"). mseccfg.MML = 1, RLB = 1, MMWP = 0.
#
# Targets core_ibex_pmp_fcov_if.sv pmp_region_cg, per instance (one per region 0..15), the MML
# half (cov_fcov_pmp_region_mml0 does MML = 0):
#   cp_region_priv_bits      the 16 MML values {MML=1, L, X, W, R}
#   pmp_{iside,iside2,dside}_priv_bits_cross   the 16 MML rows: per permission value the M and U
#                            fetch and the M and U read and write as the highest-priority match,
#                            which are exactly the legal bins of those rows (32 of 64 per fetch
#                            cross, 64 of 128 data)
#   pmp_{iside,iside2,dside}_mode_cross, cp_region_mode   again, TOR/NA4/NAPOT x allowed/denied
# pmp_wr_exec_region is in cov_fcov_pmp_region_wr_exec_c0..c4.
#
# The code region. With MML = 1 an M-mode fetch that matches no entry is denied (Smepmp 2.2), so
# the test's own code needs an entry granting M-mode execute, and it can only do that locked
# (MML_XRM = L|X|R: M-mode read and execute). Data accesses that match no entry stay allowed for
# M-mode (MMWP = 0); the test writes no memory but the probe chunks and the signature address.
# 17 entries would be needed to probe 16 regions beside it, so:
#   Phase 0 (A): entry 15 = NAPOT [0x80000000, 0x80001000) MML_XRM; it is the lowest priority, so
#                entries 0..14 on their probe chunks (all below 0x80000080) win there; probe
#                entries 0..14.
#   Phase 1 (B): entry 1 = TOR [0x80000080, 0x80001000) MML_XRM (entry 0 OFF, pmpaddr0 its
#                base), which leaves the probe area to entry 15; probe entry 15 (TOR uses
#                pmpaddr14 = A(15) as its base, entry 14 OFF).
# RLB = 1 lets the test rewrite locked entries, including the code entry at the phase change
# (Smepmp 2.3); the entry 1 rule is in place before entry 15 is cleared.
#
# Stimulus (pmp_region_sweep.h describes the probe area and the six probes):
#   setup: RLB := 1; entry 15 := code rule; entry 0 (riscv_test.h's INIT_PMP rule) OFF;
#          MML := 1 (mseccfg reads MML | RLB).
#   Phase A: 16 rounds, one per MML permission value, A field rotating TOR, NA4, NAPOT, over
#          entries 0..14: 16 x 15 x 6 = 1440 probes.
#   Phase B: the same 16 rounds over entry 15: 96 probes.
#   Liveness: 1536 probes, 464 allowed (from the masks).
#
# Expected outcomes, Smepmp 1.0 Table 2 (MML = 1; no S-mode on Ibex, so "S/U" is U):
# Mask bits: 0x01 MX, 0x02 UX, 0x04 MR, 0x08 MW, 0x10 UR, 0x20 UW.
#   LRWX  name          rule                                    M: X R W   U: X R W   mask
#   0000  MML_NONE      inaccessible                               0 0 0      0 0 0   0x00
#   0100  MML_RU        U read-only                                0 0 0      0 1 0   0x10
#   0010  MML_WRM_RU    shared data: M read/write, U read          0 1 1      0 1 0   0x1c
#   0110  MML_WRU       U read/write                               0 0 0      0 1 1   0x30
#   0001  MML_XU        U execute-only                             0 0 0      1 0 0   0x02
#   0101  MML_XRU       U read/execute                             0 0 0      1 1 0   0x12
#   0011  MML_WRM_WRU   shared data: read/write on M and U         0 1 1      0 1 1   0x3c
#   0111  MML_XWRU      U read/write/execute                       0 0 0      1 1 1   0x32
#   1000  MML_L         locked, inaccessible                       0 0 0      0 0 0   0x00
#   1100  MML_RM        M read-only                                0 1 0      0 0 0   0x04
#   1010  MML_XM_XU     shared code: execute on M and U            1 0 0      1 0 0   0x03
#   1110  MML_WRM       M read/write                               0 1 1      0 0 0   0x0c
#   1001  MML_XM        M execute-only                             1 0 0      0 0 0   0x01
#   1101  MML_XRM       M read/execute                             1 1 0      0 0 0   0x05
#   1011  MML_XRM_XU    shared code: execute on M and U, M read    1 1 0      1 0 0   0x07
#   1111  MML_RM_RU     shared data: read-only on M and U          0 1 0      0 1 0   0x14
# Round order as the table, A field cycling TOR, NA4, NAPOT: every mode gets an allowed and a
# denied fetch and data access.
#
# Instruction count: 57763 on Spike (~37 per probe, the trap and its check included).
#
# Failure: TEST_FAIL, TESTNUM (gp) as in pmp_region_sweep.h with PHASE 0 (A) or 1 (B);
# KIND 8 setup: PROBE 1 mseccfg not RLB, 2 code rule did not read back, 3 mseccfg not MML|RLB,
# 4 code beyond the code rule, 5 phase B code rule did not read back; KIND 7 liveness
# (PROBE 1 count, 2 allowed).

#include "riscv_test.h"
#include "test_macros.h"
#include "pmp_region_sweep.h"

#define CODE_SIZE       0x1000
#define CODE_TOP        (PROBE_BASE + CODE_SIZE)
#define CODE_NAPOT      ((PROBE_BASE >> 2) | ((CODE_SIZE >> 3) - 1))
#define CODE_CFG_NAPOT  (PMP_CFG_L | PMP_CFG_NAPOT | PMP_CFG_X | PMP_CFG_R)
#define CODE_CFG_TOR    (PMP_CFG_L | PMP_CFG_TOR | PMP_CFG_X | PMP_CFG_R)

  .option norvc
  .option norelax

  PROBE_AREA

RVTEST_RV32M
RVTEST_CODE_BEGIN

  li    s5, 0
  li    a2, 0
  li    a3, 0

  # ---- the whole program and its tables must lie inside the code rule ----
  li    TESTNUM, KIND_SETUP | 4
  lla   t0, code_end
  li    t1, CODE_TOP
  bgtu  t0, t1, fail

  # ---- RLB = 1 while nothing is locked ----
  li    TESTNUM, KIND_SETUP | 1
  li    t0, MSECCFG_RLB
  csrw  CSR_MSECCFG, t0
  csrr  t1, CSR_MSECCFG
  bne   t1, t0, fail

  # ---- code rule in entry 15, then INIT_PMP's entry 0 off ----
  li    TESTNUM, KIND_SETUP | 2
  li    t0, CODE_NAPOT
  csrw  pmpaddr15, t0
  csrr  t1, pmpaddr15
  bne   t1, t0, fail
  li    t0, CODE_CFG_NAPOT << 24
  csrw  pmpcfg3, t0
  csrr  t1, pmpcfg3
  bne   t1, t0, fail
  csrw  pmpcfg0, zero
  csrw  pmpcfg1, zero
  csrw  pmpcfg2, zero

  # ---- MML = 1 (sticky until reset) ----
  li    TESTNUM, KIND_SETUP | 3
  li    t0, MSECCFG_MML | MSECCFG_RLB
  csrw  CSR_MSECCFG, t0
  csrr  t1, CSR_MSECCFG
  bne   t1, t0, fail

  # ---- Phase A: entries 0..14, entry 15 keeps the code rule ----
  RUN_ROUNDS rounds_mml1, 16, 0, 14, 0, 0xffffffff, 0, 0xffffffff, 0, 0xffffffff, 0, 0x00ffffff, (CODE_CFG_NAPOT << 24)

  # ---- Phase B: code rule moves to entry 1 (TOR from pmpaddr0), entry 15 is probed ----
  li    TESTNUM, KIND_SETUP | 5
  csrw  pmpcfg0, zero
  csrw  pmpcfg1, zero
  csrw  pmpcfg2, zero
  li    t0, CODE_CFG_NAPOT << 24
  csrw  pmpcfg3, t0
  li    t0, A(16)
  csrw  pmpaddr0, t0
  li    t0, CODE_TOP >> 2
  csrw  pmpaddr1, t0
  li    t0, CODE_CFG_TOR << 8
  csrw  pmpcfg0, t0
  csrr  t1, pmpcfg0
  bne   t1, t0, fail
  li    t0, A(15)
  csrw  pmpaddr14, t0
  csrw  pmpcfg3, zero
  RUN_ROUNDS rounds_mml1, 16, 15, 15, 1, 0, (CODE_CFG_TOR << 8), 0, 0, 0, 0, 0xff000000, 0

  # ---- liveness ----
  li    TESTNUM, KIND_LIVE | 1
  li    t0, 16 * 16 * 6
  bne   a2, t0, fail
  li    TESTNUM, KIND_LIVE | 2
  li    t0, 464
  bne   a3, t0, fail
  j     pass

  PROBE_REGION_FN
  FAIL_EXITS
  TRAP_HANDLER

  TEST_PASSFAIL

# {P | A, mask}; A cycles TOR, NA4, NAPOT. Masks: header table.
  .balign 4
rounds_mml1:
  ROUND 0x00, PMP_CFG_TOR,   0x00     # MML_NONE
  ROUND 0x01, PMP_CFG_NA4,   0x10     # MML_RU
  ROUND 0x02, PMP_CFG_NAPOT, 0x1c     # MML_WRM_RU
  ROUND 0x03, PMP_CFG_TOR,   0x30     # MML_WRU
  ROUND 0x04, PMP_CFG_NA4,   0x02     # MML_XU
  ROUND 0x05, PMP_CFG_NAPOT, 0x12     # MML_XRU
  ROUND 0x06, PMP_CFG_TOR,   0x3c     # MML_WRM_WRU
  ROUND 0x07, PMP_CFG_NA4,   0x32     # MML_XWRU
  ROUND 0x80, PMP_CFG_NAPOT, 0x00     # MML_L
  ROUND 0x81, PMP_CFG_TOR,   0x04     # MML_RM
  ROUND 0x82, PMP_CFG_NA4,   0x03     # MML_XM_XU
  ROUND 0x83, PMP_CFG_NAPOT, 0x0c     # MML_WRM
  ROUND 0x84, PMP_CFG_TOR,   0x01     # MML_XM
  ROUND 0x85, PMP_CFG_NA4,   0x05     # MML_XRM
  ROUND 0x86, PMP_CFG_NAPOT, 0x07     # MML_XRM_XU
  ROUND 0x87, PMP_CFG_TOR,   0x14     # MML_RM_RU
  .balign 4
code_end:

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
