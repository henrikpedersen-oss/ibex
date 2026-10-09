# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: zcmp_push_pop_mv -- every Zcmp instruction, self-checked, cosim off
# =============================================================================
# Purpose
#   Execute cm.push, cm.pop, cm.popret, cm.popretz, cm.mvsa01 and cm.mva01s on the
#   RISC-V-mode core (cheriot_enable_i Off, the riscv-tests default) and check every
#   architectural effect in the program itself. Zcmp is only decoded with the pin Off:
#   ibex_compressed_decoder.sv raises illegal for quadrant 2 funct3 101 in CHERIoT mode.
#
# Why a directed, self-checking test
#   riscv-dv generates no Zcmp in the regression, and the Spike cosim cannot pair the
#   multiple data-side accesses of one cm.push/cm.pop with the RTL's (GAP-RV-6 in
#   ibex_cheriot_verification_spec.md). Block coverage of the full UVM regression shows
#   the Zcmp micro-sequencer in ibex_compressed_decoder.sv never runs. This test runs
#   with +disable_cosim=1; the expected values come from the Zc specification
#   (RISC-V Code Size Reduction extensions, Zcmp chapter), not from the RTL:
#     - rlist 4..15 = {ra}, {ra,s0}, {ra,s0-s1}, ... {ra,s0-s9}, and 15 = {ra,s0-s11}
#       (there is no {ra,s0-s10});
#     - RV32 stack_adj_base: rlist 4-7 = 16, 8-11 = 32, 12-14 = 48, 15 = 64;
#       stack_adj = stack_adj_base + spimm * 16;
#     - push stores the highest register at sp-4 and works down (ra lowest), then
#       sp -= stack_adj; pop loads from the same slots relative to sp + stack_adj, then
#       sp += stack_adj; popretz then sets a0 = 0; popret/popretz then return to ra;
#     - sreg specifiers r1s/r2s: 0,1 = s0,s1 (x8,x9); 2..7 = s2..s7 (x18..x23);
#       cm.mvsa01: r1s = a0, r2s = a1 (r1s == r2s reserved, not used);
#       cm.mva01s: a0 = r1s, a1 = r2s (r1s == r2s allowed and used).
#   The local toolchain (binutils 2.35) has no Zcmp mnemonics, so each instruction is
#   a .hword built from the Zc encoding (quadrant 2, funct3 101):
#     cm.push    101 11000 rlist[3:0] spimm[1:0] 10   -> 0xB802 | rlist<<4 | spimm<<2
#     cm.pop     101 11010 rlist      spimm      10   -> 0xBA02 | ...
#     cm.popretz 101 11100 rlist      spimm      10   -> 0xBC02 | ...
#     cm.popret  101 11110 rlist      spimm      10   -> 0xBE02 | ...
#     cm.mvsa01  101 011 r1s[2:0] 01 r2s[2:0] 10      -> 0xAC22 | r1s<<7 | r2s<<2
#     cm.mva01s  101 011 r1s[2:0] 11 r2s[2:0] 10      -> 0xAC62 | r1s<<7 | r2s<<2
#   Checked against an assembler that knows Zcmp: binutils 2.46 objdump disassembles
#   every .hword here as the intended cm.* instruction (see the change description).
#
# Coverage target (ibex_compressed_decoder.sv)
#   Section 1 PUSH (21 cases): CmIdle -> CmPushDecrSp (rlist 4) and
#     CmIdle -> CmPushStoreReg -> CmPushDecrSp (rlist 5..15); every rlist 4..15, every
#     spimm 0..3 (rlist 4 and 15 with all four), so cm_stack_adj_base takes all four
#     values and cm_rlist_top_reg every legal item including the internal rlist 16
#     (cm_rlist_init 15 -> 16, s11 = x27); cm_sp_addi with decr = 1. Three cases sit
#     behind a DIV, so the next cm.* waits in IF with valid_i && !id_in_ready_i.
#   Section 2 POP (42 cases): CmIdle -> CmPopIncrSp (rlist 4) and
#     CmIdle -> CmPopLoadReg -> CmPopIncrSp; CmPopIncrSp -> CmIdle (cm.pop),
#     -> CmPopZeroA0 -> CmPopRetRa (cm.popretz), -> CmPopRetRa (cm.popret); every
#     kind x rlist 4..15, every kind x spimm 0..3; cm_sp_addi with decr = 0,
#     cm_stack_adj_word, cm_zero_a0, cm_ret_ra. Four cases sit behind a DIV: every kind
#     with rlist > 4 (the CmIdle `if (valid_i && id_in_ready_i)` before CmPopLoadReg
#     with its implicit else) and popretz with rlist 4 (the one before CmPopIncrSp).
#     Xcelium scores that CmIdle code once per case label (pop, popretz, popret), so
#     each kind needs its own stalled case; popretz rlist > 4 was the one missing
#     (block coverage after UNR, 2026-10-09).
#   Section 3 MV (126 cases): cm.mvsa01 for all 56 r1s != r2s pairs and cm.mva01s for
#     all 64 pairs: CmIdle -> CmMvSecondReg -> CmIdle, cm_mvsa01/cm_mva01s/cm_mv_reg
#     with every sreg on both sides. Three of each again with the first move's source
#     loaded by the instruction just before: the first micro-op stalls in ID on the
#     load-use hazard, so CmMvSecondReg waits with id_in_ready_i low.
#   Section 4 ILLEGAL (27 cases): the reserved/unused encodings of funct3 101 --
#     push/pop/popretz/popret with rlist 0..3 (cm_rlist_d <= 3 branches), the
#     5'b011?? group with [6:5] = 00 and 10 (default of the mv case), and other
#     [12:8] values (outer default). Each must trap with mcause 2, mepc at it and
#     mtval = the 16 instruction bits (ibex_controller.sv illegal_insn_prio, pin Off),
#     and must leave sp, ra/s0-s11, a0 and the stack unwritten (the push micro-op
#     is a sw x0 that the ID decoder must suppress).
#   Section 5 BACK-TO-BACK (4 cases, after section 4 so they also show the FSM
#     recovered from the illegal flushes): push;push, pop;pop, push;popretz,
#     mvsa01;mva01s, push;mva01s;pop with no instruction in between, so each FSM
#     leaves CmIdle on the cycle it returns to it.
#
# Register use
#   Under test: ra, sp, s0-s11, a0, a1. Free for the test: gp (failure code), tp
#   (executed-check counter), t0-t2 (scratch), t3 (fill_stack link), t4 (case number,
#   for the trace), a2-a7 (trap handler results, scratch). t5/t6 are clobbered by
#   riscv_test.h's trap_vector. sp only ever points into stack[] below (16-byte
#   aligned, 512 bytes either side of stack_mid); the words around every frame are
#   filled with addr ^ ZPAT and checked afterwards.
#
# Failure codes, reported as (code << 8) in a CORE_STATUS word, then TEST_FAIL (as in
# cheriot_illegal_rv_mode):
#   code 1      liveness: the number of checks executed (tp) differs from the number
#               assembled -- a check was skipped or a return went to the wrong place
#   code 2      unexpected trap (mcause in a2, mepc in a3, mtval in a4)
#   case*100+k  check k of case `case` (cases are numbered in source order from 1;
#               t4 holds the case number in the trace). k is the k-th CHECK_* or
#               FAIL_HERE in the case macro; FAIL_HERE means a cm.popret/popretz or
#               an illegal encoding fell through instead of returning/trapping.
#
# Proving it can fail (build-time switches, not in the testlist):
#   -DZCMP_INJECT_FAIL       first push case expects ra one too high -> code 102
#   -DZCMP_INJECT_LIVENESS   expects one more check than assembled  -> code 1

