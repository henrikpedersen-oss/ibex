# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cov_block_zcmp_dummy -- Zcmp sequences with dummy instruction insertion on
# =============================================================================
# RISC-V mode (cheriot_enable_i Off; Zcmp is illegal in CHERIoT mode). Cosim off: the Spike
# cosim cannot pair the data-side accesses of one cm.push/cm.pop (GAP-RV-6), as for
# zcmp_push_pop_mv, so the program checks itself against the Zc specification.
#
# Why (suspected RTL defect, found by code reading during the 2026-10-10 block-coverage review,
# not yet seen in simulation): ibex_if_stage.sv drives the compressed decoder's
# id_in_ready_i with `id_in_ready_i & ~pc_set_i` only. When ibex_dummy_instr inserts a dummy
# instruction, ID takes the dummy (instr_out = dummy_instr_data) and the fetch is held
# (fetch_ready includes ~stall_dummy_instr), but the Zcmp FSM in ibex_compressed_decoder.sv
# still sees id_in_ready_i = 1 and advances (CmPushStoreReg/CmPopLoadReg: rlist and sp offset
# step; CmIdle: `valid_i && id_in_ready_i`; the last micro-op: back to CmIdle with the cm.*
# still in IF). The micro-op that was on the decoder output never reaches ID, or, if the dummy
# displaces the last one, the whole cm.* starts again. Nothing in ibex_dummy_instr.sv holds off
# insertion during an expansion (dummy_cnt_en counts every micro-op). The same code is in
# upstream lowRISC/ibex af456e25. With dummy_instr_mask = 0 a dummy is inserted every 1-4
# instructions, so 64 rounds of a 15-micro-op cm.push and cm.pop are all but certain to have
# dummies in the middle of a sequence.
#
# Expected behaviour (Ibex doc/03_reference/security.rst: dummy instructions "have no
# functional impact"; RISC-V Code Size Reduction extensions, Zcmp):
#   cm.push {ra, s0-s11}, -64 (0xB8F2): s11 at sp-4, s10 at sp-8, ... s0 at sp-48, ra at sp-52,
#     then sp -= 64; nothing else in memory is written, no register other than sp changes;
#   cm.pop {ra, s0-s11}, 64 (0xBAF2): the same slots back into the registers, sp += 64;
#   cm.mvsa01 s0, s1 (0xAC26): s0 = a0, s1 = a1; cm.mva01s s2, s3 (0xAD6E): a0 = s2, a1 = s3.
# Encodings as in zcmp_push_pop_mv (ENC_PUSH(15,0), ENC_POP(15,0), ENC_MVSA01(0,1),
# ENC_MVA01S(2,3)).
#
# Block coverage: none of its own (zcmp_push_pop_mv covers the FSM). It is in this testlist
# because the block review found it; it closes no coverage hole.
#
# Failure: TEST_FAIL with TESTNUM (gp); a7 = round, a6 = register number where it applies:
#   1  sp after cm.push not sp-64           2  a pushed slot (register a6) wrong
#   3  a word of the 64-byte frame outside the slots, or the word above it, was written
#   4  a register (a6) changed by cm.push   5  sp after cm.pop not restored
#   6  a register (a6) not restored by cm.pop
#   7  cm.mvsa01 result wrong               8  cm.mva01s result wrong
#   9  cpuctrlsts.dummy_instr_en did not read back set (configuration without DummyInstructions:
#      the test would prove nothing)
#   10 liveness: round count at the end wrong
#   0x100 | code  an unexpected trap (mcause a2, mepc a3)
#
# Proving it can fail (build-time switch, not in the testlist):
#   -DCOV_BLOCK_INJECT_FAIL  expects s11 one too high in its slot -> TESTNUM 2, a6 = 27

#include "riscv_test.h"
#include "test_macros.h"

#define CSR_CPUCTRLSTS 0x7c0
#define CPUCTRL_DUMMY  4
#define CPUCTRL_MASK   0x38
#define NROUNDS        64
#define ZPAT           0x3C5AC3A5
#define POISON         0x0BADF00D

#ifdef COV_BLOCK_INJECT_FAIL
#define ZINJ 1
#else
#define ZINJ 0
#endif

#define ENC_PUSH15   0xB8F2
#define ENC_POP15    0xBAF2
#define ENC_MVSA01   0xAC26
#define ENC_MVA01S   0xAD6E

# Every register of {ra, s0-s11} as (name, number).
.macro FOR_RLIST m
  \m ra,  1
  \m s0,  8
  \m s1,  9
  \m s2,  18
  \m s3,  19
  \m s4,  20
  \m s5,  21
  \m s6,  22
  \m s7,  23
  \m s8,  24
  \m s9,  25
  \m s10, 26
  \m s11, 27
