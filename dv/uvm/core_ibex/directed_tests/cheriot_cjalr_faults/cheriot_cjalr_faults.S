# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_cjalr_faults — CJALR exception causes, priority, sentry rules
# =============================================================================
# REQ_CFI_01, REQ_CFI_03, REQ_PER_03, REQ_SEL_06, REQ_SEL_08.
#
# What CHERIoT-Sail says (execute(CJALR(imm, cs1, cd)), cheri_insts.sail; all
# expected values below come from here):
#   isAllowedSentryType is, by register pair:
#     cd == c0 and cs1 == cra : isCapBackwardSentry(cs1)            (otype 4, 5)
#     otherwise, cd == cra    : unsealed or isCapForwardSentry       (0, 1, 2, 3)
#     any other pair          : unsealed or isCapForwardInheritSentry (0, 1)
#   then, in this order:
#     not(cs1.tag)                                   -> 0x02 Tag Violation
#     (sealed(cs1) & imm != 0) | not(allowed type)   -> 0x03 Seal Violation
#     not(cs1.permit_execute)                        -> 0x11 Permit_Execute
#   each against cs1 (handle_cheri_reg_exception: mtval = cs1 << 5 | cause,
#   mtval[10] = 0), with RETIRE_FAIL before C(cd) is written, so cd is
#   unchanged. MEPCC = setCapAddr(PCC, PC of the CJALR): tagged.
#   C_CJR(cs1) = CJALR(0, cs1, c0) and C_CJALR(cs1) = CJALR(0, cs1, cra)
#   (cheri_insts_cext.sail), and the plain JALR encoding is CJALR in
#   capability mode (encdec_capmode), so jalr/c.jr/c.jalr below are all CJALR.
#   Architectural otypes are 4 bits: an executable capability sealed with
#   otype 1-7 keeps that otype, a non-executable one can only be sealed with
#   9-15 (CSeal isPermittedOtype), so a data-sealed cap is never a sentry.
#   Note the return rule: CJALR c0, 0(cra) through an UNSEALED cra is a Seal
#   Violation -- only a backward sentry may be returned through.
#
# REQ_PER_03 (CSpecialRW, cheri_insts.sail): writing MTCC or MEPCC with a value
# that lacks Permit_Execute stores it with tag = 0. For MEPCC this is recovered
# here: MRET installs the untagged value as PCC, and the next fetch raises
# 0x02 against PCC (ext_fetch_check_pc: not(PCC.tag) and MTCC.tag ->
# CapEx_TagViolation; mtval = 0x402), which traps to the still-valid MTCC.
# For MTCC the trap is NOT exercised, only the legalisation: with MTCC
# untagged, the next trap installs PCC := untagged MTCC, its fetch faults, and
# that fault vectors to the same untagged MTCC again -- a livelock with no way
# back into the test. CHERIoT-Sail does not define an outcome either:
# ext_fetch_check_pc calls not_implemented("Untagged PCC and MTCC infinite
# loops; stopping now") when both PCC and MTCC are untagged. So section 1
# writes an EX-less MTCC, reads it back (tag must be 0), and restores a valid
# MTCC before any instruction that could trap or branch.
#
# Operands (built fresh in ca1 for every section):
#   exec  = CSetAddr(MTCC copy, target)      tagged, unsealed, EX, full bounds
#   data  = CSetAddr(MTDC, target)           tagged, unsealed, no EX
#   sealed with otype n = CSeal(x, CSetAddr(MScratchC, n)); MScratchC is the
#   seal root. Every operand's tag and otype are checked before use, so a
#   CSeal that silently failed shows up as a precondition, not as a wrong
#   CJALR cause.
# Every faulting CJALR targets .Ltgt; reaching it means the CJALR jumped
# instead of faulting and returns 500 + section.
#
# Trap handling: as in cheriot_perm_lc_sc, MTCC points at a test-local
# 4-byte-aligned vector per section that jumps into main; no handler returns
# with mret. A trap only needs MTCC to be valid; the faulting CJALR context is
# simply abandoned. cra (the crt's backward sentry) is copied to ca5 first and
# restored at .Lexit and after the sections that deliberately overwrite cra,
# so main can always return. mstatus.MIE is clear after the first trap, so the
# interrupt-state checks run before the first deliberate fault.
#
# How each check can fail (section k uses codes 10k .. 10k+9)
# -----------------------------------------------------------
#   1-3     Preconditions: MTCC perms 0x1EB, MTDC perms 0x07F, MScratchC SE.
#   4-6     Before the first fault: mstatus.MIE = 1, mcause = 0, mip = 0.
#   7-8     At the end: mip = 0, mcause = 28 (last trap was not an interrupt).
#   500+k   A CJALR (or MRET) that must fault jumped to its target instead.
#   900+k   Unexpected trap in section k's setup or check code.
# Fault sections, B = 10k:
#   B+0/1   operand tag / otype as built (precondition)
#   B+2     mcause = 28
#   B+3     mtval[4:0] = expected cause
#   B+4     mtval = expected (cause + cs1 index in [9:5], mtval[10] = 0)
#   B+5     MEPCC.address = the CJALR
#   B+6     MEPCC.tag = 1 (not a fetch bounds fault: PCC keeps its tag)
#   B+7     cd unchanged (sections with cd = cra or ct1)
#   B+8     tag clear after CClearTag (untagged-operand sections)
#   B+9     the CJALR fell through without trapping or jumping
#
#   k  instruction          operand                        expected   rule
#   1  cspecialw mtcc       data (no EX), aligned          readback tag 0 (PER_03)
#        codes 10/11 operand pre, 12 MTCC tag = 0, 13 MTCC address kept,
#        14 restored MTCC tag = 1.
#   2  jalr c0, 0(ca1)      untagged exec                  0x162  CFI_03
#   3  jalr c0, 0(ca1)      untagged, data, otype 9        0x162  CFI_03: tag
#                           (sealed AND no EX)                    before seal/EX
#   4  c.jr ca1             untagged data (no EX)          0x162  CFI_01/03: c.jr,
#                                                                 tag before EX
#   5  jalr c0, 0(ca1)      data sealed otype 9 (no EX)    0x163  SEL_08: seal
#                                                                 before EX
#   6  jalr c0, 0(ca1)      data sealed otype 15 (no EX)   0x163  SEL_08
#   7  jalr c0, 0(ca1)      exec sealed otype 6            0x163  SEL_08
#   8  jalr cra, 0(ca1)     exec sealed otype 7 (call)     0x163  SEL_08, cra kept
#   9  jalr c0, 0(ca1)      data, unsealed, tagged         0x171  CFI_01, PER_03
#  10  c.jalr ca1           data, unsealed, tagged         0x171  CFI_01 (c.jalr),
#                                                                 cra kept
#  11  jalr cra, 0(ca1)     backward sentry otype 4        0x163  SEL_06: call
#                                                                 needs fwd sentry
#  12  jalr c0, 0(ca1)      backward sentry otype 5        0x163  SEL_06: tail call
#  13  jalr ct1, 0(ca1)     forward sentry otype 2         0x163  SEL_06: other cd
#                                                                 needs 0 or 1;
#                                                                 t1 kept
#  14  jalr c0, 0(cra)      forward sentry otype 3 in cra  0x023  SEL_06: return
#                                                                 needs bwd sentry
#  15  jalr c0, 0(cra)      UNSEALED exec in cra           0x023  SEL_06: return
#                                                                 needs bwd sentry
#  16  jalr c0, 4(ca1)      forward sentry otype 1, imm 4  0x163  SEL_08: sealed
#                                                                 needs imm = 0
# Controls (must NOT fault; B+2 = the control trapped):
#  17  jalr ct1, 0(ca1)     otype 1 sentry, cd = ct1       jumps; B+3 link tag 1,
#        B+4 link otype 0 (unsealed: cd != cra), B+5 link address = CJALR + 4.
#  18  jalr c0, 4(ca1)      unsealed exec, imm 4           lands at target + 4;
#        B+3 landed at target + 0 (imm ignored) or fell through.
#  19  jalr c0, 0(ca1)      otype 1 sentry, imm 0          jumps (contrast to 16).
#  20  mret                 MEPCC <- data (no EX)          PER_03:
#        200 MEPCC readback tag = 0, 201 MEPCC address = .Ltgt,
#        202 mcause = 28, 203 mtval[4:0] = 0x02, 204 mtval = 0x402 (against
#        PCC), 205 MEPCC.address = .Ltgt, 206 MEPCC.tag = 0, 209 mret fell
#        through; 520 = .Ltgt executed under the untagged PCC.
#
# Register use: ca0 = execute root copy, ca1 = operand, ca2 = seal root,
# ca3 = data root, ca4 = scratch capability, ca5 = saved cra; t0/t1/t2/s0
# integer scratch (s0 = section number). a0-a5 are never an integer
# destination except a0 on exit. No x16-x31.
#
# Instruction encodings (opcode 0x5B), generated from the CHERIoT-Sail encdec
# clauses (cheri_insts.sail) and cross-checked against every .word in the
# existing cheriot_* directed tests (228 words, 0 mismatches):
#   ccleartag       ca1, ca1           = .word 0xFEB585DB
#   cgetaddr        t1, ca4            = .word 0xFEF7035B
#   cgetaddr        t1, ct1            = .word 0xFEF3035B
#   cgetaddr        t2, ct1            = .word 0xFEF303DB
#   cgetperm        t1, ca0            = .word 0xFE05035B
#   cgetperm        t1, ca2            = .word 0xFE06035B
#   cgetperm        t1, ca3            = .word 0xFE06835B
#   cgettag         t1, ca1            = .word 0xFE45835B
#   cgettag         t1, ca4            = .word 0xFE47035B
#   cgettag         t1, ct1            = .word 0xFE43035B
#   cgettag         t2, ca4            = .word 0xFE4703DB
#   cgettag         t2, ct1            = .word 0xFE4303DB
#   cgettype        t1, ca1            = .word 0xFE15835B
#   cgettype        t2, ct1            = .word 0xFE1303DB
#   cmove           ca5, cra           = .word 0xFEA087DB
#   cmove           cra, ca1           = .word 0xFEA580DB
#   cmove           cra, ca5           = .word 0xFEA780DB
#   cseal           ca1, ca1, ca4      = .word 0x16E585DB
#   csetaddr        ca1, ca0, t0       = .word 0x205505DB
#   csetaddr        ca1, ca3, t0       = .word 0x205685DB
#   csetaddr        ca4, ca0, t0       = .word 0x2055075B
#   csetaddr        ca4, ca2, t0       = .word 0x2056075B
#   csetequalexact  t1, cra, ca5       = .word 0x42F0835B
#   cspecialr       ca0, mtcc          = .word 0x03C0055B
#   cspecialr       ca2, mscratchc     = .word 0x03E0065B
#   cspecialr       ca3, mtdc          = .word 0x03D006DB
#   cspecialr       ca4, mepcc         = .word 0x03F0075B
#   cspecialr       ca4, mtcc          = .word 0x03C0075B
#   cspecialr       ct1, mepcc         = .word 0x03F0035B
#   cspecialw       mepcc, ca1         = .word 0x03F5805B
#   cspecialw       mtcc, ca1          = .word 0x03C5805B
#   cspecialw       mtcc, ca4          = .word 0x03C7005B
# jalr/c.jr/c.jalr/mret are the standard encodings (CJALR in capability mode).

    .option norelax
    .option norvc