#include "riscv_test.h"

#define ZVAL(c, r) (0x50000000 + ((c) << 8) + (r))
#define ZPOI(c, r) (0xA0000000 + ((c) << 8) + (r))
#define ZPAT       0x3C5AC3A5

#define ENC_PUSH(rl, si)    (0xB802 | ((rl) << 4) | ((si) << 2))
#define ENC_POP(rl, si)     (0xBA02 | ((rl) << 4) | ((si) << 2))
#define ENC_POPRETZ(rl, si) (0xBC02 | ((rl) << 4) | ((si) << 2))
#define ENC_POPRET(rl, si)  (0xBE02 | ((rl) << 4) | ((si) << 2))
#define ENC_MVSA01(r1, r2)  (0xAC22 | ((r1) << 7) | ((r2) << 2))
#define ENC_MVA01S(r1, r2)  (0xAC62 | ((r1) << 7) | ((r2) << 2))
/* funct3 101 quadrant 2 with an arbitrary [12:8] and [7:2] */
#define ENC_Q2F5(f, lo)     (0xA002 | ((f) << 8) | ((lo) << 2))

#ifdef ZCMP_INJECT_FAIL
#define ZINJ 1
#else
#define ZINJ 0
#endif

#define KPOP     0
#define KPOPRETZ 1
#define KPOPRET  2

