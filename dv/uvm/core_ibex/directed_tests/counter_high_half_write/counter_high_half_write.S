# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: counter_high_half_write -- writes to the upper half of every 64-bit counter
# =============================================================================
# REQ_ISA_10 (performance counters count correctly); spec coverpoints
# cp_counter_upper_half_write and cp_counter_lower_wrap (ibex_counter.sv section).
#
# RTL blocks targeted (no regression test wrote an `h` counter CSR before this one):
#   ibex_counter.sv `if (counterh_we_i) begin` (the upper-half load) in
#     cs_registers_i.mcycle_counter_i                       (mcycleh,  0xB80)
#     cs_registers_i.minstret_counter_i                     (minstreth, 0xB82)
#     cs_registers_i.gen_cntrs[0..9].gen_imp.mcounters_variable_i
#                                                           (mhpmcounter3h..12h, 0xB83..0xB8C)
#   and the low-half carry into the upper half of mcycle and minstret.
#
# Expected behaviour (not taken from the RTL):
#   - RISC-V Privileged ISA, RV32 counters: mcycleh / minstreth / mhpmcounterNh are bits 63:32
#     of the 64-bit counter. A write to the upper half sets those bits and leaves the lower half
#     alone; the counter keeps counting across 2^32, carrying into the upper half.
#   - A write to minstret/minstreth is not counted by the writing instruction (Sail
#     riscv_insts_zicsr.sail:150-152, minstret_increment = false). The low-half checks below
#     use a window, so they hold whichever way an implementation counts; the exact count is
#     Spike's to compare (csrr minstret is not pushed from the DUT, unlike mcycle/HPM).
#   - Event counters: the verified configuration has MHPMCounterNum = 10 and
#     MHPMCounterWidth = 32 (spec, "Verified configuration" table; ibex_configs.yaml
#     opentitan). A 32-bit counter has no bits 63:32 (doc/03_reference/performance_counters.rst:
#     "Their width can be parametrized between 1 and 64 bit"), so mhpmcounterNh reads 0 after
#     a write of all-ones, and the low half is unchanged by it.
#
# Runs in RISC-V mode against Spike. mcountinhibit is deliberately never touched: this Spike has
# no inhibit for minstret, so an inhibited minstret would diverge from the ISS.
# The mhpmcounter accesses come last: the optional RISC-V Sail checker
# (+riscv_sail_cosim=1) stops at the first HPM access by design (riscv_sail_unmodelled).
#
# Failure: the testbench sees TEST_FAIL; TESTNUM (gp) holds the code of the failing check.
#   1  mcycleh != H1 after the write            2  second mcycleh read != H1
#   3  mcycle low half not in [L1, L1+64K): the upper-half write disturbed the lower half
#   4  mcycle did not carry into mcycleh (hi != H1+1 after low = 0xFFFFFF00 and >= 1024 cycles)
#   5  mcycle low half after the carry not below 64K
#   6  minstreth != H2 after the write          7  second minstreth read != H2
#   8  minstret low half not in [L2, L2+256)
#   9  minstret did not carry into minstreth (low = 0xFFFFFFF0, then >= 64 instructions)
#   10 minstret low half after the carry not in [1, 256)
#   20+N  mhpmcounterNh != 0 after writing 0xFFFFFFFF (N = 3..12)
#   40+N  mhpmcounterN low half not in [0x1000+N, 0x1000+N+256) after the upper-half write
#   99    liveness: fewer checks executed than assembled
#   0x100 | code  unexpected trap while check `code` was in progress

#include "riscv_test.h"
#include "test_macros.h"

#define H1 0x5A5A0001
#define L1 0x00100000
#define H2 0xA5A50002
#define L2 0x00200000

# s1 counts the checks executed; NCHK counts the checks assembled.
.set NCHK, 0
.macro CHK_EQ a, b, code
  .set  NCHK, NCHK + 1
  li    TESTNUM, \code
  addi  s1, s1, 1
  bne   \a, \b, fail
