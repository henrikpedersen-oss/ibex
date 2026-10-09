# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_fetch_bounds — PCC bounds are enforced at instruction fetch
# =============================================================================
# REQ_BND_03, REQ_BND_07, REQ_BRA_05, REQ_BRA_08, REQ_CFI_05.
#
# What CHERIoT-Sail says (all expected values below come from here):
#   fetch() (sail-riscv/model/riscv_fetch.sail) calls ext_fetch_check_pc(PC, PC)
#   for the first 16-bit granule and, if the instruction is not compressed,
#   ext_fetch_check_pc(PC, PC + 2) for the second. Both check
#   inCapBounds(PCC, pc, 2), i.e. PCC.base <= pc and pc + 2 <= PCC.top
#   (cheri_addr_checks.sail). A failure is F_Ext_Error(CapEx_BoundsViolation);
#   ext_handle_fetch_check_error clears PCC.tag and calls
#   handle_cheri_pcc_exception, which raises mcause 28 with
#   mtval = (0b100000 @ 0x01) = 0x401 and uses PC -- the address of the
#   instruction, not PC + 2 -- as the trapping PC. handle_trap_extension sets
#   MEPCC = setCapAddr(PCC, PC), so MEPCC.address = that PC and MEPCC.tag = 0.
#   Nothing is executed: the step retires with RETIRE_FAIL before decode.
#   Branches, CJAL and CJALR do no bounds check on the target
#   (ext_control_check_pc / ext_control_check_addr return OK for every
#   address, see the CJAL and CJALR notes in cheri_insts.sail); they retire,
#   and the fault comes from the fetch of the target. CJALR installs
#   PCC = unsealCap(cs1) with cs1's bounds, whatever cs1.address is. MRET
#   installs PCC = MEPCC (prepare_xret_target), again without a bounds check.
#
# Construction
# ------------
# Each section builds a bounded execute capability over a small code region
# in .text: CSetAddr(MTCC-copy, base) then CSetBoundsExact(len = top - base).
# Regions are 4-12 bytes, far below the 511-byte limit up to which CHERIoT
# bounds are byte-exact, and CSetBoundsExact clears the tag if they were not,
# so a tag check plus a CGetTop check prove the region is exactly [base, top).
# The region is entered with CJALR (cd = c0, cs1 = ca1: an unsealed cs1 is
# permitted for a non-return, non-call register pair) or, in section 10, MRET.
# Every region instruction bumps s0 by a distinct power of two, so s0 in the
# handler says exactly which instructions ran: in-bounds ones must have run
# (liveness), the out-of-bounds one must not.
# Placement inside a region is controlled with .option norvc (all 32-bit) and
# explicit c.addi under .option rvc, and every label a check depends on is
# confirmed by the disassembly. .option norelax keeps the linker from
# changing any of it. ALIGN4 enables RVC around .balign because GAS silently
# skips a 2-byte .balign under norvc.
#
# Trap handling and recovery
# --------------------------
# A fetch fault leaves PCC and MEPCC untagged, so the faulting context can
# never be resumed. The test does not try: a trap installs PCC := MTCC, and
# MTCC always holds a tagged, unsealed, full-bounds execute capability (the
# crt's MTCC with only its address moved by SET_TRAP_VECTOR) pointing at a
# test-local 4-byte-aligned vector. The vector runs under that valid PCC and
# jumps to the section's check code in main, which is inside MTCC's bounds.
# No handler executes mret; the untagged MEPCC is only read (CSpecialR +
# CGetAddr/CGetTag). The only mret in the test (section 10) is itself the
# stimulus. main returns through cra, the crt's backward sentry, which this
# test never writes. mstatus.MIE is clear after the first trap, so the
# interrupt-state checks run before the first deliberate fault; at the end mip
# must still be 0 and mcause must still be the CHERI fault.
#
# Each section first points MTCC at .Lvec_unexpected with s0 = section number,
# so a trap during a section's setup returns 900 + section. The check code
# re-arms .Lvec_unexpected before its own CSR reads. Section 12 also re-arms it
# with s0 = 12 before each block copy, so a trap during a copy is 912 and not
# the previous case's code through its .Lvec_br.
#
# What a landed case in sections 11 and 12 proves: BR_LANDED checks only that
# no trap happened, i.e. that some c.jr a3 landing pad ran; it does not record
# which. Regions and blocks hold several cases' branches and pads, so a c.beqz
# that was not taken would fall into the next slot, possibly another case's
# branch or pad, and still pass. The condition is a4 = 0 (a not-taken c.beqz
# would be an RTL defect in itself) and every unused slot is c.ebreak; the gap
# is only that the target of a taken branch is not confirmed. Recording the
# pad (c.li t1, n; c.jr a3) needs 4 bytes, which the 2..7-byte PCCs cannot
# hold next to their branch, so it is not done (gen_branch_bounds.py).
# Faulting cases check MEPCC.address = the target and are not affected.
#
# How each check can fail (section k uses codes 20k .. 20k+13)
# ------------------------------------------------------------
#   1-3     Before the first fault: mstatus.MIE = 1, mcause = 0, mip = 0.
#   4-5     At the end: mip = 0, mcause = 28 (last trap was not an interrupt).
#   900+k   Unexpected trap while setting up section k.
# Per section (k = 1..10, 13), B = 20k:
#   B+0     Region capability tagged after CSetBoundsExact (precondition;
#           fails if the bounds were not exact or CSetBoundsExact is broken).
#   B+1     CGetTop(region) = top (precondition).
#   B+2     mcause = 28.
#   B+3     mtval[4:0] = 0x01 (Length/Bounds Violation).
#   B+4     mtval = 0x401 (reported against PCC: mtval[10] = 1, idx 0).
#   B+5     MEPCC.address = the expected faulting fetch PC.
#   B+6     MEPCC.tag = 0 (PCC tag cleared on a fetch bounds violation).
#   B+7     s0 = expected marker: the in-bounds instructions ran, the
#           out-of-bounds one did not.
#   B+8     The out-of-bounds instruction(s) ran and control fell out of the
#           region into main (no fetch check at all).
#   B+9..13 Section-specific, listed below.
#
#   Section 1 (REQ_CFI_05, REQ_BND_03)  Sequential fetch reaching PCC.Top:
#           two 32-bit instructions, the second ending exactly at Top. Fault
#           at Top, marker 3. Fails if: the top check is >= instead of >,
#           or the instruction at Top executes.
#   Section 2 (REQ_BND_07)  32-bit instruction at Top-2, Top-2 = 0 mod 4:
#           first half-word in bounds, second past Top. Fault with
#           MEPCC.address = Top-2 (not Top), marker 3. Fails if: only the
#           first granule is checked, or the second-granule PC is reported.
#   Section 3 (REQ_BND_07)  Same with Top-2 = 2 mod 4 (the instruction is
#           split across two fetch words; ibex_if_stage cheriot_force_uc
#           path). The preceding 32-bit instruction at base+2 is itself
#           word-straddling and in bounds, and must execute. Marker 3.
#   Section 4 (REQ_BND_07 control)  16-bit instruction at Top-2 with
#           Top-2 = 2 mod 4 must execute (it needs only its own 2 bytes);
#           the fault is at Top. Marker 7 (bit 4 = the c.addi at Top-2).
#           Fails if: the core requires 4 bytes of headroom for every fetch.
#   Section 5 (REQ_BND_07 control)  Same with Top-2 = 0 mod 4. Marker 3.
#   Section 6 (REQ_BRA_08)  Taken BEQ whose target (Top+8) is past Top. The
#           branch retires; MEPCC.address = target, not the branch. Marker 1.
#           Fails if: the branch itself faults (MEPCC = branch PC), or the
#           prefetched fall-through at Top raises the fault.
#   Section 7 (REQ_BRA_08, below Base)  Taken CJAL t1 to base-8. The link:
#     B+10  ct1.tag = 1        B+11  ct1 otype = 0 (cd != cra: unsealed)
#     B+12  ct1.address = JAL + 4
#           proves the jump retired and wrote its link before the fetch of
#           the target faulted. MEPCC.address = base-8, marker 1.
#   Section 8 (REQ_BRA_05)  CJALR t1 from main to a capability whose address
#           is its own Top (out of bounds, still representable):
#     B+9   the cursor-moved capability is still tagged (precondition).
#     B+10..12  link in ct1 is tagged, unsealed, address = CJALR + 4, i.e.
#           the CJALR retired without a bounds check. Fault at Top, marker 0
#           (nothing in the region ran). Fails if: CJALR checks the target
#           (fault with capcause != 0x01 against cs1, or MEPCC = the CJALR).
#     B+13  CJALR fell through without jumping.
#   Section 9 (REQ_BRA_05, below Base)  CJALR c0, -4(ca1) with ca1.address =
#           base: target base-4. Fault at base-4, marker 0.
#   Section 10 (REQ_CFI_05, trap return)  MRET to MEPCC = region capability
#           with address = Top (tagged: MEPCC legalisation only checks EX,
#           seal and bit 0). mstatus.MPP is set to M and MPIE cleared first.
#     B+9   MEPCC read back tagged    B+10  ...with address = Top
#     B+11  mret did not transfer control (fell through).
#           Fault at Top, marker 0.
#   Section 11 (REQ_BRA_08, cp_cheri_branch_bound)  One taken branch per reachable
#           value of cp_cheri_branch_bound that sections 1-10 and the random
#           streams do not produce (branch_bounds_cases.inc, generated and
#           checked against fcov_bound_check_cases() by gen_branch_bounds.py):
#           targets below, at, inside, 1..7 bytes under, at and above the top
#           of exact 2..16-byte regions, and against PCC [0x81000000, 2^32) and
#           [0, 0x81000000), whose code is copied there first (the branch must
#           be within 4 KiB of the target). Every branch is a c.beqz on a4 = 0.
#           A target whose 2 bytes are in bounds runs its landing pad, c.jr a3
#           (a3 = MTCC at the case's check); otherwise the fetch faults and the
#           vector .Lvec_br does the same jump. Case n (n = 0..28) uses codes
#           300+4n .. 300+4n+3:
#     +0/+1 region precondition (tag; CGetTop or the cursor-moved tag)
#     +2    landing: mcause != 0 (it trapped); fault: mcause != 28
#     +3    fault: mtval != 0x401 or MEPCC.address != the target
#           Anything else in a region is c.ebreak (mcause 3, code +2).
#           The last case faults, so the final mcause check still holds.
#   Section 12 (REQ_BRA_08, cp_cheri_branch_bound, cp_cheri_cjal_bound,
#           cheriot_cauipcc_cross)  The same entry and checks for code at the ends of
#           the address space. NEEDS +far_code_windows=1, which maps [0, 0x1000) and
#           [0xFFFFF000, 2^32) in CHERIoT-Sail (ibex_cosim_scoreboard.sv); without it
#           the copies there fault in the model only and the cosim reports a mismatch.
#           Blocks are copied to 0, 0xFFFFFFE0, 0x81000000 and 0x80FFFFE0, each
#           before its cases (branch_bounds_cases.inc, BRANCH_FAR_MAIN): taken
#           c.beqz and CJAL (jal t1, or c.jal where only 2 bytes fit) to targets
#           2..6 bytes under a top of 2^32, at a base of 0, 1..7 bytes under an odd
#           top over a base of 0, and 0 / 2^32 - 2..6 under the root PCC; CJAL
#           also under PCCs of length 2..7 at 0x80FFFFF0 (section 11's small
#           regions), from the base of a length-9 PCC there to 7 bytes under its top
#           (0x070) and of a length-8 one to 2 bytes under its top (0x020, its c.jr
#           pad in the last halfword), and below/at/above the bounds of the two 0x81000000 PCCs; AUIPCC
#           ca5 from PCCs at both ends whose result wraps past 2^32 or 0 out of the
#           representable range. Case n uses codes 500+6n .. 500+6n+5:
#     +0/+1 PCC precondition (CSetBoundsExact tag; cursor-moved tag)
#     +2/+3 as section 11 (landing: mcause; fault: mcause, mtval/MEPCC)
#     +4    CJAL: link tag != 1 or otype != 0 (ct1) / 4 (cra, MIE = 0);
#           AUIPCC: ca5.tag != the CHERIoT-Sail setCapAddr representability (0)
#     +5    CJAL: link address != CJAL + length; AUIPCC: ca5.address != pc + imm*2048
#           The last case faults, so the final mcause check still holds.
#   Section 13 (REQ_CFI_05, cheriot_fetch_cross acc_vio && bound_vio)  As
#           section 10 with the region capability untagged before the MEPCC
#           write (legalisation keeps it untagged): the fetch at Top violates
#           both the tag and the bounds, and the tag is reported. B = 260:
#           B+0/1 and B+5..8 as above; B+2 mcause = 28; B+3 mtval = 0x402
#           (Tag Violation against PCC); B+6 MEPCC.tag = 0 (it was already 0);
#     B+9   MEPCC read back untagged  B+10  ...with address = Top
#     B+11  mret did not transfer control (fell through).
#
# Register use: ca1 = region capability, ct1 = MTCC install scratch and CJAL/
# CJALR link, s0 = marker, t0/t1/t2 integer scratch, a2 LA_PC scratch. a0 is written only on
# exit. No x16-x31. Section 11 also uses ca3 (continuation), a4 (= 0, the branch condition) and
# ca5 (copy source, expected target); section 12 also ca5 (AUIPCC result) and cra (c.jal link).
# main keeps the crt's cra (its backward sentry) in ctp and restores it at .Lexit.
#
# Instruction encodings (opcode 0x5B), generated from the CHERIoT-Sail encdec
# clauses (cheri_insts.sail) and cross-checked against every .word in the
# existing cheriot_* directed tests (228 words, 0 mismatches):
#   cgetaddr        t1, ct1            = .word 0xFEF3035B
#   cgetaddr        t2, ct1            = .word 0xFEF303DB
#   cgettag         t1, ca1            = .word 0xFE45835B
#   cgettag         t1, ct1            = .word 0xFE43035B
#   cgettag         t2, ct1            = .word 0xFE4303DB
#   cgettop         t1, ca1            = .word 0xFF85835B
#   cgettype        t2, ct1            = .word 0xFE1303DB
#   ccleartag       ca1, ca1           = .word 0xFEB585DB
#   cmove           ctp, cra           = .word 0xFEA0825B
#   cmove           cra, ctp           = .word 0xFEA200DB
#   csetaddr        ca1, ca1, t0       = .word 0x205585DB
#   csetboundsexact ca1, ca1, t2       = .word 0x127585DB
#   cspecialr       ca1, mtcc          = .word 0x03C005DB
#   cspecialr       ct1, mepcc         = .word 0x03F0035B
#   cspecialw       mepcc, ca1         = .word 0x03F5805B
# CJAL/CJALR/MRET/BEQ are the standard JAL/JALR/MRET/BEQ encodings.

    .option norelax
    .option norvc

