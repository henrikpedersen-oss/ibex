# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cov_expr_cheriot_off_fault -- cheriot_enable_i falls as a CHERIoT access fault is reported
# =============================================================================
# As cheriot_enable_on_off (REQ_BCK_06), with the 1->0 transition placed on a faulting access
# instead of a CSC: the program raises the pin (+cheriot_enable_on_write), writes to TRIGGER_OFF,
# and loads through an untagged capability. The testbench (+cheriot_disable_on_write with
# +cheriot_disable_on_fault, core_ibex_base_test::watch_cheriot_disable_trigger) sees the LSU fail
# that load's capability check in its issue cycle (no request is sent; probe lsu_cheriot_err_next)
# and lowers the pin for the next cycle, in which the LSU reports the error, then requires
# alert_major_internal_o within +cheriot_disable_alert_window cycles. The 1->0 change breaks the
# pin contract of REQ_BCK_05 on purpose; the testbench turns CheriotEnableOneWaySwitch off for it.
#
# Expression-coverage target (regression 26231 after UNR, 2026-10-11,
# formal_cov/unr/uncovered_after_exclude.txt): ibex_load_store_unit.sv:432
#   cheriot_err_d = cheriot_err_q & (cheriot_enable_i == IbexMuBiOn);
#   row cheriot_err_q = 1 with the pin not On. cheriot_err_q is 1 only in the cycle after a
#   CHERIoT check failed in IDLE (ls_fsm_ns stays IDLE), and the LSU sees the raw pin then:
#   ibex_core.sv cheriot_enable_ex forces On only while lsu_cheriot_req_busy, which needs
#   ls_fsm_cs != IDLE. So the pin must fall in exactly that report cycle.
#
# Expected behaviour (REQ_BCK_06; not taken from the RTL): the alert (testbench); no hang; the
# faulting load traps once, at its own address, without writing rd; the program then runs in
# RISC-V mode (a plain load/store round trip through an integer base). REQ_BCK_06 does not say
# which cause an access that faulted in CHERIoT mode reports once the pin has fallen: the CHERI
# fault (mcause 0x1C, as issued) or, as the RTL is written (ibex_controller.sv load_err_prio and
# ibex_load_store_unit.sv lsu_err_is_cheriot_o both look at the pin), a load access fault
# (mcause 5, mtval = the address). Both are accepted here; that choice is open for the spec.
#
# Failure: TEST_FAIL via the signature (rv_sig_write / cap_sig_write, as cheriot_enable_on_off):
# CHERIoT did not come on, an unexpected trap or cause, the load wrote rd, or not exactly one trap.
# No cosim: neither Spike nor CHERIoT-Sail models a pin that changes mid-run (+disable_cosim=1).
#
# Proving it can fail (build-time switch, not in the testlist):
#   -DCOV_EXPR_INJECT_FAIL  the load goes through the MTDC-derived capability: no fault, so no trap
#                           (and the testbench reports no CHERIoT access fault)

#include "riscv_test.h"         // also ibex_macros.h: SIGNATURE_ADDR, CORE_STATUS, TEST_RESULT, ...

#define TRIGGER_ON  0x80200000  // must match +cheriot_enable_on_write in the testlist
#define TRIGGER_OFF 0x80200010  // must match +cheriot_disable_on_write in the testlist
#define FAULT_ADDR  0x80200100
#define POISON      0x0BADF00D
#define CAUSE_CHERI 0x1c

RVTEST_RV32M
RVTEST_CODE_BEGIN
  la    t0, trap_handler
  csrw  mtvec, t0
  li    s1, 0                   # traps taken

  li    t0, TRIGGER_ON
  sw    zero, 0(t0)
  .rept 30                      # the testbench raises the pin 6 cycles after seeing the write
  nop
  .endr

  # -- Pin On -----------------------------------------------------------------------------------
  auipc a0, 0
  .word 0xFE4502DB              # cgettag t0, a0
  li    t1, 1
  bne   t0, t1, cap_fail        # CHERIoT did not come on

  .word 0x03D0055B              # cspecialr c10, mtdc       -- c10 <- MTDC (root data capability)
  li    a2, TRIGGER_OFF
  .word 0x20C506DB              # csetaddr  c13, c10, a2    -- c13 <- c10 at TRIGGER_OFF
  sw    zero, 0(a3)             # through c13: the testbench now waits for a CHERIoT access fault
  .rept 30                      # time for the testbench to see the write
  nop
  .endr
  li    a5, FAULT_ADDR          # c15: an integer, so an untagged capability
#ifdef COV_EXPR_INJECT_FAIL
  .word 0x20F507DB              # csetaddr  c15, c10, a5    -- tagged: the load does not fault
#endif
  li    t2, POISON
fault_insn:
  lw    t2, 0(a5)               # tag violation; the pin falls as the LSU reports it

  # -- Pin Off: RISC-V mode -----------------------------------------------------------------------
  .rept 8
  nop
  .endr
  li    t1, POISON
  bne   t2, t1, rv_fail         # the faulting load wrote rd
  li    t1, 1
  bne   s1, t1, rv_fail         # not exactly one trap
  la    t0, testvar
  li    t1, 0x5A5A
  sw    t1, 0(t0)
  lw    t3, 0(t0)
  bne   t1, t3, rv_fail
  li    a2, TEST_PASS
  j     rv_sig_write

rv_fail:
  li    a2, TEST_FAIL
  j     rv_sig_write

cap_fail:
  li    a2, TEST_FAIL
  j     cap_sig_write

# CORE_STATUS then TEST_RESULT(a2) to SIGNATURE_ADDR with plain stores (pin Off).
rv_sig_write:
  li    a1, SIGNATURE_ADDR
  li    t0, (CORE_STATUS)
  slli  t1, a2, 8
  ori   t1, t1, TEST_RESULT
  sw    t0, 0(a1)
  sw    t1, 0(a1)
1: j 1b

# The same through an MTDC-derived capability (pin On).
cap_sig_write:
  li    a1, SIGNATURE_ADDR
  li    t0, (CORE_STATUS)
  slli  t1, a2, 8
  ori   t1, t1, TEST_RESULT
  .word 0x03D0055B              # cspecialr c10, mtdc
  .word 0x20B5055B              # csetaddr  c10, c10, a1
  fence iorw, iorw
  sw    t0, 0(a0)               # through c10
  sw    t1, 0(a0)
2: j 2b

# The only trap expected is the faulting load's, taken with the pin already Off (RISC-V mode). A
# trap while the pin is On would go through MTCC and is a failure by timeout, as in
# cheriot_enable_on_off.
  .balign 256                   # mtvec.base must be 256-byte aligned on Ibex
trap_handler:
  addi  s1, s1, 1
  csrr  t5, mepc
  la    t6, fault_insn
  bne   t5, t6, rv_fail
  csrr  t5, mcause
  li    t6, CAUSE_CHERI
  beq   t5, t6, 3f
  li    t6, CAUSE_LOAD_ACCESS
  bne   t5, t6, rv_fail
  csrr  t5, mtval
  li    t6, FAULT_ADDR
  bne   t5, t6, rv_fail
3:
  csrr  t5, mepc
  addi  t5, t5, 4
  csrw  mepc, t5
  mret

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 2
testvar:
  .word 0
RVTEST_DATA_END
