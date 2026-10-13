# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_zcb -- the Zcb instructions in CHERIoT mode
# =============================================================================
# The opentitan configuration has RV32ZC = RV32ZcaZcbZcmp, and ibex_compressed_decoder.sv expands
# the Zcb instructions with cheriot_enable_i On (Zcmp is illegal in CHERIoT mode, Zcb is not).
# Expected values come from the ratified Zc specification, which defines each Zcb instruction as
# an existing instruction with fixed operands, and from CHERIoT-Sail, which decodes each one to
# that instruction (sail-riscv/model/riscv_insts_zcb.sail; generated C zcb_decode_compressed,
# VENDORED_FROM 2026-10-10):
#   c.lbu rd', uimm(rs1')  = lbu rd', uimm(rs1')     uimm[1:0] = {bit 5, bit 6}
#   c.lhu rd', uimm(rs1')  = lhu                     uimm[1] = bit 5
#   c.lh  rd', uimm(rs1')  = lh                      uimm[1] = bit 5
#   c.sb  rs2', uimm(rs1') = sb                      uimm[1:0] = {bit 5, bit 6}
#   c.sh  rs2', uimm(rs1') = sh                      uimm[1] = bit 5
#   c.zext.b rd' = andi rd', rd', 0xff     c.sext.b rd' = sext.b rd', rd'
#   c.zext.h rd' = zext.h rd', rd'         c.sext.h rd' = sext.h rd', rd'
#   c.not rd'    = xori rd', rd', -1       c.mul rd', rs2' = mul rd', rd', rs2'
# So in CHERIoT mode a Zcb load or store is authorised by the capability in rs1', as lbu/sb are
# (CHERIoT-Sail LOAD/STORE -> ext_data_get_addr, cheri_addr_checks.sail): an untagged authority
# raises a tag violation (capcause 0x02), one without Permit_Load / Permit_Store a permission
# violation (0x12 / 0x13), an access outside the bounds a bounds violation (0x01); each is
# mcause 28 with mtval = (rs1' << 5) | capcause, MEPCC at the instruction, and changes no
# register or memory. An integer result clears the destination's tag. The CHERIoT-Sail cosim
# also checks every step (rd value and tag, PC + 2, the trap and its mcause/mtval).
#
# Data: buf (16 bytes, .data) = 7F 80 FF 01 | FF 7F 00 80 | A5 A5 A5 A5 | 5A 5A 5A 5A.
# cs0 = MTDC with bounds exactly [buf, buf + 16), the authority every other one derives from.
#
# Checks and failure codes (main returns 0 or the first failing code)
#   1-3     cs0: tag 1, CGetBase = buf, CGetLen 16
#   Loads (every uimm; rd' and rs1' over most registers, stores and faults add the rest):
#   10-13   c.lbu a1/a2/a3/a5, 0..3(cs0) = 0x7F, 0x80, 0xFF, 0x01 (zero-extended)
#   14-17   c.lhu a0, 0(cs0) = 0x807F; c.lhu a2, 2(cs0) = 0x01FF; c.lh a3, 0(cs0) = 0xFFFF807F;
#           c.lh a5, 2(cs0) = 0x01FF
#   18-20   ca4 = cs0 + 4: c.lh a1, 0(ca4) = 0x7FFF; c.lh a2, 2(ca4) = 0xFFFF8000;
#           c.lhu a3, 2(ca4) = 0x8000
#   21-22   c.lbu a5, 1(ca4) over a tagged a5: tag 0, value 0x7F
#   23-26   rs1' = ca0, ca1, ca2, cs1 (copies of cs0): c.lbu a1, 1(ca0) = 0x80;
#           c.lhu a5, 2(ca1) = 0x01FF; c.lh a5, 0(ca2) = 0xFFFF807F; c.lbu a1, 2(cs1) = 0xFF
#   27      c.lbu a4, 3(ca4) (rd' = rs1') = 0x80
#   Stores through ca3 = cs0 + 8, read back with lw through cs0:
#   30-33   c.sb a2, 3(ca3); c.sb a1, 0(ca3); c.sb a5, 1(ca3); c.sb a2, 2(ca3): word 8 =
#           0x78A5A5A5, 0x78A5A5AB, 0x78A501AB, 0x787801AB
#   34-35   c.sh a1, 2(ca3); c.sh a2, 0(ca3): word 8 = 0xBEEF01AB, 0xBEEF4321
#   36-38   words 12, 0 and 4 unchanged (0x5A5A5A5A, 0x01FF807F, 0x80007FFF)
#   Faults, each codes B..B+4: no trap / mcause 28 / mtval / MEPCC.address = the instruction /
#   destination register or memory unchanged:
#   40      ca4 = cs0 with exact length 2: tag 1 (41: CGetLen 2)
#   42      c.lbu a1, 1(ca4) = 0x80 (last byte in bounds)
#   50-54   c.lbu a1, 3(ca4)    bounds   mtval 0x1C1
#   60-64   c.lhu a1, 2(ca4)    bounds   mtval 0x1C1
#   70-74   c.sh a2, 2(ca4)     bounds   mtval 0x1C1  (word 0 unchanged)
#   80      ca3 = CClearTag(cs0): tag 0
#   90-94   c.lbu a1, 0(ca3)    tag      mtval 0x1A2
#   100-104 c.sb a2, 0(ca3)     tag      mtval 0x1A2  (word 0 unchanged)
#   110-111 ca5 = CAndPerm(cs0 + 12, ~LD): tag 1, LD clear (112: SD set)
#   113     c.sb a2 (0xCAFE), 0(ca5) succeeds: word 12 = 0x5A5A5AFE
#   120-124 c.lh a1, 0(ca5)     no LD    mtval 0x1F2
#   125-127 ca5 = CAndPerm(cs0 + 12, ~SD): tag 1, SD clear, LD set
#   128     c.lhu a1, 0(ca5) succeeds = 0x5AFE
#   130-134 c.sh a2, 0(ca5)     no SD    mtval 0x1F3  (word 12 unchanged)
#   Arithmetic (edge values; rd' over every register, s1 saved around its own case):
#   140-141 c.zext.b a1 (0xFFFFFF80) = 0x80; c.zext.b a0 (0x1234567F) = 0x7F
#   142-144 c.sext.b a3 (0x80) = 0xFFFFFF80; c.sext.b a5 (0xFFFFFF7F) = 0x7F;
#           c.sext.b a2 (0) = 0
#   145-146 c.zext.h a2 (0xFFFF8000) = 0x8000; c.zext.h s0 (0x1234FFFF) = 0xFFFF
#   147-149 c.sext.h a4 (0x8000) = 0xFFFF8000; c.sext.h a5 (0xFFFF7FFF) = 0x7FFF;
#           c.sext.h s1 (0x8000) = 0xFFFF8000
#   150-151 c.not a1 (0) = 0xFFFFFFFF; c.not a2 (0x5A5A5A5A) = 0xA5A5A5A5
#   152-153 c.not a5 over a tagged a5 (cs0): tag 0, value ~buf
#   160-161 c.mul a1, a2 (-3 * 7) = 0xFFFFFFEB, a2 still 7
#   162     c.mul a3, a5 (0x10001 * 0x10001) = 0x00020001 (low half)
#   163     c.mul a5, a3 (0x80000000 * -1) = 0x80000000
#   164     c.mul s0, s0 (0xFFFF * 0xFFFF) = 0xFFFE0001
#   165     c.mul a4, a0 (0x12345678 * 0) = 0
#   250 unexpected trap;  251 liveness (fewer checks executed than assembled)
#
# Encodings: the flow's assembler (rv32imc) has no Zcb, so the macros below emit the 16-bit
# words from the Zc specification's field layout; register operands are numbers 8-15 (cs0 = 8,
# cs1 = 9, ca0-ca5 = 10-15). Cross-checked with llvm-mc -triple riscv32 -mattr=+zcb,+zbb,+m.
#
# Register use: x0-x15 only. s1 check count (except around its own c.sext.h); t0/t1/t2 integer
# scratch; cs0 the buf authority until the arithmetic section; a0 the exit code, used as an
# operand only where a failure overwrites it anyway. aN and caN are the same register.

