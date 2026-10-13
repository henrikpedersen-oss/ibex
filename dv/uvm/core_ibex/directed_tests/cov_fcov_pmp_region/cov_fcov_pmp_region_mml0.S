# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cov_fcov_pmp_region_mml0 -- every PMP region, every non-MML permission, every access
# =============================================================================
# RISC-V mode (cheriot_enable_i Off, the riscv-tests default), Spike cosim on, PMPNumRegions 16,
# PMPGranularity 0 (ibex_configs.yaml "opentitan"), mseccfg.MML = 0 throughout (MML is sticky
# until reset, so the MML = 1 half is cov_fcov_pmp_region_mml1).
#
# Targets core_ibex_pmp_fcov_if.sv pmp_region_cg, per instance (option.per_instance = 1, one
# instance per region 0..15; the regression of 2026-10-10 left it at 47.26% per instance while
# 100% by type). For EVERY region, by construction:
#   cp_napot_addr_modes      all 32 sizes: section A writes pmpaddr = 2^k - 1, k = 0..31, to all
#                            16 entries while they are NAPOT (bin k = bit k clear, bits below set)
#   cp_warl_check_pmpcfg     1: section B gives every entry one pmpcfg write that is legalised
#                            (R = 0, W = 1 under MML = 0, the only legalisation with
#                            PMPGranularity 0: NA4 stays selectable, the other fields are stored
#                            as written); 0: every section A and C pmpcfg write is stored
#                            unchanged (each read back)
#   cp_region_mode           OFF (reset), TOR, NA4, NAPOT (section C rotates the mode per round)
#   cp_region_priv_bits      the 12 legal non-MML values {MML=0, L, X, W, R} (W without R is
#                            reserved, its 4 encodings are the coverpoint's illegal bins and are
#                            never stored: section B checks the legalisation)
#   cp_priv_lvl_* / cp_req_type_*   M and U; exec on both fetch channels, read and write on data
#   pmp_{iside,iside2,dside}_mode_cross   TOR/NA4/NAPOT x allowed/denied, each channel
#   pmp_{iside,iside2,dside}_priv_bits_cross   the 12 non-MML rows: per permission value, the
#                            M and U fetch, and the M and U read and write, all as the
#                            highest-priority match. These are exactly the crosses' legal bins
#                            for those rows (24 of 48 per fetch cross, 48 of 96 data): the
#                            illegal_bins exclude the opposite outcome of each one.
#   cp_edit_locked_pmpcfg / cp_edit_locked_pmpaddr   mseccfg.RLB = 1 for the whole test, and every
#                            round after a locked one rewrites pmpaddr and pmpcfg of locked entries
# The MML rows (16 of the 28 cp_region_priv_bits values) and pmp_wr_exec_region (MML only) are in
# cov_fcov_pmp_region_mml1 and cov_fcov_pmp_region_wr_exec_c0..c4.
#
# Stimulus (pmp_region_sweep.h describes the probe area and the six probes):
#   A. RLB := 1. All 16 entries NAPOT, unlocked, no permissions; pmpaddr0..15 := 2^k - 1 for
#      k = 0..31, each read back. Unlocked entries do not restrict M-mode (Privileged Spec 3.7.1),
#      so even k = 31 (the whole address space) leaves the test running.
#   B. pmpcfg0..3 each := {TOR|X|W, TOR|W, X|W, W} (all R = 0, W = 1, entries unlocked): each
#      reads back with W cleared, {TOR|X, TOR, X, 0} (Privileged Spec 3.7.1: R = 0, W = 1 is
#      reserved; ibex_cs_registers.sv and Spike both clear W), then := 0. With every pmpaddr at
#      0x7fffffff from section A the TOR entries are empty, and unlocked entries do not restrict
#      M-mode anyway.
#   C. Twelve rounds, one per non-MML permission value P, the A field rotating TOR, NA4, NAPOT.
#      Each round puts all 16 entries on their 8-byte probe chunk with P, then runs the six
#      probes (M/U fetch, M/U read, M/U write) on every chunk: 12 x 16 x 6 = 1152 probes, every
#      outcome checked against the round's mask.
#   D. Liveness: 1152 probes run, 720 of them allowed (from the masks); all entries cleared.
#
# Expected outcomes (MML = 0, MMWP = 0; Privileged Spec 3.7.1): an unlocked entry grants M-mode
# everything; a locked entry, and any entry for U-mode, grants exactly its R/W/X.
# Mask bits: 0x01 MX, 0x02 UX, 0x04 MR, 0x08 MW, 0x10 UR, 0x20 UW.
#   P      M: X R W   U: X R W   mask       P      M: X R W   U: X R W   mask
#   NONE      1 1 1      0 0 0   0x0d       L         0 0 0      0 0 0   0x00
#   R         1 1 1      0 1 0   0x1d       LR        0 1 0      0 1 0   0x14
#   WR        1 1 1      0 1 1   0x3d       LWR       0 1 1      0 1 1   0x3c
#   X         1 1 1      1 0 0   0x0f       LX        1 0 0      1 0 0   0x03
#   XR        1 1 1      1 1 0   0x1f       LXR       1 1 0      1 1 0   0x17
#   XWR       1 1 1      1 1 1   0x3f       LXWR      1 1 1      1 1 1   0x3f
# Round order NONE, R, X, WR, XR, LR, XWR, L, LWR, LX, LXR, LXWR with the A field cycling TOR,
# NA4, NAPOT gives every mode both an allowed and a denied fetch and data access.
#
# Instruction count: about 46260 (46225 on Spike before section B covered pmpcfg1..3; section C
# ~37 per probe, the trap and its check included).
#
# Failure: TEST_FAIL, TESTNUM (gp) as in pmp_region_sweep.h with PHASE 0 (section C),
# PHASE 1 (section A: ROUND = k, REGION = entry), PHASE 2 (section B: wrong legalisation,
# KIND 5, REGION = pmpcfg index),
# KIND 8 PROBE 1 mseccfg did not read back RLB, KIND 7 liveness (PROBE 1 count, 2 allowed).