# Fill stack[] around stack_mid with addr ^ ZPAT
#define FILL_LO  (-256)
#define FILL_HI  64

.set ZCASE, 0
.set ZCK, 0
.set ZNCHECK, 0

# -----------------------------------------------------------------------------
# Check helpers. Every CHECK_* counts once in ZNCHECK (assembly) and tp (run time).
# -----------------------------------------------------------------------------
.macro CASE_BEGIN
  .set ZCASE, ZCASE + 1
  .set ZCK, 0
  li      t4, ZCASE
.endm

.macro CK_NEXT
  .set ZCK, ZCK + 1
  .set ZNCHECK, ZNCHECK + 1
  addi    tp, tp, 1
  li      gp, ZCASE * 100 + ZCK
.endm

# reg == immediate (reg must not be t1)
.macro CHECK_IMM reg, val
  CK_NEXT
  li      t1, \val
  beq     \reg, t1, .Lok\@
  j       fail
.Lok\@:
.endm

# reg == reg
.macro CHECK_REG reg, ref
  CK_NEXT
  beq     \reg, \ref, .Lok\@
  j       fail
.Lok\@:
.endm

# Reached only if control flow is wrong; not counted as an executed check.
.macro FAIL_HERE
  .set ZCK, ZCK + 1
  li      gp, ZCASE * 100 + ZCK
  j       fail
.endm

# Every word in [stack_mid + lo, stack_mid + hi) still holds addr ^ ZPAT.
.macro CHECK_PAT lo, hi
  CK_NEXT
  la      t0, stack_mid + (\lo)
  la      t1, stack_mid + (\hi)
  li      t2, ZPAT
.Lloop\@:
  bgeu    t0, t1, .Lok\@
  lw      a2, 0(t0)
  xor     a3, t0, t2
  bne     a2, a3, .Lbad\@
  addi    t0, t0, 4
  j       .Lloop\@
.Lbad\@:
  j       fail
.Lok\@:
.endm

# ZN = number of registers in rlist, ZADJ = stack_adj (Zc spec table, RV32)
.macro SET_FRAME rlist, spimm
  .if \rlist == 15
    .set ZN, 13
    .set ZADJ, 64
  .else
    .set ZN, \rlist - 3
    .if \rlist < 8
      .set ZADJ, 16
    .elseif \rlist < 12
      .set ZADJ, 32
    .else
      .set ZADJ, 48
    .endif
  .endif
  .set ZADJ, ZADJ + 16 * \spimm
.endm

# ra, s0-s11 = ZVAL(case, xreg); ZXV = XOR of the values
.macro LOAD_VALS
  .set ZXV, 0
  .irp xr, 1,8,9,18,19,20,21,22,23,24,25,26,27
    li      x\xr, ZVAL(ZCASE, \xr)
    .set ZXV, ZXV ^ ZVAL(ZCASE, \xr)
  .endr
.endm

# ra, s0-s11 = ZPOI(case, xreg)
.macro LOAD_POIS
  .irp xr, 1,8,9,18,19,20,21,22,23,24,25,26,27
    li      x\xr, ZPOI(ZCASE, \xr)
  .endr
.endm

# dst = ra ^ s0 ^ ... ^ s11
.macro XOR13 dst
  xor     \dst, x1, x8
  .irp xr, 9,18,19,20,21,22,23,24,25,26,27
    xor     \dst, \dst, x\xr
  .endr
.endm

# s0-s7 = ZPOI(case, xreg); ZXS = XOR of the values
.macro LOAD_S07_POI
  .set ZXS, 0
  .irp xr, 8,9,18,19,20,21,22,23
    li      x\xr, ZPOI(ZCASE, \xr)
    .set ZXS, ZXS ^ ZPOI(ZCASE, \xr)
  .endr
.endm

