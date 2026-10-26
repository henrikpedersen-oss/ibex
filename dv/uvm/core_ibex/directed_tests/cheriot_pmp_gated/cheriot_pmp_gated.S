# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_pmp_gated -- in CHERIoT mode the ePMP has no effect (EG2 REQ_SOC_06)
# =============================================================================
# Earl Grey 2 REQ_SOC_06 (RFC CHERIoT in OpenTitan p3, "the ePMP extension will be disabled"; RFC
# CHERIoT Ibex "Execution Stage"): in CHERIoT mode the ePMP has no effect: regions and mseccfg
# (MMWP, locked entries) set before the switch deny no fetch, load or store after it.
#
# Runs on the earlgrey-pmprst build (Earl Grey's PMP reset values: MMWP = 1, RLB = 1, ROM region 2
# LRX, MMIO region 11 LRW, DV_ROM region 13 LRWX at 0x0001_0000, where the core boots), linked
# into DV_ROM as earlgrey_pmp_reset is. In RISC-V mode the program adds locked regions that deny
# everything:
#   region 0   NAPOT 0x8FFF_FFF8, 8 bytes   L R W   the end-of-test signature words only
#   region 1   NAPOT 0x8000_0000, 256 MiB   L       deny
#   region 14  NAPOT 0x0000_0000, 4 GiB     L       deny (below every Earl Grey region but 15)
# and clears mseccfg.RLB, so nothing can be undone; MMWP stays set. It checks in RISC-V mode that
# they deny (loads, a store and a fetch fault). Then it writes the trigger address (in DV_ROM) and
# the testbench raises cheriot_enable_i (+cheriot_enable_on_write). In CHERIoT mode it accesses,
# through capabilities derived from the roots, every place the PMP denies: a store and a load back
# at 0x8000_0000, 0x8010_0000, 0x8FFF_FFF0 (region 1), 0x2000_0000 and 0x0000_8000 (region 14),
# 0x0004_0100 (ROM: not writable in RISC-V mode); and it fetches: it writes two instructions to
# 0x8000_1000 and to 0x2000_0100 and calls each with CJALR. None may trap.
#
# Expected values (not from the RTL): REQ_SOC_06; the ePMP rules as earlgrey_pmp_reset states them
# (RISC-V Privileged ISA PMP, Smepmp; faults: fetch 1, load 5, store 7).
#
# Failure codes (gp; a0 = the value read, for the trace):
#   10-12  the PMP as written: pmpcfg0, pmpcfg3, mseccfg (MMWP only)
#   20-24  RISC-V mode, the regions deny: load 0x8000_0000, store 0x8010_0000, load 0x2000_0000,
#          store 0x0004_0100, fetch 0x8000_1000 (mcause and mtval)
#   30     CHERIoT mode on (AUIPCC tagged)
#   31-36  CHERIoT mode: store/load round trips at the six addresses above
#   40-41  CHERIoT mode: the fetches from 0x8000_1000 and 0x2000_0100 ran
#   0x100 | code  an unexpected trap in RISC-V mode (s10 = mcause, s11 = mtval)
#   0x200 | code  any trap in CHERIoT mode: a PMP fault where REQ_SOC_06 allows none (a3 = mcause,
#                 a4 = mtval)
#
# Proving it can fail: -DPMP_GATED_INJECT_FAIL expects the second fetch's count one too high
# (gp = 41).
#
# Cosim off: the models are not configured with these reset values, and neither models the pin.

#include "ibex_macros.h"
#include "cheriot_dv.h"

#define CAUSE_FETCH 1
#define CAUSE_LOAD  5
#define CAUSE_STORE 7
#define TRIGGER     0x00010F00        // in DV_ROM; must match +cheriot_enable_on_write
#define PATTERN     0x3C5AA5C3

#ifdef PMP_GATED_INJECT_FAIL
#define EXP_FETCHES 3
#else
#define EXP_FETCHES 2
#endif

  .option norvc
  .option norelax

.macro EXPECT_CSR csr, val, code
  li    gp, \code
  csrr  a0, \csr
  li    t1, \val
  bne   a0, t1, fail
.endm

# RISC-V mode: \insn must trap with mcause \cause and mtval \tval (earlgrey_pmp_reset's FAULTS).
.macro FAULTS cause, tval, code, insn, a, b
  li    gp, \code
  la    s9, 9f
  li    s10, -1
  li    s11, -1
  \insn \a, \b
  j     fail
9:
  mv    a0, s10
  li    t1, \cause
  bne   s10, t1, fail
  mv    a0, s11
  li    t1, \tval
  bne   s11, t1, fail
.endm

# CHERIoT mode: store PATTERN ^ \addr at \addr through the memory root, load it back.
.macro ROUND_TRIP addr, code
  li        gp, \code
  li        t1, \addr
  cspecialr a1, SCR_MTDC
  csetaddr  a1, a1, t1
  li        t2, PATTERN ^ \addr
  sw        t2, 0(a1)
  lw        a0, 0(a1)
  bne       a0, t2, fail
.endm

