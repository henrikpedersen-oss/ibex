# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: earlgrey_pmp_reset -- the PMP as Earl Grey resets it
# =============================================================================
# Earl Grey's rv_core_ibex passes ibex_top PMP reset values (PMPRstCfg / PMPRstAddr /
# PMPRstMsecCfg, OpenTitan hw/top_earlgrey/rtl/ibex_pmp_reset_pkg.sv); every other test runs on
# ibex_top's defaults (every region off, mseccfg 0). This test runs on the earlgrey-pmprst build
# (the earlgrey parameters plus those reset values, tb/ibex_pmp_reset_earlgrey_pkg.sv), which boots
# at 0x0001_0000. It checks the values the core resets to, that they protect as the ePMP rules say,
# that the lock bypass works, and then opens memory for the end-of-test signature.
#
# Self-contained: no riscv-test-env start-up (its INIT_PMP rewrites the PMP before anything could
# read the reset values) and cosim off (the reference models are not configured with these reset
# values): every value is checked here.
#
# Expected behaviour (not taken from the RTL):
#   - Reset values, Earl Grey ibex_pmp_reset_pkg.sv, at PMPGranularity 0 (pmpaddr = byte address >> 2):
#       region 2   ROM     NAPOT 0x0004_0000, 2 KiB   L R X    pmpaddr2  0x000100FF
#       region 10  -       OFF, TOR base 0x4000_0000           pmpaddr10 0x10000000
#       region 11  MMIO    TOR [0x4000_0000, 0x4201_0000) L R W pmpaddr11 0x10804000
#       region 13  DV_ROM  NAPOT 0x0001_0000, 4 KiB   L R W X  pmpaddr13 0x000041FF
#     so pmpcfg0 0x009D0000, pmpcfg1 0, pmpcfg2 0x8B000000, pmpcfg3 0x00009F00, every other
#     pmpaddr 0; mseccfg RLB = 1, MMWP = 1, MML = 0 (0x6), mseccfgh 0.
#   - RISC-V Privileged ISA, PMP: the lowest-numbered matching region decides; a locked region
#     applies to M-mode; an M-mode access no region matches succeeds -- but Smepmp: with
#     mseccfg.MMWP set it is denied. Access faults: instruction 1, load 5, store/AMO 7, mtval =
#     the address (Ibex manual, exception_interrupts.rst / pmp.rst).
#   - Smepmp: MMWP is sticky (cannot be cleared). With RLB = 1 a locked region's pmpcfg and
#     pmpaddr can be written; with RLB = 0 they cannot, and RLB cannot be set again while any
#     region is locked. Unlocked regions stay writable.
#
# Checks and failure codes (gp = the failing code; a0 = the value read, for the trace)
#   10-31  reset values: pmpcfg0-3 (10-13), pmpaddr0-15 (14-29), mseccfg (30), mseccfgh (31)
#   40-47  MMWP: no-region accesses fault (load / store / fetch at 0x8000_0000, just below and
#          just above MMIO, just above DV_ROM, just above ROM), mcause and mtval
#   50-55  regions: MMIO store + load round trip (bottom and top word), no fetch from MMIO; ROM
#          readable, not writable
#   60-63  RLB = 1: locked region 2's pmpcfg and pmpaddr rewritten and read back; MMWP sticky
#   70-74  RLB cleared: locked writes ignored, RLB cannot be set again, unlocked region 0 still
#          writable
#   80     with region 0 TOR [0, 0x9000_0000) unlocked, the 0x8000_0000 load no longer faults
#   0x100 | code  a trap where none was expected (s10 = mcause, s11 = mtval)
#
# Proving it can fail (build-time switch, not in the testlist):
#   -DEARLGREY_PMP_RESET_INJECT_FAIL  expects pmpaddr13 to reset to 0 -> gp = 27

#include "ibex_macros.h"

#define CSR_MSECCFGH 0x757

#define CAUSE_FETCH 1
#define CAUSE_LOAD  5
#define CAUSE_STORE 7

  .option norvc
  .option norelax