.macro XOR_S07 dst
  xor     \dst, x8, x9
  .irp xr, 18,19,20,21,22,23
    xor     \dst, \dst, x\xr
  .endr
.endm

# sym = x-register number of sreg specifier idx (Zc spec: 0,1 -> x8,x9; 2..7 -> x18..x23)
.macro SET_SX sym, idx
  .if \idx < 2
    .set \sym, 8 + \idx
  .else
    .set \sym, 16 + \idx
  .endif
.endm

# dst = s-register named by sreg specifier idx
.macro SREG_GET dst, idx
  .if \idx == 0
    mv      \dst, s0
  .elseif \idx == 1
    mv      \dst, s1
  .elseif \idx == 2
    mv      \dst, s2
  .elseif \idx == 3
    mv      \dst, s3
  .elseif \idx == 4
    mv      \dst, s4
  .elseif \idx == 5
    mv      \dst, s5
  .elseif \idx == 6
    mv      \dst, s6
  .else
    mv      \dst, s7
  .endif
.endm

# s-register named by sreg specifier idx = word at 0(\base)
.macro SREG_LW idx, base
  .if \idx == 0
    lw      s0, 0(\base)
  .elseif \idx == 1
    lw      s1, 0(\base)
  .elseif \idx == 2
    lw      s2, 0(\base)
  .elseif \idx == 3
    lw      s3, 0(\base)
  .elseif \idx == 4
    lw      s4, 0(\base)
  .elseif \idx == 5
    lw      s5, 0(\base)
  .elseif \idx == 6
    lw      s6, 0(\base)
  .else
    lw      s7, 0(\base)
  .endif
.endm

# A ~35-cycle DIV, so the following cm.* waits in IF with id_in_ready_i low.
.macro STALL
  li      t0, 0x7ffffff1
  li      t2, 3
  div     t0, t0, t2
.endm

# -----------------------------------------------------------------------------
# Case macros
# -----------------------------------------------------------------------------
.macro PUSH_CASE rlist, spimm, stall=0
  CASE_BEGIN
  SET_FRAME \rlist, \spimm
  jal     t3, fill_stack
  la      sp, stack_mid
  LOAD_VALS
  .if \stall
    STALL
  .endif
  .hword  ENC_PUSH(\rlist, \spimm)
  # sp decremented by stack_adj
  la      t0, stack_mid - ZADJ
  CHECK_REG sp, t0
  # register k of the list (ra = 0) is at old_sp - 4 * (N - k) = sp + ADJ - 4 * (N - k)
  .set ZK, 0
  .irp xr, 1,8,9,18,19,20,21,22,23,24,25,26,27
    .if ZK < ZN
      .set ZOFF, ZADJ - 4 * (ZN - ZK)
      lw      t0, ZOFF(sp)
      .if (ZCASE == 1) && (ZK == 0)
        CHECK_IMM t0, (ZVAL(ZCASE, \xr) + ZINJ)
      .else
        CHECK_IMM t0, ZVAL(ZCASE, \xr)
      .endif
    .endif
    .set ZK, ZK + 1
  .endr
  # push changes no register but sp
  XOR13   t0
  CHECK_IMM t0, ZXV
  # nothing written below the saved registers (padding + 16 bytes below the frame) or
  # at/above the old sp
  CHECK_PAT -ZADJ-16, -4*ZN
  CHECK_PAT 0, 16
.endm

.macro POP_CASE kind, rlist, spimm, stall=0
  CASE_BEGIN
  SET_FRAME \rlist, \spimm
  jal     t3, fill_stack
  la      sp, stack_mid - ZADJ
  la      a7, .Lret\@
  # frame: ZVAL per register; for popret/popretz the ra slot holds the return label
  .set ZK, 0
  .irp xr, 1,8,9,18,19,20,21,22,23,24,25,26,27
    .if ZK < ZN
      .set ZOFF, ZADJ - 4 * (ZN - ZK)
      .if (ZK == 0) && (\kind != KPOP)
        sw      a7, ZOFF(sp)
      .else
        li      t0, ZVAL(ZCASE, \xr)
        sw      t0, ZOFF(sp)
      .endif
    .endif
    .set ZK, ZK + 1
  .endr
  LOAD_POIS
  li      a0, ZVAL(ZCASE, 10)
  li      a1, ZVAL(ZCASE, 11)
  .if \stall
    STALL
  .endif
  .if \kind == KPOP
    .hword  ENC_POP(\rlist, \spimm)
  .elseif \kind == KPOPRETZ
    .hword  ENC_POPRETZ(\rlist, \spimm)
    FAIL_HERE
  .else
    .hword  ENC_POPRET(\rlist, \spimm)
    FAIL_HERE
  .endif