# Run-time address of \sym, at any distance. Clobbers a2. In CHERIoT mode the
# AUIPC encoding is AUIPCC, which shifts imm20 by 11, not 12, so GNU `la`
# (AUIPC + ADDI, %pcrel_hi for << 12) is only right within about +-2 KiB of
# the pc, and the regions are ~3 KiB past main. A plain LUI + ADDI of the
# symbol is no better: mseccfg_test.ld links at VMA 0x100000, which the bench
# loads at 0x80000000. So take the pc with AUIPCC 0 (same under either shift)
# and add the link-time distance (cheriot_dv.h LA_FAR, kept local here).
.macro LA_PC rd, sym
9:
    auipc   \rd, 0
    lui     a2, %hi(\sym)
    addi    a2, a2, %lo(\sym)
    add     \rd, \rd, a2
    lui     a2, %hi(9b)
    addi    a2, a2, %lo(9b)
    sub     \rd, \rd, a2
.endm

# Point MTCC at a test-local vector. Clobbers t0 and c6 (t1).
.macro SET_TRAP_VECTOR label
    LA_PC   t0, \label
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

# ca1 <- execute capability exactly [base, top), address = base.
.macro BUILD_REGION base, top, code
    LA_PC   t0, \base
    .word   0x03C005DB              # cspecialr       ca1, mtcc
    .word   0x205585DB              # csetaddr        ca1, ca1, t0
    LA_PC   t2, \top
    sub     t2, t2, t0
    .word   0x127585DB              # csetboundsexact ca1, ca1, t2
    .word   0xFE45835B              # cgettag         t1, ca1
    li      t2, 1
    CHECK_EQ t1, t2, \code
    .word   0xFF85835B              # cgettop         t1, ca1
    LA_PC   t2, \top
    CHECK_EQ t1, t2, \code+1
