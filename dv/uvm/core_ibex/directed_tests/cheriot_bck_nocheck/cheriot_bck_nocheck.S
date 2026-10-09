# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_bck_nocheck -- with cheriot_enable_i Off, loads and stores are
#                              not capability-checked (REQ_BCK_02, Off half)
# =============================================================================
# The bench is built with the CHERIoT-capable core (BaseIsa RV32IorCHERIoT, the
# same build as every other directed test); this test does not pass
# +enable_cheriot_seq=1 or +cheriot_enable_on_write, so core_ibex_dut_probe_if
# leaves cheriot_enable_i at IbexMuBiOff for the whole run. Spike is the cosim
# reference (plain RV32, no CHERIoT), which is what "unchecked" means.
#
# Why these accesses would fault in CHERIoT mode: with the pin Off no instruction
# can give a register capability metadata -- the CHERI opcodes (0x5B, 0x7B) are
# illegal, auipc is plain AUIPC and funct3=3 loads (CLC) are illegal; checks 10-15
# confirm the last two. Every base register below therefore carries the null /
# integer metadata (tag 0, no permissions, bounds [0, 0)). In CHERIoT mode
# CHERIoT-Sail ext_data_get_addr rejects such a base first on its tag:
# CapEx_TagViolation (0x02) against the base register -- the On half of
# REQ_BCK_02, which cheriot_revoke_basic already exercises (LW through an
# untagged register, mtval 0x1A2). In the RTL the whole check is
# rv32_lsu_err = (cheriot_enable_i == IbexMuBiOn) & ... (ibex_cheriot_ex.sv).
#
# What is checked (0 = pass; otherwise the failing code is reported in the
# CORE_STATUS word as (code << 8), followed by TEST_FAIL)
# ---------------------------------------------------------------------------
#   1   sw / lw word round trip through an integer (la-derived) base
#   2   sh / lh round trip, lh sign-extends 0x8001 to 0xFFFF8001
#   3   lhu of the same halfword gives 0x00008001
#   4   sb / lb round trip, lb sign-extends 0x80 to 0xFFFFFF80
#   5   lbu of the same byte gives 0x80
#   6   a pointer stored with sw and reloaded with lw works as a base (in
#       CHERIoT mode a loaded integer is untagged)
#   7   a base built by lui alone, with the low part in the offset
#   8   a base 2 KiB past the target with a negative offset (address
#       arithmetic only; there is no base-register bounds to be outside of)
#   9   the store in check 6 went to the pointed-to word and nowhere else
#   10/11/12  a CHERI instruction (cgettag) traps: [no trap] [mcause != 2]
#             [mepc != the instruction] -- evidence that the pin really is Off
#   13/14/15  a funct3=3 load (CLC in CHERIoT mode, ld in RV64) traps the same way
#   16  any other trap (the handler reports it)
#   17  mip = 0 at the end (no interrupt was expected)
#
# The pin is Off, so the riscv-tests environment (riscv_test.h) is used as is,
# including its x16-x31 zeroing; the test body itself uses only x1-x15.

#include "riscv_test.h"

#define FAIL(code) li gp, code; j fail

# norelax before RVTEST_CODE_BEGIN, not after: otherwise the linker relaxes the header's
# .align and every later .balign 4 label lands at 2 mod 4.
    .option norelax
RVTEST_RV32M
RVTEST_CODE_BEGIN
    li      s1, 0                   # 0: no trap expected; 1: expected; 2: taken

    # ── 1: word ──────────────────────────────────────────────────────────────
    la      t0, buf
    li      t1, 0x12345678
    sw      t1, 0(t0)
    lw      t2, 0(t0)
    beq     t1, t2, 1f
    FAIL(1)
1:
    # ── 2-3: halfword ────────────────────────────────────────────────────────
    li      t1, 0x8001
    sh      t1, 4(t0)
    lh      t2, 4(t0)
    li      t1, 0xFFFF8001
    beq     t1, t2, 1f
    FAIL(2)
1:  lhu     t2, 4(t0)
    li      t1, 0x8001
    beq     t1, t2, 1f
    FAIL(3)
