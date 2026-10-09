# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_scr_faults -- system-register access without PCC.SR
# =============================================================================
# REQ_PER_06, REQ_SCR_01, REQ_EXC_04. Expected values come from CHERIoT-Sail:
#   cheri_insts.sail  CSpecialRW: an SCR number other than 28-31 -> handle_illegal
#       (mcause 2) FIRST; then, if PCC lacks SR ->
#       handle_cheri_cap_exception(CapEx_AccessSystemRegsViolation, 0b1 @ scr),
#       i.e. mtval = ((0x20 + scr) << 5) | 0x18, and nothing is written (cd nor SCR).
#   sail-riscv riscv_insts_zicsr.sail CSR: check_CSR (CSR defined, not a write
#       to a read-only CSR, privilege) -> handle_illegal FIRST; then
#       ext_check_CSR (cheri_addr_checks.sail): without SR only READS of 0xB00
#       mcycle, 0xB02 minstret, 0xB80 mcycleh, 0xB82 minstreth (and the 0xC0x/0xC8x
#       user counters) pass; anything else -> handle_cheri_pcc_exception(0x18),
#       mtval = (0x20 << 5) | 0x18 = 0x418. "Write" is decided by the encoding,
#       not the value: CSRRS/CSRRC with rs1 != x0 is a write even if rs1 holds 0;
#       CSRRSI/CSRRCI with uimm = 0 is a read.
#   riscv_insts_base.sail MRET: ext_check_xret_priv = PCC.SR, else
#       handle_cheri_pcc_exception(0x18) -> mtval 0x418.
#   cheri_sys_exceptions.sail handle_trap_extension: MEPCC = PCC with the
#       faulting address, so MEPCC carries the SR-less permissions.
# The user counters cycle/time/instret (0xC00-0xC82) are deliberately not read:
# in CHERIoT-Sail they are only defined when misa.U = 1 (is_CSR_defined:
# haveUsrMode()), and the cosim model runs with misa.U = 0, so there a read is an
# illegal instruction, while ibex (ibex_decoder.sv csr_cheriot_always_ok_o) reads
# the whole 0xC00-0xC9F block without SR.
#
# Running without SR: ca0 = CAndPerm(MTCC, 0xF7F) = 0x16B (executable format
# keeps SR/LM/LG individually, so exactly SR is removed -- test 1 checks it).
# Each probe sets MTCC to its own test-local vector (MTCC keeps SR), points a copy
# of ca0 at the probe and jumps to it with CJALR (cd = c0, unsealed: permitted).
# The fault returns through MTCC, which restores SR; RESUME then leaves the trap
# with mret through an MTCC-derived MEPCC, which clears sync_exc_seen and restores
# mstatus.MIE. Region A has no fault: it returns to SR code through ca3, an
# MTCC-derived capability.
#
# Checks and failure codes (main returns 0 or the first failing code)
# ------------------------------------------------------------------
#   1  CGetPerm(ca0) = 0x16B      2  CGetTag(ca0) = 1
#   3  control: CSpecialR MTDC with SR gives a tagged capability
#   4  control: mscratch write/read with SR
#   Region A, without SR, no trap expected (5 = it trapped):
#   6  AUIPCC there has perms 0x16B (the region really runs without SR)
#   7-10 csrr mcycle / minstret / mcycleh / minstreth wrote rd
#   11 csrrsi rd, mcycle, 0 wrote rd (a read)    36 csrrci rd, minstret, 0 wrote rd
#   12 back in SR code: AUIPCC perms 0x1EB again
#   Faulting probes, each: [no trap] [mcause != 28] [mtval] [MEPCC.address] [side effect]
#   13-16  csrr mstatus                      0x418           87: MEPCC perms != 0x16B
#   17-21  csrw mscratch                     0x418   mscratch unchanged
#   22-26  csrw mcycle                       0x418   mcycle not loaded with 0x7FFFFFF0
#   27-31  csrrs rd, mcycle, t0 (t0 = 0)     0x418   rd unchanged
#   32-35  mret                              0x418   (32 also if mret jumped to MEPCC)
#   37-41  cspecialr ca4, mtdc               0x7B8   ca4 unchanged
#   42-46  cspecialw mscratchc, ca0          0x7D8   MScratchC perms still 0xE01
#   47-52  cspecialrw ca4, mtcc, ca0         0x798   ca4 unchanged (51), MTCC address
#          still the probe's vector (52)
#   53-57  cspecialr ca4, mepcc              0x7F8   ca4 unchanged
#   Illegal instruction (mcause 2) takes priority over the SR check -- [no trap]
#   [mcause != 2] [MEPCC.address] [ca4 unchanged]:
#   58-61  cspecialr ca4, SCR 1   without SR
#   62-65  cspecialr ca4, SCR 24  without SR (DEPCC: debug-mode only in ibex)
#   66-69  cspecialr ca4, SCR 27  without SR (ZTOPC: not a CHERIoT-Sail SCR)
#   70-72  cspecialr ca4, SCR 1   with SR (control: illegal regardless)
#   73-75  csrr t1, 0x7FF (undefined CSR)            without SR
#   76-78  csrw mhartid, t0 (write to read-only CSR)  without SR
#   79-81  before the first trap: mstatus.MIE = 1, mcause = 0, mip = 0
#   82/83  after the last mret: mstatus.MIE = 1, mip = 0
#   84/85/86  unexpected trap in setup / a post-trap check / the final checks
#
# Conventions as in cheriot_perm_lc_sc: test-local MTCC vectors (no memory or
# CSR access, no mret), integer scratch t0/t1/t2/s0 only, ca0-ca5 never an
# integer destination while live, no x16-x31, CHERI instructions .word-encoded
# from the Sail encdec clauses (cross-checked against cheriot_perm_lc_sc).

    .option norelax

