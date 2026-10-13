# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cov_expr_counter_hwrite -- upper-half counter writes with the low half 0 or all-ones
# =============================================================================
# RISC-V mode (cheriot_enable_i Off). Cosim off, as for cov_expr_counter_inhibit and
# cov_block_mcycleh_inhibit: the Spike in this flow does not model mcountinhibit, so the program
# checks the counters itself.
#
# Expression-coverage targets (regression 26231 after UNR, 2026-10-11,
# formal_cov/unr/uncovered_after_exclude.txt), ibex_counter.sv line 46, in the counterh_we_i
# branch (a write to mcycleh / minstreth / mhpmcounterNh):
#   counter_load[31:0] = counter_inc_i ? counter[31:0] + 32'd1 : counter[31:0];
#   row "0 | 0 - 0"  counter_inc_i = 0 with the low half 0: mcycle_counter_i, minstret_counter_i,
#                    gen_cntrs[1] (mhpmcounter4, iside_wait), [7] (mhpmcounter10, compressed
#                    instructions retired), [8] (mhpmcounter11, mul_wait), [9] (mhpmcounter12,
#                    div_wait). Section Z: every counter inhibited, low halves written 0, then the
#                    upper halves written.
#   row "0 | 1 0 -"  counter_inc_i = 1 with the low half 0xFFFFFFFF (counter + 1 = 0):
#                    mcycle_counter_i (section M), minstret_counter_i (section I), gen_cntrs[7]
#                    (section C). The rows of gen_cntrs[6] (taken branches) and gen_cntrs[9]
#                    (div_wait) that need counter_inc_i = 1 are waived (coverage_waivers_xlm.tcl):
#                    their event needs a branch / DIV in ID/EX in the cycle a CSR instruction
#                    there writes the upper half.
#   No regression test wrote an upper half with the low half at 0 or all-ones:
#   counter_high_half_write writes it with mid-range low halves and nothing inhibited,
#   cov_block_mcycleh_inhibit writes mcycleh with mcycle inhibited at non-zero low halves.
#
# How the inc = 1 rows are reached. Every CSR write except mscratch / mepc flushes the pipeline
# (ibex_id_stage.sv csr_pipe_flush), so the cycle distance from `csrw <low>` to the next
# instruction's ID/EX cycle is the flush plus a refetch. The icache is switched on
# (cpuctrlsts.icache_enable) and each loop runs twice: in the second pass every fetch hits, so the
# distance is the same in every iteration.
#   M  mcycle counts every cycle: `csrw mcycle, X ; csrw mcycleh, HW` with X = -s, s = 32..1. The
#      low half at the mcycleh write is X + d (d the fixed distance), so one s puts it at exactly
#      0xFFFFFFFF.
#   I  minstret counts retirements, made in WB (ibex_cs_registers.sv mhpmcounter_incr[2] =
#      instr_ret_i): in `csrw minstret, X ; nop ; csrw minstreth, HW` the nop retires in WB in the
#      cycle the minstreth write is in ID/EX (counter_inc_i = 1). X = -s, s = 8..0: one s puts the
#      low half at 0xFFFFFFFF in that cycle, whether or not the minstret write's own retirement
#      counts.
#   C  mhpmcounter10 counts compressed instructions retired (WB): `csrw mhpmcounter10, -1 ; c.nop
#      ; csrw mhpmcounter10h, 0`, the c.nop retiring as the upper half is written.
#
# Expected behaviour (not taken from the RTL):
#   - RISC-V Privileged ISA: a set mcountinhibit bit stops its counter; on RV32 mcycleh,
#     minstreth and mhpmcounterNh are bits 63:32 of the 64-bit counter, and writing them leaves
#     bits 31:0 alone; the counter carries from bits 31:0 into 63:32.
#   - Verified configuration (MHPMCounterNum = 10, MHPMCounterWidth = 32, ibex_configs.yaml
#     opentitan; doc/03_reference/performance_counters.rst): mhpmcounter3..12 are 32 bits wide,
#     so mhpmcounterNh reads 0 and the counter wraps from 0xFFFFFFFF to 0.
#   - Sections M and I: whether a carry out of bits 31:0 in the cycle of the upper-half write is
#     lost to the written value is left to the implementation, so each iteration accepts HW or
#     HW + 1 in the upper half (after waiting for any carry still to come), with a small low half.
#     Every s in M with X + d >= 2^32 (s = 1: X = 0xFFFFFFFF) wrapped before the write and must
#     read HW, every s with X + d <= 0xFFFFFFFE wraps after it and must read HW + 1; I's s = 0
#     (X = 0) never wraps (HW) and s = 8 does (HW + 1). Both values must be seen in the second
#     pass of each, which shows the sweep straddled 0xFFFFFFFF.
#
# Failure: TEST_FAIL with TESTNUM (gp):
#   1      mcountinhibit did not read back 0x1FFD (bits 0, 2..12)
#   2/3    mcycle != 0 / mcycleh != HZ after the inhibited writes
#   4/5    minstret != 0 / minstreth != HZ
#   6-9    mhpmcounter4 / 10 / 11 / 12 != 0      10-13  mhpmcounter4h / 10h / 11h / 12h != 0
#   20/21  M: mcycle low half not below 0x10000 / mcycleh neither HW nor HW + 1 (s3 = s)
#   22/23  M: HW / HW + 1 never seen in the second pass
#   24/25  I: minstret low half not below 0x1000 / minstreth neither HW nor HW + 1 (s3 = s)
#   26/27  I: HW / HW + 1 never seen in the second pass
#   30/31  C: mhpmcounter10h != 0 / mhpmcounter10 != 0 after the wrap
#   0x100 | code  an unexpected trap
#
# Proving it can fail (build-time switch, not in the testlist):
#   -DCOV_EXPR_INJECT_FAIL  leaves mcountinhibit clear in section Z -> mcycle counts -> TESTNUM 2

