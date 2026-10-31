# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Test: prc_2046_zicond -- czero.eqz / czero.nez results (lowRISC/ibex PR #2046)
#
# Zicond 1.0: czero.eqz rd, rs1, rs2: rd = (rs2 == 0) ? 0 : rs1
#             czero.nez rd, rs1, rs2: rd = (rs2 != 0) ? 0 : rs1
# Encoded with .insn (OP, funct3 101 / 111, funct7 0000111) so no toolchain support is needed.
#
# The operands are chosen so that a core that decodes the instructions as legal but computes
# something else (for example SLTU, the decoder's default ALU operator) gives a wrong answer:
# rs1 = 5, rs2 = 7 -> eqz 5, nez 0 (SLTU would give 1 for both).
#
# Without Zicond in the RTL the first czero traps as an illegal instruction: code 0x101.
#
# Failure: TEST_FAIL with TESTNUM (gp) =
#   1  czero.eqz with rs2 != 0 did not return rs1
#   2  czero.eqz with rs2 == 0 did not return 0
#   3  czero.nez with rs2 != 0 did not return 0
#   4  czero.nez with rs2 == 0 did not return rs1
#   5  czero.eqz with rd == rs2 (rs2 read before rd written) wrong
#   0x100|code  trap (illegal instruction) while check `code` was in progress

#include "riscv_test.h"
#include "test_macros.h"

#define CZERO_EQZ(rd, rs1, rs2) .insn r 0x33, 5, 7, rd, rs1, rs2
#define CZERO_NEZ(rd, rs1, rs2) .insn r 0x33, 7, 7, rd, rs1, rs2

RVTEST_RV32M
RVTEST_CODE_BEGIN

  li    a1, 5
  li    a2, 7

  li    TESTNUM, 1
  li    a0, 0x55
  CZERO_EQZ(a0, a1, a2)
  bne   a0, a1, fail

  li    TESTNUM, 2
  li    a0, 0x55
  CZERO_EQZ(a0, a1, zero)
  bnez  a0, fail

  li    TESTNUM, 3
  li    a0, 0x55
  CZERO_NEZ(a0, a1, a2)
  bnez  a0, fail

  li    TESTNUM, 4
  li    a0, 0x55
  CZERO_NEZ(a0, a1, zero)
  bne   a0, a1, fail

  li    TESTNUM, 5
  li    a3, -1
  CZERO_EQZ(a3, a1, a3)          # rs2 = a3 = -1 != 0 -> a3 = a1
  bne   a3, a1, fail

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