# \rd <- address of \sym at any distance. GNU `la` is AUIPC + ADDI with %pcrel_hi
# computed for imm << 12, but in capability mode that encoding is AUIPCC, which
# shifts by 11 (cheri_insts.sail AUIPCC: sign_extend(imm) << 11), so `la` is
# only right within about +-2 KiB. AUIPCC 0 is the same under either shift; the
# distance comes from absolute symbol values. As LA_FAR in cheriot_dv.h (not
# included here: its CHECK_EQ differs). \rd and \tmp must differ.
.macro LA_FAR rd, sym, tmp
9:
    auipc   \rd, 0
    lui     \tmp, %hi(\sym)
    addi    \tmp, \tmp, %lo(\sym)
    add     \rd, \rd, \tmp
    lui     \tmp, %hi(9b)
    addi    \tmp, \tmp, %lo(9b)
    sub     \rd, \rd, \tmp
.endm

# Point MTCC at a test-local vector. Clobbers t0 and c6 (t1).
.macro SET_TRAP_VECTOR label
    LA_FAR  t0, \label, t1
    .word   0x03C0035B              # cspecialr c6, mtcc
    .word   0x2053035B              # csetaddr  c6, c6, t0
    .word   0x03C3005B              # cspecialw mtcc, c6
.endm

