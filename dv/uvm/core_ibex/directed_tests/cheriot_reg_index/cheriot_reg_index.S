# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_reg_index -- register indices in mtval and in R-type operands
# =============================================================================
# Part A, REQ_EXC_01/03/05: a CHERI fault against a GPR reports that register's
# index. CHERIoT-Sail handle_cheri_reg_exception: mtval = (0 @ cs1) << 5 |
# capcause, mcause 28; the faulting instruction does not retire (MEPCC.address
# = the instruction, rd not written). In capability mode a plain lw is a load
# through cs1 = rs1 (cheri_mem / ext_data_get_addr), and jalr is CJALR. A
# register written with an integer instruction holds an untagged capability,
# and c0 is the null capability, so every probe below is a Tag Violation
# (capcause 0x02, checked before seal, permission and bounds):
#   c0  lw a1, 0(zero) and jalr zero, 0(zero)      mtval 0x002
#   cN  lw a1, 0(cN), N = 2..9 (csp, cgp, ctp, ct0-ct2, cs0, cs1)   mtval N<<5 | 2
# The other indices (cra, ca0-ca5) are what the existing fault tests use.
# cN holds the address of `word` (readable), so a core that ignored the tag
# would load instead of trapping. cs1 is the check counter (an integer) and
# is used as it is. csp, cgp, ctp and cs0 are saved with CSC first and
# restored with CLC after the sweep; the probes trap to test-local vectors,
# so nothing runs on them while they are integers. A failing probe returns
# without restoring them: after main, crt_cheriot.S needs only cra.
#
# Part B: R-type operand indices. ADD with rd, rs1 and rs2 each drawn from
# x0, t0 (x5) and a5 (x15) -- all 27 combinations, with t0 = 0x120 and
# a5 = 3 before each. rd = x0 is legal and discards the result (RISC-V
# unprivileged ISA, x0 hardwired to 0); x0 reads as 0. Assembled without RVC
# so every ADD is the 32-bit OP encoding.
#
# Checks and failure codes (main returns 0 or the first failing code)
#   Part A, each probe, codes B..B+4: no trap / mcause 28 / mtval / MEPCC.address /
#   rd (a1, preset 0x5A5A5A5A) unchanged:
#     10 lw via c0     20 jalr via c0     30 c2   40 c3   50 c4   60 c5
#     70 c6   80 c7   90 c8   100 c9
#   Part B, triple i (0..26, rs1-major, then rs2, then rd, each in the order
#   x0, t0, a5): code 110 + 2i = rd holds rs1 + rs2 (rd = x0: t0 unchanged),
#   111 + 2i = a5 unchanged (rd = x0 only)
#   164  add t1, zero, zero after the sweep (t1 preset 0x5A5A5A5A) -> 0: x0 still reads 0
#        after the last rd = x0 write (triple 24, 158)
#   250 unexpected trap;  251 liveness (fewer checks executed than assembled)
#
# Register use: x0-x15 only; s1 check count; a5 = save-area authority (part A);
# a4 = address of `word` (integer); a1 probe destination; a3 capability
# scratch; t0/t1/t2 integer scratch outside the probes.

#include "cheriot_dv.h"

    .option norelax

# Fault probe. \reg (or none, "-") is made an integer, then \insn must raise a Tag
# Violation against register \n. Codes \code..\code+4.
.macro REG_FAULT reg, n, code, insn:vararg
    SET_VEC   .Ltrap\@, t0, t1
    li        a1, 0x5A5A5A5A
    .ifnc \reg, -
    mv        \reg, a4
    .endif
.Lfault\@:
    \insn
    li        a0, \code
    j         .Lexit
    .balign 4
.Ltrap\@:
    SET_VEC   .Lunexpected, t0, t1
    csrr      t1, mcause
    EXPECT_EQI t1, 28, (\code + 1)
    csrr      t1, mtval
    EXPECT_EQI t1, ((\n << 5) | 0x02), (\code + 2)
    cspecialr a3, SCR_MEPCC
    cgetaddr  t1, a3
    LA_FAR    t0, .Lfault\@, a3
    EXPECT_EQ t1, t0, (\code + 3)
    EXPECT_EQI a1, 0x5A5A5A5A, (\code + 4)
    RESUME    .Lnext\@, a3, t0
