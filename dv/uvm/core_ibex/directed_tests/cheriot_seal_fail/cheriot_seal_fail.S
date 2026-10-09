# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_seal_fail -- every failing arm of CSeal/CUnseal, sealed-cap
#                            immutability, and sealed caps as authorities
# =============================================================================
# REQ_SEL_01..04. All expected values come from CHERIoT-Sail
# (cheriot-sail-upstream/src/cheri_insts.sail and cheri_addr_checks.sail), not
# from the verification spec.
#
# What CHERIoT-Sail says
# ----------------------
# CSeal cd, cs1, cs2 never traps. cd = cs1 sealed with otype = cs2.address; cd
# keeps cs1's tag only if ALL of: cs2.tag, cs2 unsealed, cs2.permit_seal (SE),
# cs2.base <= cs2.address < cs2.top, cs1 unsealed (clearTagIfSealed), and
# cs2.address is 1..7 when cs1 has EX, 9..15 otherwise (isPermittedOtype, which
# looks at the whole 32-bit address, not its low bits).
# CUnseal cd, cs1, cs2 never traps. cd = cs1 unsealed, GL = cs1.GL & cs2.GL; cd
# keeps the tag only if cs2.tag, cs1 sealed, cs2 unsealed,
# inCapBounds(cs2, cs1.otype, 1) and cs2.permit_unseal (US). cs2.address is NOT
# compared with the otype.
# CIncAddr, CIncAddrImm, CSetAddr, CSetBounds, CSetBoundsExact, CSetBoundsImm,
# CSetBoundsRoundDown and CSeal start from clearTagIfSealed(cs1); AUICGP clears
# the tag if CGP (c3) is sealed. CAndPerm on a sealed cs1 clears the tag unless
# (mask | GL) == 0xFFF over the 12 architectural permission bits -- i.e. the
# only mask bit allowed to be 0 is GL; the upper 20 bits of rs2 are ignored.
# lw/sw (ext_data_get_addr) and CLC/CSC (LoadCapImm/StoreCapImm) check tag,
# then seal, before any permission or bounds check: a sealed authority raises
# CapEx_SealViolation (0x03) against it, mtval = (0 @ reg) @ 0x03.
#
# Permission bits (CGetPerm): 11 U0, 10 SE, 9 US, 8 EX, 7 SR, 6 MC, 5 LD,
# 4 SL, 3 LM, 2 SD, 1 LG, 0 GL. Reset roots: MTCC 0x1EB, MTDC 0x07F,
# MScratchC 0xE01 (GL US SE U0, the sealing root). Every CAndPerm result below
# is read back with CGetPerm, because capToEncCap compresses the permissions:
#   S & 0xBFF = 0xA01, S & 0xDFF = 0xC01, S & 0xFFE = 0xE00 (sealing format
#   stores U0/SE/US individually); D & 0x7E = 0x7E, D & 0xFFD = 0x7D
#   (mem-rw-cap format stores SL/LM/LG individually); X & 0xFFE = 0x1EA
#   (executable format stores SR/LM/LG individually). None of these is lossy.
#
# Operands: D = MTDC with address buf (data, perms 0x7F); X = MTCC with address
# buf (executable, 0x1EB); S@n = MScratchC with address n (full bounds, so any n
# is in bounds); Ds9 = CSeal(D, S@9); Xs1 = CSeal(X, S@1), an inheriting sentry.
#
# The "cs2.address below cs2.base" arm of CSeal is not constructible: CHERIoT's
# representable region starts at the base, so setCapAddr to an address below
# the base changes the decoded bounds and clears the tag -- the CSeal would then
# fail on cs2.tag, not on the bounds. Only address >= top is exercised (22-24).
#
# Checks and failure codes (main returns 0, or the code of the first failure)
# -------------------------------------------------------------------------
# Preconditions
#   1  CGetPerm(D) = 0x7F    2  CGetPerm(X) = 0x1EB    3  CGetPerm(S) = 0xE01
#   4  CGetTag(S) = 1
# CSeal, permitted arms (controls)
#   5/6   CSeal(D, S@9):  tag 1, CGetType 9     7/8   CSeal(D, S@15): tag 1, type 15
#   9/10  CSeal(X, S@1):  tag 1, type 1         11/12 CSeal(X, S@7):  tag 1, type 7
# CSeal, failing arms (each: tag 0, no trap)
#   13 cs2 untagged: CSeal(D, CClearTag(S@9))
#   14/15 precondition: S9s = CSeal(S@9, S@9) has tag 1, type 9 (S has no EX)
#   16 cs2 sealed: CSeal(D, S9s)
#   17/18 precondition: S@9 & 0xBFF has perms 0xA01, tag 1
#   19 cs2 lacks SE: CSeal(D, S@9 & 0xBFF)
#   20/21 precondition: Sb = CSetBoundsImm(S@9, 3) has base 9, length 3
#   22 control: CSeal(D, Sb@11) tag 1 (last in-bounds otype)
#   23 precondition: Sb@12 still tagged (address = top is representable)
#   24 cs2.address = cs2.top: CSeal(D, Sb@12)
#   25 cs1 sealed: CSeal(Ds9, S@10)
#   26-29 executable cs1, otype not in 1..7: S@0, S@8, S@9, S@0x101 (0x101 has
#         the low bits of a legal otype; RTL must look at all 32 bits)
#   30-35 data cs1, otype not in 9..15: S@0, S@1, S@7, S@8, S@16, S@0x109
# CUnseal
#   36 precondition: Ds9 tag 1
#   37-40 control: CUnseal(Ds9, S@9): tag 1, type 0, perms 0x7F,
#         CSetEqualExact(result, D) = 1
#   41 control: CUnseal(Ds9, S@0): tag 1 -- cs2.address != otype is fine
#   42 cs2 untagged: CUnseal(Ds9, CClearTag(S@9))
#   43 cs1 unsealed: CUnseal(D, S@9)
#   44 cs2 sealed: CUnseal(Ds9, S9s)
#   45 precondition: S@9 & 0xDFF has perms 0xC01
#   46 cs2 lacks US: CUnseal(Ds9, S@9 & 0xDFF)
#   47/48 precondition: Sb2 = CSetBoundsImm(S@10, 2) has base 10, length 2
#   49 otype below cs2.base: CUnseal(Ds9, Sb2)
#   50 control: CUnseal(CSeal(D, S@10), Sb2) tag 1 (otype = base)
#   51 control: CUnseal(CSeal(D, S@11), Sb2) tag 1 (otype = top - 1)
#   52 otype = cs2.top: CUnseal(CSeal(D, S@12), Sb2)
#   53 precondition: S@9 & 0xFFE (local sealing authority) has perms 0xE00
#   54/55 CUnseal(Ds9, S@9 & 0xFFE): tag 1, perms 0x7E (GL = 1 & 0)
#   56 precondition: CAndPerm(D, 0x7E) has perms 0x7E
#   57 precondition: CSeal(D & 0x7E, S@9) tag 1
#   58/59 CUnseal(that, S@9): tag 1, perms 0x7E (GL = 0 & 1)
#   60/61 control, sentry: CUnseal(Xs1, S@1): tag 1, perms 0x1EB
# Modifying a sealed capability (sealed operand Ds9 gives tag 0; the same
# instruction on the unsealed D is the control and keeps the tag)
#   62/63 CIncAddr cd, cs1, zero        64/65 CIncAddrImm cd, cs1, 0
#   66/67 CSetAddr to its own address   68/69 CSetBounds 8
#   70/71 CSetBoundsExact 8             72/73 CSetBoundsImm 8
#   74/75 CSetBoundsRoundDown 8
#   76/77 AUICGP cd, 0 with c3 = Ds9 / c3 = D;  78 control's address = buf
#   79-81 CAndPerm(Ds9, 0xFFF): tag 1, type 9, perms 0x7F   (mask all ones)
#   82-84 CAndPerm(Ds9, 0xFFE): tag 1, type 9, perms 0x7E   (only GL cleared)
#   85    CAndPerm(Ds9, 0xFFFFFFFE): tag 1 (bits 31:12 of rs2 are ignored)
#   86    CAndPerm(Ds9, 0xFFD): tag 0 (LG cleared)
#   87    CAndPerm(Ds9, 0x7FF): tag 0 (clears U0, which Ds9 does not even have:
#         the rule is on the mask, not on the permissions that change)
#   88/89 control: CAndPerm(D, 0xFFD): tag 1, perms 0x7D
#   90-92 CAndPerm(Xs1, 0xFFE): tag 1, type 1, perms 0x1EA (sentry, GL only)
# Loads and stores through sealed authorities
#   93-95 interrupt state before the first deliberate trap: mstatus.MIE = 1,
#         mcause = 0, mip = 0
#   96/97 controls: lw through D and through X read the stored word, no trap
#   98    any trap during 96/97
#   For each of the six faults below: (a) the instruction did not trap,
#   (b) mcause != 28, (c) mtval != expected, (d) MEPCC.address != the faulting
#   instruction, (e) its destination / target changed.
#   99-103   lw s0, 0(ca3), ca3 = Ds9      mtval 0x1A3 (c13, 0x03)
#   104-108  sw t2, 0(ca3), ca3 = Ds9      mtval 0x1A3, word unchanged
#   109-113  lw s0, 0(ca4), ca4 = Xs1      mtval 0x1C3 (c14, 0x03)
#   114-118  sw t2, 0(ca4), ca4 = Xs1      mtval 0x1C3 -- Xs1 lacks SD too, but
#            the seal check comes first (ext_data_get_addr order)
#   119-123  clc ca5, 16(ca3)              mtval 0x1A3, ca5 not written
#   124-128  csc ca0, 16(ca3)              mtval 0x1A3, slot 2 still holds X
#   129/130  after the last resume: mstatus.MIE = 1 (restored by mret), mip = 0
#   131-136  unexpected trap in: setup, CSeal, CUnseal, modify, a post-trap
#            check, or the gp restore
#
# Trap handling: as cheriot_perm_lc_sc, MTCC points at a test-local vector per
# section (no memory or CSR access, no mret in a vector). Each deliberate fault
# lands on its own label; after the checks, RESUME writes MEPCC with an
# MTCC-derived capability for the next label and executes mret, so the next
# fault is not a double fault (cpuctrlsts.sync_exc_seen is cleared by mret) and
# mstatus.MIE is restored from MPIE.
#
# Registers: ca0 = D, ca2 = X (both kept), ca1 = sealing authority, ca3-ca5
# scratch capabilities. Integer scratch t0, t1, t2, s0 only; ca0-ca5 are never
# an integer destination while live (aN and caN are the same register). c3 (gp)
# is saved to buf+8 before AUICGP uses it and restored before returning;
# .option norelax keeps the linker from relaxing anything. No GNU `la`: every
# address goes through LA_PC (see there). No x16-x31. CHERI instructions are .word-encoded from the Sail encdec
# clauses (cross-checked against cheriot_perm_lc_sc / cheriot_rtos_cmove).

    .option norelax