# Fall through if \a == \b, else return \code from main.
.macro CHECK_EQ a, b, code
    beq     \a, \b, 1f
    li      a0, \code
    j       .Lexit
1:
.endm

.macro ALIGN4
    .option push
    .option rvc
    .balign 4
    .option pop
.endm

# ca1 <- execute root / data root with address \label. Clobbers t0, t1.
.macro MK_EXEC label
    LA_FAR  t0, \label, t1
    .word   0x205505DB              # csetaddr        ca1, ca0, t0
.endm
.macro MK_DATA label
    LA_FAR  t0, \label, t1
    .word   0x205685DB              # csetaddr        ca1, ca3, t0
.endm

# ca1 <- CSeal(ca1, seal root with address \otype).
.macro SEAL otype
    li      t0, \otype
    .word   0x2056075B              # csetaddr        ca4, ca2, t0
    .word   0x16E585DB              # cseal           ca1, ca1, ca4
.endm

.macro EXPECT_OPERAND tag, otype, sect
    .word   0xFE45835B              # cgettag         t1, ca1
    li      t2, \tag
    CHECK_EQ t1, t2, 10*\sect+0
    .word   0xFE15835B              # cgettype        t1, ca1
    li      t2, \otype
    CHECK_EQ t1, t2, 10*\sect+1