#include "riscv_test.h"
#include "test_macros.h"
#include "pmp_region_sweep.h"

  .option norvc
  .option norelax

  PROBE_AREA

RVTEST_RV32M
RVTEST_CODE_BEGIN

  li    s5, 0
  li    a2, 0
  li    a3, 0

  # ---- RLB = 1 for the whole test: locked entries stay rewritable ----
  li    TESTNUM, KIND_SETUP | 1
  li    t0, MSECCFG_RLB
  csrw  CSR_MSECCFG, t0
  csrr  t1, CSR_MSECCFG
  bne   t1, t0, fail

  # ---- A. NAPOT sizes: pmpaddr = 2^k - 1, k = 0..31, all 16 entries ----
  li    t3, (PMP_CFG_NAPOT) * 0x01010101
  csrw  pmpcfg0, t3
  csrw  pmpcfg1, t3
  csrw  pmpcfg2, t3
  csrw  pmpcfg3, t3
  li    s10, 0                        # k
  li    t3, 0                         # 2^k - 1
1:
  slli  s9, s10, 8
  li    t0, 1 << 16
  or    s9, s9, t0
  .set .Lk_i, 0
  .rept 16
  csrw  0x3b0 + .Lk_i, t3
  csrr  t2, 0x3b0 + .Lk_i
  ori   TESTNUM, s9, (.Lk_i << 4) | 8
  bne   t2, t3, fail_csr
  .set .Lk_i, .Lk_i + 1
  .endr
  slli  t3, t3, 1
  ori   t3, t3, 1
  addi  s10, s10, 1
  li    t0, 32
  blt   s10, t0, 1b
  csrw  pmpcfg0, zero
  csrw  pmpcfg1, zero
  csrw  pmpcfg2, zero
  csrw  pmpcfg3, zero

  # ---- B. WARL: R = 0, W = 1 is reserved under MML = 0, W reads back 0; every entry ----
  .set .Lb_n, 0
  .rept 4
  li    TESTNUM, KIND_CSR | (2 << 16) | (.Lb_n << 4)
  li    t0, ((PMP_CFG_TOR | PMP_CFG_X | PMP_CFG_W) << 24) | ((PMP_CFG_TOR | PMP_CFG_W) << 16) | ((PMP_CFG_X | PMP_CFG_W) << 8) | PMP_CFG_W
  csrw  0x3a0 + .Lb_n, t0
  csrr  t1, 0x3a0 + .Lb_n
  li    t0, ((PMP_CFG_TOR | PMP_CFG_X) << 24) | (PMP_CFG_TOR << 16) | (PMP_CFG_X << 8)
  bne   t1, t0, fail
  csrw  0x3a0 + .Lb_n, zero
  .set .Lb_n, .Lb_n + 1
  .endr

  # ---- C. 12 rounds x 16 regions x 6 probes ----
  RUN_ROUNDS rounds_mml0, 12, 0, 15, 0, 0xffffffff, 0, 0xffffffff, 0, 0xffffffff, 0, 0xffffffff, 0

  # ---- D. liveness, then clear (the last round's entries are locked: RLB = 1 allows it) ----
  li    TESTNUM, KIND_LIVE | 1
  li    t0, 12 * 16 * 6
  bne   a2, t0, fail
  li    TESTNUM, KIND_LIVE | 2
  li    t0, 720
  bne   a3, t0, fail
  csrw  pmpcfg0, zero
  csrw  pmpcfg1, zero
  csrw  pmpcfg2, zero
  csrw  pmpcfg3, zero
  j     pass

  PROBE_REGION_FN
  FAIL_EXITS
  TRAP_HANDLER

  TEST_PASSFAIL

# {P | A, mask}; A cycles TOR, NA4, NAPOT. Masks: header table.
  .balign 4
rounds_mml0:
  ROUND 0x00, PMP_CFG_TOR,   0x0d     # NONE
  ROUND 0x01, PMP_CFG_NA4,   0x1d     # R
  ROUND 0x04, PMP_CFG_NAPOT, 0x0f     # X
  ROUND 0x03, PMP_CFG_TOR,   0x3d     # WR
  ROUND 0x05, PMP_CFG_NA4,   0x1f     # XR
  ROUND 0x81, PMP_CFG_NAPOT, 0x14     # LR
  ROUND 0x07, PMP_CFG_TOR,   0x3f     # XWR
  ROUND 0x80, PMP_CFG_NA4,   0x00     # L
  ROUND 0x83, PMP_CFG_NAPOT, 0x3c     # LWR
  ROUND 0x84, PMP_CFG_TOR,   0x03     # LX
  ROUND 0x85, PMP_CFG_NA4,   0x17     # LXR
  ROUND 0x87, PMP_CFG_NAPOT, 0x3f     # LXWR
  .balign 4

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
