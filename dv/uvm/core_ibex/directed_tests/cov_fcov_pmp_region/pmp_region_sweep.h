# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Shared body of cov_fcov_pmp_region_mml0 and cov_fcov_pmp_region_mml1: per-region PMP access
# sweeps. Included by the test after riscv_test.h / test_macros.h; the test supplies the round
# table and calls RUN_ROUNDS. See the test headers for the targeted bins.
#
# Probe area. RVTEST_CODE_BEGIN puts _start at .org 0x80 of .text.init, so 0x80000000..0x8000007F
# is the lowest part of the image and holds no code. PROBE_AREA fills it with ecall, in 16 chunks
# of 8 bytes, one per PMP region: chunk i = [0x80000000 + 8i, +8), target address T_i = its first
# word. Every mode puts region i on chunk i and only there:
#   TOR    pmpaddr[i] = A(i+1)   region i = [A(i), A(i+1)); region 0 = [0, A(1)), nothing below
#                                address below 0x80000000 is touched
#   NA4    pmpaddr[i] = A(i)     region i = [T_i, T_i + 4)
#   NAPOT  pmpaddr[i] = A(i)     A(i) is even, so the NAPOT size is 8 bytes: [T_i, T_i + 8)
# with A(i) = (0x80000000 + 8i) >> 2. Code, the trap handler, the round table and the signature
# address are all at or above 0x80000080, outside every probe region in every mode, so a round
# can never deny the test its own code or data (under MML = 1 the test's code region must still
# grant M-mode execute; see cov_fcov_pmp_region_mml1).
#
# Probes. For region i the test does six accesses to T_i, each ending in exactly one trap that the
# handler records (mcause -> s6, mtval -> s7, mepc -> s8) before resuming at the continuation the
# probe armed in s5:
#   P1 MX M-mode fetch: jr T_i.                   allowed: ecall, mcause 11, mepc T_i
#   P2 UX U-mode fetch: mret to T_i, MPP = U.     allowed: ecall, mcause 8,  mepc T_i
#   P3 MR M-mode lw from T_i, then ecall.         allowed: mcause 11 at the ecall, rd = 0x73
#   P4 MW M-mode sw of 0x73 (the word already there, so code is unchanged), then ecall
#   P5 UR lw with mstatus.MPRV = 1, MPP = U (effective U-mode data access), then ecall
#   P6 UW sw with MPRV = 1, MPP = U, then ecall
#   denied: fetch -> mcause 1, mtval T_i, mepc T_i; load -> mcause 5, store -> mcause 7, mtval T_i,
#   mepc the access.
# A fetch of T_i also drives the PMP's second fetch channel (PMP_I2 checks pc + 2 for every fetch,
# ibex_core.sv pc_if_inc), and T_i + 2 lies in the same chunk and region, so each fetch probe
# samples the iside2 crosses with the same region, permission bits, privilege and result as the
# iside ones.
#
# The expected outcome of each probe is a bit of the round's expectation mask (bit k-1 for probe
# k): Privileged Spec 3.7 (PMP; locked entries also bind M-mode, unlocked entries do not) and
# Smepmp 1.0 Table 2 (mseccfg.MML = 1). Each mask is listed with its derivation in the test.
#
# Registers: gp TESTNUM; a0 T_i; a1 round mask; a2 probes run; a3 probes allowed; s2 round table
# pointer; s3 region; s4 access address; s5 armed continuation (0 = no trap expected); s6/s7/s8
# mcause/mtval/mepc of the last trap; s9 failure-code base; s10 round; s11 round cfg byte.
# t5/t6 belong to riscv_test.h's trap_vector. t0-t4 scratch.
#
# Failure: TEST_FAIL with TESTNUM (gp) = KIND << 20 | PHASE << 16 | ROUND << 8 | REGION << 4 | PROBE
#   KIND: 1 wrong mcause, 2 wrong mtval, 3 wrong mepc, 4 an allowed load read the wrong data,
#         5 pmpcfg/pmpaddr read back wrong (REGION = CSR or entry index, PROBE = 0 cfg, 8 addr),
#         6 a trap with no probe armed, 7 liveness (probe counts at the end), 8 setup
#   PHASE as the test defines it; ROUND = index in the round table; PROBE 1..6 as above.

#define PROBE_BASE      0x80000000
#define A(i)            ((PROBE_BASE + 8 * (i)) >> 2)
#define ECALL_INSN      0x00000073

#define PMP_CFG_R       0x01
#define PMP_CFG_W       0x02
#define PMP_CFG_X       0x04
#define PMP_CFG_TOR     0x08
#define PMP_CFG_NA4     0x10
#define PMP_CFG_NAPOT   0x18
#define PMP_CFG_L       0x80