.endm

.macro CLEAR_OPERAND_TAG sect
    .word   0xFEB585DB              # ccleartag       ca1, ca1
    .word   0xFE45835B              # cgettag         t1, ca1
    CHECK_EQ t1, zero, 10*\sect+8
.endm

# The trap was a CHERI fault with mtval \mtval raised by the instruction at
# \pc, with a tagged MEPCC.
.macro CHECK_CJALR_FAULT mtval, pc, sect
    SET_TRAP_VECTOR .Lvec_unexpected
    csrr    t1, mcause
    li      t2, 28
    CHECK_EQ t1, t2, 10*\sect+2
    csrr    t1, mtval
    andi    t2, t1, 0x1F
    li      t0, (\mtval) & 0x1F
    CHECK_EQ t2, t0, 10*\sect+3
    li      t2, \mtval
    CHECK_EQ t1, t2, 10*\sect+4
    .word   0x03F0035B              # cspecialr       ct1, mepcc
    .word   0xFEF3035B              # cgetaddr        t1, ct1
    LA_FAR  t2, \pc, t0
    CHECK_EQ t1, t2, 10*\sect+5
    .word   0x03F0035B              # cspecialr       ct1, mepcc
    .word   0xFE43035B              # cgettag         t1, ct1
    li      t2, 1
    CHECK_EQ t1, t2, 10*\sect+6
.endm

# cra still holds the crt's return sentry (saved in ca5).
.macro CHECK_CRA_KEPT sect
    .word   0x42F0835B              # csetequalexact  t1, cra, ca5
    li      t2, 1
    CHECK_EQ t1, t2, 10*\sect+7
.endm

    .text
    .globl main

# Test-local trap vectors: no memory access, no CSR access, no mret.
    ALIGN4
.Lvec_unexpected:
    addi    a0, s0, 900
    j       .Lexit
    ALIGN4
.Lvec_s2:   j .Ls2_check
    ALIGN4
.Lvec_s3:   j .Ls3_check
    ALIGN4
.Lvec_s4:   j .Ls4_check
    ALIGN4
.Lvec_s5:   j .Ls5_check
    ALIGN4
.Lvec_s6:   j .Ls6_check
    ALIGN4
.Lvec_s7:   j .Ls7_check
    ALIGN4
.Lvec_s8:   j .Ls8_check
    ALIGN4
.Lvec_s9:   j .Ls9_check
    ALIGN4
.Lvec_s10:  j .Ls10_check
    ALIGN4
.Lvec_s11:  j .Ls11_check
    ALIGN4
.Lvec_s12:  j .Ls12_check
    ALIGN4