# \rd <- address of \sym at any distance. GNU `la` is AUIPC + ADDI with %pcrel_hi
# computed for imm << 12, but in capability mode that encoding is AUIPCC, which
# shifts by 11 (cheri_insts.sail AUIPCC: sign_extend(imm) << 11), so `la` is
# only right within about +-2 KiB. AUIPCC 0 is the same under either shift; the
# distance comes from absolute symbol values. As LA_FAR in cheriot_dv.h (not
# included here: its RESUME takes different arguments). \rd and \tmp must differ.
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

# Clobbers t0 and c6 (t1).
.macro SET_TRAP_VECTOR label
    LA_FAR  t0, \label, t1
    .word   0x03C0035B              # cspecialr c6, mtcc
    .word   0x2053035B              # csetaddr c6, c6, t0
    .word   0x03C3005B              # cspecialw mtcc, c6
.endm

.macro RESUME label
    LA_FAR  t0, \label, t1
    .word   0x03C0035B              # cspecialr c6, mtcc
    .word   0x2053035B              # csetaddr c6, c6, t0
    .word   0x03F3005B              # cspecialw mepcc, c6
    mret
.endm

# Jump to label with PCC = ca0 (no SR). Clobbers t0, ca1.
.macro ENTER_NOSR label
    LA_FAR  t0, \label, a1
    .word   0x205505DB              # csetaddr ca1, ca0, t0
    jalr    zero, 0(a1)
.endm

# mcause / mtval / MEPCC.address after a deliberate CHERI fault.
.macro CHERI_FAULT mtval, pc, c_cause, c_tval, c_pc
    csrr    t1, mcause
    li      t2, 28
    bne     t1, t2, .Lfail_\c_cause
    csrr    t1, mtval
    li      t2, \mtval
    bne     t1, t2, .Lfail_\c_tval
    .word   0x03F0035B              # cspecialr ct1, mepcc
    .word   0xFEF3035B              # cgetaddr t1, ct1
    LA_FAR  t2, \pc, t0
    bne     t1, t2, .Lfail_\c_pc