#define KIND_CAUSE      (1 << 20)
#define KIND_MTVAL      (2 << 20)
#define KIND_MEPC       (3 << 20)
#define KIND_DATA       (4 << 20)
#define KIND_CSR        (5 << 20)
#define KIND_UNEXP      (6 << 20)
#define KIND_LIVE       (7 << 20)
#define KIND_SETUP      (8 << 20)

# ---------------------------------------------------------------------------------------------
# Thirty-two ecall words at 0x80000000, before RVTEST_CODE_BEGIN's .org 0x80.
.macro PROBE_AREA
  .section .text.init, "ax"
  .global probe_area
probe_area:
  .rept 32
  .word ECALL_INSN
  .endr
.endm

# ---------------------------------------------------------------------------------------------
# Check a fetch probe. \bit: the mask bit; \ok_cause: mcause of the ecall if allowed.
.macro CHECK_FETCH bit, ok_cause
  bne   s8, a0, fail_mepc
  andi  t0, a1, \bit
  beqz  t0, .Ldeny\@
  li    t0, \ok_cause
  bne   s6, t0, fail_cause
  addi  a3, a3, 1
  j     .Ldone\@
.Ldeny\@:
  li    t0, CAUSE_FETCH_ACCESS
  bne   s6, t0, fail_cause
  bne   s7, a0, fail_mtval
.Ldone\@:
  addi  a2, a2, 1
.endm

# Check a data probe: s4 = address of the access, the ecall follows it. \is_load: check t1.
.macro CHECK_DATA bit, flt_cause, is_load
  andi  t0, a1, \bit
  beqz  t0, .Ldeny\@
  li    t0, CAUSE_MACHINE_ECALL
  bne   s6, t0, fail_cause
  addi  t0, s4, 4
  bne   s8, t0, fail_mepc
  .if \is_load
  li    t0, ECALL_INSN
  bne   t1, t0, fail_data
  .endif
  addi  a3, a3, 1
  j     .Ldone\@
.Ldeny\@:
  li    t0, \flt_cause
  bne   s6, t0, fail_cause
  bne   s7, a0, fail_mtval
  bne   s8, s4, fail_mepc
.Ldone\@:
  addi  a2, a2, 1
.endm

# Effective data privilege U for the next load/store (M-mode code, mstatus.MPRV = 1, MPP = U).
# The trap the probe ends in sets MPP = M, and the handler clears MPRV.
.macro DATA_AS_U
  li    t0, MSTATUS_MPP
  csrc  mstatus, t0
  li    t0, MSTATUS_MPRV
  csrs  mstatus, t0
.endm

# ---------------------------------------------------------------------------------------------
# The six probes of one region: a0 = T_i, a1 = mask, s9 = failure-code base. Returns via ra
# (no trap touches ra).
.macro PROBE_REGION_FN
probe_region:
  # probe 1: MX
  ori   TESTNUM, s9, 1
  lla   s5, .Lmx_ret
  jr    a0
.Lmx_ret:
  CHECK_FETCH 0x01, CAUSE_MACHINE_ECALL

  # probe 2: UX
  ori   TESTNUM, s9, 2
  li    t0, MSTATUS_MPP
  csrc  mstatus, t0
  csrw  mepc, a0
  lla   s5, .Lux_ret
  mret
.Lux_ret:
  CHECK_FETCH 0x02, CAUSE_USER_ECALL

  # probe 3: MR
  ori   TESTNUM, s9, 3
  li    t1, -1
  lla   s4, .Lmr_acc
  lla   s5, .Lmr_ret
.Lmr_acc:
  lw    t1, 0(a0)
  ecall
.Lmr_ret:
  CHECK_DATA 0x04, CAUSE_LOAD_ACCESS, 1

  # probe 4: MW
  ori   TESTNUM, s9, 4
  li    t1, ECALL_INSN
  lla   s4, .Lmw_acc
  lla   s5, .Lmw_ret
.Lmw_acc:
  sw    t1, 0(a0)
  ecall
.Lmw_ret:
  CHECK_DATA 0x08, CAUSE_STORE_ACCESS, 0

  # probe 5: UR
  ori   TESTNUM, s9, 5
  li    t1, -1
  lla   s4, .Lur_acc
  lla   s5, .Lur_ret
  DATA_AS_U
.Lur_acc:
  lw    t1, 0(a0)
  ecall
.Lur_ret:
  CHECK_DATA 0x10, CAUSE_LOAD_ACCESS, 1

  # probe 6: UW
  ori   TESTNUM, s9, 6
  li    t1, ECALL_INSN
  lla   s4, .Luw_acc
  lla   s5, .Luw_ret
  DATA_AS_U
.Luw_acc:
  sw    t1, 0(a0)
  ecall
.Luw_ret:
  CHECK_DATA 0x20, CAUSE_STORE_ACCESS, 0
  ret
