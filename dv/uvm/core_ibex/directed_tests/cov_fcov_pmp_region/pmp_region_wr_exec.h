# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Shared body of cov_fcov_pmp_region_wr_exec_c0..c4. The including test defines
# WR_EXEC_CODE_REGION (0..4): the entry that holds the code rule, and the variant index.
#
# Targets core_ibex_pmp_fcov_if.sv pmp_region_cg.pmp_wr_exec_region, per instance (one per entry
# 0..15). The cross samples, on a write to the entry's pmpcfg CSR while mseccfg.MML = 1 and the
# entry is not executable, the entry's current {MML, L, X, W, R} x the written ones x RLB,
# whether or not the write takes effect. Its 126 bins per entry:
#   from (9)  MML_NONE, MML_RU, MML_WRM_RU, MML_WRU, MML_WRM_WRU      (unlocked)
#             MML_L, MML_RM, MML_WRM, MML_RM_RU                       (locked)
#   to (7)    MML_XU, MML_XRU, MML_XWRU (unlocked), MML_XM_XU, MML_XM, MML_XRM, MML_XRM_XU (locked)
#   x RLB 0/1
# Every other (from, to) is an ignore bin.
#
# Why five tests. With RLB = 0 a locked entry can never be rewritten (Privileged Spec 3.7.1) and
# RLB cannot be set again while any entry is locked (Smepmp 2.3), so an entry reaches only ONE
# locked "from" value with RLB = 0 per reset; and under MML = 1 the test's code needs a locked
# M-executable entry (MML_XRM), which is never a "from" value. Variant v puts the code rule in
# entry v and every other entry i in locked value F[(v - i) mod 5 - 1] (F[0] when that is -1 and
# i != v): each entry is the code entry in at most one variant and sees all four locked values
# over the other four (entries 5..15 see F[0] twice).
#
# Sequence (M-mode throughout, MMWP = 0; all probed entries have A = OFF, so no write changes
# what any access matches):
#   1. RLB := 1; entry C := NAPOT [0x80000000, 0x80001000) L|X|R; the other entries OFF;
#      MML := 1 (mseccfg reads MML | RLB).
#   2. RLB = 1: for each of the 9 "from" values F and 7 "to" values T: every non-code entry := F,
#      then := T. RLB = 1 lifts both the lock (Privileged Spec 3.7.1 with Smepmp 2.3) and the
#      Smepmp rule against new M-executable locked entries, so every write takes effect: each
#      pmpcfg reads back as written. Last, every non-code entry := MML_NONE (unlocked).
#   3. RLB := 0 (mseccfg reads MML). For each unlocked F (5) and each T: := F, then := T. The
#      unlocked T take effect; the locked executable T (MML_XM_XU, MML_XM, MML_XRM, MML_XRM_XU)
#      are ignored (Smepmp 2.3: with MML = 1 and RLB = 0 a rule that is M-mode-only executable
#      or a locked shared region cannot be added), so the entry reads back F.
#   4. Every non-code entry := its locked F for this variant (locked, not executable: allowed).
#      Then each of the 7 T in every byte: all ignored (locked, RLB = 0), every pmpcfg reads
#      back unchanged.
# The code entry's byte is written with its own value throughout (it is executable, so it is
# never sampled).
#
# Instruction count: 9669 to 10082 on Spike, depending on the variant.
#
# Failure: TEST_FAIL with TESTNUM (gp) = STEP << 16 | FROM << 8 | TO << 4 | CSR, where FROM and
# TO are table indices (TO = 15 for the write of F), CSR the pmpcfg index read back wrong;
# STEP 1 setup (0 mseccfg RLB, 1 code rule, 2 mseccfg MML|RLB, 3 code beyond the rule,
# 0x100 | CSR clearing the other entries),
# STEP 2/3/4 as above (step 3 also CSR 4: mseccfg not MML after clearing RLB);
# 0x800000 | ... an unexpected trap (no trap is expected anywhere).

#ifndef WR_EXEC_CODE_REGION
#error "WR_EXEC_CODE_REGION (0..4) must be defined"
#endif

#define C_REG           WR_EXEC_CODE_REGION
#define C_CSR           (C_REG / 4)
#define C_SHIFT         (8 * (C_REG % 4))
#define CODE_BASE       0x80000000
#define CODE_SIZE       0x1000
#define CODE_TOP        (CODE_BASE + CODE_SIZE)
#define CODE_NAPOT      ((CODE_BASE >> 2) | ((CODE_SIZE >> 3) - 1))
#define CODE_CFG        0x9d            /* L | NAPOT | X | R: MML_XRM */