.endm

# mcause = 2 and MEPCC.address after a deliberate illegal instruction.
.macro ILLEGAL pc, c_cause, c_pc
    csrr    t1, mcause
    li      t2, 2
    bne     t1, t2, .Lfail_\c_cause
    .word   0x03F0035B              # cspecialr ct1, mepcc
    .word   0xFEF3035B              # cgetaddr t1, ct1
    LA_FAR  t2, \pc, t0
    bne     t1, t2, .Lfail_\c_pc
.endm

# ca4 still holds the integer 0x1234 it was given (tag 0).
.macro CA4_UNTOUCHED code
    .word   0xFE47035B              # cgettag t1, ca4
    bnez    t1, .Lfail_\code
    .word   0xFEF7035B              # cgetaddr t1, ca4
    li      t2, 0x1234
    bne     t1, t2, .Lfail_\code
.endm

    .text
    .globl main

.balign 4
.Lvec_setup:    j .Lfail_84
.balign 4
.Lvec_post:     j .Lfail_85
.balign 4
.Lvec_final:    j .Lfail_86
.balign 4
.Lvec_regionA:  j .Lfail_5
.balign 4
.Lvec_p1:       j .Ltrap_p1
.balign 4
.Lvec_p2:       j .Ltrap_p2
.balign 4
.Lvec_p3:       j .Ltrap_p3
.balign 4
.Lvec_p4:       j .Ltrap_p4
.balign 4
.Lvec_p5:       j .Ltrap_p5
.balign 4
.Lvec_p6:       j .Ltrap_p6
.balign 4
.Lvec_p7:       j .Ltrap_p7
.balign 4
.Lvec_p8:       j .Ltrap_p8
.balign 4
.Lvec_p9:       j .Ltrap_p9
.balign 4
.Lvec_p10:      j .Ltrap_p10
.balign 4
.Lvec_p11:      j .Ltrap_p11
.balign 4
.Lvec_p12:      j .Ltrap_p12
.balign 4
.Lvec_p13:      j .Ltrap_p13
.balign 4
.Lvec_p14:      j .Ltrap_p14
.balign 4
.Lvec_p15:      j .Ltrap_p15
.balign 4
.Lmret_escaped: j .Lfail_32         # MEPCC target for probe 5: mret must not get here

main:
    csrsi   mstatus, 8              # set mstatus.MIE (bit 3)
    SET_TRAP_VECTOR .Lvec_setup

    # ── Tests 1-4: setup and controls with SR ────────────────────────────────
    .word   0x03C0055B              # cspecialr ca0, mtcc
    li      t0, 0xF7F               # clear SR (bit 7)
    .word   0x1A55055B              # candperm ca0, ca0, t0
    .word   0xFE05035B              # cgetperm t1, ca0
    li      t2, 0x16B
    bne     t1, t2, .Lfail_1
    .word   0xFE45035B              # cgettag t1, ca0
    li      t2, 1
    bne     t1, t2, .Lfail_2
    .word   0x03D0075B              # cspecialr ca4, mtdc
    .word   0xFE47035B              # cgettag t1, ca4
    li      t2, 1
    bne     t1, t2, .Lfail_3
    li      t2, 0x5A5A5A5A
    csrw    mscratch, t2
    csrr    t1, mscratch
    bne     t1, t2, .Lfail_4

    # ── Tests 5-12: region A, no SR, nothing may trap ────────────────────────
    SET_TRAP_VECTOR .Lvec_regionA
    LA_FAR  t0, .LbackA, t1
    .word   0x03C006DB              # cspecialr ca3, mtcc
    .word   0x205686DB              # csetaddr ca3, ca3, t0  way back, with SR
    ENTER_NOSR .LregionA