.Lret\@:
  # sp incremented by stack_adj
  la      t0, stack_mid
  CHECK_REG sp, t0
  # listed registers loaded, the rest untouched
  .set ZK, 0
  .irp xr, 1,8,9,18,19,20,21,22,23,24,25,26,27
    .if ZK < ZN
      .if (ZK == 0) && (\kind != KPOP)
        CHECK_REG x\xr, a7
      .else
        CHECK_IMM x\xr, ZVAL(ZCASE, \xr)
      .endif
    .else
      CHECK_IMM x\xr, ZPOI(ZCASE, \xr)
    .endif
    .set ZK, ZK + 1
  .endr
  .if \kind == KPOPRETZ
    CHECK_REG a0, zero
  .else
    CHECK_IMM a0, ZVAL(ZCASE, 10)
  .endif
  CHECK_IMM a1, ZVAL(ZCASE, 11)
  # pop stores nothing: frame padding and the words around the frame unchanged
  CHECK_PAT -ZADJ-16, -ZADJ
  CHECK_PAT -ZADJ, -4*ZN
  CHECK_PAT 0, 16
.endm

# ldhz = 1: the source of the first move (a0) is loaded by the instruction just before, so the
# first micro-op stalls in ID on the load-use hazard while the decoder already presents the
# second (CmMvSecondReg with id_in_ready_i low).
.macro MVSA01_CASE r1, r2, ldhz=0
  CASE_BEGIN
  SET_SX  ZX1, \r1
  SET_SX  ZX2, \r2
  LOAD_S07_POI
  li      a0, ZVAL(ZCASE, 10)
  li      a1, ZVAL(ZCASE, 11)
  .if \ldhz
    la      t0, ldhz_word
    sw      a0, 0(t0)
    li      a0, 0
    lw      a0, 0(t0)
  .endif
  .hword  ENC_MVSA01(\r1, \r2)
  SREG_GET t0, \r1
  CHECK_IMM t0, ZVAL(ZCASE, 10)
  SREG_GET t0, \r2
  CHECK_IMM t0, ZVAL(ZCASE, 11)
  CHECK_IMM a0, ZVAL(ZCASE, 10)
  CHECK_IMM a1, ZVAL(ZCASE, 11)
  # the other six s-registers untouched
  XOR_S07 t0
  CHECK_IMM t0, (ZXS ^ ZPOI(ZCASE, ZX1) ^ ZPOI(ZCASE, ZX2) ^ ZVAL(ZCASE, 10) ^ ZVAL(ZCASE, 11))
.endm

# ldhz = 1: as MVSA01_CASE; the first move's source is the s-register named by r1.
.macro MVA01S_CASE r1, r2, ldhz=0
  CASE_BEGIN
  SET_SX  ZX1, \r1
  SET_SX  ZX2, \r2
  LOAD_S07_POI
  li      a0, ZVAL(ZCASE, 10)
  li      a1, ZVAL(ZCASE, 11)
  .if \ldhz
    la      t0, ldhz_word
    li      t1, ZPOI(ZCASE, ZX1)
    sw      t1, 0(t0)
    SREG_LW \r1, t0
  .endif
  .hword  ENC_MVA01S(\r1, \r2)
  CHECK_IMM a0, ZPOI(ZCASE, ZX1)
  CHECK_IMM a1, ZPOI(ZCASE, ZX2)
  # s0-s7 untouched
  XOR_S07 t0
  CHECK_IMM t0, ZXS
.endm

# An encoding that must raise an illegal instruction exception and have no effect.
.macro ILLEGAL_CASE enc
  CASE_BEGIN
  jal     t3, fill_stack
  la      sp, stack_mid
  LOAD_VALS
  li      a0, ZVAL(ZCASE, 10)
  li      a2, -1
  li      a3, -1
  li      a4, -1
  la      a5, .Lres\@                      # arms mtvec_handler
.Lins\@:
  .hword  \enc
  FAIL_HERE
