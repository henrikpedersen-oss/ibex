# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cov_expr_pmp_tor -- empty TOR regions, a fetch at address 0, a trap vector at 0
# =============================================================================
# RISC-V mode (cheriot_enable_i Off, the riscv-tests default), Spike cosim on.
#
# Expression-coverage targets (merged regression after UNR, 2026-10-09):
#   ibex_pmp.sv `(region_match_eq | region_match_gt) & region_match_lt` (TOR arm), row
#     eq = 1, lt = 0, for every region of channels 0/1 (I, I2) and regions 0 and 2 of
#     channel 2 (D): an access at exactly the start address of a TOR region whose top is not
#     above its start (an empty TOR region). Row eq = 1, lt = 1 for region 15 of channels 0/1:
#     a fetch at exactly the start of a non-empty TOR region 15.
#   ibex_controller.sv `instr_fetch_err_plus2_i ? (pc_id_i + 2) : pc_id_i`, row plus2 = 0 with
#     pc_id_i = 0: an instruction access fault at pc 0.
#   ibex_if_stage.sv EXC_PC_EXC `{csr_mtvec_i[31:8], 8'h00}` = 0: an exception taken with the
#     mtvec base at 0 (RISC-V mode).
#
# Expected behaviour (not taken from the RTL):
#   - RISC-V Privileged ISA, PMP: "If PMP entry i's A field is set to TOR, the entry matches any
#     address y such that pmpaddr[i-1] <= y < pmpaddr[i] ... If pmpaddr[i-1] >= pmpaddr[i] and
#     pmpcfg[i].A = TOR, then PMP entry i matches no addresses." Entry 0 uses 0 as its bottom.
#   - A locked entry (L = 1) is enforced in M-mode; with no matching entry an M-mode access
#     succeeds (mseccfg.MMWP = 0). Smepmp: with mseccfg.RLB = 1 locked entries can be rewritten,
#     which lets this test lock and unlock entries.
#   - So: an M-mode fetch and load at the start of an empty, locked, no-permission TOR entry
#     must succeed; a fetch at the start of a locked TOR entry [X, X+16) without X faults
#     (mcause 1, mtval X), with X it succeeds.
#   - Instruction access fault at pc 0: mcause 1, mepc 0, mtval 0.
#   - mtvec base 0 (Ibex keeps MODE = vectored): an exception jumps to address 0.
#
# The bench memory and Spike answer every address (ibex_cosim_scoreboard.sv), so code and data
# can be placed at address 0. Word 0 is stored before it is read or fetched (an uninitialised
# d-side read returns bad integrity by default; +enable_bad_intg_on_uninit_access=0 as well).
#
# Failure: TEST_FAIL with the failing check's code in TESTNUM (gp):
#   1..16  region r-1 (1 = region 0): an access at the start of the empty TOR region trapped
#          (the empty region matched)
#   20     region 15 [X, X+16) with X: the fetch trapped
#   21/22/23  region 15 [X, X+16) without X: no fault / mcause not 1 / mtval not X
#   30/31/32  fetch at pc 0 under a locked no-X TOR region [0, 4): no fault / mcause not 1 /
#          mtval not 0 (mepc checked in the handler: 0x100 | code)
#   40/41  mtvec base 0: the handler at 0 did not run / mcause not 3 (breakpoint)
#   50     liveness: the number of fetches that returned (s7) is not 17 (address 0 once, the
#          stub for regions 1..15 and for region 15 with X)
#   0x100 | code  a trap other than the expected one (wrong mepc, or none expected)

#include "riscv_test.h"
#include "test_macros.h"

#define CSR_MSECCFG   0x747
#define MSECCFG_RLB   0x4
#define PMP_TOR_L     0x88          /* A = TOR, L = 1, R = W = X = 0 */
#define PMP_TOR_L_RX  0x8d          /* A = TOR, L = 1, R, X */
#define PMP_TOR_L_R   0x89          /* A = TOR, L = 1, R */

# Registers: s2 = stub address X, s3 = X >> 2, s7 = stub returns (liveness),
#   s8 = expected mcause (0: no trap expected), s9 = expected mtval, s10 = expected mepc,
#   s11 = resume address after an expected trap. t5/t6 belong to riscv_test.h's trap_vector.

.macro CLEAR_PMPCFG
  csrw  pmpcfg0, zero
  csrw  pmpcfg1, zero
  csrw  pmpcfg2, zero
  csrw  pmpcfg3, zero
.endm

# Region \r (1..15) as an empty locked TOR entry starting at X: pmpaddr[r-1] = pmpaddr[r] = X>>2,
# every other entry OFF; then fetch and load at X. Failure code \r.
.macro EMPTY_TOR_AT_X r
  li    TESTNUM, \r + 1
  CLEAR_PMPCFG
  csrw  0x3b0 + \r - 1, s3
  csrw  0x3b0 + \r, s3
  li    t0, PMP_TOR_L << (8 * (\r % 4))
  csrw  0x3a0 + (\r / 4), t0
  mv    t1, s2
  jalr  ra, 0(s2)
  CLEAR_PMPCFG
.endm

  .option norvc
  .option norelax