# rd <- run-time address of sym, at any distance; tmp is clobbered and must
# differ from rd. In CHERIoT mode the AUIPC encoding is AUIPCC, which shifts
# imm20 by 11, not 12, so GNU `la` (AUIPC + ADDI, %pcrel_hi for << 12) is only
# right within about +-2 KiB of the pc: the vectors are ~2 KiB behind the later
# sections and buf is in .data. A plain LUI + ADDI of the symbol is no better
# (mseccfg_test.ld links at VMA 0x100000, loaded at 0x80000000). So take the
# pc with AUIPCC 0 (same under either shift) and add the link-time distance
# (cheriot_dv.h LA_FAR, kept local here).
.macro LA_PC rd, sym, tmp
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
    LA_PC   t0, \label, t1
    .word   0x03C0035B              # cspecialr c6, mtcc
    .word   0x2053035B              # csetaddr c6, c6, t0
    .word   0x03C3005B              # cspecialw mtcc, c6
.endm

# Leave the current trap: MEPCC <- MTCC-derived cap at label, mret. Clobbers t0, c6.
.macro RESUME label
    LA_PC   t0, \label, t1
    .word   0x03C0035B              # cspecialr c6, mtcc
    .word   0x2053035B              # csetaddr c6, c6, t0
    .word   0x03F3005B              # cspecialw mepcc, c6
    mret
