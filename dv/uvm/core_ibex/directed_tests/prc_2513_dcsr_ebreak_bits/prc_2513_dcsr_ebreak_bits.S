# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Test: prc_2513_dcsr_ebreak_bits -- an M-mode ebreak follows dcsr.ebreakm, not dcsr.ebreaku
#                                     (lowRISC/ibex PR #2513, second commit)
#
# Debug spec: dcsr.ebreakm (bit 15) makes an M-mode ebreak enter debug mode; dcsr.ebreaku
# (bit 12) does the same for U-mode. PR #2513 fixes the Spike cosim's pc_is_debug_ebreak(),
# which tests bit 12 for M-mode and bit 15 for U-mode (swapped). The generated debug tests set
# both bits, so nothing noticed. This test sets them one at a time, with the cosim on:
#   part A: ebreakm = 1, ebreaku = 0, M-mode ebreak -> debug mode, cause EBREAK
#   part B: ebreakm = 0, ebreaku = 1, M-mode ebreak -> ordinary breakpoint exception (mcause 3)
# A cosim that reads the wrong bit takes the wrong path for one of them.
#
# Sequence (core_ibex_debug_halt_once_test sends one halt request after INITIALIZED):
#   1. The program reports INITIALIZED and waits. Halt: dcsr.cause must be HALTREQ; set ebreakm,
#      clear ebreaku; dpc := site_a; dret.                                         (phase 1 -> 2)
#   2. site_a: ebreak must enter debug mode with cause EBREAK and dpc = site_a. Clear ebreakm, set
#      ebreaku; dpc := site_b; dret.                                                (phase 2 -> 3)
#   3. site_b: ebreak must take a breakpoint exception: mcause 3, mepc = site_b. The handler
#      skips it (mepc + 4) and returns.                                             (phase 3 -> 4)
#   4. done: phase must be 4.
# Failure: TEST_FAIL with TESTNUM (gp) =
#   1 no halt request arrived    2 halt: wrong cause    3 site_a: wrong cause   4 site_a: wrong dpc
#   5 site_a took an exception instead of entering debug mode
#   6 site_b entered debug mode instead of trapping     7 site_b: wrong mcause  8 site_b: wrong mepc
#   9 done reached in the wrong phase

#include "riscv_test.h"
#include "test_macros.h"

#define DBG_CAUSE_EBREAK  1
#define DBG_CAUSE_HALTREQ 3
#define DCSR_EBREAKM_BIT  0x8000
#define DCSR_EBREAKU_BIT  0x1000
# The bench reads core status at +signature_addr, 4 bytes above SIGNATURE_ADDR.
#define CORE_STATUS_ADDR (SIGNATURE_ADDR + 4)

# DmHaltAddr is the start of .text.init and DmExceptionAddr 8 bytes later. The reset code of
# RVTEST_CODE_BEGIN starts at offset 0x80.
  .section .text.init
  .option push
  .option norvc
  j    debug_entry
  nop
  j    fail
  .option pop

RVTEST_RV32M
RVTEST_CODE_BEGIN

  la   t0, phase
  li   t1, 1
  sw   t1, 0(t0)
  li   t0, CORE_STATUS_ADDR
  li   t1, (INITIALIZED << 8) | CORE_STATUS
  sw   t1, 0(t0)
  li   TESTNUM, 1
  li   t2, 100000
1:
  addi t2, t2, -1
  bnez t2, 1b
  j    fail

  .balign 4
  .option push
  .option norvc
site_a:
  ebreak
  j    fail
site_b:
  ebreak
  j    done
  .option pop

done:
  li   TESTNUM, 9
  la   t0, phase
  lw   t0, 0(t0)
  li   t1, 4
  bne  t0, t1, fail
  li   TESTNUM, 99
  j    pass

  TEST_PASSFAIL

# Part B's breakpoint exception lands here; anything else fails.
.balign 4
mtvec_handler:
  la   t0, phase
  lw   t0, 0(t0)
  li   t1, 3
  beq  t0, t1, 1f
  li   TESTNUM, 5
  j    fail
1:
  li   TESTNUM, 7
  csrr t0, mcause
  li   t1, CAUSE_BREAKPOINT
  bne  t0, t1, fail
  li   TESTNUM, 8
  csrr t0, mepc
  la   t1, site_b
  bne  t0, t1, fail
  addi t0, t0, 4
  csrw mepc, t0
  la   t0, phase
  li   t1, 4
  sw   t1, 0(t0)
  mret

debug_entry:
  csrw dscratch0, t0
  csrw dscratch1, t1
  la   t0, phase
  lw   t0, 0(t0)
  li   t1, 1
  beq  t0, t1, debug_halt
  li   t1, 2
  beq  t0, t1, debug_site_a
  li   TESTNUM, 6
  j    fail

debug_halt:
  li   TESTNUM, 2
  csrr t0, dcsr
  srli t0, t0, 6
  andi t0, t0, 7
  li   t1, DBG_CAUSE_HALTREQ
  bne  t0, t1, fail
  li   t0, DCSR_EBREAKU_BIT
  csrc dcsr, t0
  li   t0, DCSR_EBREAKM_BIT
  csrs dcsr, t0
  la   t0, site_a
  csrw dpc, t0
  li   t0, 2
  j    debug_set_phase

debug_site_a:
  li   TESTNUM, 3
  csrr t0, dcsr
  srli t0, t0, 6
  andi t0, t0, 7
  li   t1, DBG_CAUSE_EBREAK
  bne  t0, t1, fail
  li   TESTNUM, 4
  csrr t0, dpc
  la   t1, site_a
  bne  t0, t1, fail
  li   t0, DCSR_EBREAKM_BIT
  csrc dcsr, t0
  li   t0, DCSR_EBREAKU_BIT
  csrs dcsr, t0
  la   t0, site_b
  csrw dpc, t0
  li   t0, 3
  li   TESTNUM, 6

debug_set_phase:
  la   t1, phase
  sw   t0, 0(t1)
  csrr t0, dscratch0
  csrr t1, dscratch1
  dret

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
phase:
  .word 0
RVTEST_DATA_END