.Lvec_s13:  j .Ls13_check
    ALIGN4
.Lvec_s14:  j .Ls14_check
    ALIGN4
.Lvec_s15:  j .Ls15_check
    ALIGN4
.Lvec_s16:  j .Ls16_check
    ALIGN4
.Lvec_ctrl: j .Lctrl_trapped        # sections 17-19: a control trapped
    ALIGN4
.Lvec_s20:  j .Ls20_check

# Target of every CJALR that must fault. A sled, so that a wrongly taken
# jump with imm 4 (section 16) also lands in it.
    ALIGN4
.Ltgt:
    j       .Ltgt_hit
    j       .Ltgt_hit
.Ltgt_hit:
    addi    a0, s0, 500
    j       .Lexit

.Lctrl_trapped:
    slli    t0, s0, 3
    slli    a0, s0, 1
    add     a0, a0, t0              # 10k
    addi    a0, a0, 2               # 10k + 2
    j       .Lexit

    ALIGN4
main:
    csrsi   mstatus, 8              # set mstatus.MIE (bit 3)
    .word   0xFEA087DB              # cmove           ca5, cra
    li      s0, 0
    SET_TRAP_VECTOR .Lvec_unexpected

    # ── Tests 1-3: the three roots ───────────────────────────────────────────
    .word   0x03C0055B              # cspecialr       ca0, mtcc
    .word   0x03E0065B              # cspecialr       ca2, mscratchc
    .word   0x03D006DB              # cspecialr       ca3, mtdc
    .word   0xFE05035B              # cgetperm        t1, ca0
    li      t2, 0x1EB
    CHECK_EQ t1, t2, 1
    .word   0xFE06835B              # cgetperm        t1, ca3
    li      t2, 0x07F
    CHECK_EQ t1, t2, 2
    .word   0xFE06035B              # cgetperm        t1, ca2
    li      t2, 0x400               # SE (Permit_Seal)
    and     t1, t1, t2
    CHECK_EQ t1, t2, 3

    # ── Section 1: MTCC written without EX is stored untagged ────────────────
    li      s0, 1
    MK_DATA .Lvec_unexpected
    EXPECT_OPERAND 1, 0, 1
    LA_FAR  t0, .Lvec_unexpected, t1
    .word   0x03C5805B              # cspecialw       mtcc, ca1     MTCC <- no-EX capability
    .word   0x03C0075B              # cspecialr       ca4, mtcc
    .word   0xFE4703DB              # cgettag         t2, ca4
    .word   0xFEF7035B              # cgetaddr        t1, ca4
    .word   0x2055075B              # csetaddr        ca4, ca0, t0  restore a valid MTCC before any branch
    .word   0x03C7005B              # cspecialw       mtcc, ca4
    CHECK_EQ t2, zero, 12
    CHECK_EQ t1, t0, 13
    .word   0x03C0075B              # cspecialr       ca4, mtcc
    .word   0xFE47035B              # cgettag         t1, ca4
    li      t2, 1
    CHECK_EQ t1, t2, 14

    # ── Tests 4-6: interrupt state, before the first deliberate fault ────────
    csrr    t1, mstatus
    andi    t1, t1, 8
    li      t2, 8
    CHECK_EQ t1, t2, 4
    csrr    t1, mcause
    CHECK_EQ t1, zero, 5
    csrr    t1, mip
    CHECK_EQ t1, zero, 6

    # ── Section 2: untagged cs1 -> 0x02 ──────────────────────────────────────
    li      s0, 2
    SET_TRAP_VECTOR .Lvec_unexpected
    MK_EXEC .Ltgt
    EXPECT_OPERAND 1, 0, 2
    CLEAR_OPERAND_TAG 2
    SET_TRAP_VECTOR .Lvec_s2
.Ls2_cjalr:
    jalr    zero, 0(a1)
    li      a0, 29
    j       .Lexit
.Ls2_check:
    CHECK_CJALR_FAULT 0x162, .Ls2_cjalr, 2

    # ── Section 3: untagged AND sealed AND no EX -> 0x02 (tag first) ─────────
    li      s0, 3
    SET_TRAP_VECTOR .Lvec_unexpected
    MK_DATA .Ltgt
    SEAL    9
    EXPECT_OPERAND 1, 9, 3
    CLEAR_OPERAND_TAG 3
    SET_TRAP_VECTOR .Lvec_s3