1:
    # ── 4-5: byte ────────────────────────────────────────────────────────────
    li      t1, 0x80
    sb      t1, 6(t0)
    lb      t2, 6(t0)
    li      t1, 0xFFFFFF80
    beq     t1, t2, 1f
    FAIL(4)
1:  lbu     t2, 6(t0)
    li      t1, 0x80
    beq     t1, t2, 1f
    FAIL(5)
1:
    # ── 6, 9: a loaded pointer as the base ───────────────────────────────────
    la      t1, target
    sw      t1, 8(t0)               # buf+8 <- &target
    lw      s0, 8(t0)               # s0 = &target, loaded from memory
    li      t2, 0x0C0FFEE0
    sw      t2, 0(s0)
    lw      t1, 0(s0)
    beq     t1, t2, 1f
    FAIL(6)
1:  la      t1, target
    lw      t1, 0(t1)
    beq     t1, t2, 1f
    FAIL(9)
1:  lw      t1, 8(t0)               # the pointer itself was not overwritten
    la      t2, target
    beq     t1, t2, 1f
    FAIL(9)
1:
    # ── 7: lui-only base ─────────────────────────────────────────────────────
    lui     s0, %hi(target)
    li      t2, 0x600DF00D
    sw      t2, %lo(target)(s0)
    lw      t1, %lo(target)(s0)
    beq     t1, t2, 1f
    FAIL(7)
1:
    # ── 8: base past the target, negative offset ─────────────────────────────
    la      s0, target
    addi    s0, s0, 2044
    addi    s0, s0, 4               # s0 = target + 2048
    li      t2, 0x7E57AB1E
    sw      t2, -2048(s0)
    la      t1, target
    lw      t1, 0(t1)
    beq     t1, t2, 1f
    FAIL(8)
1:
    # ── 10-12: cgettag is illegal with the pin Off ───────────────────────────
    li      s1, 1
.Lcheri_insn:
    .word   0xFE45035B              # cgettag t1, ca0
    li      t1, 2
    beq     s1, t1, 1f
    FAIL(10)
1:
    # ── 13-15: a funct3=3 load is illegal with the pin Off ───────────────────
    li      s1, 3
.Lclc_insn:
    .word   0x00053583              # clc ca1, 0(ca0)
    li      t1, 4
    beq     s1, t1, 1f
    FAIL(13)
1:
    li      s1, 0
    # ── 17: no interrupt ─────────────────────────────────────────────────────
    csrr    t1, mip
    beqz    t1, 1f
    FAIL(17)
1:
    RVTEST_PASS

# Failure report: (code << 8) | CORE_STATUS, then TEST_FAIL. gp holds the code.
fail:
    fence
    li      t0, SIGNATURE_ADDR
    slli    t1, gp, 8
    sw      t1, 0(t0)
    li      t1, (TEST_FAIL << 8) | TEST_RESULT
    sw      t1, 0(t0)
1:  j       1b

# Called from riscv_test.h's trap_vector (it has already used t5/t6).
# s1 = 1: the cgettag at .Lcheri_insn is expected; s1 = 3: the load at .Lclc_insn.
# Either must be an illegal instruction at exactly that pc; then skip it (4 bytes).
    .balign 4
    .globl mtvec_handler
mtvec_handler:
    li      t1, 1
    beq     s1, t1, 2f
    li      t1, 3
    beq     s1, t1, 3f
    FAIL(16)
2:  csrr    t1, mcause
    li      t2, 2
    beq     t1, t2, 1f
    FAIL(11)
1:  csrr    t1, mepc
    la      t2, .Lcheri_insn
    beq     t1, t2, 1f
    FAIL(12)
1:  li      s1, 2
    j       4f
3:  csrr    t1, mcause
    li      t2, 2
    beq     t1, t2, 1f
    FAIL(14)
1:  csrr    t1, mepc
    la      t2, .Lclc_insn
    beq     t1, t2, 1f
    FAIL(15)
1:  li      s1, 4
4:  csrr    t1, mepc
    addi    t1, t1, 4
    csrw    mepc, t1
    mret

RVTEST_CODE_END

    .data
RVTEST_DATA_BEGIN
    .balign 8
buf:    .space 16                   # +0 word, +4 halfword, +6 byte, +8 pointer
target: .word 0
RVTEST_DATA_END
