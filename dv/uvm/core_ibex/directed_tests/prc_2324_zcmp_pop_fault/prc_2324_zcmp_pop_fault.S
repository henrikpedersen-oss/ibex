# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Test: prc_2324_zcmp_pop_fault -- a cm.pop that faults part-way, then a normal cm.pop, cosim on
#                                   (lowRISC/ibex PR #2324)
#
# PR #2324 teaches the Spike cosim to pair the several RVFI items Ibex retires for one Zcmp
# instruction with Spike's single step. Its bookkeeping (pending_expanded_insn, dut_reg_changes)
# is cleared only on the last operation; a trap part-way through returns from step() early and
# leaves it set, so the next expanded instruction is checked against stale state. This test
# makes exactly that happen and then runs an ordinary cm.pop with the cosim ON: a cosim that does
# not recover reports a mismatch (UVM_FATAL) at the second cm.pop.
#
# Only cm.pop is used: the frames are written with plain stores (STORE_FRAME, the same layout
# cm.push {ra,s0-s1},-16 produces), so this test does not depend on how the cosim handles
# cm.push. prc_2324_zcmp_push_pop covers cm.push followed by cm.pop.
#
# How the fault is made: PMP entry 0 is a locked NA4 region with no permissions over the s0
# slot of a {ra, s0-s1} frame, so the M-mode load of s0 by cm.pop takes a load access fault
# (mseccfg.RLB = 1 first, so the lock can be removed again). Entry 1 allows everything.
# Which of ra/s1 was loaded before the fault is implementation defined (Zc spec: the
# instruction is restartable), so the test rewrites ra, s0, s1 after the trap before using them.
#
# Expected (Zc spec, privileged spec): the faulting cm.pop traps with mcause 5, mepc = its own
# PC, mtval = the s0 slot address, and leaves sp unchanged (the sp update is the last step).
#
# Encoding (binutils 2.35 has no Zcmp mnemonics): cm.pop {ra,s0-s1},16 = 0xBA62 (rlist 6,
# spimm 0, stack_adj 16).
#
# Failure: TEST_FAIL with TESTNUM (gp) =
#   1  no trap from the faulting cm.pop       2  mcause != 5
#   3  mepc != the cm.pop's address           4  mtval != the s0 slot
#   5  sp changed by the faulting cm.pop      6-8  second pop: ra, s0, s1 wrong
#   9  sp wrong after the second pop          10 liveness (trap count != 1)
#   0x10000|code  unexpected trap while check `code` was in progress

#include "riscv_test.h"
#include "test_macros.h"

#define CM_POP_RA_S1_16   .hword 0xBA62

# The frame cm.push {ra,s0-s1},-16 writes, with plain stores: s1 at sp-4, s0 at sp-8,
# ra at sp-12, then sp -= 16.
#define STORE_FRAME \
  sw s1, -4(sp); sw s0, -8(sp); sw ra, -12(sp); addi sp, sp, -16

#define PMP_NA4_CFG 0x10
#define PMP_LOCK    0x80

RVTEST_RV32M
RVTEST_CODE_BEGIN

  li    s2, 0                    # expected-trap flag
  li    s3, 0                    # trap count

  # mseccfg.RLB = 1 (no entry is locked yet), so the lock below can be removed later.
  csrsi 0x747, 4

  la    s4, frame_top            # sp before push (16-byte aligned)
  addi  s5, s4, -8               # s0 slot: push stores s1 at sp-4, s0 at sp-8, ra at sp-12

  # ---- first push: ra, s0, s1 = known values ----
  mv    s6, sp                   # keep the program's sp
  mv    sp, s4
  li    ra, 0x11111111
  li    s0, 0x22222222
  li    s1, 0x33333333
  STORE_FRAME                    # what cm.push {ra,s0-s1},-16 does, with plain stores
  # sp = s4 - 16

  # ---- lock a no-access NA4 region on the s0 slot ----
  srli  t0, s5, 2
  csrw  pmpaddr0, t0
  li    t0, -1
  csrw  pmpaddr1, t0             # NAPOT over everything
  li    t0, ((PMP_NAPOT | PMP_R | PMP_W | PMP_X) << 8) | PMP_LOCK | PMP_NA4_CFG
  csrw  pmpcfg0, t0

  # ---- the faulting cm.pop ----
  li    TESTNUM, 1
  li    s2, 1
  la    s7, pop_fault
pop_fault:
  CM_POP_RA_S1_16
  # handler returns here (mepc + 2)
  li    s2, 0
  beqz  s3, fail                 # 1: no trap

  li    TESTNUM, 2
  li    t0, 5
  bne   a2, t0, fail
  li    TESTNUM, 3
  bne   a3, s7, fail
  li    TESTNUM, 4
  bne   a4, s5, fail
  li    TESTNUM, 5
  addi  t0, s4, -16
  bne   sp, t0, fail

  # ---- unlock (RLB = 1) and restore allow-all in entry 0 ----
  li    t0, -1
  csrw  pmpaddr0, t0
  li    t0, PMP_NAPOT | PMP_R | PMP_W | PMP_X
  csrw  pmpcfg0, t0

  # ---- ordinary push/pop with new values; the cosim must still be in step ----
  mv    sp, s4
  li    ra, 0x44444444
  li    s0, 0x55555555
  li    s1, 0x66666666
  STORE_FRAME
  li    ra, 0
  li    s0, 0
  li    s1, 0
  CM_POP_RA_S1_16

  li    TESTNUM, 6
  li    t0, 0x44444444
  bne   ra, t0, fail
  li    TESTNUM, 7
  li    t0, 0x55555555
  bne   s0, t0, fail
  li    TESTNUM, 8
  li    t0, 0x66666666
  bne   s1, t0, fail
  li    TESTNUM, 9
  bne   sp, s4, fail

  li    TESTNUM, 10
  li    t0, 1
  bne   s3, t0, fail
  mv    sp, s6
  j     pass

  TEST_PASSFAIL

# The expected trap (s2 = 1): record mcause/mepc/mtval in a2/a3/a4, skip the 2-byte cm.pop.
.balign 256
mtvec_handler:
  beqz  s2, 1f
  addi  s3, s3, 1
  csrr  a2, mcause
  csrr  a3, mepc
  csrr  a4, mtval
  addi  t0, a3, 2
  csrw  mepc, t0
  mret
1:
  li    t6, 0x10000
  or    TESTNUM, TESTNUM, t6
  j     fail

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA

.balign 16
frame:
  .space 64
frame_top:
  .space 16

RVTEST_DATA_END
