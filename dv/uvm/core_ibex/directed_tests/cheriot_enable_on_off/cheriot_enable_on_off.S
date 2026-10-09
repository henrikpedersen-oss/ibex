# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_enable_on_off -- cheriot_enable_i 0->1, then 1->0 while a CSC waits (REQ_BCK_06)
# =============================================================================
# The core starts in RISC-V mode with cheriot_enable_i Off. As cheriot_enable_transition, the
# program checks RISC-V mode, writes to TRIGGER_ON and the testbench raises the pin
# (+cheriot_enable_on_write). In CHERIoT mode the program checks a CSC/CLC round trip, writes to
# TRIGGER_OFF, and issues one more CSC. The testbench (+cheriot_disable_on_write,
# core_ibex_base_test::watch_cheriot_disable_trigger) slows the d-side grants once it sees the
# TRIGGER_OFF write, lowers the pin while that CSC waits for the grant of its first word (LSU state
# CTX_WAIT_GNT1; the LSU must hold the request until granted and complete the CSC), and
# requires alert_major_internal_o within +cheriot_disable_alert_window cycles. The program then
# continues in RISC-V mode without a trap.
#
# The 1->0 transition breaks the pin contract (REQ_BCK_05: once asserted, cheriot_enable_i stays
# high). REQ_BCK_06 is what the core must do when the contract is broken anyway: raise an alert
# rather than switch the capability checks off silently. The testbench's check is the verdict; the
# program's own result only says it got back to RISC-V mode.
#
#   1. RISC-V mode, pin Off: arithmetic, a load/store round trip, auipc untagged (checked later).
#   2. Pin On: auipc is CAUIPCC (tagged); a capability stored with CSC loads back tagged with CLC.
#   3. TRIGGER_OFF write, then the CSC the pin is lowered under.
#   4. Back in RISC-V mode: the result is written with plain stores, as with the pin Off.
#
# Signature writes: while CHERIoT is on, a plain sw is authorised by its base register as a
# capability, so a failure found then goes through an MTDC-derived capability (cap_sig_write), as
# in cheriot_enable_transition. After step 3 the pin is Off and a plain sw works (rv_sig_write).
#
# No cosim: neither Spike nor CHERIoT-Sail models a pin that changes mid-run (+disable_cosim=1).

#include "riscv_test.h"         // also ibex_macros.h: SIGNATURE_ADDR, CORE_STATUS, TEST_RESULT, ...

#define TRIGGER_ON  0x80200000  // must match +cheriot_enable_on_write in the testlist
#define TRIGGER_OFF 0x80200010  // must match +cheriot_disable_on_write in the testlist
#define CAPBUF      0x80200100  // 8-byte aligned scratch for the CSC/CLC round trip

RVTEST_RV32M
RVTEST_CODE_BEGIN
  # Any trap is a failure.
  la    t0, trap_fail
  csrw  mtvec, t0

  # -- 1. RISC-V mode, pin Off ---------------------------------------------------------------
  li    t0, 42
  li    t1, 58
  add   t2, t0, t1
  li    t3, 100
  bne   t2, t3, rv_fail

  la    t0, testvar
  li    t1, 0xDEAD
  sw    t1, 0(t0)
  lw    t2, 0(t0)
  bne   t1, t2, rv_fail

  auipc s0, 0                   # plain AUIPC: untagged, checked once cgettag is legal

  li    t0, TRIGGER_ON
  sw    zero, 0(t0)
  .rept 30                      # the testbench raises the pin 6 cycles after seeing the write
  nop
  .endr

  # -- 2. Pin On ------------------------------------------------------------------------------
  auipc a0, 0
  .word 0xFE4502DB              # cgettag t0, a0
  li    t1, 1
  bne   t0, t1, cap_fail        # CHERIoT did not come on
  .word 0xFE4402DB              # cgettag t0, s0
  bnez  t0, cap_fail            # the pre-switch auipc must have no tag

  .word 0x03D0055B              # cspecialr c10, mtdc       -- c10 <- MTDC (root data capability)
  li    a1, CAPBUF
  .word 0x20B505DB              # csetaddr  c11, c10, a1    -- c11 <- c10 at CAPBUF
  .word 0x00A5B023              # csc       c10, 0(c11)
  .word 0x0005B603              # clc       c12, 0(c11)
  .word 0xFE4602DB              # cgettag   t0, c12
  li    t1, 1
  bne   t0, t1, cap_fail        # the stored capability must load back tagged

  # -- 3. TRIGGER_OFF, then the CSC the pin is lowered under ---------------------------------
  li    a2, TRIGGER_OFF
  .word 0x20C506DB              # csetaddr  c13, c10, a2    -- c13 <- c10 at TRIGGER_OFF
  sw    zero, 0(a3)             # through c13
  .rept 30                      # time for the testbench to see the write and slow the grants
  nop
  .endr
  li    a4, CAPBUF + 0x40
  .word 0x20E5075B              # csetaddr  c14, c10, a4    -- c14 <- c10 at CAPBUF+0x40
  .word 0x00E5B423              # csc       c14, 8(c11)     -- waits for a grant; the pin drops
  .rept 30                      # time for the pin change to take effect
  nop
  .endr

  # -- 4. Pin Off again: RISC-V mode, plain stores ---------------------------------------------
  # The CSC under the pin change wrote both words: an access in progress completes as issued
  # (REQ_BCK_06). Expected values from the RTL's design choice, not from the ISA (no pin there).
  li    a1, CAPBUF
  lw    t0, 8(a1)
  li    t1, CAPBUF + 0x40
  bne   t0, t1, rv_fail         # first word: c14's address
  lw    t0, 12(a1)
  lw    t1, 4(a1)
  bne   t0, t1, rv_fail         # second word: c14's metadata, the same as c10's (step 2)
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

  .balign 256                   # mtvec.base must be 256-byte aligned on Ibex
trap_fail:
  li    a2, TEST_FAIL
  j     rv_sig_write            # a trap after step 3 is in RISC-V mode; before it the test times out

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 2
testvar:
  .word 0
RVTEST_DATA_END