#include "cheriot_dv.h"

    .option norelax

# ---- Zcb encodings ---------------------------------------------------------------------------

.macro ZCB_REG r
  .if (\r < 8) || (\r > 15)
  .error "Zcb register operands must be x8-x15"
  .endif
.endm
.macro c_lbu rd, uimm, rs1
  ZCB_REG \rd
  ZCB_REG \rs1
  .hword 0x8000 | ((\rs1 - 8) << 7) | (((\uimm) & 1) << 6) | ((((\uimm) >> 1) & 1) << 5) | ((\rd - 8) << 2)
.endm
.macro c_lhu rd, uimm, rs1
  ZCB_REG \rd
  ZCB_REG \rs1
  .hword 0x8400 | ((\rs1 - 8) << 7) | ((((\uimm) >> 1) & 1) << 5) | ((\rd - 8) << 2)
.endm
.macro c_lh rd, uimm, rs1
  ZCB_REG \rd
  ZCB_REG \rs1
  .hword 0x8440 | ((\rs1 - 8) << 7) | ((((\uimm) >> 1) & 1) << 5) | ((\rd - 8) << 2)
.endm
.macro c_sb rs2, uimm, rs1
  ZCB_REG \rs2
  ZCB_REG \rs1
  .hword 0x8800 | ((\rs1 - 8) << 7) | (((\uimm) & 1) << 6) | ((((\uimm) >> 1) & 1) << 5) | ((\rs2 - 8) << 2)