.Ls3_cjalr:
    jalr    zero, 0(a1)
    li      a0, 39
    j       .Lexit
.Ls3_check:
    CHECK_CJALR_FAULT 0x162, .Ls3_cjalr, 3

    # ── Section 4: c.jr through untagged, no-EX cs1 -> 0x02 ──────────────────
    li      s0, 4
    SET_TRAP_VECTOR .Lvec_unexpected
    MK_DATA .Ltgt
    EXPECT_OPERAND 1, 0, 4
    CLEAR_OPERAND_TAG 4
    SET_TRAP_VECTOR .Lvec_s4
.Ls4_cjalr:
    .option rvc
    c.jr    a1
    .option norvc
    li      a0, 49
    j       .Lexit
.Ls4_check:
    CHECK_CJALR_FAULT 0x162, .Ls4_cjalr, 4

    # ── Section 5: data-sealed otype 9, no EX -> 0x03 (seal before EX) ───────
    li      s0, 5
    SET_TRAP_VECTOR .Lvec_unexpected
    MK_DATA .Ltgt
    SEAL    9
    EXPECT_OPERAND 1, 9, 5
    SET_TRAP_VECTOR .Lvec_s5
.Ls5_cjalr:
    jalr    zero, 0(a1)
    li      a0, 59
    j       .Lexit
.Ls5_check:
    CHECK_CJALR_FAULT 0x163, .Ls5_cjalr, 5

    # ── Section 6: data-sealed otype 15 -> 0x03 ──────────────────────────────
    li      s0, 6
    SET_TRAP_VECTOR .Lvec_unexpected
    MK_DATA .Ltgt
    SEAL    15
    EXPECT_OPERAND 1, 15, 6
    SET_TRAP_VECTOR .Lvec_s6
.Ls6_cjalr:
    jalr    zero, 0(a1)
    li      a0, 69
    j       .Lexit
.Ls6_check:
    CHECK_CJALR_FAULT 0x163, .Ls6_cjalr, 6

    # ── Section 7: executable sealed, non-sentry otype 6 -> 0x03 ─────────────
    li      s0, 7
    SET_TRAP_VECTOR .Lvec_unexpected
    MK_EXEC .Ltgt
    SEAL    6
    EXPECT_OPERAND 1, 6, 7
    SET_TRAP_VECTOR .Lvec_s7
.Ls7_cjalr:
    jalr    zero, 0(a1)
    li      a0, 79
    j       .Lexit
.Ls7_check:
    CHECK_CJALR_FAULT 0x163, .Ls7_cjalr, 7

    # ── Section 8: executable sealed otype 7 used for a call -> 0x03 ─────────
    li      s0, 8
    SET_TRAP_VECTOR .Lvec_unexpected
    MK_EXEC .Ltgt
    SEAL    7
    EXPECT_OPERAND 1, 7, 8
    SET_TRAP_VECTOR .Lvec_s8
.Ls8_cjalr:
    jalr    ra, 0(a1)
    li      a0, 89
    j       .Lexit
.Ls8_check:
    CHECK_CRA_KEPT 8
    CHECK_CJALR_FAULT 0x163, .Ls8_cjalr, 8

    # ── Section 9: tagged, unsealed, no EX -> 0x11 ───────────────────────────
    li      s0, 9
    SET_TRAP_VECTOR .Lvec_unexpected
    MK_DATA .Ltgt
    EXPECT_OPERAND 1, 0, 9
    SET_TRAP_VECTOR .Lvec_s9
.Ls9_cjalr:
    jalr    zero, 0(a1)
    li      a0, 99
    j       .Lexit
.Ls9_check:
    CHECK_CJALR_FAULT 0x171, .Ls9_cjalr, 9

    # ── Section 10: c.jalr through tagged, unsealed, no EX -> 0x11 ───────────
    li      s0, 10
    SET_TRAP_VECTOR .Lvec_unexpected
    MK_DATA .Ltgt
    EXPECT_OPERAND 1, 0, 10
    SET_TRAP_VECTOR .Lvec_s10