.endm

# ---------------------------------------------------------------------------------------------
# Failure exits: OR the kind into TESTNUM and fail.
.macro FAIL_EXITS
fail_cause:
  li    t0, KIND_CAUSE
  j     fail_kind
fail_mtval:
  li    t0, KIND_MTVAL
  j     fail_kind
fail_mepc:
  li    t0, KIND_MEPC
  j     fail_kind
fail_data:
  li    t0, KIND_DATA
  j     fail_kind
fail_csr:
  li    t0, KIND_CSR
fail_kind:
  or    TESTNUM, TESTNUM, t0
  j     fail
.endm

# RVTEST_CODE_BEGIN's trap_vector jumps here. Every trap must be one a probe armed (s5 != 0).
# Return to M-mode at the continuation, with MPRV clear.
.macro TRAP_HANDLER
  .balign 4
  .global mtvec_handler
mtvec_handler:
  beqz  s5, .Lunexpected
  csrr  s6, mcause
  csrr  s7, mtval
  csrr  s8, mepc
  li    t6, MSTATUS_MPRV
  csrc  mstatus, t6
  li    t6, MSTATUS_MPP
  csrs  mstatus, t6
  csrw  mepc, s5
  li    s5, 0
  mret
.Lunexpected:
  li    t6, KIND_UNEXP
  or    TESTNUM, TESTNUM, t6
  j     fail
.endm

# ---------------------------------------------------------------------------------------------
# pmpaddr[i] := t0 + 2 * i for i = lo..hi, each read back (failure: KIND_CSR, PROBE 8).
.macro SET_PMPADDRS lo, hi
  .set .Lpa_i, \lo
  .rept \hi - \lo + 1
  addi  t1, t0, 2 * .Lpa_i
  csrw  0x3b0 + .Lpa_i, t1
  csrr  t2, 0x3b0 + .Lpa_i
  ori   TESTNUM, s9, (.Lpa_i << 4) | 8
  bne   t2, t1, fail_csr
  .set .Lpa_i, .Lpa_i + 1
  .endr
.endm

# pmpcfg\n := (t3 & \keep) | \fix, read back (failure: KIND_CSR, REGION = n, PROBE 0).
.macro SET_PMPCFG n, keep, fix
  li    t0, \keep
  and   t1, t3, t0
  li    t0, \fix
  or    t1, t1, t0
  csrw  0x3a0 + \n, t1
  csrr  t2, 0x3a0 + \n
  ori   TESTNUM, s9, (\n << 4)
  bne   t2, t1, fail_csr
.endm

# Run every round of \table (\nrounds entries of {cfg byte, mask}) over regions \lo..\hi.
# Per round: pmpaddr for the round's mode (written while the previous round's entries are still
# in place, locked or not: mseccfg.RLB = 1), then the cfg byte in every probed region's slot of
# pmpcfg0..3 (keep/fix masks preserve the test's code region), then the six probes per region.
.macro RUN_ROUNDS table, nrounds, lo, hi, phase, k0, f0, k1, f1, k2, f2, k3, f3
  lla   s2, \table
  li    s10, 0
.Lround\@:
  lbu   s11, 0(s2)
  lbu   a1, 1(s2)
  slli  s9, s10, 8
  li    t0, \phase << 16
  or    s9, s9, t0
  # pmpaddr: TOR -> A(i+1), NA4 / NAPOT -> A(i)
  li    t0, A(0)
  andi  t1, s11, 0x18
  li    t2, PMP_CFG_TOR
  bne   t1, t2, .Lnot_tor\@
  li    t0, A(1)
.Lnot_tor\@:
  SET_PMPADDRS \lo, \hi
  # t3 = the cfg byte in all four slots
  slli  t3, s11, 8
  or    t3, t3, s11
  slli  t0, t3, 16
  or    t3, t3, t0
  SET_PMPCFG 0, \k0, \f0
  SET_PMPCFG 1, \k1, \f1
  SET_PMPCFG 2, \k2, \f2
  SET_PMPCFG 3, \k3, \f3
  # probes
  li    s3, \lo
.Lregion\@:
  slli  a0, s3, 3
  li    t0, PROBE_BASE
  add   a0, a0, t0
  slli  t0, s3, 4
  slli  s9, s10, 8
  or    s9, s9, t0
  li    t0, \phase << 16
  or    s9, s9, t0
  jal   ra, probe_region
  addi  s3, s3, 1
  li    t0, \hi
  ble   s3, t0, .Lregion\@
  addi  s2, s2, 2
  addi  s10, s10, 1
  li    t0, \nrounds
  blt   s10, t0, .Lround\@
.endm

# Round table entry: the cfg byte (permission bits P with the round's A field) and the mask.
.macro ROUND p, a, mask
  .byte (\p) | (\a), \mask
.endm