.Lres\@:
  CHECK_IMM a2, CAUSE_ILLEGAL_INSTRUCTION
  la      t0, .Lins\@
  CHECK_REG a3, t0
  CHECK_IMM a4, \enc
  la      t0, stack_mid
  CHECK_REG sp, t0
  XOR13   t0
  CHECK_IMM t0, ZXV
  CHECK_IMM a0, ZVAL(ZCASE, 10)
  CHECK_PAT -128, 16
.endm

# norelax before RVTEST_CODE_BEGIN (see cheriot_illegal_rv_mode)
    .option norelax
RVTEST_RV32M
RVTEST_CODE_BEGIN
    li      tp, 0
    li      gp, 0
    li      a5, 0                         # no trap expected
    j       zcmp_start

# Called from riscv_test.h's trap_vector (t5/t6 already used). a5 = resume address of
# an expected trap, 0 if none is expected.
    .balign 4
    .globl mtvec_handler
mtvec_handler:
    csrr    a2, mcause
    csrr    a3, mepc
    csrr    a4, mtval
    beqz    a5, 1f
    csrw    mepc, a5
    li      a5, 0
    mret
1:  li      gp, 2
    j       fail

# Fill [stack_mid + FILL_LO, stack_mid + FILL_HI) with addr ^ ZPAT. Link t3.
fill_stack:
    la      t0, stack_mid + FILL_LO
    la      t1, stack_mid + FILL_HI
    li      t2, ZPAT
1:  xor     a2, t0, t2
    sw      a2, 0(t0)
    addi    t0, t0, 4
    bltu    t0, t1, 1b
    jr      t3

# Failure report: (gp << 8) | CORE_STATUS, then TEST_FAIL.
fail:
    fence
    li      t0, SIGNATURE_ADDR
    slli    t1, gp, 8
    sw      t1, 0(t0)
    li      t1, (TEST_FAIL << 8) | TEST_RESULT
    sw      t1, 0(t0)
1:  j       1b

zcmp_start:
# ---- Section 1: cm.push ------------------------------------------------------
# every rlist, spimm cycling through 0..3
    PUSH_CASE  4, 0
    PUSH_CASE  5, 1
    PUSH_CASE  6, 2
    PUSH_CASE  7, 3
    PUSH_CASE  8, 0
    PUSH_CASE  9, 1
    PUSH_CASE 10, 2
    PUSH_CASE 11, 3
    PUSH_CASE 12, 0
    PUSH_CASE 13, 1
    PUSH_CASE 14, 2
    PUSH_CASE 15, 3
# the smallest and largest list with every spimm (stack_adj 16..112)
    PUSH_CASE  4, 1
    PUSH_CASE  4, 2
    PUSH_CASE  4, 3
    PUSH_CASE 15, 0
    PUSH_CASE 15, 1
    PUSH_CASE 15, 2
# behind a DIV: CmIdle with valid_i && !id_in_ready_i
    PUSH_CASE  4, 0, 1
    PUSH_CASE  9, 2, 1
    PUSH_CASE 15, 3, 1

# ---- Section 2: cm.pop / cm.popretz / cm.popret -------------------------------
    POP_CASE KPOP,  4, 1
    POP_CASE KPOP,  5, 2
    POP_CASE KPOP,  6, 3
    POP_CASE KPOP,  7, 0
    POP_CASE KPOP,  8, 1
    POP_CASE KPOP,  9, 2
    POP_CASE KPOP, 10, 3
    POP_CASE KPOP, 11, 0
    POP_CASE KPOP, 12, 1
    POP_CASE KPOP, 13, 2
    POP_CASE KPOP, 14, 3
    POP_CASE KPOP, 15, 0
    POP_CASE KPOP,  4, 0
    POP_CASE KPOP, 15, 3

    POP_CASE KPOPRETZ,  4, 2
    POP_CASE KPOPRETZ,  5, 3
    POP_CASE KPOPRETZ,  6, 0
    POP_CASE KPOPRETZ,  7, 1
    POP_CASE KPOPRETZ,  8, 2
    POP_CASE KPOPRETZ,  9, 3
    POP_CASE KPOPRETZ, 10, 0
    POP_CASE KPOPRETZ, 11, 1
    POP_CASE KPOPRETZ, 12, 2
    POP_CASE KPOPRETZ, 13, 3
    POP_CASE KPOPRETZ, 14, 0
    POP_CASE KPOPRETZ, 15, 1

    POP_CASE KPOPRET,  4, 3
    POP_CASE KPOPRET,  5, 0
    POP_CASE KPOPRET,  6, 1
    POP_CASE KPOPRET,  7, 2
    POP_CASE KPOPRET,  8, 3
    POP_CASE KPOPRET,  9, 0
    POP_CASE KPOPRET, 10, 1
    POP_CASE KPOPRET, 11, 2
    POP_CASE KPOPRET, 12, 3
    POP_CASE KPOPRET, 13, 0
    POP_CASE KPOPRET, 14, 1
    POP_CASE KPOPRET, 15, 2