.Ls10_cjalr:
    .option rvc
    c.jalr  a1
    .option norvc
    li      a0, 109
    j       .Lexit
.Ls10_check:
    CHECK_CRA_KEPT 10
    CHECK_CJALR_FAULT 0x171, .Ls10_cjalr, 10

    # ── Section 11: backward sentry (4) used for a call -> 0x03 ──────────────
    li      s0, 11
    SET_TRAP_VECTOR .Lvec_unexpected
    MK_EXEC .Ltgt
    SEAL    4
    EXPECT_OPERAND 1, 4, 11
    SET_TRAP_VECTOR .Lvec_s11
.Ls11_cjalr:
    jalr    ra, 0(a1)
    li      a0, 119
    j       .Lexit
.Ls11_check:
    CHECK_CRA_KEPT 11
    CHECK_CJALR_FAULT 0x163, .Ls11_cjalr, 11

    # ── Section 12: backward sentry (5) used as a tail call -> 0x03 ──────────
    li      s0, 12
    SET_TRAP_VECTOR .Lvec_unexpected
    MK_EXEC .Ltgt
    SEAL    5
    EXPECT_OPERAND 1, 5, 12
    SET_TRAP_VECTOR .Lvec_s12
.Ls12_cjalr:
    jalr    zero, 0(a1)
    li      a0, 129
    j       .Lexit
.Ls12_check:
    CHECK_CJALR_FAULT 0x163, .Ls12_cjalr, 12

    # ── Section 13: forward sentry (2) with cd = ct1 -> 0x03 ─────────────────
    li      s0, 13
    SET_TRAP_VECTOR .Lvec_unexpected
    MK_EXEC .Ltgt
    SEAL    2
    EXPECT_OPERAND 1, 2, 13
    SET_TRAP_VECTOR .Lvec_s13
    li      t1, 0x5A5               # sentinel: a faulting CJALR must not write cd
.Ls13_cjalr:
    jalr    t1, 0(a1)
    li      a0, 139
    j       .Lexit
.Ls13_check:
    li      t2, 0x5A5
    CHECK_EQ t1, t2, 137
    CHECK_CJALR_FAULT 0x163, .Ls13_cjalr, 13

    # ── Section 14: return through a forward sentry (3) -> 0x03 vs cra ───────
    li      s0, 14
    SET_TRAP_VECTOR .Lvec_unexpected
    MK_EXEC .Ltgt
    SEAL    3
    EXPECT_OPERAND 1, 3, 14
    .word   0xFEA580DB              # cmove           cra, ca1
    SET_TRAP_VECTOR .Lvec_s14
.Ls14_cjalr:
    jalr    zero, 0(ra)
    li      a0, 149
    j       .Lexit
.Ls14_check:
    .word   0xFEA780DB              # cmove           cra, ca5      restore the crt's return sentry
    CHECK_CJALR_FAULT 0x023, .Ls14_cjalr, 14

    # ── Section 15: return through an UNSEALED cra -> 0x03 vs cra ────────────
    li      s0, 15
    SET_TRAP_VECTOR .Lvec_unexpected
    MK_EXEC .Ltgt
    EXPECT_OPERAND 1, 0, 15
    .word   0xFEA580DB              # cmove           cra, ca1
    SET_TRAP_VECTOR .Lvec_s15
.Ls15_cjalr:
    jalr    zero, 0(ra)
    li      a0, 159
    j       .Lexit
.Ls15_check:
    .word   0xFEA780DB              # cmove           cra, ca5      restore the crt's return sentry
    CHECK_CJALR_FAULT 0x023, .Ls15_cjalr, 15

    # ── Section 16: sealed (otype 1) with imm = 4 -> 0x03 ────────────────────
    li      s0, 16
    SET_TRAP_VECTOR .Lvec_unexpected
    MK_EXEC .Ltgt
    SEAL    1
    EXPECT_OPERAND 1, 1, 16
    SET_TRAP_VECTOR .Lvec_s16
.Ls16_cjalr:
    jalr    zero, 4(a1)
    li      a0, 169
    j       .Lexit