.endm

# ca1 <- S@addr (MScratchC with its address set to addr). Clobbers t0.
.macro SEAL_AUTH addr
    li      t0, \addr
    .word   0x03E005DB              # cspecialr ca1, mscratchc
    .word   0x205585DB              # csetaddr ca1, ca1, t0
.endm

# t1 <- tag of ca3; fail with code if it is not val. Clobbers t1, t2.
.macro TAG3 val, code
    .word   0xFE46835B              # cgettag t1, ca3
    li      t2, \val
    bne     t1, t2, .Lfail_\code
.endm
.macro TAG4 val, code
    .word   0xFE47035B              # cgettag t1, ca4
    li      t2, \val
    bne     t1, t2, .Lfail_\code
.endm
.macro TYPE3 val, code
    .word   0xFE16835B              # cgettype t1, ca3
    li      t2, \val
    bne     t1, t2, .Lfail_\code
.endm
.macro PERM3 val, code
    .word   0xFE06835B              # cgetperm t1, ca3
    li      t2, \val
    bne     t1, t2, .Lfail_\code
.endm
.macro PERM4 val, code
    .word   0xFE07035B              # cgetperm t1, ca4
    li      t2, \val
    bne     t1, t2, .Lfail_\code
.endm

# Checks common to every deliberate fault: mcause 28, mtval, MEPCC at the fault.
# Clobbers t0, t1, t2.
.macro FAULT_CSRS mtval, pc, c_cause, c_tval, c_pc
    csrr    t1, mcause
    li      t2, 28
    bne     t1, t2, .Lfail_\c_cause
    csrr    t1, mtval
    li      t2, \mtval
    bne     t1, t2, .Lfail_\c_tval
    .word   0x03F0035B              # cspecialr ct1, mepcc
    .word   0xFEF3035B              # cgetaddr t1, ct1
    LA_PC   t2, \pc, t0
    bne     t1, t2, .Lfail_\c_pc
