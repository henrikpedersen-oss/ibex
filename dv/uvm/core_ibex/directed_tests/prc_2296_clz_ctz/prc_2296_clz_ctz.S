# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Test: prc_2296_clz_ctz -- clz / ctz / cpop results (lowRISC/ibex PR #2296)
#
# PR #2296 changes how ibex_alu.sv builds the trailing-zero mask for clz/ctz: (x - 1) & ~x
# instead of ~spread_lowest_set_bit(x) & ~x. Both must give, per Zbb:
#   clz(x) = number of leading zeros, ctz(x) = number of trailing zeros, clz(0) = ctz(0) = 32
#   cpop(x) = number of set bits (shares the popcount tree, selected by the same mux)
# Encoded with .insn (OP-IMM, funct3 001, imm 0x600/0x601/0x602) so no toolchain Zbb support is
# needed. Needs RV32B with Zbb (earlgrey: RV32BFull).
#
# Checks: a table of edge values, then for i = 0..31: 1<<i, (-1)<<i and 0xFFFFFFFF>>i.
# Failure: TEST_FAIL with TESTNUM (gp) =
#   1000 + 10*n + k   table entry n (k: 1 clz, 2 ctz, 3 cpop)
#   2000 + 10*i + k   x = 1 << i
#   3000 + 10*i + k   x = -1 << i
#   4000 + 10*i + k   x = 0xFFFFFFFF >> i (logical)
#   99                liveness: wrong number of checks executed
#   0x10000 | code    unexpected trap while check `code` was in progress

#include "riscv_test.h"
#include "test_macros.h"

#define CLZ(rd, rs1)  .insn i 0x13, 1, rd, rs1, 0x600
#define CTZ(rd, rs1)  .insn i 0x13, 1, rd, rs1, 0x601
#define CPOP(rd, rs1) .insn i 0x13, 1, rd, rs1, 0x602

# Check x in a0 against clz a1, ctz a2, cpop a3; code base in a4. Uses t0, t1. s1 counts checks.
.macro CHECK3
  CLZ(t0, a0)
  addi  TESTNUM, a4, 1
  addi  s1, s1, 1
  bne   t0, a1, fail
  CTZ(t0, a0)
  addi  TESTNUM, a4, 2
  addi  s1, s1, 1
  bne   t0, a2, fail
  CPOP(t0, a0)
  addi  TESTNUM, a4, 3
  addi  s1, s1, 1
  bne   t0, a3, fail
.endm

RVTEST_RV32M
RVTEST_CODE_BEGIN

  li    s1, 0

  # ---- table ----
  la    s2, table
  la    s3, table_end
  li    a4, 1000
1:
  lw    a0, 0(s2)
  lw    a1, 4(s2)
  lw    a2, 8(s2)
  lw    a3, 12(s2)
  CHECK3
  addi  s2, s2, 16
  addi  a4, a4, 10
  bltu  s2, s3, 1b

  # ---- x = 1 << i ----
  li    s4, 0                    # i
  li    s5, 32
2:
  li    a0, 1
  sll   a0, a0, s4
  li    a1, 31
  sub   a1, a1, s4               # clz = 31 - i
  mv    a2, s4                   # ctz = i
  li    a3, 1
  li    a4, 10
  mul   a4, a4, s4
  addi  a4, a4, 2000
  CHECK3
  addi  s4, s4, 1
  bltu  s4, s5, 2b

  # ---- x = -1 << i ----
  li    s4, 0
3:
  li    a0, -1
  sll   a0, a0, s4
  li    a1, 0                    # clz = 0
  mv    a2, s4                   # ctz = i
  li    a3, 32
  sub   a3, a3, s4               # cpop = 32 - i
  li    a4, 10
  mul   a4, a4, s4
  li    t2, 3000
  add   a4, a4, t2
  CHECK3
  addi  s4, s4, 1
  bltu  s4, s5, 3b

  # ---- x = 0xFFFFFFFF >> i ----
  li    s4, 0
4:
  li    a0, -1
  srl   a0, a0, s4
  mv    a1, s4                   # clz = i
  li    a2, 0                    # ctz = 0
  li    a3, 32
  sub   a3, a3, s4               # cpop = 32 - i
  li    a4, 10
  mul   a4, a4, s4
  li    t2, 4000
  add   a4, a4, t2
  CHECK3
  addi  s4, s4, 1
  bltu  s4, s5, 4b

  # ---- liveness: 3 checks per table row + 3 * 3 * 32 ----
  li    TESTNUM, 99
  la    t0, table
  la    t1, table_end
  sub   t1, t1, t0
  srli  t1, t1, 4                # rows
  slli  t0, t1, 1
  add   t0, t0, t1               # 3 * rows
  addi  t0, t0, 288
  bne   s1, t0, fail
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

.balign 4
#            x,           clz, ctz, cpop
table:
  .word 0x00000000,    32,  32,   0
  .word 0x00000001,    31,   0,   1
  .word 0x80000000,     0,  31,   1
  .word 0xFFFFFFFF,     0,   0,  32
  .word 0x00010000,    15,  16,   1
  .word 0x00008000,    16,  15,   1
  .word 0x00F00F00,     8,   8,   8
  .word 0x7FFFFFFE,     1,   1,  30
  .word 0x40000002,     1,   1,   2
  .word 0x12345678,     3,   3,  13
  .word 0xF0000000,     0,  28,   4
  .word 0x0000000F,    28,   0,   4
  .word 0x80000001,     0,   0,   2
  .word 0x00018000,    15,  15,   2
table_end:

RVTEST_DATA_END