.endm

# First thing in a section's check code: the marker, then re-arm the
# unexpected vector with s0 = section number.
.macro CHECK_MARKER marker, sect
    li      t2, \marker
    CHECK_EQ s0, t2, 20*\sect+7
    li      s0, \sect
    SET_TRAP_VECTOR .Lvec_unexpected
.endm

# The trap was a fetch bounds violation against PCC at \fetch_pc.
.macro CHECK_FETCH_FAULT fetch_pc, sect
    csrr    t1, mcause
    li      t2, 28
    CHECK_EQ t1, t2, 20*\sect+2
    csrr    t1, mtval
    andi    t2, t1, 0x1F
    li      t0, 0x01
    CHECK_EQ t2, t0, 20*\sect+3
    li      t2, 0x401
    CHECK_EQ t1, t2, 20*\sect+4
    .word   0x03F0035B              # cspecialr       ct1, mepcc
    .word   0xFEF3035B              # cgetaddr        t1, ct1
    LA_PC   t2, \fetch_pc
    CHECK_EQ t1, t2, 20*\sect+5
    .word   0x03F0035B              # cspecialr       ct1, mepcc
    .word   0xFE43035B              # cgettag         t1, ct1
    CHECK_EQ t1, zero, 20*\sect+6
.endm

# The link in ct1 is a tagged, unsealed capability with address \link.
# Uses t0/t2 only, so it runs before anything that clobbers t1.
.macro CHECK_LINK link, sect
    .word   0xFE4303DB              # cgettag         t2, ct1
    li      t0, 1
    CHECK_EQ t2, t0, 20*\sect+10
    .word   0xFE1303DB              # cgettype        t2, ct1
    CHECK_EQ t2, zero, 20*\sect+11
    .word   0xFEF303DB              # cgetaddr        t2, ct1
    LA_PC   t0, \link
    CHECK_EQ t2, t0, 20*\sect+12