.endm

# a2 = round base value: register n holds a2 + n.
.macro SETV r, n
  addi  \r, a2, \n
.endm
.macro POIS r, n
  li    \r, POISON
.endm
.macro CHKV r, n
  li    a6, \n
  addi  t1, a2, \n
  bne   \r, t1, fail
.endm

# Pushed slot of register n at \off(a3) (a3 = sp before the push).
.macro SLOT off, n, inj=0
  li    a6, \n
  lw    t0, \off(a3)
  addi  t1, a2, \n + \inj
  bne   t0, t1, fail
.endm

# Word at \off(a3) still holds addr ^ ZPAT.
.macro UNTOUCHED off
  addi  t0, a3, \off
  li    t1, ZPAT
  xor   t1, t1, t0
  lw    t0, \off(a3)
  bne   t0, t1, fail
.endm

  .option norvc
  .option norelax

RVTEST_RV32M
RVTEST_CODE_BEGIN

  la    sp, stack_mid
  li    a7, 0

  # ---- Dummy instructions on, at the highest rate ----
  li    t0, CPUCTRL_MASK
  csrc  CSR_CPUCTRLSTS, t0
  csrsi CSR_CPUCTRLSTS, CPUCTRL_DUMMY
  li    TESTNUM, 9
  csrr  t0, CSR_CPUCTRLSTS
  andi  t0, t0, CPUCTRL_DUMMY
  beqz  t0, fail

round:
  # a2 = 0x50000000 + round << 8
  slli  a2, a7, 8
  li    t0, 0x50000000
  add   a2, a2, t0
  mv    a3, sp

  # Fill [sp-64, sp+4) with addr ^ ZPAT.
  addi  t0, a3, -64
  addi  t2, a3, 4
  li    t1, ZPAT
1:
  xor   t3, t0, t1
  sw    t3, 0(t0)
  addi  t0, t0, 4
  bne   t0, t2, 1b

  FOR_RLIST SETV

  # ---- cm.push {ra, s0-s11}, -64 ----
  .hword ENC_PUSH15
  .hword 0x0001                      # c.nop: keeps the next 32-bit instruction word aligned
  li    TESTNUM, 1
  addi  t0, a3, -64
  bne   sp, t0, fail
  li    TESTNUM, 4
  FOR_RLIST CHKV
  li    TESTNUM, 2
  SLOT  -4,  27, ZINJ
  SLOT  -8,  26
  SLOT  -12, 25
  SLOT  -16, 24
  SLOT  -20, 23
  SLOT  -24, 22
  SLOT  -28, 21
  SLOT  -32, 20
  SLOT  -36, 19
  SLOT  -40, 18
  SLOT  -44, 9
  SLOT  -48, 8
  SLOT  -52, 1
  li    TESTNUM, 3
  li    a6, 0
  UNTOUCHED -56
  UNTOUCHED -60
  UNTOUCHED -64
  UNTOUCHED 0

  FOR_RLIST POIS

  # ---- cm.pop {ra, s0-s11}, 64 ----
  .hword ENC_POP15
  .hword 0x0001
  li    TESTNUM, 5
  bne   sp, a3, fail
  li    TESTNUM, 6
  FOR_RLIST CHKV

  # ---- cm.mvsa01 s0, s1 / cm.mva01s s2, s3 ----
  addi  a0, a2, 0x41
  addi  a1, a2, 0x42
  li    s0, POISON
  li    s1, POISON
  .hword ENC_MVSA01
  .hword 0x0001
  li    TESTNUM, 7
  addi  t1, a2, 0x41
  bne   s0, t1, fail
  addi  t1, a2, 0x42
  bne   s1, t1, fail
  addi  s2, a2, 0x43
  addi  s3, a2, 0x44
  li    a0, POISON
  li    a1, POISON
  .hword ENC_MVA01S
  .hword 0x0001
  li    TESTNUM, 8
  addi  t1, a2, 0x43
  bne   a0, t1, fail
  addi  t1, a2, 0x44
  bne   a1, t1, fail

  addi  a7, a7, 1
  li    t0, NROUNDS
  bltu  a7, t0, round

  li    TESTNUM, 10
  li    t0, NROUNDS
  bne   a7, t0, fail

  csrci CSR_CPUCTRLSTS, CPUCTRL_DUMMY
  TEST_PASSFAIL

mtvec_handler:
  csrr  a2, mcause
  csrr  a3, mepc
  ori   TESTNUM, TESTNUM, 0x100
  j     fail

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
  .balign 16
stack_lo:
  .space 256
stack_mid:
  .space 64
RVTEST_DATA_END
