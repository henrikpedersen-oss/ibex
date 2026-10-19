# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: minstret_exact -- minstret counts exactly the instructions retired
# =============================================================================
# RISC-V mode (cheriot_enable_i Off), cosim off: the program checks every value itself, so the
# result does not depend on a reference model. Written for the TestRIG riscv mismatches of
# 2026-10-19: once minstret reads were compared, the core and RISC-V Sail disagreed by 1 to 6, in
# both directions, with writes to minstret and mcountinhibit nearby, and TestRIG's random CSR
# traffic could not tell which side miscounts.
#
# Method: each check brackets a short sequence between `csrr s0, minstret` and
# `csrr s1, minstret` and compares s1 - s0 with the number of instructions that retire in between,
# plus 1 for the first read itself. The whole suite runs four times: the memory agents delay
# responses at random, so each pass meets the counter in a different pipeline state.
#
# Expected behaviour (not taken from the RTL):
#   - RISC-V Unprivileged ISA, Zicsr: "if a CSR access instruction reads a CSR, it reads the
#     value prior to the execution of the instruction. If a CSR access instruction writes such a
#     CSR, the write is done instead of the increment." So a read sees every instruction that
#     retired before it, and `csrw minstret, X` followed by `csrr minstret` reads exactly X.
#   - RISC-V Privileged ISA, minstret / mcountinhibit: minstret counts instructions retired; an
#     instruction that takes an exception does not retire; mret retires. While mcountinhibit.IR is
#     set minstret does not count.
#   - Zcmp (cm.push / cm.pop) and compressed instructions are single instructions: one each.
#   - Left open by the RISC-V specifications, fixed by the Ibex manual
#     (doc/03_reference/performance_counters.rst): a CSR instruction that writes mcountinhibit is
#     counted according to the value it writes, so one that sets IR is not counted (section S: 1)
#     and one that clears it is (section C: 6). Both must also hold in every pipeline state (after
#     a load, after a divide) and in every pass: a count that depends on timing is a defect.
#
# Failure: TEST_FAIL with TESTNUM (gp) = the check below; s9 holds the value measured (the
# difference, or the value read for sections W), so the trace shows what the core counted.
#   10-16  plain, branches and jumps        17-20  loads and stores
#   21-23  multiply and divide              24-27  fences and CSR writes
#   28-30  compressed, cm.push, cm.pop      31-34  traps: ecall, illegal CSR (delta, mcause)
#   40-43  W: minstret written, then read (exact value)
#   50-52  S: setting IR (1; the same after a load / a divide, and in every pass)
#   55-57  C: clearing IR (6; the same rules)
#   0x100 | code  a trap where none was expected
#
# Proving it can fail (build-time switch, not in the testlist):
#   -DMINSTRET_INJECT_FAIL  adds a nop to check 12's sequence without counting it -> TESTNUM 12

#include "riscv_test.h"
#include "test_macros.h"

#define WVAL 1000                     /* the value written to minstret in sections W */

# s1 - s0 must be \exp.
.macro CHK id, exp
  sub   s9, s1, s0
  li    TESTNUM, \id
  li    t6, \exp
  bne   s9, t6, fail
.endm

# s1 - s0 must lie in [\lo, \hi].
.macro CHK_RANGE id, lo, hi
  sub   s9, s1, s0
  li    TESTNUM, \id
  li    t6, \lo
  blt   s9, t6, fail
  li    t6, \hi
  bgt   s9, t6, fail
.endm

# s9 must equal \ref.
.macro CHK_SAME id, ref
  li    TESTNUM, \id
  bne   s9, \ref, fail
.endm

# One measurement: s0 := minstret, the sequence, s1 := minstret (written out at each use).

  .option norvc
  .option norelax

RVTEST_RV32M
RVTEST_CODE_BEGIN

  csrr  s11, mtvec                    # restored before the end
  la    t0, cnt_handler
  csrw  mtvec, t0
  csrw  mcountinhibit, zero
  la    a5, buf
  li    s2, 0                         # pass
  li    s3, -1                        # S reference (set in the first pass)
  li    s4, -1                        # C reference

