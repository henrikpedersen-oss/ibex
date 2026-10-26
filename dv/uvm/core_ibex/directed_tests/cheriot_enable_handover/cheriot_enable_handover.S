# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_enable_handover -- the state the core hands CHERIoT software (EG2 REQ_SOC_07)
# =============================================================================
# Earl Grey 2 REQ_SOC_07 (RFC CHERIoT Ibex "Handover to CHERIoT Mode Software"): after the switch,
# PCC is the executable root and execution continues at the next PC; MTCC and MEPCC are the
# executable root with the address of mtvec and mepc; MTDC and MScratchC are the memory and sealing
# roots; every general-purpose register's tag is 0, whatever ePMP mode left in x16-x31. This
# holds for a switch during WFI and after a store.
#
# The core starts in RISC-V mode with cheriot_enable_i Off. The program writes mtvec and mepc,
# turns dummy instructions on (cpuctrlsts.dummy_instr_en; a SecureIbex build has them) and fills
# x1-x31: x16-x31 with all ones, which in this register file are the flops that hold the
# capability halves of x1-x15 in CHERIoT mode (ibex_register_file_ff g_rf_shared_flops). Then it
# writes the trigger address and the testbench raises the pin (+cheriot_enable_on_write):
#   default          after the store, cheriot_enable_delay cycles later, while the program runs NOPs
#   -DHANDOVER_WFI   during WFI (+cheriot_enable_on_sleep=1): the program sleeps right after the
#                    store, the testbench raises the pin in SLEEP and then irq_timer_i to wake the
#                    core; mie.MTIE is set and mstatus.MIE clear, so WFI ends without a trap.
# Then, before any general-purpose register is written, it reads every register it can and every
# SCR. In CHERIoT mode only x0-x15 exist (an access to x16-x31 is an illegal instruction), so
# x1-x15 are what CHERIoT software can see.
#
# Expected values (documents, not the RTL): REQ_SOC_07; the roots as the core specification's
# REQ_BCK_03 gives them (CHERIoT-Sail root_cap_exe 0x1EB, root_cap_mem 0x07F, root_cap_seal 0xE01;
# base 0, length 2^32, which CGetLen reports as 0xFFFFFFFF; unsealed, otype 0); MTCC's address
# bits [1:0] = 0 (core REQ_SCR_02: CHERIoT has only direct mode).
#
# Failure codes (a0, through TEST_END_A0; checked in this order):
#    1  a tag in x1-x15 (the OR of the fifteen CGetTag results)
#    2-7   PCC (AUIPCC 0): tag, perms, base, length, otype, address = the next PC of the program
#    8-13  MTCC: tag, perms, base, length, otype, address with bits [1:0] cleared = mtvec's
#    14-19 MEPCC: tag, perms, base, length, otype, address = mepc
#    20-24 MTDC: tag, perms, base, length, otype
#    25-29 MScratchC: tag, perms, base, length, otype
#    30    MTCC address bits [1:0] = 0. Expected to FAIL on the pinned RTL: the switch keeps
#          mtvec's vectored MODE bit (EG2 status/rtl_tickets.md F39, GAP-RTL-14)
#    99    a trap after the switch
# A trap before the switch cannot report (cspecialr is illegal with the pin Off): the run ends by
# timeout, still a failure. No alert may be raised (the testbench's NoAlertsTriggered; REQ_CIB_02:
# a register last written in ePMP mode raises none when read after the switch, by an instruction
# or a dummy instruction).
#
# Proving it can fail: -DHANDOVER_INJECT_FAIL expects check 1 to see a tag, so it fails with code 1
# (the plain test's first failure is code 30).
#
# No cosim: neither Spike nor CHERIoT-Sail models a pin that changes mid-run (+disable_cosim=1).

#include "riscv_test.h"
#include "cheriot_dv.h"

#define TRIGGER_ADDR CHERIOT_ON_TRIGGER  // must match +cheriot_enable_on_write in the testlist
#define MEPC_VAL     0x80002468
#define PERM_EXE     0x1EB
#define PERM_MEM     0x07F
#define PERM_SEAL    0xE01
#define CSR_CPUCTRLSTS 0x7C0

#ifdef HANDOVER_INJECT_FAIL
#define EXP_TAGS 1
#else
#define EXP_TAGS 0
#endif

# The checks of one root capability in \c: tag 1, perms \perm, base 0, length 2^32, otype 0.
.macro CHECK_ROOT c, perm, code
  cgettag   a2, \c
  CHECK_EQI a2, 1, \code, t1
  cgetperm  a2, \c
  CHECK_EQI a2, \perm, (\code + 1), t1
  cgetbase  a2, \c
  CHECK_EQ  a2, x0, (\code + 2)
  cgetlen   a2, \c
  CHECK_EQI a2, -1, (\code + 3), t1
  cgettype  a2, \c
  CHECK_EQ  a2, x0, (\code + 4)