.Lnext\@:
.endm

# add \rd, \rs1, \rs2 with t0 = 0x120, a5 = 3; \sum is rs1 + rs2.
.macro RRR rd, rs1, rs2, sum, code
    li        t0, 0x120
    li        a5, 0x3
    add       \rd, \rs1, \rs2
    .ifc \rd, zero
    EXPECT_EQI t0, 0x120, \code
    EXPECT_EQI a5, 0x3, (\code + 1)
    .else
    EXPECT_EQI \rd, \sum, \code
    .endif
.endm

    .text
    .globl main
main:
    li        s1, 0
    SET_VEC   .Lunexpected, t0, t1

    # ── Part A ───────────────────────────────────────────────────────────────
    DCAP_FAR  a5, saved, t0
    csc       sp, a5, 0
    csc       gp, a5, 8
    csc       tp, a5, 16
    csc       s0, a5, 24
    LA_FAR    a4, word, t0

    REG_FAULT -,  0, 10,  lw a1, 0(zero)
    REG_FAULT -,  0, 20,  jalr zero, 0(zero)
    REG_FAULT sp, 2, 30,  lw a1, 0(sp)
    REG_FAULT gp, 3, 40,  lw a1, 0(gp)
    REG_FAULT tp, 4, 50,  lw a1, 0(tp)
    REG_FAULT t0, 5, 60,  lw a1, 0(t0)
    REG_FAULT t1, 6, 70,  lw a1, 0(t1)
    REG_FAULT t2, 7, 80,  lw a1, 0(t2)
    REG_FAULT s0, 8, 90,  lw a1, 0(s0)
    REG_FAULT -,  9, 100, lw a1, 0(s1)

    clc       sp, a5, 0
    clc       gp, a5, 8
    clc       tp, a5, 16
    clc       s0, a5, 24

    # ── Part B ───────────────────────────────────────────────────────────────
    .option push
    .option norvc
    RRR       zero, zero, zero, 0x000, 110
    RRR       t0, zero, zero, 0x000, 112
    RRR       a5, zero, zero, 0x000, 114
    RRR       zero, zero, t0, 0x120, 116
    RRR       t0, zero, t0, 0x120, 118
    RRR       a5, zero, t0, 0x120, 120
    RRR       zero, zero, a5, 0x003, 122
    RRR       t0, zero, a5, 0x003, 124
    RRR       a5, zero, a5, 0x003, 126
    RRR       zero, t0, zero, 0x120, 128
    RRR       t0, t0, zero, 0x120, 130
    RRR       a5, t0, zero, 0x120, 132
    RRR       zero, t0, t0, 0x240, 134
    RRR       t0, t0, t0, 0x240, 136
    RRR       a5, t0, t0, 0x240, 138
    RRR       zero, t0, a5, 0x123, 140
    RRR       t0, t0, a5, 0x123, 142
    RRR       a5, t0, a5, 0x123, 144
    RRR       zero, a5, zero, 0x003, 146
    RRR       t0, a5, zero, 0x003, 148
    RRR       a5, a5, zero, 0x003, 150
    RRR       zero, a5, t0, 0x123, 152
    RRR       t0, a5, t0, 0x123, 154
    RRR       a5, a5, t0, 0x123, 156
    RRR       zero, a5, a5, 0x006, 158
    RRR       t0, a5, a5, 0x006, 160
    RRR       a5, a5, a5, 0x006, 162
    # 164: x0 read after the sweep. The last rd = x0 triple (158, add zero, a5, a5 = 6) is
    # not followed by any read of x0 above, so a core that let that write through would
    # otherwise pass. t1 is preset so a skipped write would also be caught.
    li        t1, 0x5A5A5A5A
    add       t1, zero, zero
    EXPECT_EQI t1, 0, 164
    .option pop

    CHECK_LIVENESS 251
    li        a0, 0
    j         .Lexit

    .balign 4
.Lunexpected:
    li        a0, 250
.Lexit:
    ret

    .data
    .balign 8
saved:
    .space  32
word:
    .word   0x600DF00D