pass_loop:
  # ---- Plain, branches and jumps ----
  csrr  s0, minstret
  csrr  s1, minstret
  CHK   10, 1

  csrr  s0, minstret
  nop
  csrr  s1, minstret
  CHK   11, 2

  csrr  s0, minstret
  .rept 8
  nop
  .endr
#ifdef MINSTRET_INJECT_FAIL
  nop
#endif
  csrr  s1, minstret
  CHK   12, 9

  csrr  s0, minstret
  beq   zero, zero, 1f                # taken: the nop does not execute
  nop
1:
  csrr  s1, minstret
  CHK   13, 2

  csrr  s0, minstret
  bne   zero, zero, 1f                # not taken
  nop
1:
  csrr  s1, minstret
  CHK   14, 3

  csrr  s0, minstret
  jal   zero, 1f
  nop
1:
  csrr  s1, minstret
  CHK   15, 2

  la    t0, 1f
  csrr  s0, minstret
  jalr  zero, 0(t0)
  nop
1:
  csrr  s1, minstret
  CHK   16, 2

  # ---- Loads and stores (the read right behind the access: the access must be counted) ----
  csrr  s0, minstret
  lw    t0, 0(a5)
  csrr  s1, minstret
  CHK   17, 2

  csrr  s0, minstret
  lw    t0, 0(a5)
  add   t0, t0, t0                    # load-use stall
  csrr  s1, minstret
  CHK   18, 3

  csrr  s0, minstret
  sw    s2, 4(a5)
  lw    t0, 4(a5)
  csrr  s1, minstret
  CHK   19, 3

  csrr  s0, minstret
  lw    t0, 0(a5)
  lw    t1, 4(a5)
  lw    t2, 8(a5)
  csrr  s1, minstret
  CHK   20, 4

  # ---- Multiply and divide ----
  li    t1, 1000
  li    t2, 7
  csrr  s0, minstret
  mul   t0, t1, t2
  csrr  s1, minstret
  CHK   21, 2

  csrr  s0, minstret
  div   t0, t1, t2                    # multi-cycle
  csrr  s1, minstret
  CHK   22, 2

  csrr  s0, minstret
  div   t0, t1, t2
  add   t0, t0, t0
  csrr  s1, minstret
  CHK   23, 3

  # ---- Fences and CSR writes (most CSR writes flush the pipeline) ----
  csrr  s0, minstret
  fence
  csrr  s1, minstret
  CHK   24, 2

  csrr  s0, minstret
  fence.i
  csrr  s1, minstret
  CHK   25, 2

  csrr  s0, minstret
  csrw  mscratch, t0
  csrr  s1, minstret
  CHK   26, 2

  csrr  s0, minstret
  csrw  mie, zero
  csrr  s1, minstret
  CHK   27, 2

  # ---- Compressed and Zcmp (encodings as data: the toolchain's -march has no Zcmp) ----
  csrr  s0, minstret
  .hword 0x0001                       # c.nop
  .hword 0x0001
  .hword 0x0001
  csrr  s1, minstret
  CHK   28, 4

  mv    s8, sp
  la    sp, stack_top
  csrr  s0, minstret
  .hword 0xB842                       # cm.push {ra}, -16
  csrr  s1, minstret
  CHK   29, 2

  csrr  s0, minstret
  .hword 0xBA42                       # cm.pop {ra}, 16
  csrr  s1, minstret
  CHK   30, 2
  mv    sp, s8

  # ---- Traps: the trapping instruction does not retire; cnt_handler's 5 instructions do ----
  li    s10, -1
  csrr  s0, minstret
  ecall
  csrr  s1, minstret
  CHK   31, 6
  li    TESTNUM, 32
  li    t6, 11                        # environment call from M-mode
  bne   s10, t6, fail

  li    s10, -1
  csrr  s0, minstret
  csrr  t0, 0x7ff                     # no such CSR: illegal instruction
  csrr  s1, minstret
  CHK   33, 6
  li    TESTNUM, 34
  li    t6, 2
  bne   s10, t6, fail

  # ---- W: a write replaces the writing instruction's increment ----
  li    t2, WVAL
  csrw  minstret, t2
  csrr  s9, minstret
  li    TESTNUM, 40
  li    t6, WVAL
  bne   s9, t6, fail

  csrw  minstret, t2
  nop
  csrr  s9, minstret
  li    TESTNUM, 41
  li    t6, WVAL + 1
  bne   s9, t6, fail

  li    t1, 1000
  li    t0, 7
  div   t0, t1, t0                    # still in flight when the write is in ID/EX
  csrw  minstret, t2
  csrr  s9, minstret
  li    TESTNUM, 42
  li    t6, WVAL
  bne   s9, t6, fail

  lw    t0, 0(a5)                     # waiting for its response when the write is in ID/EX
  csrw  minstret, t2
  csrr  s9, minstret
  li    TESTNUM, 43
  li    t6, WVAL
  bne   s9, t6, fail

  # ---- S: setting mcountinhibit.IR ----
  csrr  s0, minstret
  csrsi mcountinhibit, 4
  .rept 5
  nop
  .endr
  csrr  s1, minstret
  csrci mcountinhibit, 4
  CHK   50, 1
  bgez  s3, 1f
  mv    s3, s9                        # first pass: the reference