# behind a DIV
    POP_CASE KPOP,     15, 3, 1
    POP_CASE KPOPRETZ,  4, 0, 1
    POP_CASE KPOPRET,   9, 1, 1
    POP_CASE KPOPRETZ, 10, 2, 1

# ---- Section 3: cm.mvsa01 (r1s != r2s) and cm.mva01s (all pairs) --------------
.irp r1, 0,1,2,3,4,5,6,7
  .irp r2, 0,1,2,3,4,5,6,7
    .if \r1 != \r2
      MVSA01_CASE \r1, \r2
    .endif
  .endr
.endr

.irp r1, 0,1,2,3,4,5,6,7
  .irp r2, 0,1,2,3,4,5,6,7
    MVA01S_CASE \r1, \r2
  .endr
.endr

# second move presented while the first stalls in ID (load-use hazard on its source)
    MVSA01_CASE 0, 1, 1
    MVSA01_CASE 2, 7, 1
    MVSA01_CASE 5, 3, 1
    MVA01S_CASE 0, 1, 1
    MVA01S_CASE 6, 6, 1
    MVA01S_CASE 7, 2, 1

# ---- Section 4: reserved encodings of quadrant 2 funct3 101 -------------------
# rlist 0..3 is reserved for every push/pop form (cm_rlist_d <= 3)
    ILLEGAL_CASE ENC_PUSH(0, 0)
    ILLEGAL_CASE ENC_PUSH(1, 1)
    ILLEGAL_CASE ENC_PUSH(2, 2)
    ILLEGAL_CASE ENC_PUSH(3, 3)
    ILLEGAL_CASE ENC_POP(0, 1)
    ILLEGAL_CASE ENC_POP(1, 2)
    ILLEGAL_CASE ENC_POP(2, 3)
    ILLEGAL_CASE ENC_POP(3, 0)
    ILLEGAL_CASE ENC_POPRETZ(0, 2)
    ILLEGAL_CASE ENC_POPRETZ(1, 3)
    ILLEGAL_CASE ENC_POPRETZ(2, 0)
    ILLEGAL_CASE ENC_POPRETZ(3, 1)
    ILLEGAL_CASE ENC_POPRET(0, 3)
    ILLEGAL_CASE ENC_POPRET(1, 0)
    ILLEGAL_CASE ENC_POPRET(2, 1)
    ILLEGAL_CASE ENC_POPRET(3, 2)
# [12:10] = 011 with [6:5] = 00 / 10: neither cm.mvsa01 (01) nor cm.mva01s (11)
    ILLEGAL_CASE (0xAC02 | (3 << 7) | (5 << 2))
    ILLEGAL_CASE (0xAC42 | (6 << 7) | (1 << 2))
# other [12:8] values (outer default; c.fsdsp in RV32DC, no D here)
    ILLEGAL_CASE ENC_Q2F5(0x00, 0x15)
    ILLEGAL_CASE ENC_Q2F5(0x08, 0x2a)
    ILLEGAL_CASE ENC_Q2F5(0x10, 0x3f)
    ILLEGAL_CASE ENC_Q2F5(0x16, 0x01)
    ILLEGAL_CASE ENC_Q2F5(0x19, 0x10)
    ILLEGAL_CASE ENC_Q2F5(0x1b, 0x10)
    ILLEGAL_CASE ENC_Q2F5(0x1d, 0x10)
    ILLEGAL_CASE ENC_Q2F5(0x1f, 0x10)
    ILLEGAL_CASE ENC_Q2F5(0x07, 0x00)