.endm

#include "cheriot_fetch_bounds/branch_bounds_cases.inc"

    .text
    .globl main

# Test-local trap vectors: no memory access, no CSR access, no mret.
    ALIGN4
.Lvec_unexpected:
    addi    a0, s0, 900
    j       .Lexit
    ALIGN4
.Lvec_s1:   j .Ls1_check
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
.Lvec_s13:  j .Ls13_check
    ALIGN4
.Lvec_br:   jalr zero, 0(a3)        # section 11: continue at the case's check

    ALIGN4
main:
    .word   0xFEA0825B              # cmove           ctp, cra (section 12 writes cra)
    csrsi   mstatus, 8              # set mstatus.MIE (bit 3)
    li      s0, 0
    SET_TRAP_VECTOR .Lvec_unexpected

    # ── Tests 1-3: interrupt state, before the first deliberate fault ────────
    csrr    t1, mstatus
    andi    t1, t1, 8
    li      t2, 8
    CHECK_EQ t1, t2, 1
    csrr    t1, mcause
    CHECK_EQ t1, zero, 2
    csrr    t1, mip
    CHECK_EQ t1, zero, 3

    # ── Section 1: sequential fetch reaches Top ──────────────────────────────
    li      s0, 1
    SET_TRAP_VECTOR .Lvec_unexpected
    BUILD_REGION .Ls1_base, .Ls1_top, 20
    SET_TRAP_VECTOR .Lvec_s1
    li      s0, 0
    jalr    zero, 0(a1)
