# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cov_expr_fetch_wrap -- a 32-bit instruction at 2^32 - 2 whose second half (at 0) faults
# =============================================================================
# RISC-V mode (cheriot_enable_i Off). Cosim off: the second half of this instruction is at
# address 0 after the 32-bit wrap of pc + 2, which Spike computes in 64 bits; the expected values
# below come from the specification, not from either model.
#
# Expression-coverage target (merged regression after UNR, 2026-10-09):
#   ibex_controller.sv `instr_fetch_err_plus2_i ? (pc_id_i + 32'd2) : pc_id_i`, row plus2 = 1
#   with pc_id_i + 2 = 0: an instruction access fault on the second half of an uncompressed
#   instruction at 0xFFFFFFFE.
#
# Expected behaviour (RISC-V Privileged ISA): the instruction at 0xFFFFFFFE continues at
# address 0 (RV32 addresses wrap). With PMP entry 1 a locked TOR entry [0, 4) without X, the
# fetch of its second half faults: mcause 1 (instruction access fault), mepc = 0xFFFFFFFE (the
# instruction), mtval = 0 (the faulting part of the access: mtval "is written with the
# faulting virtual address"; Ibex reports pc + 2 for a fault on the second half, see
# doc/03_reference/exception_interrupts.rst).
# Control case first, without the PMP entry: the same instruction (addi x0, x0, 0) executes and
# the `ret` at address 2 returns, so the fault in the second case comes from the entry.
#
# Failure: TEST_FAIL with TESTNUM (gp):
#   1  control case: a trap, or did not return
#   2  PMP case: no trap      3 mcause not 1      4 mepc not 0xFFFFFFFE      5 mtval not 0
#   0x100 | code  an unexpected trap

#include "riscv_test.h"
#include "test_macros.h"

#define CSR_MSECCFG   0x747
#define MSECCFG_RLB   0x4
#define PMP_TOR_L     0x88          /* A = TOR, L = 1, no permissions */

  .option norvc
  .option norelax

RVTEST_RV32M
RVTEST_CODE_BEGIN

  li    s8, 0                       # 1: a trap is expected
  csrsi CSR_MSECCFG, MSECCFG_RLB
  csrw  pmpcfg0, zero
  csrw  pmpcfg1, zero
  csrw  pmpcfg2, zero
  csrw  pmpcfg3, zero

  # 0xFFFFFFFE: low half of addi x0, x0, 0 (0x00000013); 0x0: its high half (0x0000);
  # 0x2: ret (0x00008067).
  li    t0, -2
  li    t1, 0x0013
  sh    t1, 0(t0)
  li    t1, 0x80670000
  sw    t1, 0(zero)
  sw    zero, 4(zero)
  fence.i

  # ---- Control: no PMP entry, the wrapped instruction runs and returns ----
  # (A trap here reaches mtvec_handler with s8 = 0: code 0x101. Not returning: timeout.)
  li    TESTNUM, 1
  li    t0, -2
  jalr  ra, 0(t0)

  # ---- PMP entry 1: locked TOR [0, 4) without X ----
  csrw  pmpaddr0, zero
  li    t0, 1
  csrw  pmpaddr1, t0
  li    t0, PMP_TOR_L << 8
  csrw  pmpcfg0, t0
  li    TESTNUM, 2
  li    s8, 1
  la    s11, 1f
  li    t0, -2
  jalr  ra, 0(t0)
  j     fail                        # did not trap
1:
  li    TESTNUM, 3
  li    t1, CAUSE_FETCH_ACCESS
  bne   s9, t1, fail
  li    TESTNUM, 4
  li    t1, -2
  bne   s10, t1, fail
  li    TESTNUM, 5
  bnez  s6, fail

  csrw  pmpcfg0, zero
  li    TESTNUM, 1
  TEST_PASSFAIL

# RVTEST_CODE_BEGIN's trap_vector jumps here. Records mcause/mepc/mtval in s9/s10/s6.
mtvec_handler:
  beqz  s8, 9f
  li    s8, 0
  csrr  s9, mcause
  csrr  s10, mepc
  csrr  s6, mtval
  csrw  mepc, s11
  mret
9:ori   TESTNUM, TESTNUM, 0x100
  j     fail

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