.LregionA:
    .word   0x00000617              # auipcc ca2, 0
    .word   0xFE06035B              # cgetperm t1, ca2
    li      t2, 0x16B
    bne     t1, t2, .Lfail_6
    li      t2, 0xDEADBEEF
    mv      t1, t2
    csrr    t1, mcycle
    beq     t1, t2, .Lfail_7
    mv      t1, t2
    csrr    t1, minstret
    beq     t1, t2, .Lfail_8
    mv      t1, t2
    csrr    t1, mcycleh
    beq     t1, t2, .Lfail_9
    mv      t1, t2
    csrr    t1, minstreth
    beq     t1, t2, .Lfail_10
    mv      t1, t2
    csrrsi  t1, mcycle, 0
    beq     t1, t2, .Lfail_11
    mv      t1, t2
    csrrci  t1, minstret, 0
    beq     t1, t2, .Lfail_36
    jalr    zero, 0(a3)             # back to SR code
.LbackA:
    .word   0x00000617              # auipcc ca2, 0
    .word   0xFE06035B              # cgetperm t1, ca2
    li      t2, 0x1EB
    bne     t1, t2, .Lfail_12

    # ── Tests 79-81: interrupt state before the first deliberate trap ────────
    csrr    t1, mstatus
    andi    t1, t1, 8
    beqz    t1, .Lfail_79
    csrr    t1, mcause
    bnez    t1, .Lfail_80
    csrr    t1, mip
    bnez    t1, .Lfail_81

    # ── Tests 13-16, 87: csrr mstatus without SR ─────────────────────────────
    SET_TRAP_VECTOR .Lvec_p1
    ENTER_NOSR .Lfault_p1
.Lfault_p1:
    csrr    t1, mstatus
    j       .Lfail_13
.Ltrap_p1:
    SET_TRAP_VECTOR .Lvec_post
    CHERI_FAULT 0x418, .Lfault_p1, 14, 15, 16
    .word   0x03F0035B              # cspecialr ct1, mepcc
    .word   0xFE03035B              # cgetperm t1, ct1
    li      t2, 0x16B
    bne     t1, t2, .Lfail_87
    RESUME  .Lnext_p2
.Lnext_p2:

    # ── Tests 17-21: csrw mscratch without SR ────────────────────────────────
    SET_TRAP_VECTOR .Lvec_p2
    li      t2, 0xA5A5A5A5
    ENTER_NOSR .Lfault_p2
.Lfault_p2:
    csrw    mscratch, t2
    j       .Lfail_17
.Ltrap_p2:
    SET_TRAP_VECTOR .Lvec_post
    CHERI_FAULT 0x418, .Lfault_p2, 18, 19, 20
    csrr    t1, mscratch
    li      t2, 0x5A5A5A5A
    bne     t1, t2, .Lfail_21
    RESUME  .Lnext_p3
.Lnext_p3:

    # ── Tests 22-26: csrw mcycle without SR (the allow-list is read-only) ────
    SET_TRAP_VECTOR .Lvec_p3
    li      t2, 0x7FFFFFF0
    ENTER_NOSR .Lfault_p3
.Lfault_p3:
    csrw    mcycle, t2
    j       .Lfail_22
.Ltrap_p3:
    SET_TRAP_VECTOR .Lvec_post
    CHERI_FAULT 0x418, .Lfault_p3, 23, 24, 25
    csrr    t1, mcycle
    li      t2, 0x40000000
    bgeu    t1, t2, .Lfail_26
    RESUME  .Lnext_p4
.Lnext_p4:

    # ── Tests 27-31: csrrs rd, mcycle, t0 with t0 = 0 is a write ─────────────
    SET_TRAP_VECTOR .Lvec_p4
    li      s0, 0xDEADBEEF
    ENTER_NOSR .Lfault_p4
.Lfault_p4:
    li      t0, 0                   # value 0, but rs1 = x5, not x0
.Lfault_p4_csr:
    csrrs   s0, mcycle, t0
    j       .Lfail_27
