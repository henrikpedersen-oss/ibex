# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cov_block_zbk -- Zbkb / Zbkx instructions riscv-dv never generates
# =============================================================================
# RISC-V mode (cheriot_enable_i Off), Spike cosim on (ISA string ..._Zbkb_Zbkx for RV32BFull,
# core_ibex_base_test.sv get_isa_string).
#
# Block-coverage targets (merged regression 30527 after UNR, 2026-10-10,
# formal_cov/unr/uncovered_after_exclude.txt). riscv-dv's ibex target lists RV32ZBA/ZBB/ZBC/ZBS
# and the draft RV32B group (riscv_core_setting.tpl.sv), none of which is Zbkb/Zbkx, so after the
# upstream merge to ratified bitmanip (RV32BFull = Zba Zbb Zbc Zbs Zbkb Zbkx) nothing executes:
#   ibex_decoder.sv  OP-IMM 001 5'b0_0001 (zip / reserved shfli, lines 473-478), OP-IMM 101
#                    5'b0_1101 brev8 and reserved grevi (511-514), 5'b0_0101 reserved gorci (520),
#                    5'b0_0001 unzip / reserved unshfli (522-525), OP pack with rs2 != x0 (578-579),
#                    the xperm4 / xperm8 labels (584-590); ALU decode 1048, 1079, 1084 (the
#                    implicit else), 1088, 1138-1139, 1160-1164.
#   ibex_alu.sv      result mux ALU_ZIP/ALU_UNZIP (844), ALU_XPERM4/ALU_XPERM8 (847), ALU_BREV8
#                    (874); gen_alu_rvb_full shuffle_flip (586, 595, 628), the xperm sel/vld
#                    conversion (678-690) and gen_xperm_n[0..7] `vld[i] ? val_n[sel[i]] : '0`
#                    true part (706: every nibble needs a valid selector at least once).
#
# Expression-coverage targets (regression 26231 after UNR, 2026-10-11, uncovered_after_exclude.txt),
# ibex_alu.sv gen_alu_rvb_full, the two shuffle_flip stages of unzip (lines 596-604 and 629-637):
#   the 9-term OR `(s & 32'h8822_4411) | ((s << 6) & FLIP_MASK_L[0]) | ... | ((s >> 21) &
#   FLIP_MASK_R[3])`, rows "term k is the first non-zero one" (k = 2..9) and "all zero", and each
#   term's `&` row with its shifted operand zero. The flip is a bit permutation whose nine terms
#   partition the 32 bits, so unzip of 0 and of every single-bit operand 1 << b (b = 0..31) gives
#   every row of both stages (the second stage sees a permutation of the operand, again one bit).
#   Checks 1-4 and 14 make the first term non-zero every time, which is why only row 1 was hit.
#   Checks 15-16 below; a Python model of the RTL network confirmed the row reach (2026-10-11).
#
# Expected values come from the ratified specification (RISC-V Bit-Manipulation ISA-extensions
# 1.0.0, Zbkb and Zbkx), computed independently of the RTL (Python model of the spec pseudo-code):
#   zip   rd[2i] = rs1[i], rd[2i+1] = rs1[i+16]          unzip  the inverse
#   brev8 bit order reversed inside each byte              pack   {rs2[15:0], rs1[15:0]}
#   xperm4 rd.nibble[i] = rs2.nibble[i] < 8 ? rs1.nibble[rs2.nibble[i]] : 0
#   xperm8 rd.byte[i]   = rs2.byte[i]   < 4 ? rs1.byte[rs2.byte[i]]     : 0
# Reserved encodings: the Zbkb forms are the shfli/unshfli/grevi/gorci immediates fixed at
# 0x0F (zip/unzip), 0x07 (brev8, orc.b) and 0x18 (rev8); every other immediate of those
# instructions is not part of any ratified extension and must raise an illegal instruction
# exception with mtval = the instruction (Ibex doc/03_reference/cs_registers.rst, mtval), rd
# unwritten. Encodings are .word (binutils 2.35 has no Zbk mnemonics):
#   zip    a2, a0      0x08F51613   unzip  a2, a0      0x08F55613   brev8  a2, a0  0x68755613
#   xperm4 a2, a0, a1  0x28B52633   xperm8 a2, a0, a1  0x28B54633   pack   a2, a0, a1 0x08B54633
#   shfli  a2, a0, 8   0x08851613   unshfli a2, a0, 8  0x08855613
#   grevi  a2, a0, 1   0x68155613   gorci  a2, a0, 1   0x28155613
#
# Failure: TEST_FAIL with TESTNUM (gp):
#   1-2  zip (two operands)     3-4  unzip      5-6  brev8      7-9  xperm4      10-12 xperm8
#   13   pack                   14   zip;unzip round trip (rd = rs1)
#   15   unzip(0) != 0          16   unzip(1 << b) != the spec's single bit (s4 = b): bit 2i
#                                    goes to i, bit 2i+1 to 16 + i
#   20-23 a reserved encoding did not trap with mcause 2 / mtval = it, or wrote a2
#   0x100 | code  an unexpected trap (wrong mcause or mtval, or a trap outside checks 20-23)
#
# Proving it can fail (build-time switch, not in the testlist):
#   -DCOV_BLOCK_INJECT_FAIL  check 1 expects zip(A1) with bit 0 flipped -> TESTNUM 1