# Write t3 (one byte per entry, replicated) to pmpcfg0..3 with the code entry's byte replaced by
# CODE_CFG, and expect t4 (same treatment) back. TESTNUM's low nibble = CSR index.
.macro WR_ALL_CFG
  .set .Lw_n, 0
  .rept 4
  .if .Lw_n == C_CSR
  li    t0, ~(0xff << C_SHIFT)
  and   t1, t3, t0
  and   t2, t4, t0
  li    t0, CODE_CFG << C_SHIFT
  or    t1, t1, t0
  or    t2, t2, t0
  .else
  mv    t1, t3
  mv    t2, t4
  .endif
  csrw  0x3a0 + .Lw_n, t1
  csrr  t0, 0x3a0 + .Lw_n
  andi  TESTNUM, TESTNUM, -16
  ori   TESTNUM, TESTNUM, .Lw_n
  bne   t0, t2, fail
  .set .Lw_n, .Lw_n + 1
  .endr
.endm

# \dst := \src byte replicated into all four bytes.
.macro REP4 dst, src
  slli  \dst, \src, 8
  or    \dst, \dst, \src
  slli  t0, \dst, 16
  or    \dst, \dst, t0
.endm

# Locked "from" value of entry \i in this variant (the code entry gets CODE_CFG).
.macro LOCKED_BYTE i
  .set .Llb_idx, (C_REG - (\i) + 20) % 5
  .if (\i) == C_REG
  .set .Llb, CODE_CFG
  .elseif .Llb_idx <= 1
  .set .Llb, 0x80             /* MML_L */
  .elseif .Llb_idx == 2
  .set .Llb, 0x81             /* MML_RM */
  .elseif .Llb_idx == 3
  .set .Llb, 0x83             /* MML_WRM */
  .else
  .set .Llb, 0x87             /* MML_RM_RU */
  .endif
.endm

# pmpcfg\n's value in step 4.
.macro LOCKED_WORD n
  LOCKED_BYTE (4 * \n)
  .set .Llw, .Llb
  LOCKED_BYTE (4 * \n + 1)
  .set .Llw, .Llw | (.Llb << 8)
  LOCKED_BYTE (4 * \n + 2)
  .set .Llw, .Llw | (.Llb << 16)
  LOCKED_BYTE (4 * \n + 3)
  .set .Llw, .Llw | (.Llb << 24)
.endm

  .option norvc
  .option norelax

RVTEST_RV32M
RVTEST_CODE_BEGIN

  # ---- 1. setup ----
  li    TESTNUM, (1 << 16) | 3
  lla   t0, code_end
  li    t1, CODE_TOP
  bgtu  t0, t1, fail
  li    TESTNUM, (1 << 16) | 0
  li    t0, MSECCFG_RLB
  csrw  CSR_MSECCFG, t0
  csrr  t1, CSR_MSECCFG
  bne   t1, t0, fail
  li    TESTNUM, (1 << 16) | 1
  li    t0, CODE_NAPOT
  csrw  0x3b0 + C_REG, t0
  csrr  t1, 0x3b0 + C_REG
  bne   t1, t0, fail
  li    t0, CODE_CFG << C_SHIFT
  csrw  0x3a0 + C_CSR, t0
  csrr  t1, 0x3a0 + C_CSR
  bne   t1, t0, fail
  li    TESTNUM, (1 << 16) | 0x100
  li    t3, 0
  li    t4, 0
  WR_ALL_CFG                          # every other entry OFF (INIT_PMP's entry 0 included)
  li    TESTNUM, (1 << 16) | 2
  li    t0, MSECCFG_MML | MSECCFG_RLB
  csrw  CSR_MSECCFG, t0
  csrr  t1, CSR_MSECCFG
  bne   t1, t0, fail

  # ---- 2. RLB = 1: 9 x 7 (from, to), every write takes effect ----
  li    s2, 0                         # from index
1:
  lla   t0, from_all
  add   t0, t0, s2
  lbu   s4, 0(t0)                     # F
  li    s3, 0                         # to index