.endm
.macro c_sh rs2, uimm, rs1
  ZCB_REG \rs2
  ZCB_REG \rs1
  .hword 0x8C00 | ((\rs1 - 8) << 7) | ((((\uimm) >> 1) & 1) << 5) | ((\rs2 - 8) << 2)
.endm
# Unary forms: funct6 100111, rd', 11, sub-op in bits 4:2.
.macro c_unary rd, op
  ZCB_REG \rd
  .hword 0x9C61 | ((\rd - 8) << 7) | ((\op) << 2)
.endm
.macro c_zext_b rd
  c_unary \rd, 0
.endm
.macro c_sext_b rd
  c_unary \rd, 1
.endm
.macro c_zext_h rd
  c_unary \rd, 2
.endm
.macro c_sext_h rd
  c_unary \rd, 3
.endm
.macro c_not rd
  c_unary \rd, 5
.endm
.macro c_mul rd, rs2
  ZCB_REG \rd
  ZCB_REG \rs2
  .hword 0x9C41 | ((\rd - 8) << 7) | ((\rs2 - 8) << 2)
.endm

# ---- Checks ----------------------------------------------------------------------------------

# \insn (one Zcb load or store) must raise a CHERI exception with \mtval. Codes \code (no trap),
# \code+1 (mcause), \code+2 (mtval), \code+3 (MEPCC); the caller checks \code+4 afterwards.
.macro ZCB_FAULT insn, mtval, code
    SET_VEC   .Ltrap\@, t0, t1
.Lfault\@:
    \insn
    li        a0, \code
    j         .Lexit
    .balign 4
.Ltrap\@:
    SET_VEC   .Lunexpected, t0, t1
    csrr      t1, mcause
    EXPECT_EQI t1, MCAUSE_CHERI, (\code + 1)
    csrr      t1, mtval
    EXPECT_EQI t1, \mtval, (\code + 2)
    cspecialr t0, SCR_MEPCC
    cgetaddr  t1, t0
    LA_FAR    t0, .Lfault\@, t2
    EXPECT_EQ t1, t0, (\code + 3)
    RESUME    .Lnext\@, t0, t1
.Lnext\@:
.endm

# lw t1, \off(cs0) must read \val. Code \code.
.macro BUF_WORD off, val, code
    lw        t1, \off(s0)
    EXPECT_EQI t1, \val, \code
.endm

    .text
    .globl main