.endm

    .text
    .globl main

# Test-local trap vectors: no memory access, no CSR access, no mret.
.balign 4
.Lvec_setup:    j .Lfail_131
.balign 4
.Lvec_cseal:    j .Lfail_132
.balign 4
.Lvec_cunseal:  j .Lfail_133
.balign 4
.Lvec_modify:   j .Lfail_134
.balign 4
.Lvec_post:     j .Lfail_135
.balign 4
.Lvec_restore:  j .Lfail_136
.balign 4
.Lvec_ls_ctrl:  j .Lfail_98
.balign 4
.Lvec_f1:       j .Ltrap_f1
.balign 4
.Lvec_f2:       j .Ltrap_f2
.balign 4
.Lvec_f3:       j .Ltrap_f3
.balign 4
.Lvec_f4:       j .Ltrap_f4
.balign 4
.Lvec_f5:       j .Ltrap_f5
.balign 4
.Lvec_f6:       j .Ltrap_f6

main:
    csrsi   mstatus, 8              # set mstatus.MIE (bit 3)
    SET_TRAP_VECTOR .Lvec_setup

    # ── Setup: D, X, save gp ─────────────────────────────────────────────────
    LA_PC   t0, buf, t1
    .word   0x03D0055B              # cspecialr ca0, mtdc
    .word   0x2055055B              # csetaddr ca0, ca0, t0  D = MTDC @ buf
    .word   0x00353423              # csc c3, 8(ca0)  save gp -> buf+8
    .word   0x03C0065B              # cspecialr ca2, mtcc
    .word   0x2056065B              # csetaddr ca2, ca2, t0  X = MTCC @ buf

    # ── Tests 1-4: preconditions ──────────────────────────────────────────────
    .word   0xFE05035B              # cgetperm t1, ca0
    li      t2, 0x7F
    bne     t1, t2, .Lfail_1
    .word   0xFE06035B              # cgetperm t1, ca2
    li      t2, 0x1EB
    bne     t1, t2, .Lfail_2
    .word   0x03E005DB              # cspecialr ca1, mscratchc
    .word   0xFE05835B              # cgetperm t1, ca1
    li      t2, 0xE01
    bne     t1, t2, .Lfail_3
    .word   0xFE45835B              # cgettag t1, ca1
    li      t2, 1
    bne     t1, t2, .Lfail_4

    # ── Tests 5-35: CSeal ────────────────────────────────────────────────────
    SET_TRAP_VECTOR .Lvec_cseal

    SEAL_AUTH 9
    .word   0x16B506DB              # cseal ca3, ca0, ca1  CSeal(D, S@9)
    TAG3    1, 5
    TYPE3   9, 6
    SEAL_AUTH 15
    .word   0x16B506DB              # cseal ca3, ca0, ca1  CSeal(D, S@15)
    TAG3    1, 7
    TYPE3   15, 8
    SEAL_AUTH 1
    .word   0x16B606DB              # cseal ca3, ca2, ca1  CSeal(X, S@1)
    TAG3    1, 9
    TYPE3   1, 10
    SEAL_AUTH 7
    .word   0x16B606DB              # cseal ca3, ca2, ca1  CSeal(X, S@7)
    TAG3    1, 11
    TYPE3   7, 12

    # cs2 untagged
    SEAL_AUTH 9
    .word   0xFEB585DB              # ccleartag ca1, ca1
    .word   0x16B506DB              # cseal ca3, ca0, ca1
    TAG3    0, 13

    # cs2 sealed
    SEAL_AUTH 9
    .word   0x16B585DB              # cseal ca1, ca1, ca1  S9s = CSeal(S@9, S@9)
    .word   0xFE45835B              # cgettag t1, ca1
    li      t2, 1
    bne     t1, t2, .Lfail_14
    .word   0xFE15835B              # cgettype t1, ca1
    li      t2, 9
    bne     t1, t2, .Lfail_15
    .word   0x16B506DB              # cseal ca3, ca0, ca1
    TAG3    0, 16

    # cs2 lacks SE
    SEAL_AUTH 9
    li      t0, 0xBFF
    .word   0x1A5585DB              # candperm ca1, ca1, t0
    .word   0xFE05835B              # cgetperm t1, ca1
    li      t2, 0xA01
    bne     t1, t2, .Lfail_17
    .word   0xFE45835B              # cgettag t1, ca1
    li      t2, 1
    bne     t1, t2, .Lfail_18
    .word   0x16B506DB              # cseal ca3, ca0, ca1
    TAG3    0, 19

    # cs2.address outside cs2's bounds: Sb = [9, 12) in ca5
    SEAL_AUTH 9
    .word   0x0035A7DB              # csetboundsimm ca5, ca1, 3
    .word   0xFE27835B              # cgetbase t1, ca5
    li      t2, 9
    bne     t1, t2, .Lfail_20
    .word   0xFE37835B              # cgetlen t1, ca5
    li      t2, 3
    bne     t1, t2, .Lfail_21
    li      t0, 11
    .word   0x205785DB              # csetaddr ca1, ca5, t0  Sb@11
    .word   0x16B506DB              # cseal ca3, ca0, ca1
    TAG3    1, 22
    li      t0, 12
    .word   0x205785DB              # csetaddr ca1, ca5, t0  Sb@12 = top
    .word   0xFE45835B              # cgettag t1, ca1
    li      t2, 1
    bne     t1, t2, .Lfail_23
    .word   0x16B506DB              # cseal ca3, ca0, ca1
    TAG3    0, 24

    # cs1 sealed
    SEAL_AUTH 9
    .word   0x16B5075B              # cseal ca4, ca0, ca1  Ds9 (tag checked in test 5)
    SEAL_AUTH 10
    .word   0x16B706DB              # cseal ca3, ca4, ca1  CSeal(Ds9, S@10)
    TAG3    0, 25

    # executable cs1, otype outside 1..7
    SEAL_AUTH 0
    .word   0x16B606DB              # cseal ca3, ca2, ca1
    TAG3    0, 26
    SEAL_AUTH 8
    .word   0x16B606DB              # cseal ca3, ca2, ca1
    TAG3    0, 27
    SEAL_AUTH 9
    .word   0x16B606DB              # cseal ca3, ca2, ca1
    TAG3    0, 28
    SEAL_AUTH 0x101
    .word   0x16B606DB              # cseal ca3, ca2, ca1
    TAG3    0, 29

    # data cs1, otype outside 9..15
    SEAL_AUTH 0
    .word   0x16B506DB              # cseal ca3, ca0, ca1
    TAG3    0, 30
    SEAL_AUTH 1
    .word   0x16B506DB              # cseal ca3, ca0, ca1
    TAG3    0, 31
    SEAL_AUTH 7
    .word   0x16B506DB              # cseal ca3, ca0, ca1
    TAG3    0, 32
    SEAL_AUTH 8
    .word   0x16B506DB              # cseal ca3, ca0, ca1
    TAG3    0, 33
    SEAL_AUTH 16
    .word   0x16B506DB              # cseal ca3, ca0, ca1
    TAG3    0, 34
    SEAL_AUTH 0x109
    .word   0x16B506DB              # cseal ca3, ca0, ca1
    TAG3    0, 35

    # ── Tests 36-61: CUnseal ─────────────────────────────────────────────────
    SET_TRAP_VECTOR .Lvec_cunseal

    SEAL_AUTH 9
    .word   0x16B506DB              # cseal ca3, ca0, ca1  ca3 = Ds9
    TAG3    1, 36
    .word   0x18B6875B              # cunseal ca4, ca3, ca1  CUnseal(Ds9, S@9)
    TAG4    1, 37
    .word   0xFE17035B              # cgettype t1, ca4
    bnez    t1, .Lfail_38
    PERM4   0x7F, 39
    .word   0x42A7035B              # csetequalexact t1, ca4, ca0
    li      t2, 1
    bne     t1, t2, .Lfail_40

    SEAL_AUTH 0
    .word   0x18B6875B              # cunseal ca4, ca3, ca1  CUnseal(Ds9, S@0)
    TAG4    1, 41

    SEAL_AUTH 9
    .word   0xFEB585DB              # ccleartag ca1, ca1
    .word   0x18B6875B              # cunseal ca4, ca3, ca1  cs2 untagged
    TAG4    0, 42

    SEAL_AUTH 9
    .word   0x18B5075B              # cunseal ca4, ca0, ca1  cs1 (D) unsealed
    TAG4    0, 43

    SEAL_AUTH 9
    .word   0x16B585DB              # cseal ca1, ca1, ca1  S9s
    .word   0x18B6875B              # cunseal ca4, ca3, ca1  cs2 sealed
    TAG4    0, 44

    SEAL_AUTH 9
    li      t0, 0xDFF
    .word   0x1A5585DB              # candperm ca1, ca1, t0  no US
    .word   0xFE05835B              # cgetperm t1, ca1
    li      t2, 0xC01
    bne     t1, t2, .Lfail_45
    .word   0x18B6875B              # cunseal ca4, ca3, ca1
    TAG4    0, 46

    # otype against cs2's bounds: Sb2 = [10, 12) in ca5
    SEAL_AUTH 10
    .word   0x0025A7DB              # csetboundsimm ca5, ca1, 2
    .word   0xFE27835B              # cgetbase t1, ca5
    li      t2, 10
    bne     t1, t2, .Lfail_47
    .word   0xFE37835B              # cgetlen t1, ca5
    li      t2, 2
    bne     t1, t2, .Lfail_48
    .word   0x18F6875B              # cunseal ca4, ca3, ca5  otype 9 < base 10
    TAG4    0, 49
    SEAL_AUTH 10
    .word   0x16B506DB              # cseal ca3, ca0, ca1  Ds10
    .word   0x18F6875B              # cunseal ca4, ca3, ca5
    TAG4    1, 50
    SEAL_AUTH 11
    .word   0x16B506DB              # cseal ca3, ca0, ca1  Ds11
    .word   0x18F6875B              # cunseal ca4, ca3, ca5
    TAG4    1, 51
    SEAL_AUTH 12
    .word   0x16B506DB              # cseal ca3, ca0, ca1  Ds12
    .word   0x18F6875B              # cunseal ca4, ca3, ca5  otype 12 = top
    TAG4    0, 52

    # GL = cs1.GL & cs2.GL
    SEAL_AUTH 9
    .word   0x16B506DB              # cseal ca3, ca0, ca1  ca3 = Ds9 again
    li      t0, 0xFFE
    .word   0x1A5585DB              # candperm ca1, ca1, t0  local sealing authority
    .word   0xFE05835B              # cgetperm t1, ca1
    li      t2, 0xE00
    bne     t1, t2, .Lfail_53
    .word   0x18B6875B              # cunseal ca4, ca3, ca1
    TAG4    1, 54
    PERM4   0x7E, 55

    li      t0, 0x7E
    .word   0x1A55075B              # candperm ca4, ca0, t0  D & 0x7E (local data cap)
    PERM4   0x7E, 56
    SEAL_AUTH 9
    .word   0x16B707DB              # cseal ca5, ca4, ca1
    .word   0xFE47835B              # cgettag t1, ca5
    li      t2, 1
    bne     t1, t2, .Lfail_57
    .word   0x18B7875B              # cunseal ca4, ca5, ca1
    TAG4    1, 58
    PERM4   0x7E, 59

    SEAL_AUTH 1
    .word   0x16B607DB              # cseal ca5, ca2, ca1  Xs1
    .word   0x18B7875B              # cunseal ca4, ca5, ca1
    TAG4    1, 60
    PERM4   0x1EB, 61

    # ── Tests 62-92: modifying a sealed capability ───────────────────────────
    SET_TRAP_VECTOR .Lvec_modify
    SEAL_AUTH 9
    .word   0x16B506DB              # cseal ca3, ca0, ca1  ca3 = Ds9 (tag checked in test 36)

    .word   0x2206875B              # cincaddr ca4, ca3, zero
    TAG4    0, 62
    .word   0x2205075B              # cincaddr ca4, ca0, zero
    TAG4    1, 63
    .word   0x0006975B              # cincaddrimm ca4, ca3, 0
    TAG4    0, 64
    .word   0x0005175B              # cincaddrimm ca4, ca0, 0
    TAG4    1, 65
    .word   0xFEF682DB              # cgetaddr t0, ca3
    .word   0x2056875B              # csetaddr ca4, ca3, t0
    TAG4    0, 66
    .word   0x2055075B              # csetaddr ca4, ca0, t0
    TAG4    1, 67
    li      t0, 8
    .word   0x1056875B              # csetbounds ca4, ca3, t0
    TAG4    0, 68
    .word   0x1055075B              # csetbounds ca4, ca0, t0
    TAG4    1, 69
    .word   0x1256875B              # csetboundsexact ca4, ca3, t0
    TAG4    0, 70
    .word   0x1255075B              # csetboundsexact ca4, ca0, t0
    TAG4    1, 71
    .word   0x0086A75B              # csetboundsimm ca4, ca3, 8
    TAG4    0, 72
    .word   0x0085275B              # csetboundsimm ca4, ca0, 8
    TAG4    1, 73
    .word   0x1456875B              # csetboundsrounddown ca4, ca3, t0
    TAG4    0, 74
    .word   0x1455075B              # csetboundsrounddown ca4, ca0, t0
    TAG4    1, 75

    .word   0xFEA681DB              # cmove c3, ca3  CGP = Ds9
    .word   0x0000077B              # auicgp ca4, 0
    TAG4    0, 76
    .word   0xFEA501DB              # cmove c3, ca0  CGP = D
    .word   0x0000077B              # auicgp ca4, 0
    TAG4    1, 77
    .word   0xFEF7035B              # cgetaddr t1, ca4
    LA_PC   t2, buf, t0
    bne     t1, t2, .Lfail_78

    li      t0, 0xFFF
    .word   0x1A56875B              # candperm ca4, ca3, t0
    TAG4    1, 79
    .word   0xFE17035B              # cgettype t1, ca4
    li      t2, 9
    bne     t1, t2, .Lfail_80
    PERM4   0x7F, 81
    li      t0, 0xFFE
    .word   0x1A56875B              # candperm ca4, ca3, t0
    TAG4    1, 82
    .word   0xFE17035B              # cgettype t1, ca4
    li      t2, 9
    bne     t1, t2, .Lfail_83
    PERM4   0x7E, 84
    li      t0, -2
    .word   0x1A56875B              # candperm ca4, ca3, t0
    TAG4    1, 85
    li      t0, 0xFFD
    .word   0x1A56875B              # candperm ca4, ca3, t0
    TAG4    0, 86
    li      t0, 0x7FF
    .word   0x1A56875B              # candperm ca4, ca3, t0
    TAG4    0, 87
    li      t0, 0xFFD
    .word   0x1A55075B              # candperm ca4, ca0, t0
    TAG4    1, 88
    PERM4   0x7D, 89

    SEAL_AUTH 1
    .word   0x16B607DB              # cseal ca5, ca2, ca1  Xs1
    li      t0, 0xFFE
    .word   0x1A57875B              # candperm ca4, ca5, t0
    TAG4    1, 90
    .word   0xFE17035B              # cgettype t1, ca4
    li      t2, 1
    bne     t1, t2, .Lfail_91
    PERM4   0x1EA, 92

    # ── Tests 93-95: interrupt state, before the first deliberate trap ───────
    csrr    t1, mstatus
    andi    t1, t1, 8
    beqz    t1, .Lfail_93
    csrr    t1, mcause
    bnez    t1, .Lfail_94
    csrr    t1, mip
    bnez    t1, .Lfail_95

    # ── Tests 96-98: controls, unsealed authorities ──────────────────────────
    SET_TRAP_VECTOR .Lvec_ls_ctrl
    li      t2, 0x13572468
    sw      t2, 0(a0)               # through D
    .word   0x00C53823              # csc ca2, 16(ca0)  slot 2 <- X (tagged)
    lw      t1, 0(a0)               # through D
    bne     t1, t2, .Lfail_96
    lw      t1, 0(a2)               # through X (EX, LD)
    bne     t1, t2, .Lfail_97

    # sealed operands for the faults: ca3 = Ds9, ca4 = Xs1
    SEAL_AUTH 9
    .word   0x16B506DB              # cseal ca3, ca0, ca1
    SEAL_AUTH 1
    .word   0x16B6075B              # cseal ca4, ca2, ca1

    # ── Tests 99-103: lw through a data-sealed cap ───────────────────────────
    SET_TRAP_VECTOR .Lvec_f1
    li      s0, 0x0BADF00D