.Ltrap_p4:
    SET_TRAP_VECTOR .Lvec_post
    CHERI_FAULT 0x418, .Lfault_p4_csr, 28, 29, 30
    li      t2, 0xDEADBEEF
    bne     s0, t2, .Lfail_31
    RESUME  .Lnext_p5
.Lnext_p5:

    # ── Tests 32-35: mret without SR ─────────────────────────────────────────
    SET_TRAP_VECTOR .Lvec_p5
    LA_FAR  t0, .Lmret_escaped, t1
    .word   0x03C0035B              # cspecialr c6, mtcc
    .word   0x2053035B              # csetaddr c6, c6, t0
    .word   0x03F3005B              # cspecialw mepcc, c6  where a wrongly executed mret would go
    ENTER_NOSR .Lfault_p5
.Lfault_p5:
    mret
    j       .Lfail_32
.Ltrap_p5:
    SET_TRAP_VECTOR .Lvec_post
    CHERI_FAULT 0x418, .Lfault_p5, 33, 34, 35
    RESUME  .Lnext_p6
.Lnext_p6:

    # ── Tests 37-41: CSpecialR MTDC without SR ───────────────────────────────
    SET_TRAP_VECTOR .Lvec_p6
    li      a4, 0x1234              # ca4 := integer 0x1234, tag 0
    ENTER_NOSR .Lfault_p6
.Lfault_p6:
    .word   0x03D0075B              # cspecialr ca4, mtdc
    j       .Lfail_37
.Ltrap_p6:
    SET_TRAP_VECTOR .Lvec_post
    CHERI_FAULT 0x7B8, .Lfault_p6, 38, 39, 40
    CA4_UNTOUCHED 41
    RESUME  .Lnext_p7
.Lnext_p7:

    # ── Tests 42-46: CSpecialW MScratchC without SR ──────────────────────────
    SET_TRAP_VECTOR .Lvec_p7
    ENTER_NOSR .Lfault_p7
.Lfault_p7:
    .word   0x03E5005B              # cspecialw mscratchc, ca0
    j       .Lfail_42
.Ltrap_p7:
    SET_TRAP_VECTOR .Lvec_post
    CHERI_FAULT 0x7D8, .Lfault_p7, 43, 44, 45
    .word   0x03E0065B              # cspecialr ca2, mscratchc
    .word   0xFE06035B              # cgetperm t1, ca2
    li      t2, 0xE01
    bne     t1, t2, .Lfail_46
    RESUME  .Lnext_p8
.Lnext_p8:

    # ── Tests 47-52: CSpecialRW MTCC without SR ──────────────────────────────
    SET_TRAP_VECTOR .Lvec_p8
    li      a4, 0x1234
    ENTER_NOSR .Lfault_p8
.Lfault_p8:
    .word   0x03C5075B              # cspecialrw ca4, mtcc, ca0
    j       .Lfail_47
.Ltrap_p8:
    .word   0x03C0035B              # cspecialr ct1, mtcc  before SET_TRAP_VECTOR overwrites it
    .word   0xFEF3045B              # cgetaddr s0, ct1
    SET_TRAP_VECTOR .Lvec_post
    CHERI_FAULT 0x798, .Lfault_p8, 48, 49, 50
    CA4_UNTOUCHED 51
    LA_FAR  t2, .Lvec_p8, t0
    bne     s0, t2, .Lfail_52
    RESUME  .Lnext_p9
.Lnext_p9:

    # ── Tests 53-57: CSpecialR MEPCC without SR ──────────────────────────────
    SET_TRAP_VECTOR .Lvec_p9
    li      a4, 0x1234
    ENTER_NOSR .Lfault_p9
.Lfault_p9:
    .word   0x03F0075B              # cspecialr ca4, mepcc
    j       .Lfail_53
.Ltrap_p9:
    SET_TRAP_VECTOR .Lvec_post
    CHERI_FAULT 0x7F8, .Lfault_p9, 54, 55, 56
    CA4_UNTOUCHED 57
    RESUME  .Lnext_p10