#include "riscv_test.h"
#include "test_macros.h"

#define POISON  0x0BADF00D
#define OPA     0x8E3C5A17
#define OPB     0x12345678

#ifdef COV_BLOCK_INJECT_FAIL
#define ZINJ 1
#else
#define ZINJ 0
#endif

#define ENC_ZIP     0x08F51613
#define ENC_UNZIP   0x08F55613
#define ENC_BREV8   0x68755613
#define ENC_XPERM4  0x28B52633
#define ENC_XPERM8  0x28B54633
#define ENC_PACK    0x08B54633
#define ENC_SHFLI8  0x08851613
#define ENC_UNSHFL8 0x08855613
#define ENC_GREVI1  0x68155613
#define ENC_GORCI1  0x28155613

# a2 := op(a0, a1) for the instruction word \enc; a2 must equal \exp.
.macro RCHECK code, enc, a, b, exp
  li    TESTNUM, \code
  li    a0, \a
  li    a1, \b
  li    a2, POISON
  .word \enc
  li    t1, \exp
  bne   a2, t1, fail
.endm

# One reserved encoding: the handler sets s1 when it sees mcause 2 with mtval = \enc (in s3).
.macro ILLEGAL_CHECK code, enc
  li    TESTNUM, \code
  li    s1, 0
  li    s3, \enc
  li    a0, OPA
  li    a2, POISON
  .word \enc
  beqz  s1, fail
  li    t1, POISON
  bne   a2, t1, fail
.endm

  .option norvc
  .option norelax

RVTEST_RV32M
RVTEST_CODE_BEGIN

  # ---- Zbkb ----
  RCHECK 1,  ENC_ZIP,    OPA, 0,          (0x91EC0BB5 ^ ZINJ)
  RCHECK 2,  ENC_ZIP,    OPB, 0,          0x131C1F60
  RCHECK 3,  ENC_UNZIP,  OPA, 0,          0xB63126C7
  RCHECK 4,  ENC_UNZIP,  OPB, 0,          0x141646EC
  RCHECK 5,  ENC_BREV8,  OPA, 0,          0x713C5AE8
  RCHECK 6,  ENC_BREV8,  OPB, 0,          0x482C6A1E
  RCHECK 13, ENC_PACK,   OPA, OPB,        0x56785A17

  # ---- Zbkx: all selectors valid (every gen_xperm_n[i] takes its true part), mixed, none ----
  RCHECK 7,  ENC_XPERM4, OPA, 0x76543210, OPA
  RCHECK 8,  ENC_XPERM4, OPA, 0x0F1E2D3C, 0x7010A050
  RCHECK 9,  ENC_XPERM4, OPA, 0x89ABCDEF, 0x00000000
  RCHECK 10, ENC_XPERM8, OPA, 0x03020100, OPA
  RCHECK 11, ENC_XPERM8, OPA, 0x00010302, 0x175A8E3C
  RCHECK 12, ENC_XPERM8, OPA, 0x04FF0280, 0x00003C00

  # ---- zip then unzip gives the operand back (rd of the first is rs1 of the second) ----
  li    TESTNUM, 14
  li    a0, OPA
  .word ENC_ZIP
  mv    a0, a2
  .word ENC_UNZIP
  li    t1, OPA
  bne   a2, t1, fail

  # ---- unzip of 0 and of each single-bit operand: every row of both shuffle_flip stages ----
  li    TESTNUM, 15
  li    a0, 0
  li    a2, POISON
  .word ENC_UNZIP
  bnez  a2, fail
  li    TESTNUM, 16
  li    s4, 0                       # b
1:
  li    a0, 1
  sll   a0, a0, s4
  li    a2, POISON
  .word ENC_UNZIP
  srli  t2, s4, 1                   # expected: 1 << (b/2 + 16 * (b & 1))
  andi  t3, s4, 1
  slli  t3, t3, 4
  add   t2, t2, t3
  li    t1, 1
  sll   t1, t1, t2
  bne   a2, t1, fail
  addi  s4, s4, 1
  li    t3, 32
  blt   s4, t3, 1b

  # ---- Reserved immediates of the Zbkb/Zbb forms ----
  ILLEGAL_CHECK 20, ENC_SHFLI8
  ILLEGAL_CHECK 21, ENC_UNSHFL8
  ILLEGAL_CHECK 22, ENC_GREVI1
  ILLEGAL_CHECK 23, ENC_GORCI1

  TEST_PASSFAIL

# RVTEST_CODE_BEGIN's trap_vector jumps here (t5, t6 are free): only checks 20-23 may trap.
mtvec_handler:
  li    t5, 20
  blt   TESTNUM, t5, 1f
  li    t5, 23
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