.Lfault_f1:
    lw      s0, 0(a3)               # FAULT: ca3 sealed
    j       .Lfail_99
.Ltrap_f1:
    SET_TRAP_VECTOR .Lvec_post
    FAULT_CSRS 0x1A3, .Lfault_f1, 100, 101, 102
    li      t2, 0x0BADF00D
    bne     s0, t2, .Lfail_103
    RESUME  .Lnext_f2
.Lnext_f2:

    # ── Tests 104-108: sw through a data-sealed cap ──────────────────────────
    SET_TRAP_VECTOR .Lvec_f2
    li      t2, 0x5555AAAA
.Lfault_f2:
    sw      t2, 0(a3)               # FAULT: ca3 sealed
    j       .Lfail_104
.Ltrap_f2:
    SET_TRAP_VECTOR .Lvec_post
    FAULT_CSRS 0x1A3, .Lfault_f2, 105, 106, 107
    lw      t1, 0(a0)
    li      t2, 0x13572468
    bne     t1, t2, .Lfail_108
    RESUME  .Lnext_f3
.Lnext_f3:

    # ── Tests 109-113: lw through a sentry ───────────────────────────────────
    SET_TRAP_VECTOR .Lvec_f3
    li      s0, 0x0BADF00D
.Lfault_f3:
    lw      s0, 0(a4)               # FAULT: ca4 is a sentry
    j       .Lfail_109