# CHERIoT mode: write `addi a0, a0, 1; ret` at \addr, then call it through PCC's root.
.macro FETCH_AT addr
  li        t1, \addr
  cspecialr a1, SCR_MTDC
  csetaddr  a1, a1, t1
  li        t2, 0x00150513            # addi a0, a0, 1
  sw        t2, 0(a1)
  li        t2, 0x00008067            # ret (CJALR cnull, cra)
  sw        t2, 4(a1)
  fence.i
  auipc     a2, 0                     # AUIPCC: the executable root (PCC)
  csetaddr  a2, a2, t1
  jalr      ra, 0(a2)                 # CJALR cra, ca2
.endm

  .section .text.init
  .globl _start

# 0x0001_0000: mtvec's reset value (vectored, base = the boot address). tp = 0 in RISC-V mode,
# 1 in CHERIoT mode; in CHERIoT mode only x1-x15 may be used.
trap_entry:
  bnez  tp, cheri_trap
  csrr  s10, mcause
  csrr  s11, mtval
  beqz  s9, unexpected_trap
  csrw  mepc, s9
  li    s9, 0
  mret
unexpected_trap:
  ori   gp, gp, 0x100
  j     fail
cheri_trap:
  csrr  a3, mcause
  csrr  a4, mtval
  ori   gp, gp, 0x200
  j     fail

  .org 0x80
_start:
  j     main

  .text
main:
  li    s9, 0
  li    gp, 0
  li    tp, 0

  # ---- The deny-all regions, locked, and RLB cleared ----
  li    t0, 0x23FFFFFE                # region 0: NAPOT 0x8FFF_FFF8, 8 bytes
  csrw  pmpaddr0, t0
  li    t0, 0x21FFFFFF                # region 1: NAPOT 0x8000_0000, 256 MiB
  csrw  pmpaddr1, t0
  li    t0, 0x1FFFFFFF                # region 14: NAPOT 0, 4 GiB
  csrw  pmpaddr14, t0
  li    t0, 0x009D989B                # 0: L NAPOT RW; 1: L NAPOT; 2: the ROM as at reset
  csrw  pmpcfg0, t0
  li    t0, 0x00989F00                # 13: DV_ROM as at reset; 14: L NAPOT
  csrw  pmpcfg3, t0
  csrci CSR_MSECCFG, MSECCFG_RLB
  EXPECT_CSR pmpcfg0, 0x009D989B, 10
  EXPECT_CSR pmpcfg3, 0x00989F00, 11
  EXPECT_CSR CSR_MSECCFG, 0x2, 12

  # ---- 20-24: in RISC-V mode they deny ----
  li    t2, 0x80000000
  FAULTS CAUSE_LOAD,  0x80000000, 20, lw, a0, 0(t2)
  li    t2, 0x80100000
  FAULTS CAUSE_STORE, 0x80100000, 21, sw, a0, 0(t2)
  li    t2, 0x20000000
  FAULTS CAUSE_LOAD,  0x20000000, 22, lw, a0, 0(t2)
  li    t2, 0x00040100
  FAULTS CAUSE_STORE, 0x00040100, 23, sw, a0, 0(t2)
  li    t2, 0x80001000
  FAULTS CAUSE_FETCH, 0x80001000, 24, jalr, x0, 0(t2)

  # ---- The switch ----
  li    t2, TRIGGER
  sw    zero, 0(t2)
  .rept 30                            # the pin rises cheriot_enable_delay (6) cycles after the store
  nop
  .endr
  li    tp, 1                         # from here a trap is a CHERIoT-mode one

  # ---- 30: CHERIoT mode is on ----
  li    gp, 30
  auipc a1, 0
  cgettag a0, a1
  li    t1, 1
  bne   a0, t1, fail

  # ---- 31-36: loads and stores the PMP denies ----
  ROUND_TRIP 0x80000000, 31
  ROUND_TRIP 0x80100000, 32
  ROUND_TRIP 0x8FFFFFF0, 33
  ROUND_TRIP 0x20000000, 34
  ROUND_TRIP 0x00008000, 35
  ROUND_TRIP 0x00040100, 36

  # ---- 40-41: fetches the PMP denies ----
  li    a0, 0
  li    gp, 40
  FETCH_AT 0x80001000
  li    t1, 1
  bne   a0, t1, fail
  li    gp, 41
  FETCH_AT 0x20000100
  li    t1, EXP_FETCHES
  bne   a0, t1, fail

pass:
  li    gp, 0
  li    t1, (FINISHED_IRQ << 8) | CORE_STATUS
  li    t2, (TEST_PASS << 8) | TEST_RESULT
  j     sig

# Fails with gp = the code.
fail:
  li    t1, (FINISHED_IRQ << 8) | CORE_STATUS
  li    t2, (TEST_FAIL << 8) | TEST_RESULT

# Writes t1 then t2 to the signature address (region 0 allows it in RISC-V mode); in CHERIoT mode
# through the memory root.
sig:
  fence
  li    a1, SIGNATURE_ADDR
  beqz  tp, 1f
  cspecialr a2, SCR_MTDC
  csetaddr  a1, a2, a1
1:
  sw    t1, 0(a1)
  sw    t2, 0(a1)
2:
  j     2b