# \csr must read \val.
.macro EXPECT_CSR csr, val, code
  li    gp, \code
  csrr  a0, \csr
  li    t1, \val
  bne   a0, t1, fail
.endm

# The instruction \insn (operands \a, \b) must trap with mcause \cause and mtval \tval; the
# handler resumes at the label after it.
.macro FAULTS cause, tval, code, insn, a, b
  li    gp, \code
  la    s9, 9f
  li    s10, -1
  li    s11, -1
  \insn \a, \b
  j     fail                          # did not trap
9:
  mv    a0, s10
  li    t1, \cause
  bne   s10, t1, fail
  mv    a0, s11
  li    t1, \tval
  bne   s11, t1, fail
.endm

  .section .text.init
  .globl _start

# 0x0001_0000: mtvec's reset value is {boot address[31:8], 8'h01} (vectored), so every exception
# enters here. An expected fault sets s9 to its resume point; anything else fails the test.
trap_entry:
  csrr  s10, mcause
  csrr  s11, mtval
  beqz  s9, unexpected_trap
  csrw  mepc, s9
  li    s9, 0
  mret
unexpected_trap:
  ori   gp, gp, 0x100
  j     fail

  .org 0x80
# 0x0001_0080: the reset vector (boot address + 0x80).
_start:
  j     main

  .text
main:
  li    s9, 0
  li    gp, 0

  # ---- 10-31: the reset values, read before anything writes a PMP CSR ----
  EXPECT_CSR pmpcfg0,   0x009D0000, 10
  EXPECT_CSR pmpcfg1,   0x00000000, 11
  EXPECT_CSR pmpcfg2,   0x8B000000, 12
  EXPECT_CSR pmpcfg3,   0x00009F00, 13
  EXPECT_CSR pmpaddr0,  0x00000000, 14
  EXPECT_CSR pmpaddr1,  0x00000000, 15
  EXPECT_CSR pmpaddr2,  0x000100FF, 16
  EXPECT_CSR pmpaddr3,  0x00000000, 17
  EXPECT_CSR pmpaddr4,  0x00000000, 18
  EXPECT_CSR pmpaddr5,  0x00000000, 19
  EXPECT_CSR pmpaddr6,  0x00000000, 20
  EXPECT_CSR pmpaddr7,  0x00000000, 21
  EXPECT_CSR pmpaddr8,  0x00000000, 22
  EXPECT_CSR pmpaddr9,  0x00000000, 23
  EXPECT_CSR pmpaddr10, 0x10000000, 24
  EXPECT_CSR pmpaddr11, 0x10804000, 25
  EXPECT_CSR pmpaddr12, 0x00000000, 26
#ifdef EARLGREY_PMP_RESET_INJECT_FAIL
  EXPECT_CSR pmpaddr13, 0x00000000, 27
#else
  EXPECT_CSR pmpaddr13, 0x000041FF, 27