.Ltrap_f3:
    SET_TRAP_VECTOR .Lvec_post
    FAULT_CSRS 0x1C3, .Lfault_f3, 110, 111, 112
    li      t2, 0x0BADF00D
    bne     s0, t2, .Lfail_113
    RESUME  .Lnext_f4
.Lnext_f4:

    # ── Tests 114-118: sw through a sentry ───────────────────────────────────
    SET_TRAP_VECTOR .Lvec_f4
    li      t2, 0x5555AAAA
.Lfault_f4:
    sw      t2, 0(a4)               # FAULT: ca4 is a sentry (and lacks SD)
    j       .Lfail_114
.Ltrap_f4:
    SET_TRAP_VECTOR .Lvec_post
    FAULT_CSRS 0x1C3, .Lfault_f4, 115, 116, 117
    lw      t1, 0(a0)
    li      t2, 0x13572468
    bne     t1, t2, .Lfail_118
    RESUME  .Lnext_f5
.Lnext_f5:

    # ── Tests 119-123: CLC through a data-sealed cap ─────────────────────────
    SET_TRAP_VECTOR .Lvec_f5
    li      a5, 0x0BADF00D          # ca5 := untagged, address 0x0BADF00D
.Lfault_f5:
    .word   0x0106B783              # clc ca5, 16(ca3)  FAULT: ca3 sealed
    j       .Lfail_119