.Ls1_check:
    CHECK_MARKER 3, 1
    CHECK_FETCH_FAULT .Ls1_top, 1

    # ── Section 2: 32-bit instruction straddles Top (Top-2 = 0 mod 4) ────────
    li      s0, 2
    SET_TRAP_VECTOR .Lvec_unexpected
    BUILD_REGION .Ls2_base, .Ls2_insn+2, 40
    SET_TRAP_VECTOR .Lvec_s2
    li      s0, 0
    jalr    zero, 0(a1)
.Ls2_check:
    CHECK_MARKER 3, 2
    CHECK_FETCH_FAULT .Ls2_insn, 2

    # ── Section 3: 32-bit instruction straddles Top (Top-2 = 2 mod 4) ────────
    li      s0, 3
    SET_TRAP_VECTOR .Lvec_unexpected
    BUILD_REGION .Ls3_base, .Ls3_insn+2, 60
    SET_TRAP_VECTOR .Lvec_s3
    li      s0, 0
    jalr    zero, 0(a1)
.Ls3_check:
    CHECK_MARKER 3, 3
    CHECK_FETCH_FAULT .Ls3_insn, 3

    # ── Section 4: 16-bit instruction ending at Top executes (2 mod 4) ───────
    li      s0, 4
    SET_TRAP_VECTOR .Lvec_unexpected
    BUILD_REGION .Ls4_base, .Ls4_top, 80
    SET_TRAP_VECTOR .Lvec_s4
    li      s0, 0
    jalr    zero, 0(a1)