.Lnext_p10:

    # ── Tests 58-61: undefined SCR 1 without SR -> illegal, not 0x18 ─────────
    SET_TRAP_VECTOR .Lvec_p10
    li      a4, 0x1234
    ENTER_NOSR .Lfault_p10
.Lfault_p10:
    .word   0x0210075B              # cspecialr ca4, 1
    j       .Lfail_58
.Ltrap_p10:
    SET_TRAP_VECTOR .Lvec_post
    ILLEGAL .Lfault_p10, 59, 60
    CA4_UNTOUCHED 61
    RESUME  .Lnext_p11
.Lnext_p11:

    # ── Tests 62-65: SCR 24 without SR ───────────────────────────────────────
    SET_TRAP_VECTOR .Lvec_p11
    li      a4, 0x1234
    ENTER_NOSR .Lfault_p11
.Lfault_p11:
    .word   0x0380075B              # cspecialr ca4, 24
    j       .Lfail_62
.Ltrap_p11:
    SET_TRAP_VECTOR .Lvec_post
    ILLEGAL .Lfault_p11, 63, 64
    CA4_UNTOUCHED 65
    RESUME  .Lnext_p12
.Lnext_p12:

    # ── Tests 66-69: SCR 27 without SR ───────────────────────────────────────
    SET_TRAP_VECTOR .Lvec_p12
    li      a4, 0x1234
    ENTER_NOSR .Lfault_p12
.Lfault_p12:
    .word   0x03B0075B              # cspecialr ca4, 27
    j       .Lfail_66
.Ltrap_p12:
    SET_TRAP_VECTOR .Lvec_post
    ILLEGAL .Lfault_p12, 67, 68
    CA4_UNTOUCHED 69
    RESUME  .Lnext_p13
.Lnext_p13:

    # ── Tests 70-72: SCR 1 with SR (control) ─────────────────────────────────
    SET_TRAP_VECTOR .Lvec_p13
.Lfault_p13:
    .word   0x0210075B              # cspecialr ca4, 1
    j       .Lfail_70
.Ltrap_p13:
    SET_TRAP_VECTOR .Lvec_post
    ILLEGAL .Lfault_p13, 71, 72
    RESUME  .Lnext_p14
.Lnext_p14:

    # ── Tests 73-75: undefined CSR 0x7FF without SR ──────────────────────────
    SET_TRAP_VECTOR .Lvec_p14
    ENTER_NOSR .Lfault_p14
.Lfault_p14:
    csrr    t1, 0x7FF
    j       .Lfail_73
.Ltrap_p14:
    SET_TRAP_VECTOR .Lvec_post
    ILLEGAL .Lfault_p14, 74, 75
    RESUME  .Lnext_p15
.Lnext_p15:

    # ── Tests 76-78: write to read-only mhartid without SR ───────────────────
    SET_TRAP_VECTOR .Lvec_p15
    li      t2, 0x55
    ENTER_NOSR .Lfault_p15
.Lfault_p15:
    csrw    mhartid, t2
    j       .Lfail_76
.Ltrap_p15:
    SET_TRAP_VECTOR .Lvec_post
    ILLEGAL .Lfault_p15, 77, 78
    RESUME  .Lnext_end
.Lnext_end:

    # ── Tests 82-83: interrupt state after the last mret ─────────────────────
    SET_TRAP_VECTOR .Lvec_final
    csrr    t1, mstatus
    andi    t1, t1, 8
    beqz    t1, .Lfail_82
    csrr    t1, mip
    bnez    t1, .Lfail_83

    li      a0, 0
    ret

