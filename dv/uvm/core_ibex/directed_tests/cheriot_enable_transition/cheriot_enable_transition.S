# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_enable_transition -- cheriot_enable_i 0->1 while running (#827, REQ_BCK_05)
# =============================================================================
# The core starts with cheriot_enable_i Off (RISC-V mode). The program checks RISC-V mode works,
# writes to the trigger address, and the testbench raises the pin a few cycles later
# (+cheriot_enable_on_write, core_ibex_base_test::watch_cheriot_enable_trigger). The program then
# checks CHERIoT mode is active: auipc decodes as CAUIPCC and returns a tagged capability.
#
#   1. RISC-V arithmetic and a load/store round trip work with the pin Off.
#   2. With the pin Off, auipc is plain AUIPC: its result has no tag. Read after the switch,
#      from the register the pre-switch auipc wrote -- cgettag is illegal before it.
#   3. After the switch, auipc is CAUIPCC: its result is tagged (PCC-derived).
#
# Ported from the standalone Sonata-style testbench (backup/<date>/ibex-private/sonata_xlm,
# top_cheriot_enable_xlm.sv), which built the old core (cheri_ex.sv) and was never brought into
# this repo, so make cheriot-enable-xlm could not run. There, pass/fail was the address fetched
# from; here it is the riscv-dv signature handshake the base test waits on.
#
# Signature write: once CHERIoT is on, a plain sw is authorised by its base register as a
# capability, and an integer register has no tag -- so RVTEST_PASS/RVTEST_FAIL (plain sw through
# x2) would fault. Every result write goes through a capability derived from MTDC, as
# crt_cheriot.S does. A failure found before the switch (rv_fail) cannot use that path -- cspecialr
# is illegal with the pin Off -- so it ends by timeout instead, which is still a failure.
#
# No cosim: neither Spike nor CHERIoT-Sail models a pin that changes mid-run, so the test is
# self-checking (+disable_cosim=1 in its testlist entry).

#include "riscv_test.h"         // also ibex_macros.h: SIGNATURE_ADDR, CORE_STATUS, TEST_RESULT, ...

#define TRIGGER_ADDR 0x80200000   // must match +cheriot_enable_on_write in the testlist

RVTEST_RV32M
RVTEST_CODE_BEGIN
  # Any trap before the result is written is a failure.
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

  # -- 2. auipc with the pin Off: plain AUIPC, result untagged (checked after the switch) -------
  auipc s0, 0

  # -- Trigger the transition ----------------------------------------------------------------
  li    t0, TRIGGER_ADDR
  sw    zero, 0(t0)
  # The testbench raises the pin cheriot_enable_delay (6) cycles after seeing the write; 30 NOPs
  # cover that plus the pipeline drain.
  .rept 30
  nop
  .endr

  # -- 3. auipc with the pin On: CAUIPCC, result tagged ---------------------------------------
  auipc a0, 0
  .word 0xFE4502DB              # cgettag t0, a0   (t0 = tag of ca0)
  li    t1, 1
  bne   t0, t1, cap_fail        # untagged: CHERIoT did not come on (or CAUIPCC is broken)

  # Check 2, now that cgettag is legal: the auipc executed before the switch left no tag on s0.
  .word 0xFE4402DB              # cgettag t0, s0   (t0 = tag of cs0)
  bnez  t0, cap_fail

  li    a2, TEST_PASS
  j     sig_write

rv_fail:
cap_fail:
  li    a2, TEST_FAIL
  j     sig_write

# Writes CORE_STATUS then TEST_RESULT(a2) to SIGNATURE_ADDR through an MTDC-derived capability.
# Reached with CHERIoT on in every path except rv_fail; there cspecialr is illegal, the trap goes
# to trap_fail, and the test ends by timeout -- still a failure, and the one path that can only be
# reached if RISC-V mode itself is broken.
sig_write:
  li    a1, SIGNATURE_ADDR      # 0x8ffffff8 = cfg.signature_addr - 4, where the base test waits
  li    t0, (CORE_STATUS)
  slli  t1, a2, 8
  ori   t1, t1, TEST_RESULT     # t1 = (result << 8) | TEST_RESULT
  .word 0x03D0055B              # cspecialr c10, mtdc      -- c10 <- MTDC (root data capability)
  .word 0x20B5055B              # csetaddr  c10, c10, a1   -- c10.address <- SIGNATURE_ADDR
  fence iorw, iorw
  sw    t0, 0(a0)               # through c10: CORE_STATUS
  sw    t1, 0(a0)               # through c10: TEST_RESULT
1: j 1b

  .balign 256                   # mtvec.base must be 256-byte aligned on Ibex
trap_fail:
  li    a2, TEST_FAIL
  j     sig_write

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 2
testvar:
  .word 0
RVTEST_DATA_END