RVTEST_RV32M
RVTEST_CODE_BEGIN

  li    s8, 0
  li    s7, 0
  la    s2, stub
  srli  s3, s2, 2
  csrsi CSR_MSECCFG, MSECCFG_RLB

  # Word 0 holds `ret`, so a fetch at 0 returns at once and a load from 0 is initialised.
  li    t0, 0x00008067
  sw    t0, 0(zero)
  fence.i

  # ---- Region 0: TOR with pmpaddr0 = 0 is empty; fetch and load at 0 (channels I, I2, D) ----
  li    TESTNUM, 1
  CLEAR_PMPCFG
  csrw  pmpaddr0, zero
  li    t0, PMP_TOR_L
  csrw  pmpcfg0, t0
  lw    t1, 0(zero)
  li    t0, 0x00008067
  bne   t1, t0, fail
  jalr  ra, 0(zero)
  addi  s7, s7, 1
  CLEAR_PMPCFG

  # ---- Regions 1..15: empty TOR entry starting at the stub ----
  EMPTY_TOR_AT_X 1
  EMPTY_TOR_AT_X 2
  EMPTY_TOR_AT_X 3
  EMPTY_TOR_AT_X 4
  EMPTY_TOR_AT_X 5
  EMPTY_TOR_AT_X 6
  EMPTY_TOR_AT_X 7
  EMPTY_TOR_AT_X 8
  EMPTY_TOR_AT_X 9
  EMPTY_TOR_AT_X 10
  EMPTY_TOR_AT_X 11
  EMPTY_TOR_AT_X 12
  EMPTY_TOR_AT_X 13
  EMPTY_TOR_AT_X 14
  EMPTY_TOR_AT_X 15

  # ---- Region 15 non-empty [X, X+16): fetch at its start, with and without X ----
  li    TESTNUM, 20
  CLEAR_PMPCFG
  csrw  pmpaddr14, s3
  addi  t0, s3, 4
  csrw  pmpaddr15, t0
  li    t0, PMP_TOR_L_RX << 24
  csrw  pmpcfg3, t0
  mv    t1, s2
  jalr  ra, 0(s2)

  # Prove the locked entry is enforced: without X the same fetch faults.
  li    TESTNUM, 21
  li    t0, PMP_TOR_L_R << 24
  csrw  pmpcfg3, t0
  li    s8, CAUSE_FETCH_ACCESS
  mv    s9, s2
  mv    s10, s2
  la    s11, 1f
  jalr  ra, 0(s2)
  j     fail                          # the fetch did not fault
1:
  bnez  s8, fail                      # the handler did not see it
  CLEAR_PMPCFG

  # ---- Fetch at pc 0 under a locked no-X TOR entry [0, 4) (region 1): mtval = pc = 0 ----
  li    TESTNUM, 30
  csrw  pmpaddr0, zero
  li    t0, 1
  csrw  pmpaddr1, t0
  li    t0, PMP_TOR_L << 8
  csrw  pmpcfg0, t0
  li    s8, CAUSE_FETCH_ACCESS
  li    s9, 0
  li    s10, 0
  la    s11, 2f
  jalr  ra, 0(zero)
  j     fail
2:
  bnez  s8, fail
  CLEAR_PMPCFG

  # ---- Trap vector at 0: mtvec base 0, a breakpoint jumps to the handler copied to 0 ----
  li    TESTNUM, 40
  la    t1, vec0_handler
  li    t2, 0
  li    t3, 5
3:lw    t0, 0(t1)
  sw    t0, 0(t2)
  addi  t1, t1, 4
  addi  t2, t2, 4
  addi  t3, t3, -1
  bnez  t3, 3b
  fence.i
  li    t6, 0
  csrw  mtvec, zero
  ebreak
  la    t0, trap_vector
  csrw  mtvec, t0
  li    t0, 0x5a
  bne   t6, t0, fail
  li    TESTNUM, 41
  csrr  t0, mcause
  li    t1, CAUSE_BREAKPOINT
  bne   t0, t1, fail

  # ---- Liveness ----
  li    TESTNUM, 50
  li    t0, 17
  bne   s7, t0, fail
  csrci CSR_MSECCFG, MSECCFG_RLB
  li    TESTNUM, 1
  TEST_PASSFAIL

# t1 = X on entry: the load reads the stub's own first word (channel D at X).
  .balign 16
stub:
  lw    t0, 0(t1)
  addi  s7, s7, 1
  ret

# Copied to address 0 for the mtvec-base-0 case (t5/t6 are free in a handler here).
  .balign 4
vec0_handler:
  csrr  t5, mepc
  addi  t5, t5, 4
  csrw  mepc, t5
  li    t6, 0x5a
  mret

# RVTEST_CODE_BEGIN's trap_vector jumps here: only the expected trap is accepted.
mtvec_handler:
  beqz  s8, 9f
  csrr  t5, mcause
  bne   t5, s8, 8f
  csrr  t5, mtval
  bne   t5, s9, 7f
  csrr  t5, mepc
  bne   t5, s10, 9f
  li    s8, 0
  csrw  mepc, s11
  mret
8:addi  TESTNUM, TESTNUM, 1           # mcause wrong: code + 1
  j     fail
7:addi  TESTNUM, TESTNUM, 2           # mtval wrong: code + 2
  j     fail
9:ori   TESTNUM, TESTNUM, 0x100
  j     fail

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