#include "riscv_test.h"
#include "test_macros.h"

#define CSR_CPUCTRLSTS  0x7c0
#define INHIBIT_ALL     0x1FFD          /* mcountinhibit: mcycle, minstret, mhpmcounter3..12 */
#define HZ              0x5A5A0003      /* upper half written in section Z */
#define HW              0x00C0FFEE      /* upper half written in sections M and I */

# Busy-wait \n loop iterations (t2).
.macro WAIT n
  li    t2, \n
91:
  addi  t2, t2, -1
  bnez  t2, 91b
.endm

# \reg must read \val (t6), else fail with \code.
.macro CHK_CSR csr, val, code
  li    TESTNUM, \code
  csrr  t5, \csr
  li    t6, \val
  bne   t5, t6, fail
.endm

  .option norvc
  .option norelax

RVTEST_RV32M
RVTEST_CODE_BEGIN

  # ---- Z: upper halves written while every counter is inhibited and its low half is 0 ----
  li    t0, INHIBIT_ALL
#ifdef COV_EXPR_INJECT_FAIL
  li    t0, 0
#endif
  csrw  mcountinhibit, t0
#ifndef COV_EXPR_INJECT_FAIL
  CHK_CSR mcountinhibit, INHIBIT_ALL, 1
#endif
  csrw  mcycle, zero
  csrw  minstret, zero
  csrw  mhpmcounter4, zero
  csrw  mhpmcounter10, zero
  csrw  mhpmcounter11, zero
  csrw  mhpmcounter12, zero
  li    t1, HZ
  csrw  mcycleh, t1
  csrw  minstreth, t1
  csrw  mhpmcounter4h, t1
  csrw  mhpmcounter10h, t1
  csrw  mhpmcounter11h, t1
  csrw  mhpmcounter12h, t1
  WAIT  8
  CHK_CSR mcycle, 0, 2
  CHK_CSR mcycleh, HZ, 3
  CHK_CSR minstret, 0, 4
  CHK_CSR minstreth, HZ, 5
  CHK_CSR mhpmcounter4, 0, 6
  CHK_CSR mhpmcounter10, 0, 7
  CHK_CSR mhpmcounter11, 0, 8
  CHK_CSR mhpmcounter12, 0, 9
  CHK_CSR mhpmcounter4h, 0, 10
  CHK_CSR mhpmcounter10h, 0, 11
  CHK_CSR mhpmcounter11h, 0, 12
  CHK_CSR mhpmcounter12h, 0, 13
  csrw  mcountinhibit, zero

  # Fetches hit in the icache from the second pass of each loop on.
  csrsi CSR_CPUCTRLSTS, 1

  # ---- M: mcycleh written with mcycle's low half at 0xFFFFFFFF ----
  li    s5, 0                       # pass
10:
  li    s3, 32                      # s
  li    s6, 0                       # HW seen
  li    s7, 0                       # HW + 1 seen
11:
  neg   t0, s3
  li    t1, HW
  csrw  mcycle, t0
  csrw  mcycleh, t1
  WAIT  40
  csrr  a0, mcycleh
  csrr  a1, mcycle
  li    TESTNUM, 20
  li    t3, 0x10000
  bgeu  a1, t3, fail
  li    t3, HW
  bne   a0, t3, 12f
  li    s6, 1
  j     13f
12:
  addi  t3, t3, 1
  li    TESTNUM, 21
  bne   a0, t3, fail
  li    s7, 1
13:
  addi  s3, s3, -1
  bnez  s3, 11b
  addi  s5, s5, 1
  li    t3, 2
  blt   s5, t3, 10b
  li    TESTNUM, 22
  beqz  s6, fail
  li    TESTNUM, 23
  beqz  s7, fail

  # ---- I: minstreth written with minstret's low half at 0xFFFFFFFF and a retirement in WB ----
  li    s5, 0
20:
  li    s3, 8
  li    s6, 0
  li    s7, 0
21:
  neg   t0, s3
  li    t1, HW
  csrw  minstret, t0
  nop
  csrw  minstreth, t1
  WAIT  16
  csrr  a0, minstreth
  csrr  a1, minstret
  li    TESTNUM, 24
  li    t3, 0x1000
  bgeu  a1, t3, fail
  li    t3, HW
  bne   a0, t3, 22f
  li    s6, 1
  j     23f
22:
  addi  t3, t3, 1
  li    TESTNUM, 25
  bne   a0, t3, fail
  li    s7, 1
23:
  addi  s3, s3, -1
  bgez  s3, 21b
  addi  s5, s5, 1
  li    t3, 2
  blt   s5, t3, 20b
  li    TESTNUM, 26
  beqz  s6, fail
  li    TESTNUM, 27
  beqz  s7, fail

  # ---- C: mhpmcounter10h written as a compressed instruction retires with the count at -1 ----
  li    s5, 0
30:
  li    t0, -1
  csrw  mhpmcounter10, t0
  .balign 8                         # c.nop and the 32-bit write behind it in one 64-bit line
  .hword 0x0001                     # c.nop
  csrw  mhpmcounter10h, zero
  WAIT  8
  CHK_CSR mhpmcounter10h, 0, 30
  CHK_CSR mhpmcounter10, 0, 31
  addi  s5, s5, 1
  li    t3, 2
  blt   s5, t3, 30b
  .hword 0x0001                     # c.nop: back to 32-bit alignment

  TEST_PASSFAIL

mtvec_handler:
  ori   TESTNUM, TESTNUM, 0x100
  j     fail

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