.Ls4_check:
    CHECK_MARKER 7, 4
    CHECK_FETCH_FAULT .Ls4_top, 4

    # ── Section 5: 16-bit instruction ending at Top executes (0 mod 4) ───────
    li      s0, 5
    SET_TRAP_VECTOR .Lvec_unexpected
    BUILD_REGION .Ls5_base, .Ls5_top, 100
    SET_TRAP_VECTOR .Lvec_s5
    li      s0, 0
    jalr    zero, 0(a1)
.Ls5_check:
    CHECK_MARKER 3, 5
    CHECK_FETCH_FAULT .Ls5_top, 5

    # ── Section 6: taken branch to a target past Top ─────────────────────────
    li      s0, 6
    SET_TRAP_VECTOR .Lvec_unexpected
    BUILD_REGION .Ls6_base, .Ls6_top, 120
    SET_TRAP_VECTOR .Lvec_s6
    li      s0, 0
    jalr    zero, 0(a1)
.Ls6_check:
    CHECK_MARKER 1, 6
    CHECK_FETCH_FAULT .Ls6_target, 6

    # ── Section 7: taken CJAL to a target below Base ─────────────────────────
    li      s0, 7
    SET_TRAP_VECTOR .Lvec_unexpected
    BUILD_REGION .Ls7_base, .Ls7_top, 140
    SET_TRAP_VECTOR .Lvec_s7
    li      s0, 0
    jalr    zero, 0(a1)
.Ls7_check:
    CHECK_LINK .Ls7_top, 7          # .Ls7_top = the CJAL + 4
    CHECK_MARKER 1, 7
    CHECK_FETCH_FAULT .Ls7_below, 7

    # ── Section 8: CJALR to a capability whose address is its Top ────────────
    li      s0, 8
    SET_TRAP_VECTOR .Lvec_unexpected
    BUILD_REGION .Ls8_base, .Ls8_top, 160
    LA_PC   t0, .Ls8_top
    .word   0x205585DB              # csetaddr        ca1, ca1, t0
    .word   0xFE45835B              # cgettag         t1, ca1
    li      t2, 1
    CHECK_EQ t1, t2, 169
    SET_TRAP_VECTOR .Lvec_s8
    li      s0, 0
.Ls8_cjalr:
    jalr    t1, 0(a1)
    li      a0, 173                 # fell through: CJALR did not jump
    j       .Lexit
.Ls8_check:
    CHECK_LINK .Ls8_cjalr+4, 8
    CHECK_MARKER 0, 8
    CHECK_FETCH_FAULT .Ls8_top, 8

    # ── Section 9: CJALR with a negative offset to below Base ────────────────
    li      s0, 9
    SET_TRAP_VECTOR .Lvec_unexpected
    BUILD_REGION .Ls9_base, .Ls9_top, 180
    SET_TRAP_VECTOR .Lvec_s9
    li      s0, 0
    jalr    zero, -4(a1)