# ---- Section 5: back-to-back Zcmp instructions ---------------------------------
# B1: push {ra,s0-s11},-112 ; push {ra,s0-s1},-16 ; ... ; pop 16 ; pop 112
    CASE_BEGIN
    jal     t3, fill_stack
    la      sp, stack_mid
    LOAD_VALS
    .hword  ENC_PUSH(15, 3)
    .hword  ENC_PUSH(6, 0)
    la      t0, stack_mid - 128
    CHECK_REG sp, t0
    lw      t0, 12(sp)                    # inner frame: s1 at old sp - 4
    CHECK_IMM t0, ZVAL(ZCASE, 9)
    lw      t0, 8(sp)
    CHECK_IMM t0, ZVAL(ZCASE, 8)
    lw      t0, 4(sp)
    CHECK_IMM t0, ZVAL(ZCASE, 1)
    lw      t0, 124(sp)                   # outer frame: s11 at stack_mid - 4
    CHECK_IMM t0, ZVAL(ZCASE, 27)
    lw      t0, 76(sp)                    # outer frame: ra at stack_mid - 52
    CHECK_IMM t0, ZVAL(ZCASE, 1)
    LOAD_POIS
    .hword  ENC_POP(6, 0)
    .hword  ENC_POP(15, 3)
    la      t0, stack_mid
    CHECK_REG sp, t0
    .irp xr, 1,8,9,18,19,20,21,22,23,24,25,26,27
      CHECK_IMM x\xr, ZVAL(ZCASE, \xr)
    .endr

# B2: push {ra,s0},-32 ; popretz {ra,s0},32 -- returns to the ra just pushed
    CASE_BEGIN
    jal     t3, fill_stack
    la      sp, stack_mid
    LOAD_VALS
    la      ra, .Lb2_ret
    li      a0, ZVAL(ZCASE, 10)
    .hword  ENC_PUSH(5, 1)
    .hword  ENC_POPRETZ(5, 1)
    FAIL_HERE
.Lb2_ret:
    la      t0, .Lb2_ret
    CHECK_REG ra, t0
    la      t0, stack_mid
    CHECK_REG sp, t0
    CHECK_IMM s0, ZVAL(ZCASE, 8)
    CHECK_REG a0, zero

# B3: mvsa01 s3, s6 ; mva01s s6, s3 -- swaps a0 and a1 through s3/s6
    CASE_BEGIN
    LOAD_S07_POI
    li      a0, ZVAL(ZCASE, 10)
    li      a1, ZVAL(ZCASE, 11)
    .hword  ENC_MVSA01(3, 6)
    .hword  ENC_MVA01S(6, 3)
    CHECK_IMM a0, ZVAL(ZCASE, 11)
    CHECK_IMM a1, ZVAL(ZCASE, 10)
    CHECK_IMM s3, ZVAL(ZCASE, 10)
    CHECK_IMM s6, ZVAL(ZCASE, 11)

# B4: push {ra,s0-s2},-48 ; mva01s s0, s2 ; pop {ra,s0-s2},48 -- three FSMs in a row
    CASE_BEGIN
    jal     t3, fill_stack
    la      sp, stack_mid
    LOAD_VALS
    li      a0, ZVAL(ZCASE, 10)
    li      a1, ZVAL(ZCASE, 11)
    .hword  ENC_PUSH(7, 2)
    .hword  ENC_MVA01S(0, 2)
    .hword  ENC_POP(7, 2)
    CHECK_IMM a0, ZVAL(ZCASE, 8)
    CHECK_IMM a1, ZVAL(ZCASE, 18)
    la      t0, stack_mid
    CHECK_REG sp, t0
    XOR13   t0
    CHECK_IMM t0, ZXV

# ---- Liveness: every check above executed exactly once --------------------------
# Textually after every check, so ZNCHECK is final here (gas .set is read in place).
#ifdef ZCMP_INJECT_LIVENESS
    .set ZNCHECK, ZNCHECK + 1
#endif
    li      t0, ZNCHECK
    li      gp, 1
    bne     tp, t0, fail
    RVTEST_PASS

RVTEST_CODE_END

    .data
RVTEST_DATA_BEGIN
    .balign 16
stack_lo:
    .space  512
stack_mid:
    .space  512
stack_hi:
ldhz_word:
    .word   0
RVTEST_DATA_END
