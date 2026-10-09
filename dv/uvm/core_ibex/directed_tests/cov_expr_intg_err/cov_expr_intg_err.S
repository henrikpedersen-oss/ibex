# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cov_expr_intg_err -- an internal NMI pending inside the NMI handler; Zcmp fetch errors
# =============================================================================
# RISC-V mode (cheriot_enable_i Off). rtl_test core_ibex_cheriot_mem_err_test (mode-agnostic:
# NoAlertsTriggered off, a bus alert required per integrity error, no other alert). Cosim off:
# the program checks itself. The bench injects bad integrity by address:
#   +dside_intg_err_lo/hi = INTG_ADDR (every load of it), +iside_intg_err_lo/hi = ZC_BLOCK
#   (every fetch of its four words).
#
# Expression-coverage targets (merged regression after UNR, 2026-10-09):
#   ibex_core.sv (RVFI) `~use_capture ? id_stage_i.controller_i.irq_nm_int : captured_nmi_int`,
#     row use_capture = 0 with irq_nm_int = 1: instructions entering ID while an internal NMI is
#     pending and cannot be taken. The NMI handler loads INTG_ADDR again; that second bad
#     response sets the internal NMI while nmi_mode blocks it, and the handler runs on.
#   ibex_compressed_decoder.sv CmIdle `valid_i && id_in_ready_i`, row valid_i = 0, for cm.push
#     with rlist 4 (line 641), cm.pop with rlist 4 (709) and 5 (718), cm.mvsa01 (791): a Zcmp
#     instruction in IF with a fetch error (valid_i = fetch_valid & ~fetch_err). A bad-integrity
#     response keeps the fetched bits, so the decoder sees the real cm.* encoding.
#
# Expected behaviour (not taken from the RTL):
#   - Ibex doc/03_reference/exception_interrupts.rst / security.rst: a load response with bad
#     integrity raises the internal NMI (mcause 0xFFFFFFE0, mtval = the load address) and does
#     not write the destination register; NMIs do not nest (the handler is not interrupted by
#     another NMI); after mret the pending one is taken, before the instruction mret returned
#     to executes (so its mepc equals the first NMI's).
#   - Interrupts are precise: each instruction after the faulting load executes exactly once.
#   - A fetch response with bad integrity is an instruction access fault (mcause 1, mepc = mtval
#     = the instruction). A faulting cm.* does not execute: sp and memory are unchanged.
#
# Failure: TEST_FAIL with TESTNUM (gp):
#   1  NMIs taken != 2          2/3  NMI mcause not 0xFFFFFFE0 (first / second)
#   4/5  NMI mtval not INTG_ADDR (first / second)      6  second NMI mepc != first NMI mepc
#   7  the faulting load wrote t0      8  the instructions after the load did not run once each
#   10 fetch faults != 4      11 fetch fault mcause not 1      12 fetch fault mepc/mtval not the
#      next ZC_BLOCK word      13 sp changed across the Zcmp block
#   0x100 | code  an unexpected exception

#include "riscv_test.h"
#include "test_macros.h"

#define INTG_ADDR     0x80002000      /* +dside_intg_err_lo=80002000 +dside_intg_err_hi=80002003 */
#define ZC_BLOCK      0x80001000      /* +iside_intg_err_lo=80001000 +iside_intg_err_hi=8000100f */
#define NMI_CAUSE     0xFFFFFFE0
#define POISON        0x0BADF00D

# Registers: s2 NMIs taken, s3/s4 first/second NMI mcause, s5/s6 their mtval, s7/s8 their mepc,
#   s9 fetch faults, s10 next expected fault address, s11 sp before the Zcmp block.

  .option norvc
  .option norelax

RVTEST_RV32M
RVTEST_CODE_BEGIN

  la    t0, mtvec_table
  csrw  mtvec, t0
  li    s2, 0
  li    s9, 0

  # ---- Internal NMI, and a second one raised inside the NMI handler ----
  li    a0, INTG_ADDR
  li    t0, POISON
  li    a5, 0
  lw    t0, 0(a0)                   # bad integrity: internal NMI, t0 not written
  addi  a5, a5, 1
  addi  a5, a5, 1
  addi  a5, a5, 1
  addi  a5, a5, 1
  addi  a5, a5, 1
  addi  a5, a5, 1
  addi  a5, a5, 1
  addi  a5, a5, 1
  li    TESTNUM, 7
  li    t1, POISON
  bne   t0, t1, fail
  li    TESTNUM, 8
  li    t1, 8
  bne   a5, t1, fail
  li    TESTNUM, 1
  li    t1, 2
  bne   s2, t1, fail
  li    TESTNUM, 2
  li    t1, NMI_CAUSE
  bne   s3, t1, fail
  li    TESTNUM, 3
  bne   s4, t1, fail
  li    TESTNUM, 4
  bne   s5, a0, fail
  li    TESTNUM, 5
  bne   s6, a0, fail
  li    TESTNUM, 6
  bne   s7, s8, fail

  # ---- Zcmp encodings fetched with bad integrity: four instruction access faults ----
  li    s10, ZC_BLOCK
  mv    s11, sp
  li    t0, ZC_BLOCK
  jr    t0
zc_back:
  li    TESTNUM, 10
  li    t1, 4
  bne   s9, t1, fail
  li    TESTNUM, 13
  bne   sp, s11, fail

  li    TESTNUM, 1
  TEST_PASSFAIL

# ---- Vector table (Ibex mtvec is vectored): exceptions at +0, NMIs at +0x7c ----
  .balign 256
mtvec_table:
  j     exc_handler
  .org  mtvec_table + 0x7c
  j     nmi_handler

# Instruction access faults on ZC_BLOCK: check, then resume at the next word.
exc_handler:
  csrr  t5, mcause
  li    t6, CAUSE_FETCH_ACCESS
  bne   t5, t6, 1f
  csrr  t5, mepc
  li    TESTNUM, 12
  bne   t5, s10, fail
  csrr  t5, mtval
  bne   t5, s10, fail
  addi  s9, s9, 1
  addi  s10, s10, 4
  csrw  mepc, s10
  mret
1:li    TESTNUM, 11
  ori   TESTNUM, TESTNUM, 0x100
  j     fail

# First entry: record, raise a second internal NMI (deferred: nmi_mode), run on, mret.
# Second entry (the deferred NMI, taken right after that mret): record, mret.
nmi_handler:
  addi  s2, s2, 1
  li    t5, 1
  bne   s2, t5, 2f
  csrr  s3, mcause
  csrr  s5, mtval
  csrr  s7, mepc
  li    t5, INTG_ADDR
  lw    t6, 0(t5)                   # bad integrity again: internal NMI pending in nmi_mode
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  mret
2:csrr  s4, mcause
  csrr  s6, mtval
  csrr  s8, mepc
  mret

# ---- Zcmp encodings at a fixed address, inside the i-side integrity window ----
# cm.push {ra}, -16 = 0xB842; cm.pop {ra}, 16 = 0xBA42; cm.pop {ra, s0}, 16 = 0xBA52;
# cm.mvsa01 s0, s1 = 0xAC26 (zcmp_push_pop_mv ENC_*). Each in its own word, then c.nop.
  .org  ZC_BLOCK - 0x80000000
zc_block:
  .hword 0xB842
  .hword 0x0001
  .hword 0xBA42
  .hword 0x0001
  .hword 0xBA52
  .hword 0x0001
  .hword 0xAC26
  .hword 0x0001
  j     zc_back

# ---- The load target of the d-side integrity window ----
  .org  INTG_ADDR - 0x80000000
intg_word:
  .word 0x12345678

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