.Ls9_check:
    CHECK_MARKER 0, 9
    CHECK_FETCH_FAULT .Ls9_below, 9

    # ── Section 10: MRET to an MEPCC whose address is its Top ────────────────
    li      s0, 10
    SET_TRAP_VECTOR .Lvec_unexpected
    BUILD_REGION .Ls10_base, .Ls10_top, 200
    LA_PC   t0, .Ls10_top
    .word   0x205585DB              # csetaddr        ca1, ca1, t0
    .word   0x03F5805B              # cspecialw       mepcc, ca1
    .word   0x03F0035B              # cspecialr       ct1, mepcc
    .word   0xFE43035B              # cgettag         t1, ct1
    li      t2, 1
    CHECK_EQ t1, t2, 209
    .word   0x03F0035B              # cspecialr       ct1, mepcc
    .word   0xFEF3035B              # cgetaddr        t1, ct1
    LA_PC   t2, .Ls10_top
    CHECK_EQ t1, t2, 210
    li      t0, 0x1800              # mstatus.MPP = M
    csrs    mstatus, t0
    li      t0, 0x80                # mstatus.MPIE = 0: MIE stays 0 after mret
    csrc    mstatus, t0
    SET_TRAP_VECTOR .Lvec_s10
    li      s0, 0
    mret
    li      a0, 211                 # fell through: mret did not transfer
    j       .Lexit
.Ls10_check:
    CHECK_MARKER 0, 10
    CHECK_FETCH_FAULT .Ls10_top, 10

    # ── Section 11: one taken branch per cp_cheri_branch_bound value ─────────
    BRANCH_BOUNDS_MAIN

    # ── Section 12: branch, CJAL and AUIPCC at both ends of the address space ─
    BRANCH_FAR_MAIN

    # ── Section 13: MRET to an untagged MEPCC whose address is its Top ───────
    li      s0, 13
    SET_TRAP_VECTOR .Lvec_unexpected
    BUILD_REGION .Ls13_base, .Ls13_top, 260
    LA_PC   t0, .Ls13_top
    .word   0x205585DB              # csetaddr        ca1, ca1, t0
    .word   0xFEB585DB              # ccleartag       ca1, ca1
    .word   0x03F5805B              # cspecialw       mepcc, ca1
    .word   0x03F0035B              # cspecialr       ct1, mepcc
    .word   0xFE43035B              # cgettag         t1, ct1
    CHECK_EQ t1, zero, 269
    .word   0x03F0035B              # cspecialr       ct1, mepcc
    .word   0xFEF3035B              # cgetaddr        t1, ct1
    LA_PC   t2, .Ls13_top
    CHECK_EQ t1, t2, 270
    li      t0, 0x1800              # mstatus.MPP = M
    csrs    mstatus, t0
    li      t0, 0x80                # mstatus.MPIE = 0
    csrc    mstatus, t0
    SET_TRAP_VECTOR .Lvec_s13
    li      s0, 0
    mret
    li      a0, 271                 # fell through: mret did not transfer
    j       .Lexit
.Ls13_check:
    CHECK_MARKER 0, 13
    csrr    t1, mcause
    li      t2, 28
    CHECK_EQ t1, t2, 262
    csrr    t1, mtval
    li      t2, 0x402               # Tag Violation against PCC, not Bounds
    CHECK_EQ t1, t2, 263
    .word   0x03F0035B              # cspecialr       ct1, mepcc
    .word   0xFEF3035B              # cgetaddr        t1, ct1
    LA_PC   t2, .Ls13_top
    CHECK_EQ t1, t2, 265
    .word   0x03F0035B              # cspecialr       ct1, mepcc
    .word   0xFE43035B              # cgettag         t1, ct1
    CHECK_EQ t1, zero, 266

    # ── Tests 4-5: final interrupt state ─────────────────────────────────────
    csrr    t1, mip
    CHECK_EQ t1, zero, 4
    csrr    t1, mcause
    li      t2, 28
    CHECK_EQ t1, t2, 5

    li      a0, 0
.Lexit:
    .word   0xFEA200DB              # cmove           cra, ctp
    jalr    zero, 0(ra)             # ret through the crt's backward sentry

# "Ran past" stubs: an out-of-bounds instruction executed and fell out.
.Ls1_ran_past:  li a0, 28;  j .Lexit
.Ls2_ran_past:  li a0, 48;  j .Lexit
.Ls3_ran_past:  li a0, 68;  j .Lexit
.Ls4_ran_past:  li a0, 88;  j .Lexit
.Ls5_ran_past:  li a0, 108; j .Lexit
.Ls6_ran_past:  li a0, 128; j .Lexit
.Ls7_ran_past:  li a0, 148; j .Lexit
.Ls8_ran_past:  li a0, 168; j .Lexit
.Ls9_ran_past:  li a0, 188; j .Lexit
.Ls10_ran_past: li a0, 208; j .Lexit
.Ls13_ran_past: li a0, 268; j .Lexit