.endm

RVTEST_RV32M
RVTEST_CODE_BEGIN
  .option push
  .option norvc

  # -- RISC-V mode, pin Off: mtvec, mepc, dummy instructions, then every register ---------------
  la    t0, trap_fail
  csrw  mtvec, t0
  li    t0, MEPC_VAL
  csrw  mepc, t0
  li    t0, 0x4                       # cpuctrlsts.dummy_instr_en, dummy_instr_mask 0
  csrs  CSR_CPUCTRLSTS, t0
#ifdef HANDOVER_WFI
  li    t0, 0x80                      # mie.MTIE; mstatus.MIE is 0 (riscv-test-env start-up)
  csrs  mie, t0
#endif

  li    x16, -1
  li    x17, -1
  li    x18, -1
  li    x19, -1
  li    x20, -1
  li    x21, -1
  li    x22, -1
  li    x23, -1
  li    x24, -1
  li    x25, -1
  li    x26, -1
  li    x27, -1
  li    x28, -1
  li    x29, -1
  li    x30, -1
  li    x31, -1
  li    x1,  0x5A5A0001
  li    x2,  0x5A5A0002
  li    x3,  0x5A5A0003
  li    x4,  0x5A5A0004
  li    x6,  0x5A5A0006
  li    x7,  0x5A5A0007
  li    x8,  0x5A5A0008
  li    x9,  0x5A5A0009
  li    x10, 0x5A5A000A
  li    x11, 0x5A5A000B
  li    x12, 0x5A5A000C
  li    x13, 0x5A5A000D
  li    x14, 0x5A5A000E
  li    x15, 0x5A5A000F
  li    x5,  TRIGGER_ADDR             # x5's filler is the trigger address

  # -- The switch ------------------------------------------------------------------------------
  sw    x0, 0(x5)
#ifdef HANDOVER_WFI
  wfi                                 # the pin rises while the core sleeps; irq_timer_i wakes it
  csrw  mie, x0                       # mask the held line (writes no general-purpose register)
#else
  .rept 30                            # the pin rises cheriot_enable_delay (6) cycles after the store
  nop
  .endr
#endif

  # -- CHERIoT mode: every general-purpose register's tag, in place, before any is written -------
  .irp r, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
  cgettag x\r, x\r
  .endr
  .irp r, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
  or    x1, x1, x\r
  .endr
  SIG_INIT                            # s1 := the signature capability (from MTDC); clobbers t0
  CHECK_EQI x1, EXP_TAGS, 1, t1

  # -- PCC: AUIPCC 0 is PCC with the address of this instruction -------------------------------
pcc_probe:
  auipc a1, 0
  CHECK_ROOT a1, PERM_EXE, 2
  cgetaddr  a2, a1
  DCAP_FAR  a3, exp_pcc, t1
  lw        t1, 0(a3)
  CHECK_EQ  a2, t1, 7

  # -- MTCC: the executable root at mtvec ----------------------------------------------------
  cspecialr a1, SCR_MTCC
  CHECK_ROOT a1, PERM_EXE, 8
  cgetaddr  a2, a1
  andi      a2, a2, -4
  DCAP_FAR  a3, exp_mtvec, t1
  lw        t1, 0(a3)
  andi      t1, t1, -4
  CHECK_EQ  a2, t1, 13

  # -- MEPCC: the executable root at mepc ----------------------------------------------------
  cspecialr a1, SCR_MEPCC
  CHECK_ROOT a1, PERM_EXE, 14
  cgetaddr  a2, a1
  CHECK_EQI a2, MEPC_VAL, 19, t1

  # -- MTDC and MScratchC: the memory and sealing roots --------------------------------------
  cspecialr a1, SCR_MTDC
  CHECK_ROOT a1, PERM_MEM, 20
  cspecialr a1, SCR_MSCRATCHC
  CHECK_ROOT a1, PERM_SEAL, 25

  # -- MTCC's address bits [1:0] (core REQ_SCR_02; F39) --------------------------------------
  cspecialr a1, SCR_MTCC
  cgetaddr  a2, a1
  andi      a2, a2, 3
  CHECK_EQ  a2, x0, 30

  li    a0, 0
test_end:
  TEST_END_A0

  # mtvec: 256-byte aligned (Ibex's mtvec is vectored only). Every slot of the vector table leads
  # to the same place, so an exception (base) and any interrupt (base + 4 * cause) fail alike, in
  # either mode.
  .balign 256
trap_fail:
  .rept 32
  j     trap_common
  .endr
trap_common:
  SIG_INIT
  li    a0, 99
  j     test_end

  .option pop
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  .align 2
exp_pcc:
  .word pcc_probe
exp_mtvec:
  .word trap_fail
RVTEST_DATA_END