.Ltrap_f5:
    SET_TRAP_VECTOR .Lvec_post
    FAULT_CSRS 0x1A3, .Lfault_f5, 120, 121, 122
    .word   0xFE47835B              # cgettag t1, ca5
    bnez    t1, .Lfail_123
    .word   0xFEF7835B              # cgetaddr t1, ca5
    li      t2, 0x0BADF00D
    bne     t1, t2, .Lfail_123
    RESUME  .Lnext_f6
.Lnext_f6:

    # ── Tests 124-128: CSC through a data-sealed cap ─────────────────────────
    SET_TRAP_VECTOR .Lvec_f6
.Lfault_f6:
    .word   0x00A6B823              # csc ca0, 16(ca3)  FAULT: ca3 sealed
    j       .Lfail_124
.Ltrap_f6:
    SET_TRAP_VECTOR .Lvec_post
    FAULT_CSRS 0x1A3, .Lfault_f6, 125, 126, 127
    .word   0x01053783              # clc ca5, 16(ca0)  slot 2 must still hold X
    .word   0x42C7835B              # csetequalexact t1, ca5, ca2
    li      t2, 1
    bne     t1, t2, .Lfail_128
    RESUME  .Lnext_end
.Lnext_end:

    # ── Tests 129-130: interrupt state after the last mret ───────────────────
    SET_TRAP_VECTOR .Lvec_restore
    csrr    t1, mstatus
    andi    t1, t1, 8
    beqz    t1, .Lfail_129
    csrr    t1, mip
    bnez    t1, .Lfail_130

    .word   0x00853183              # clc c3, 8(ca0)  restore gp
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
.Lfail_88:  li a0, 88; ret
.Lfail_89:  li a0, 89; ret
.Lfail_90:  li a0, 90; ret
.Lfail_91:  li a0, 91; ret
.Lfail_92:  li a0, 92; ret
.Lfail_93:  li a0, 93; ret
.Lfail_94:  li a0, 94; ret
.Lfail_95:  li a0, 95; ret
.Lfail_96:  li a0, 96; ret
.Lfail_97:  li a0, 97; ret
.Lfail_98:  li a0, 98; ret
.Lfail_99:  li a0, 99; ret
.Lfail_100: li a0, 100; ret
.Lfail_101: li a0, 101; ret
.Lfail_102: li a0, 102; ret
.Lfail_103: li a0, 103; ret
.Lfail_104: li a0, 104; ret
.Lfail_105: li a0, 105; ret
.Lfail_106: li a0, 106; ret
.Lfail_107: li a0, 107; ret
.Lfail_108: li a0, 108; ret
.Lfail_109: li a0, 109; ret
.Lfail_110: li a0, 110; ret
.Lfail_111: li a0, 111; ret
.Lfail_112: li a0, 112; ret
.Lfail_113: li a0, 113; ret
.Lfail_114: li a0, 114; ret
.Lfail_115: li a0, 115; ret
.Lfail_116: li a0, 116; ret
.Lfail_117: li a0, 117; ret
.Lfail_118: li a0, 118; ret
.Lfail_119: li a0, 119; ret
.Lfail_120: li a0, 120; ret
.Lfail_121: li a0, 121; ret
.Lfail_122: li a0, 122; ret
.Lfail_123: li a0, 123; ret
.Lfail_124: li a0, 124; ret
.Lfail_125: li a0, 125; ret
.Lfail_126: li a0, 126; ret
.Lfail_127: li a0, 127; ret
.Lfail_128: li a0, 128; ret
.Lfail_129: li a0, 129; ret
.Lfail_130: li a0, 130; ret
.Lfail_131: li a0, 131; ret
.Lfail_132: li a0, 132; ret
.Lfail_133: li a0, 133; ret
.Lfail_134: li a0, 134; ret
.Lfail_135: li a0, 135; ret
.Lfail_136: li a0, 136; ret

    .data
    .balign 8
buf:                                # +0 data word, +8 saved gp, +16 cap slot
    .space  32
