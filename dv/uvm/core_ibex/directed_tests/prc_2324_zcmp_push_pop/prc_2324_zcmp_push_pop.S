# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Test: prc_2324_zcmp_push_pop -- cm.push then cm.pop with the cosim on (lowRISC/ibex PR #2324)
#
# The basic claim of PR #2324: the Spike cosim can check Zcmp instructions, which Ibex retires as
# several RVFI items at one PC while Spike executes them in one step. The simplest real use is a
# function prologue/epilogue: cm.push, some code, cm.pop at another address. Run with the cosim
# ON (no +disable_cosim): any bookkeeping left over from the cm.push shows up as a cosim mismatch
# at the cm.pop.
#
# Also self-checking against the Zc spec: cm.push {ra,s0-s1},-16 stores s1 at sp-4, s0 at sp-8,
# ra at sp-12 and subtracts 16 from sp; cm.pop {ra,s0-s1},16 loads them back and adds 16.
# Encodings (binutils 2.35 has no Zcmp mnemonics): cm.push = 0xB862, cm.pop = 0xBA62.
#
# Failure: TEST_FAIL with TESTNUM (gp) =
#   1  sp after cm.push != sp - 16       2-4  stored s1, s0, ra wrong in memory
#   5-7  ra, s0, s1 after cm.pop wrong   8  sp after cm.pop != the original sp
#   9  second round (push/pop again at other addresses): a value wrong
#   0x10000|code  unexpected trap while check `code` was in progress

#include "riscv_test.h"
#include "test_macros.h"

#define CM_PUSH_RA_S1_16  .hword 0xB862
#define CM_POP_RA_S1_16   .hword 0xBA62

RVTEST_RV32M
RVTEST_CODE_BEGIN

  mv    s6, sp                   # keep the program's sp
  la    s4, frame_top
  mv    sp, s4
  li    ra, 0x11111111
  li    s0, 0x22222222
  li    s1, 0x33333333

  li    TESTNUM, 1
  CM_PUSH_RA_S1_16
  addi  t0, s4, -16
  bne   sp, t0, fail
  li    TESTNUM, 2
  lw    t1, -4(s4)
  bne   t1, s1, fail
  li    TESTNUM, 3
  lw    t1, -8(s4)
  bne   t1, s0, fail
  li    TESTNUM, 4
  lw    t1, -12(s4)
  bne   t1, ra, fail

  li    ra, 0
  li    s0, 0
  li    s1, 0
  li    TESTNUM, 5
  CM_POP_RA_S1_16                # a different PC from the cm.push
  li    t0, 0x11111111
  bne   ra, t0, fail
  li    TESTNUM, 6
  li    t0, 0x22222222
  bne   s0, t0, fail
  li    TESTNUM, 7
  li    t0, 0x33333333
  bne   s1, t0, fail
  li    TESTNUM, 8
  bne   sp, s4, fail

  # Second round, again at new addresses.
  li    TESTNUM, 9
  li    ra, 0x44444444
  li    s0, 0x55555555
  li    s1, 0x66666666
  CM_PUSH_RA_S1_16
  li    ra, 0
  li    s0, 0
  li    s1, 0
  CM_POP_RA_S1_16
  li    t0, 0x44444444
  bne   ra, t0, fail
  li    t0, 0x55555555
  bne   s0, t0, fail
  li    t0, 0x66666666
  bne   s1, t0, fail
  bne   sp, s4, fail

  mv    sp, s6
  li    TESTNUM, 99
  j     pass

  TEST_PASSFAIL

.balign 256
mtvec_handler:
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