1:
  CHK_SAME 50, s3

  csrr  s0, minstret
  lw    t0, 0(a5)
  add   t0, t0, t0                    # two counted instructions, then the write
  csrsi mcountinhibit, 4
  .rept 5
  nop
  .endr
  csrr  s1, minstret
  csrci mcountinhibit, 4
  sub   s9, s1, s0
  addi  s9, s9, -2
  CHK_SAME 51, s3

  li    t1, 1000
  li    t0, 7
  csrr  s0, minstret
  div   t0, t1, t0                    # one counted instruction, still in flight at the write
  csrsi mcountinhibit, 4
  .rept 5
  nop
  .endr
  csrr  s1, minstret
  csrci mcountinhibit, 4
  sub   s9, s1, s0
  addi  s9, s9, -1
  CHK_SAME 52, s3

  # ---- C: clearing mcountinhibit.IR ----
  csrsi mcountinhibit, 4
  csrr  s0, minstret                  # not counted: IR is set
  csrci mcountinhibit, 4
  .rept 5
  nop
  .endr
  csrr  s1, minstret
  CHK   55, 6
  bgez  s4, 1f
  mv    s4, s9
1:
  CHK_SAME 55, s4

  csrsi mcountinhibit, 4
  csrr  s0, minstret
  lw    t0, 0(a5)                     # not counted (IR set), possibly still in WB at the clear
  add   t0, t0, t0
  csrci mcountinhibit, 4
  .rept 5
  nop
  .endr
  csrr  s1, minstret
  sub   s9, s1, s0
  CHK_SAME 56, s4

  li    t1, 1000
  li    t0, 7
  csrsi mcountinhibit, 4
  csrr  s0, minstret
  div   t0, t1, t0                    # not counted (IR set), possibly still in flight at the clear
  csrci mcountinhibit, 4
  .rept 5
  nop
  .endr
  csrr  s1, minstret
  sub   s9, s1, s0
  CHK_SAME 57, s4

  # ---- Next pass ----
  addi  s2, s2, 1
  li    t6, 4
  blt   s2, t6, pass_loop

  csrw  mtvec, s11
  TEST_PASSFAIL

# Expected traps (sections 31-34): record mcause, skip the 4-byte instruction. Exactly 5
# instructions, all retired: the trap checks count them. Ibex's mtvec is vectored and 256-byte
# aligned; exceptions enter at its base.
  .balign 256
cnt_handler:
  csrr  s10, mcause
  csrr  t3, mepc
  addi  t3, t3, 4
  csrw  mepc, t3
  mret

# A trap through the environment's vector (before mtvec is replaced, or after it is restored).
mtvec_handler:
  ori   TESTNUM, TESTNUM, 0x100
  j     fail

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
  .balign 16
buf:
  .word 0x11111111, 0x22222222, 0x33333333, 0x44444444
  .balign 16
stack:
  .fill 16, 4, 0
stack_top:
RVTEST_DATA_END