main:
    li        s1, 0
    SET_VEC   .Lunexpected, t0, t1

    # cs0 := MTDC over [buf, buf + 16), exact (length < 512).
    DCAP_FAR  s0, buf, t0
    li        t1, 16
    csetboundsexact s0, s0, t1
    cgettag   t2, s0
    EXPECT_EQI t2, 1, 1
    cgetbase  t1, s0
    LA_FAR    t0, buf, t2
    EXPECT_EQ t1, t0, 2
    cgetlen   t1, s0
    EXPECT_EQI t1, 16, 3

    # ---- Loads ----
    c_lbu     11, 0, 8                      # c.lbu a1, 0(cs0)
    EXPECT_EQI a1, 0x7F, 10
    c_lbu     12, 1, 8                      # c.lbu a2, 1(cs0)
    EXPECT_EQI a2, 0x80, 11
    c_lbu     13, 2, 8                      # c.lbu a3, 2(cs0)
    EXPECT_EQI a3, 0xFF, 12
    c_lbu     15, 3, 8                      # c.lbu a5, 3(cs0)
    EXPECT_EQI a5, 0x01, 13
    c_lhu     10, 0, 8                      # c.lhu a0, 0(cs0)
    EXPECT_EQI a0, 0x807F, 14
    c_lhu     12, 2, 8                      # c.lhu a2, 2(cs0)
    EXPECT_EQI a2, 0x01FF, 15
    c_lh      13, 0, 8                      # c.lh a3, 0(cs0)
    EXPECT_EQI a3, 0xFFFF807F, 16
    c_lh      15, 2, 8                      # c.lh a5, 2(cs0)
    EXPECT_EQI a5, 0x01FF, 17
    cincaddrimm a4, s0, 4
    c_lh      11, 0, 14                     # c.lh a1, 0(ca4)
    EXPECT_EQI a1, 0x7FFF, 18
    c_lh      12, 2, 14                     # c.lh a2, 2(ca4)
    EXPECT_EQI a2, 0xFFFF8000, 19
    c_lhu     13, 2, 14                     # c.lhu a3, 2(ca4)
    EXPECT_EQI a3, 0x8000, 20
    cmove     a5, s0                        # a5 tagged: the load must clear the tag
    c_lbu     15, 1, 14                     # c.lbu a5, 1(ca4)
    cgettag   t1, a5
    EXPECT_EQI t1, 0, 21
    EXPECT_EQI a5, 0x7F, 22
    cmove     a0, s0
    c_lbu     11, 1, 10                     # c.lbu a1, 1(ca0)
    EXPECT_EQI a1, 0x80, 23
    cmove     a1, s0
    c_lhu     15, 2, 11                     # c.lhu a5, 2(ca1)
    EXPECT_EQI a5, 0x01FF, 24
    cmove     a2, s0
    c_lh      15, 0, 12                     # c.lh a5, 0(ca2)
    EXPECT_EQI a5, 0xFFFF807F, 25
    mv        t0, s1                        # cs1 as the authority, count saved in t0
    cmove     s1, s0
    c_lbu     11, 2, 9                      # c.lbu a1, 2(cs1)
    mv        s1, t0
    EXPECT_EQI a1, 0xFF, 26
    c_lbu     14, 3, 14                     # c.lbu a4, 3(ca4)
    EXPECT_EQI a4, 0x80, 27

    # ---- Stores through ca3 = cs0 + 8 ----
    cincaddrimm a3, s0, 8
    li        a2, 0x12345678
    c_sb      12, 3, 13                     # c.sb a2, 3(ca3)
    BUF_WORD  8, 0x78A5A5A5, 30
    li        a1, 0xFFFFFFAB
    c_sb      11, 0, 13                     # c.sb a1, 0(ca3)
    BUF_WORD  8, 0x78A5A5AB, 31
    li        a5, 0x00000001
    c_sb      15, 1, 13                     # c.sb a5, 1(ca3)
    BUF_WORD  8, 0x78A501AB, 32
    c_sb      12, 2, 13                     # c.sb a2, 2(ca3)
    BUF_WORD  8, 0x787801AB, 33
    li        a1, 0x1234BEEF
    c_sh      11, 2, 13                     # c.sh a1, 2(ca3)
    BUF_WORD  8, 0xBEEF01AB, 34
    li        a2, 0x87654321
    c_sh      12, 0, 13                     # c.sh a2, 0(ca3)
    BUF_WORD  8, 0xBEEF4321, 35
    BUF_WORD  12, 0x5A5A5A5A, 36
    BUF_WORD  0, 0x01FF807F, 37
    BUF_WORD  4, 0x80007FFF, 38

    # ---- Bounds: ca4 = cs0 with length 2 ----
    li        t1, 2
    csetboundsexact a4, s0, t1
    cgettag   t1, a4
    EXPECT_EQI t1, 1, 40
    cgetlen   t1, a4
    EXPECT_EQI t1, 2, 41
    c_lbu     11, 1, 14                     # c.lbu a1, 1(ca4)
    EXPECT_EQI a1, 0x80, 42
    li        a1, 0x5A5A5A5A
    ZCB_FAULT "c_lbu 11, 3, 14", 0x1C1, 50  # c.lbu a1, 3(ca4)
    EXPECT_EQI a1, 0x5A5A5A5A, 54
    ZCB_FAULT "c_lhu 11, 2, 14", 0x1C1, 60  # c.lhu a1, 2(ca4)
    EXPECT_EQI a1, 0x5A5A5A5A, 64
    li        a2, 0x0000CAFE
    ZCB_FAULT "c_sh 12, 2, 14", 0x1C1, 70   # c.sh a2, 2(ca4)
    BUF_WORD  0, 0x01FF807F, 74

    # ---- Tag: ca3 = CClearTag(cs0) ----
    ccleartag a3, s0
    cgettag   t1, a3
    EXPECT_EQI t1, 0, 80
    ZCB_FAULT "c_lbu 11, 0, 13", 0x1A2, 90  # c.lbu a1, 0(ca3)
    EXPECT_EQI a1, 0x5A5A5A5A, 94
    ZCB_FAULT "c_sb 12, 0, 13", 0x1A2, 100  # c.sb a2, 0(ca3)
    BUF_WORD  0, 0x01FF807F, 104

    # ---- Permissions: ca5 = cs0 + 12 without LD, then without SD (CGetPerm LD = bit 5,
    # SD = bit 2; the compressed format keeps the other one, checked below) ----
    cincaddrimm a5, s0, 12
    li        t0, ~0x20
    candperm  a5, a5, t0
    cgettag   t1, a5
    EXPECT_EQI t1, 1, 110
    cgetperm  t1, a5
    andi      t0, t1, 0x20
    EXPECT_EQI t0, 0, 111
    andi      t0, t1, 0x04
    EXPECT_EQI t0, 0x04, 112
    c_sb      12, 0, 15                     # c.sb a2, 0(ca5): SD present
    BUF_WORD  12, 0x5A5A5AFE, 113
    ZCB_FAULT "c_lh 11, 0, 15", 0x1F2, 120  # c.lh a1, 0(ca5)
    EXPECT_EQI a1, 0x5A5A5A5A, 124
    cincaddrimm a5, s0, 12
    li        t0, ~0x04
    candperm  a5, a5, t0
    cgettag   t1, a5
    EXPECT_EQI t1, 1, 125
    cgetperm  t1, a5
    andi      t0, t1, 0x04
    EXPECT_EQI t0, 0, 126
    andi      t0, t1, 0x20
    EXPECT_EQI t0, 0x20, 127
    c_lhu     11, 0, 15                     # c.lhu a1, 0(ca5): LD present
    EXPECT_EQI a1, 0x5AFE, 128
    ZCB_FAULT "c_sh 12, 0, 15", 0x1F3, 130  # c.sh a2, 0(ca5)
    BUF_WORD  12, 0x5A5A5AFE, 134

    # ---- Arithmetic ----
    li        a1, 0xFFFFFF80
    c_zext_b  11
    EXPECT_EQI a1, 0x80, 140
    li        a0, 0x1234567F
    c_zext_b  10
    EXPECT_EQI a0, 0x7F, 141
    li        a3, 0x80
    c_sext_b  13
    EXPECT_EQI a3, 0xFFFFFF80, 142
    li        a5, 0xFFFFFF7F
    c_sext_b  15
    EXPECT_EQI a5, 0x7F, 143
    li        a2, 0
    c_sext_b  12
    EXPECT_EQI a2, 0, 144
    li        a2, 0xFFFF8000
    c_zext_h  12
    EXPECT_EQI a2, 0x8000, 145
    li        s0, 0x1234FFFF                # cs0 is no longer needed
    c_zext_h  8
    EXPECT_EQI s0, 0xFFFF, 146
    li        a4, 0x8000
    c_sext_h  14
    EXPECT_EQI a4, 0xFFFF8000, 147
    li        a5, 0xFFFF7FFF
    c_sext_h  15
    EXPECT_EQI a5, 0x7FFF, 148
    mv        t0, s1                        # count saved in t0
    li        s1, 0x8000
    c_sext_h  9
    mv        t1, s1
    mv        s1, t0
    EXPECT_EQI t1, 0xFFFF8000, 149
    li        a1, 0
    c_not     11
    EXPECT_EQI a1, 0xFFFFFFFF, 150
    li        a2, 0x5A5A5A5A
    c_not     12
    EXPECT_EQI a2, 0xA5A5A5A5, 151
    DCAP_FAR  a5, buf, t0                   # tagged, cursor buf: c.not must clear the tag
    c_not     15
    cgettag   t1, a5
    EXPECT_EQI t1, 0, 152
    LA_FAR    t0, buf, t1
    not       t0, t0
    EXPECT_EQ a5, t0, 153
    li        a1, -3
    li        a2, 7
    c_mul     11, 12
    EXPECT_EQI a1, 0xFFFFFFEB, 160
    EXPECT_EQI a2, 7, 161
    li        a3, 0x10001
    li        a5, 0x10001
    c_mul     13, 15
    EXPECT_EQI a3, 0x00020001, 162
    li        a5, 0x80000000
    li        a3, -1
    c_mul     15, 13
    EXPECT_EQI a5, 0x80000000, 163
    li        s0, 0xFFFF
    c_mul     8, 8
    EXPECT_EQI s0, 0xFFFE0001, 164
    li        a4, 0x12345678
    li        a0, 0
    c_mul     14, 10
    EXPECT_EQI a4, 0, 165

    CHECK_LIVENESS 251
    li        a0, 0
    j         .Lexit

    .balign 4
.Lunexpected:
    li        a0, 250
.Lexit:
    ret

    .data
    .balign 16
buf:
    .byte     0x7F, 0x80, 0xFF, 0x01
    .byte     0xFF, 0x7F, 0x00, 0x80
    .word     0xA5A5A5A5
    .word     0x5A5A5A5A