2:
  lla   t0, to_exec
  add   t0, t0, s3
  lbu   s5, 0(t0)                     # T
  slli  TESTNUM, s2, 8
  ori   TESTNUM, TESTNUM, 0xf0
  li    t0, 2 << 16
  or    TESTNUM, TESTNUM, t0
  REP4  t3, s4
  mv    t4, t3
  WR_ALL_CFG                          # := F
  slli  TESTNUM, s2, 8
  slli  t0, s3, 4
  or    TESTNUM, TESTNUM, t0
  li    t0, 2 << 16
  or    TESTNUM, TESTNUM, t0
  REP4  t3, s5
  mv    t4, t3
  WR_ALL_CFG                          # := T, sampled as (F, T, RLB = 1)
  addi  s3, s3, 1
  li    t0, 7
  blt   s3, t0, 2b
  addi  s2, s2, 1
  li    t0, 9
  blt   s2, t0, 1b
  li    t3, 0
  li    t4, 0
  WR_ALL_CFG                          # all MML_NONE: unlocked again before RLB is cleared

  # ---- 3. RLB = 0: 5 unlocked from x 7 to; locked executable targets are ignored ----
  li    TESTNUM, (3 << 16) | 4
  li    t0, MSECCFG_MML
  csrw  CSR_MSECCFG, t0
  csrr  t1, CSR_MSECCFG
  bne   t1, t0, fail
  li    s2, 0
1:
  lla   t0, from_all
  add   t0, t0, s2
  lbu   s4, 0(t0)                     # F (the first five of from_all are the unlocked ones)
  li    s3, 0
2:
  lla   t0, to_exec
  add   t0, t0, s3
  lbu   s5, 0(t0)
  slli  TESTNUM, s2, 8
  ori   TESTNUM, TESTNUM, 0xf0
  li    t0, 3 << 16
  or    TESTNUM, TESTNUM, t0
  REP4  t3, s4
  mv    t4, t3
  WR_ALL_CFG                          # := F
  slli  TESTNUM, s2, 8
  slli  t0, s3, 4
  or    TESTNUM, TESTNUM, t0
  li    t0, 3 << 16
  or    TESTNUM, TESTNUM, t0
  REP4  t3, s5
  mv    t4, t3
  andi  t0, s5, 0x80
  beqz  t0, 3f
  REP4  t4, s4                        # locked executable target: ignored, reads back F
3:
  WR_ALL_CFG                          # := T, sampled as (F, T, RLB = 0)
  addi  s3, s3, 1
  li    t0, 7
  blt   s3, t0, 2b
  addi  s2, s2, 1
  li    t0, 5
  blt   s2, t0, 1b
  li    t3, 0
  li    t4, 0
  WR_ALL_CFG                          # back to MML_NONE (from an unlocked state)

  # ---- 4. RLB = 0: lock every non-code entry in its variant value, then 7 ignored writes ----
  .set .Lc_n, 0
  .rept 4
  LOCKED_WORD .Lc_n
  li    TESTNUM, (4 << 16) | 0xff0 | .Lc_n
  li    t1, .Llw
  csrw  0x3a0 + .Lc_n, t1
  csrr  t0, 0x3a0 + .Lc_n
  bne   t0, t1, fail
  .set .Lc_n, .Lc_n + 1
  .endr
  li    s3, 0
2:
  lla   t0, to_exec
  add   t0, t0, s3
  lbu   s5, 0(t0)
  slli  TESTNUM, s3, 4
  li    t0, (4 << 16) | 0xf00
  or    TESTNUM, TESTNUM, t0
  REP4  t3, s5
  .set .Lc_n, 0
  .rept 4
  LOCKED_WORD .Lc_n
  .if .Lc_n == C_CSR
  li    t0, ~(0xff << C_SHIFT)
  and   t1, t3, t0
  li    t0, CODE_CFG << C_SHIFT
  or    t1, t1, t0
  .else
  mv    t1, t3
  .endif
  csrw  0x3a0 + .Lc_n, t1             # sampled as (locked F, T, RLB = 0) and ignored
  csrr  t0, 0x3a0 + .Lc_n
  li    t2, .Llw
  andi  TESTNUM, TESTNUM, -16
  ori   TESTNUM, TESTNUM, .Lc_n
  bne   t0, t2, fail
  .set .Lc_n, .Lc_n + 1
  .endr
  addi  s3, s3, 1
  li    t0, 7
  blt   s3, t0, 2b

  j     pass

  TEST_PASSFAIL

# No trap is expected: RVTEST_FAIL only stores to the signature address, which no entry matches
# (M-mode, MMWP = 0).
  .balign 4
  .global mtvec_handler
mtvec_handler:
  li    t6, 0x800000
  or    TESTNUM, TESTNUM, t6
  j     fail

# MML "from" values: the five unlocked first, then the four locked.
from_all:
  .byte 0x00, 0x01, 0x02, 0x03, 0x06, 0x80, 0x81, 0x83, 0x87
# MML executable "to" values: XU, XRU, XWRU, XM_XU, XM, XRM, XRM_XU.
to_exec:
  .byte 0x04, 0x05, 0x07, 0x82, 0x84, 0x85, 0x86
  .balign 4
code_end:

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