.Ls16_check:
    CHECK_CJALR_FAULT 0x163, .Ls16_cjalr, 16

    # ── Section 17 (control): otype 1 sentry, cd = ct1 is permitted ──────────
    li      s0, 17
    SET_TRAP_VECTOR .Lvec_unexpected
    MK_EXEC .Ls17_tgt
    SEAL    1
    EXPECT_OPERAND 1, 1, 17
    SET_TRAP_VECTOR .Lvec_ctrl
.Ls17_cjalr:
    jalr    t1, 0(a1)
    li      a0, 179
    j       .Lexit
.Ls17_tgt:
    .word   0xFE4303DB              # cgettag         t2, ct1
    li      t0, 1
    CHECK_EQ t2, t0, 173
    .word   0xFE1303DB              # cgettype        t2, ct1
    CHECK_EQ t2, zero, 174
    .word   0xFEF303DB              # cgetaddr        t2, ct1
    LA_FAR  t0, .Ls17_cjalr+4, t1
    CHECK_EQ t2, t0, 175

    # ── Section 18 (control): unsealed with imm = 4 is permitted ─────────────
    li      s0, 18
    SET_TRAP_VECTOR .Lvec_unexpected
    MK_EXEC .Ls18_tgt
    EXPECT_OPERAND 1, 0, 18
    SET_TRAP_VECTOR .Lvec_ctrl
.Ls18_cjalr:
    jalr    zero, 4(a1)
.Ls18_tgt:
    j       .Ls18_noimm             # target + 0 (or fell through)
    j       .Ls18_ok                # target + 4
.Ls18_noimm:
    li      a0, 183
    j       .Lexit
.Ls18_ok:

    # ── Section 19 (control): otype 1 sentry, cd = c0, imm = 0 permitted ─────
    li      s0, 19
    SET_TRAP_VECTOR .Lvec_unexpected
    MK_EXEC .Ls19_tgt
    SEAL    1
    EXPECT_OPERAND 1, 1, 19
    SET_TRAP_VECTOR .Lvec_ctrl
.Ls19_cjalr:
    jalr    zero, 0(a1)
    li      a0, 199
    j       .Lexit
.Ls19_tgt:

    # ── Section 20: MEPCC written without EX; MRET faults with 0x02 on PCC ───
    li      s0, 20
    SET_TRAP_VECTOR .Lvec_unexpected
    MK_DATA .Ltgt
    .word   0x03F5805B              # cspecialw       mepcc, ca1    MEPCC <- no-EX capability
    .word   0x03F0075B              # cspecialr       ca4, mepcc
    .word   0xFE47035B              # cgettag         t1, ca4
    CHECK_EQ t1, zero, 200
    .word   0xFEF7035B              # cgetaddr        t1, ca4
    LA_FAR  t2, .Ltgt, t0
    CHECK_EQ t1, t2, 201
    li      t0, 0x1800              # mstatus.MPP = M
    csrs    mstatus, t0
    li      t0, 0x80                # mstatus.MPIE = 0: MIE stays 0 after mret
    csrc    mstatus, t0
    SET_TRAP_VECTOR .Lvec_s20
    mret
    li      a0, 209
    j       .Lexit
.Ls20_check:
    SET_TRAP_VECTOR .Lvec_unexpected
    csrr    t1, mcause
    li      t2, 28
    CHECK_EQ t1, t2, 202
    csrr    t1, mtval
    andi    t2, t1, 0x1F
    li      t0, 0x02
    CHECK_EQ t2, t0, 203
    li      t2, 0x402
    CHECK_EQ t1, t2, 204
    .word   0x03F0035B              # cspecialr       ct1, mepcc
    .word   0xFEF3035B              # cgetaddr        t1, ct1
    LA_FAR  t2, .Ltgt, t0
    CHECK_EQ t1, t2, 205
    .word   0x03F0035B              # cspecialr       ct1, mepcc
    .word   0xFE43035B              # cgettag         t1, ct1
    CHECK_EQ t1, zero, 206

    # ── Tests 7-8: final interrupt state ─────────────────────────────────────
    csrr    t1, mip
    CHECK_EQ t1, zero, 7
    csrr    t1, mcause
    li      t2, 28
    CHECK_EQ t1, t2, 8

    li      a0, 0
.Lexit:
    .word   0xFEA780DB              # cmove           cra, ca5      the crt's return sentry
    jalr    zero, 0(ra)