# ── Bounded code regions (entered only through a bounded PCC) ───────────────
# [base, top) is the PCC bounds; everything at or after top, or before base,
# must never execute.

    ALIGN4
.Ls1_base:
    addi    s0, s0, 1               # base+0
    addi    s0, s0, 2               # base+4, ends at Top
.Ls1_top:                           # base+8
    addi    s0, s0, 16              # OUT: must not execute
    j       .Ls1_ran_past

    ALIGN4
.Ls2_base:
    .option rvc
    c.addi  s0, 1                   # base+0
    c.addi  s0, 2                   # base+2
    .option norvc
.Ls2_insn:                          # base+4 = Top-2 (0 mod 4); Top = base+6
    addi    s0, s0, 16              # 32-bit, second half past Top: OUT
    j       .Ls2_ran_past

    ALIGN4
.Ls3_base:
    .option rvc
    c.addi  s0, 1                   # base+0
    .option norvc
    addi    s0, s0, 2               # base+2..5, word-straddling, in bounds
.Ls3_insn:                          # base+6 = Top-2 (2 mod 4); Top = base+8
    addi    s0, s0, 16              # 32-bit, second half past Top: OUT
    j       .Ls3_ran_past

    ALIGN4
.Ls4_base:
    addi    s0, s0, 1               # base+0
    .option rvc
    c.addi  s0, 2                   # base+4
    c.addi  s0, 4                   # base+6 = Top-2 (2 mod 4): must execute
    .option norvc
.Ls4_top:                           # base+8
    addi    s0, s0, 16              # OUT
    j       .Ls4_ran_past

    ALIGN4
.Ls5_base:
    addi    s0, s0, 1               # base+0
    .option rvc
    c.addi  s0, 2                   # base+4 = Top-2 (0 mod 4): must execute
    .option norvc
.Ls5_top:                           # base+6
    addi    s0, s0, 16              # OUT (32-bit, word-straddling)
    j       .Ls5_ran_past

    ALIGN4
.Ls6_base:
    addi    s0, s0, 1               # base+0
    beq     zero, zero, .Ls6_target # base+4: taken, target past Top
.Ls6_top:                           # base+8
    addi    s0, s0, 16              # OUT (fall-through, never architecturally reached)
    j       .Ls6_ran_past
.Ls6_target:                        # base+16
    addi    s0, s0, 32              # OUT: branch target
    j       .Ls6_ran_past

    ALIGN4
.Ls7_below:                         # base-8
    addi    s0, s0, 16              # OUT: CJAL target
    j       .Ls7_ran_past           # base-4
.Ls7_base:
    addi    s0, s0, 1               # base+0
    jal     t1, .Ls7_below          # base+4: CJAL, link -> ct1
.Ls7_top:                           # base+8
    addi    s0, s0, 32              # OUT
    j       .Ls7_ran_past

    ALIGN4
.Ls8_base:
    addi    s0, s0, 16              # in bounds, but CJALR jumps past it
.Ls8_top:                           # base+4
    addi    s0, s0, 32              # OUT: CJALR target
    j       .Ls8_ran_past

    ALIGN4
.Ls9_below:                         # base-4
    addi    s0, s0, 16              # OUT: CJALR target
.Ls9_base:
    addi    s0, s0, 32              # in bounds, but not the target
.Ls9_top:                           # base+4
    j       .Ls9_ran_past

    ALIGN4
.Ls10_base:
    addi    s0, s0, 16              # in bounds, but not the MRET target
.Ls10_top:                          # base+4
    addi    s0, s0, 32              # OUT: MRET target
    j       .Ls10_ran_past

    ALIGN4
.Ls13_base:
    addi    s0, s0, 16              # in bounds, but not the MRET target
.Ls13_top:                          # base+4
    addi    s0, s0, 32              # OUT: MRET target
    j       .Ls13_ran_past

# Section 11 regions and the two blocks copied to 0x81000000 and 0x81000000 - 32.
    BRANCH_BOUNDS_REGIONS

# Section 12 blocks, each copied to its window before its cases run.
    BRANCH_FAR_BLOCKS