#endif
  EXPECT_CSR pmpaddr14, 0x00000000, 28
  EXPECT_CSR pmpaddr15, 0x00000000, 29
  EXPECT_CSR CSR_MSECCFG,  0x6, 30
  EXPECT_CSR CSR_MSECCFGH, 0x0, 31

  # ---- 40-47: MMWP denies M-mode every address no region matches ----
  li    t2, 0x80000000
  FAULTS CAUSE_LOAD,  0x80000000, 40, lw, t0, 0(t2)
  FAULTS CAUSE_STORE, 0x80000000, 41, sw, t0, 0(t2)
  FAULTS CAUSE_FETCH, 0x80000000, 42, jalr, zero, 0(t2)
  li    t2, 0x3FFFFFFC                # the word below MMIO
  FAULTS CAUSE_LOAD,  0x3FFFFFFC, 43, lw, t0, 0(t2)
  li    t2, 0x42010000                # the word above MMIO
  FAULTS CAUSE_LOAD,  0x42010000, 44, lw, t0, 0(t2)
  li    t2, 0x00011000                # the word above DV_ROM
  FAULTS CAUSE_LOAD,  0x00011000, 45, lw, t0, 0(t2)
  FAULTS CAUSE_FETCH, 0x00011000, 46, jalr, zero, 0(t2)
  li    t2, 0x00040800                # the word above ROM
  FAULTS CAUSE_LOAD,  0x00040800, 47, lw, t0, 0(t2)

  # ---- 50-55: what the reset regions allow ----
  li    t2, 0x40000000                # MMIO (region 11): read and write
  li    t3, 0x5A5A1234
  li    gp, 50
  sw    t3, 0(t2)
  lw    a0, 0(t2)
  bne   a0, t3, fail
  li    t2, 0x4200FFFC                # its top word
  li    gp, 51
  sw    t3, 0(t2)
  lw    a0, 0(t2)
  bne   a0, t3, fail
  li    t2, 0x40000000
  FAULTS CAUSE_FETCH, 0x40000000, 52, jalr, zero, 0(t2)   # no execute
  li    t2, 0x00040000                # ROM (region 2): read, execute, no write
  li    gp, 53
  lw    a0, 0(t2)                     # must not trap (uninitialised: any value)
  FAULTS CAUSE_STORE, 0x00040000, 54, sw, t0, 0(t2)
  li    t2, 0x000407FC                # its top word
  li    gp, 55
  lw    a0, 0(t2)

  # ---- 60-63: RLB = 1 lets M-mode rewrite a locked region ----
  li    t0, 0x00990000                # region 2: L NAPOT R (X dropped)
  csrw  pmpcfg0, t0
  EXPECT_CSR pmpcfg0, 0x00990000, 60
  li    t0, 0x0001007F                # region 2: 1 KiB
  csrw  pmpaddr2, t0
  EXPECT_CSR pmpaddr2, 0x0001007F, 61
  li    t0, 0x009D0000                # back to the reset values
  csrw  pmpcfg0, t0
  li    t0, 0x000100FF
  csrw  pmpaddr2, t0
  EXPECT_CSR pmpcfg0,  0x009D0000, 62
  csrci CSR_MSECCFG, MSECCFG_MMWP     # MMWP is sticky
  EXPECT_CSR CSR_MSECCFG, 0x6, 63

  # ---- 70-74: RLB cleared: the locked regions stay as they are ----
  csrci CSR_MSECCFG, MSECCFG_RLB
  EXPECT_CSR CSR_MSECCFG, 0x2, 70
  li    t0, 0x00990000
  csrw  pmpcfg0, t0                   # region 2 locked: ignored
  EXPECT_CSR pmpcfg0, 0x009D0000, 71
  li    t0, 0x0001007F
  csrw  pmpaddr2, t0                  # ignored
  EXPECT_CSR pmpaddr2, 0x000100FF, 72
  csrsi CSR_MSECCFG, MSECCFG_RLB      # locked regions exist: RLB stays 0
  EXPECT_CSR CSR_MSECCFG, 0x2, 73
  li    t0, 0x24000000                # region 0: TOR [0, 0x9000_0000), unlocked RWX, which
  csrw  pmpaddr0, t0                  # covers the end-of-test signature
  csrsi pmpcfg0, 0x0F
  EXPECT_CSR pmpcfg0,  0x009D000F, 74

  # ---- 80: memory is open ----
  li    t2, 0x80000000
  li    gp, 80
  lw    a0, 0(t2)                     # must not trap

pass:
  li    gp, 0
  fence
  li    t2, SIGNATURE_ADDR
  li    t1, (FINISHED_IRQ << 8) | CORE_STATUS
  sw    t1, 0(t2)
  li    t1, (TEST_PASS << 8) | TEST_RESULT
  sw    t1, 0(t2)
1:
  j     1b

# Fails with gp = the code. The signature address is reachable only through region 0, so fail
# opens it first; region 0 is never locked, so that works at any point of the test.
fail:
  li    t0, 0x24000000
  csrw  pmpaddr0, t0
  csrsi pmpcfg0, 0x0F
  fence
  li    t2, SIGNATURE_ADDR
  li    t1, (FINISHED_IRQ << 8) | CORE_STATUS
  sw    t1, 0(t2)
  li    t1, (TEST_FAIL << 8) | TEST_RESULT
  sw    t1, 0(t2)
1:
  j     1b