.Lfail_1:   li a0, 1; ret
.Lfail_2:   li a0, 2; ret
.Lfail_3:   li a0, 3; ret
.Lfail_4:   li a0, 4; ret
.Lfail_5:   li a0, 5; ret
.Lfail_6:   li a0, 6; ret
.Lfail_7:   li a0, 7; ret
.Lfail_8:   li a0, 8; ret
.Lfail_9:   li a0, 9; ret
.Lfail_10:  li a0, 10; ret
.Lfail_11:  li a0, 11; ret
.Lfail_12:  li a0, 12; ret
.Lfail_13:  li a0, 13; ret
.Lfail_14:  li a0, 14; ret
.Lfail_15:  li a0, 15; ret
.Lfail_16:  li a0, 16; ret
.Lfail_17:  li a0, 17; ret
.Lfail_18:  li a0, 18; ret
.Lfail_19:  li a0, 19; ret
.Lfail_20:  li a0, 20; ret
.Lfail_21:  li a0, 21; ret
.Lfail_22:  li a0, 22; ret
.Lfail_23:  li a0, 23; ret
.Lfail_24:  li a0, 24; ret
.Lfail_25:  li a0, 25; ret
.Lfail_26:  li a0, 26; ret
.Lfail_27:  li a0, 27; ret
.Lfail_28:  li a0, 28; ret
.Lfail_29:  li a0, 29; ret
.Lfail_30:  li a0, 30; ret
.Lfail_31:  li a0, 31; ret
.Lfail_32:  li a0, 32; ret
.Lfail_33:  li a0, 33; ret
.Lfail_34:  li a0, 34; ret
.Lfail_35:  li a0, 35; ret
.Lfail_36:  li a0, 36; ret
.Lfail_37:  li a0, 37; ret
.Lfail_38:  li a0, 38; ret
.Lfail_39:  li a0, 39; ret
.Lfail_40:  li a0, 40; ret
.Lfail_41:  li a0, 41; ret
.Lfail_42:  li a0, 42; ret
.Lfail_43:  li a0, 43; ret
.Lfail_44:  li a0, 44; ret
.Lfail_45:  li a0, 45; ret
.Lfail_46:  li a0, 46; ret
.Lfail_47:  li a0, 47; ret
.Lfail_48:  li a0, 48; ret
.Lfail_49:  li a0, 49; ret
.Lfail_50:  li a0, 50; ret
.Lfail_51:  li a0, 51; ret
.Lfail_52:  li a0, 52; ret
.Lfail_53:  li a0, 53; ret
.Lfail_54:  li a0, 54; ret
.Lfail_55:  li a0, 55; ret
.Lfail_56:  li a0, 56; ret
.Lfail_57:  li a0, 57; ret
.Lfail_58:  li a0, 58; ret
.Lfail_59:  li a0, 59; ret
.Lfail_60:  li a0, 60; ret
.Lfail_61:  li a0, 61; ret
.Lfail_62:  li a0, 62; ret
.Lfail_63:  li a0, 63; ret
.Lfail_64:  li a0, 64; ret
.Lfail_65:  li a0, 65; ret
.Lfail_66:  li a0, 66; ret
.Lfail_67:  li a0, 67; ret
.Lfail_68:  li a0, 68; ret
.Lfail_69:  li a0, 69; ret
.Lfail_70:  li a0, 70; ret
.Lfail_71:  li a0, 71; ret
.Lfail_72:  li a0, 72; ret
.Lfail_73:  li a0, 73; ret
.Lfail_74:  li a0, 74; ret
.Lfail_75:  li a0, 75; ret
.Lfail_76:  li a0, 76; ret
.Lfail_77:  li a0, 77; ret
.Lfail_78:  li a0, 78; ret
.Lfail_79:  li a0, 79; ret
.Lfail_80:  li a0, 80; ret
.Lfail_81:  li a0, 81; ret
.Lfail_82:  li a0, 82; ret
.Lfail_83:  li a0, 83; ret
.Lfail_84:  li a0, 84; ret
.Lfail_85:  li a0, 85; ret
.Lfail_86:  li a0, 86; ret
.Lfail_87:  li a0, 87; ret
