# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: ibex_decode_holes -- packh, packu, reserved OP-IMM encodings, HPM counter writes
# =============================================================================
# RISC-V mode (cheriot_enable_i Off, the riscv-tests default), cosim on.
#
# RTL blocks no regression test reached (Jasper UNR found them reachable, 2026-10-08):
#   ibex_decoder.sv   {7'b000_0100,3'b111} ALU_PACKH and its label in the RV32B legality case
#   ibex_alu.sv       the pack_result packh arm and the ALU_PACKH result label
#   ibex_decoder.sv   default of the unary case (instr[31:27] = 01100, funct3 001) in both the
#                     legality and the ALU decode; srli/srai with instr[25] set
#   ibex_cs_registers.sv  the mhpmcounter3..31 write label (which counter was never written is
#                     not named by the UNR report, so every one is written)
# riscv-dv never emits packh; `pack` only appears as zext.h.
#
# Expected behaviour (not taken from the RTL):
#   - Zbkb (ratified scalar crypto bit-manipulation, in RV32BFull): packh rd = {16'b0, rs2[7:0],
#     rs1[7:0]}. packu belonged to the draft 0.93 Zbp only, which Ibex no longer implements
#     (lowRISC/ibex#2459): it is an illegal instruction.
#   - RV32I: srli/srai with shamt[5] = 1 are reserved, illegal on RV32. OP-IMM funct3 001 with
#     funct7 0110000 and rs2 = 15 is no instruction (Zbb's unary group is clz, ctz, cpop,
#     sext.b, sext.h: rs2 0-2, 4, 5). Illegal instruction: mcause 2, mtval = the instruction
#     (doc/03_reference/cs_registers.rst, mtval).
#   - doc/03_reference/performance_counters.rst: "Unavailable counters always read 0"; the
#     verified configuration has MHPMCounterNum = 10, so mhpmcounter13..31 are unavailable.
#
# Encodings (.word: the directed flow sets no -march):
#   packh a2,a0,a1 = 0x08B57633   packu a2,a0,a1 = 0x48B54633
#   OP-IMM funct3 001 funct7 0110000 rs2 15, rd a2, rs1 a0 = 0x60F51613
#   srli a2,a0 with funct7 0000001 (shamt 33) = 0x02155613
#   srai a2,a0 with funct7 0100001 (shamt 33) = 0x42155613
#
# Failure: the testbench sees TEST_FAIL; TESTNUM (gp) holds the code of the failing check.
#   1  packh result
#   2/3/4/5  the reserved encoding (packu / unary rs2 = 15 / srli shamt 33 / srai shamt 33) took
#          no illegal-instruction exception, or wrote a2
#   6  mhpmcounterN (N = 13..31) read non-zero after writing all-ones
#   0x100 | code  a trap other than the expected illegal instruction (wrong mcause or mtval,
#          or any trap outside checks 2-5)

#include "riscv_test.h"
#include "test_macros.h"

#define A_VAL 0x12345678
#define B_VAL 0x9ABCDEF0
#define POISON 0x0BADF00D

# One reserved encoding: the handler sets s1 when it sees mcause 2 with mtval = \enc (in s3).
.macro ILLEGAL_CHECK code, enc
  li    TESTNUM, \code
  li    s1, 0
  li    s3, \enc
  li    a2, POISON
  .word \enc
  beqz  s1, fail
  li    t1, POISON
  bne   a2, t1, fail
.endm

RVTEST_RV32M
RVTEST_CODE_BEGIN

  li    a0, A_VAL
  li    a1, B_VAL

  li    TESTNUM, 1
  .word 0x08B57633              # packh a2, a0, a1
  li    t1, 0x0000F078
  bne   a2, t1, fail

  ILLEGAL_CHECK 2, 0x48B54633   # packu (draft Zbp only)
  ILLEGAL_CHECK 3, 0x60F51613   # unary group, rs2 = 15
  ILLEGAL_CHECK 4, 0x02155613   # srli shamt 33
  ILLEGAL_CHECK 5, 0x42155613   # srai shamt 33

  # Write every mhpmcounterN low half: 0 to the available ones, all-ones to the rest, which
  # must still read 0.
  li    TESTNUM, 6
  li    t2, 0xFFFFFFFF
  .set N, 3
  .rept 29
    .if N <= 12
      csrw  0xB00 + N, zero
    .else
      csrw  0xB00 + N, t2
      csrr  t0, 0xB00 + N
      bnez  t0, fail
    .endif
    .set N, N + 1
  .endr

  TEST_PASSFAIL

# RVTEST_CODE_BEGIN's trap_vector jumps here (t5, t6 are free).
mtvec_handler:
  li    t5, 2
  blt   TESTNUM, t5, 1f
  li    t5, 5
  bgt   TESTNUM, t5, 1f
  csrr  t5, mcause
  li    t6, CAUSE_ILLEGAL_INSTRUCTION
  bne   t5, t6, 1f
  csrr  t5, mtval
  bne   t5, s3, 1f
  li    s1, 1
  csrr  t5, mepc
  addi  t5, t5, 4
  csrw  mepc, t5
  mret
1:
  ori   TESTNUM, TESTNUM, 0x100
  j     fail

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