.endm
# Uses t6: \a must not be t6.
.macro CHK_EQI a, imm, code
  li    t6, \imm
  CHK_EQ \a, t6, \code
.endm
# \a <u \imm. Uses t6.
.macro CHK_LTU a, imm, code
  .set  NCHK, NCHK + 1
  li    TESTNUM, \code
  addi  s1, s1, 1
  li    t6, \imm
  bgeu  \a, t6, fail
.endm

# A consistent 64-bit read: upper, lower, upper again, retried if the upper half moved.
.macro READ64 hi, lo, csrh, csrl, tmp
1:
  csrr  \hi, \csrh
  csrr  \lo, \csrl
  csrr  \tmp, \csrh
  bne   \hi, \tmp, 1b
.endm

# Event counter N: low half := 0x1000+N, upper half := all-ones, then read both back.
.macro HPM_CHECK n
  li    t0, 0x1000 + \n
  csrw  0xB00 + \n, t0
  li    t1, 0xFFFFFFFF
  csrw  0xB80 + \n, t1
  csrr  a0, 0xB80 + \n
  csrr  a1, 0xB00 + \n
  CHK_EQ a0, zero, 20 + \n
  sub   a1, a1, t0
  CHK_LTU a1, 0x100, 40 + \n
.endm

RVTEST_RV32M
RVTEST_CODE_BEGIN

  .option push
  .option norvc                   # no compressed instructions: keeps mhpmcounter10 still
  li    s1, 0

  # ── mcycle: upper-half write, lower half untouched ──────────────────────────
  li    t0, L1
  csrw  mcycle, t0
  li    t0, H1
  csrw  mcycleh, t0
  csrr  a0, mcycleh
  csrr  a1, mcycle
  csrr  a2, mcycleh
  CHK_EQI a0, H1, 1
  CHK_EQI a2, H1, 2
  li    t0, L1
  sub   a1, a1, t0
  CHK_LTU a1, 0x10000, 3

  # ── mcycle: carry from the lower into the upper half ────────────────────────
  li    t0, 0xFFFFFF00            # 256 cycles below the wrap
  csrw  mcycle, t0
  li    t0, 512
2:
  addi  t0, t0, -1
  bnez  t0, 2b                    # >= 1024 instructions, so >= 1024 cycles
  READ64 a0, a1, mcycleh, mcycle, a2
  CHK_EQI a0, H1 + 1, 4
  CHK_LTU a1, 0x10000, 5

  # ── minstret: upper-half write, lower half untouched ────────────────────────
  li    t0, L2
  csrw  minstret, t0
  li    t0, H2
  csrw  minstreth, t0
  csrr  a0, minstreth
  csrr  a1, minstret
  csrr  a2, minstreth
  CHK_EQI a0, H2, 6
  CHK_EQI a2, H2, 7
  li    t0, L2
  sub   a1, a1, t0
  CHK_LTU a1, 0x100, 8

  # ── minstret: carry from the lower into the upper half ──────────────────────
  li    t0, 0xFFFFFFF0            # 16 instructions below the wrap
  csrw  minstret, t0
  li    t0, 32
3:
  addi  t0, t0, -1
  bnez  t0, 3b                    # 64 instructions retire
  READ64 a0, a1, minstreth, minstret, a2
  CHK_EQI a0, H2 + 1, 9
  addi  a1, a1, -1                # [1, 256) -> [0, 255)
  CHK_LTU a1, 0xFF, 10

  # ── mhpmcounter3h..12h (32-bit event counters) ──────────────────────────────
  .irp n, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
    HPM_CHECK \n
  .endr

  li    TESTNUM, 99
  li    t0, NCHK
  bne   s1, t0, fail
  j     pass
  .option pop

  TEST_PASSFAIL

# Any trap is unexpected. RVTEST_CODE_BEGIN's trap_vector jumps here; keep the code of the check
# in progress and mark it.
.balign 256
mtvec_handler:
  ori   TESTNUM, TESTNUM, 0x100
  j     fail

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
