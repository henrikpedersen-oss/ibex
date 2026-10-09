# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_perm_lc_sc — CLC/CSC through an authority without MC
# =============================================================================
# CHERIoT has ONE permission for moving capabilities through memory: MC
# (Permit_Load_Store_Capability, bit 6 of the CGetPerm word). CHERIoT-Sail
# (cheri_insts.sail, LoadCapImm / StoreCapImm) uses the one field
# permit_load_store_cap for both directions; there is no separate "LC" and
# "SC" bit. So the "no-LC" and the "no-SC" authority are the same capability.
#
# What CHERIoT-Sail says (all expected values below come from here):
#   CLC  auth tagged, unsealed, LD, in bounds, aligned, but no MC
#          -> no exception; cd = memory value with tag := 0. Nothing else is
#             changed: the LG/LM attenuation (GL, LG, SD, LM cleared) only
#             applies "if cr.tag", and the tag is already clear, so the
#             loaded perms, bounds and address are exactly what was stored.
#   CSC  auth tagged, unsealed, SD, but no MC, cs2 TAGGED
#          -> CapEx_PermitStoreCapViolation (0x15) against cs1, raised
#             before the bounds and alignment checks; nothing is written.
#   CSC  same authority, cs2 UNTAGGED
#          -> no exception (the check is "not(MC) & cs2.tag"); the full
#             64-bit value is written with tag 0 (translateAddr(Write(Data))).
#   mtval = (0 @ regidx) @ capcause = (11 << 5) | 0x15 = 0x175 for cs1 = ca1.
#
# Authorities (both derived from MTDC, perms 0x07F = GL LG SD LM SL LD MC):
#   ca0  MC present:  perms 0x07F.
#   ca1  MC absent:   CAndPerm(ca0, 0x25) -> 0x25 = GL SD LD.
#        0x25 is chosen because it is a fixed point of the permission
#        compression: without MC, LD|SD can only be encoded in the mem-data
#        format (capToEncCap), which has no room for LG, LM or SL. A mask of
#        0x3F (just "clear MC") would therefore also decode to 0x25; check 3
#        confirms the perms so a compression surprise shows up there and not
#        as a confusing failure further down.
# Stored capabilities (full-range MTDC derivatives, so any cursor is
# representable):
#   ca2  global: perms 0x07F, address G = 0x80001230.
#   ca3  local:  CAndPerm(.., 0x7E) (GL cleared), perms 0x07E, address
#        L = 0x80004560. ca0 has SL, so storing it through ca0 keeps its tag.
#
# Memory: four 8-byte slots in .data (not 0x80080000):
#   slot 0  global cap stored through ca0     slot 2  target of the denied CSC
#   slot 1  local cap stored through ca0      slot 3  target of the untagged CSC
# Slots 2 and 3 are pre-loaded with the tagged local cap, so an unwanted
# write (slot 2) or a missing write (slot 3) is visible in both tag and data.
#
# How each check can fail
# -----------------------
# Preconditions (not RTL bugs in the feature under test, but a failure here
# would make the later checks meaningless):
#   Test 1  CGetPerm(ca0) = 0x07F.   MTDC reset perms / CSetAddr changed perms.
#   Test 2  CGetTag(ca1) = 1.        CAndPerm cleared the tag of an unsealed cap.
#   Test 3  CGetPerm(ca1) = 0x025.   CAndPerm / compression did not give GL SD LD.
#   Test 4  CGetPerm(ca2) = 0x07F.   Global stored cap is not what we think.
#   Test 5  CGetPerm(ca3) = 0x07E.   Local stored cap still has GL.
# Controls, through ca0 (MC present) -- the same path, which must keep the tag:
#   Test 6  CLC slot 0 via ca0: tag = 1.
#           Fails if: lc_ctag (ibex_cheriot_ex.sv, CLOAD_CAP) is set although
#           MC is present, CSC did not drive data_tag_o, or TRVK revokes.
#   Test 7  ...and CSetEqualExact(loaded, ca2) = 1 (exact round trip).
#   Test 8  CLC slot 1 (local) via ca0: tag = 1.
#           Fails if: the local cap lost its tag on the SL-authorised CSC
#           (perm_vio_slc wrong) or on the load.
#   Test 9  ...and CSetEqualExact(loaded, ca3) = 1.
# REQ_PER_04 / REQ_LOC_03 -- CLC through ca1 (no MC):
#   Test 10 A trap was taken during the two no-MC CLCs.
#           Fails if: the RTL raises an exception (e.g. capcause 0x14
#           Permit_Load_Capability) instead of silently clearing the tag.
#   Test 11 Global cap: tag = 0.
#           Fails if: lc_ctag is not driven from ~perms.MC, or
#           cheriot_mem_to_cap ignores clrperm.CTAG (cap.valid).
#   Test 12 ...address word = G.  Fails if: the integer half is dropped or
#           zeroed together with the tag (the data word must still arrive).
#   Test 13 ...perms = 0x07F (GL still set).
#           Fails if: the GL/LG/SD/LM attenuation (ca1 lacks LG and LM) is
#           applied to an untagged result; Sail and cheriot_mask_loaded_cperms
#           gate it on the tag.
#   Test 14 ...CSetEqualExact(loaded, CClearTag(ca2)) = 1: only the tag differs.
#           Fails if: any other field (bounds, otype, reserved) is altered.
#   Test 15 Local cap: tag = 0.      As test 11, for a Global=0 capability.
#   Test 16 ...address word = L.     As test 12.
#   Test 17 ...perms = 0x07E.        As test 13.
#   Test 18 ...CSetEqualExact(loaded, CClearTag(ca3)) = 1.  As test 14.
# REQ_PER_05, untagged half -- CSC of an untagged value through ca1:
#   Test 19 CGetTag(CClearTag(ca2)) = 0.  Precondition: the source is untagged.
#   Test 20 A trap was taken by this CSC.
#           Fails if: PVIO_SC (ibex_cheriot_ex.sv, perm_vio_vec) ignores
#           cs2's tag and faults every CSC through a no-MC authority.
#   Test 21 CLC slot 3 via ca0: tag = 0 (slot previously held a tagged cap).
#           Fails if: data_tag_o is driven from something other than
#           cs2.valid (e.g. a stale tag), forging a capability.
#   Test 22 ...address word = G.  Fails if: the store was suppressed.
#   Test 23 ...CSetEqualExact(loaded, source) = 1.
#           Fails if: the metadata word was not written (only half a store).
# Interrupt state, before the deliberate fault (no interrupt expected):
#   Tests 24-26  mstatus.MIE = 1, mcause = 0, mip = 0.
# REQ_PER_05, tagged half -- CSC of tagged ca2 through ca1 into slot 2:
#   Test 27 The CSC traps (reaching the next instruction means it did not).
#           Fails if: PVIO_SC is not computed, or not included in the CSC
#           fault condition.
#   Test 28 mcause = 28 (CHERI fault).
#   Test 29 mtval[4:0] = 0x15 (Permit_Store_Capability), not SD/bounds/etc.
#           Fails if: exception priority is wrong or a different perm bit
#           is checked.
#   Test 30 mtval = 0x175: cause reported against cs1 = c11 (the authority),
#           not cs2 = c12. Fails if: the wrong register index is recorded.
#   Test 31 MEPCC address = the faulting CSC.
#   Test 32 CLC slot 2 via ca0: tag = 1 -- the denied store left the old
#           tagged value in place. Fails if: the store was still issued
#           (with or without the tag) before the fault took effect.
#   Test 33 ...CSetEqualExact(loaded, ca3) = 1: the data words are unchanged.
#   Test 34 Any other trap (setup, controls, interrupt checks): the generic
#           test-local vector was entered. mcause/mtval in the trace say why.
#
# Trap handling
# -------------
# As in cheriot_revoke_basic / juliet_cwe131_fault: crt_cheriot.S's trap_entry
# cannot return under CHERIoT, so MTCC is pointed at test-local vectors that
# jump straight to a failure label (or, for the deliberate fault, to
# .Ltrap_taken). Each section that might trap wrongly gets its own vector, so
# an unexpected trap reports which section it came from. A vector does no
# memory or CSR access and never executes mret; after a trap mstatus.MIE stays
# clear, which is why the interrupt checks run before the deliberate fault.
# Vectors must be 4-byte aligned or the MTCC write clears the tag.
#
# Register use: ca0 = MC authority, ca1 = no-MC authority, ca2 = global cap,
# ca3 = local cap, ca4 = loaded value, ca5 = CClearTag reference. Integer
# scratch is only t0, t1, t2 (c6 is the MTCC install scratch, as in crt).
# ca0-ca5 are never an integer destination after setup: aN and caN are the
# same register. No x16-x31.
#
# Instruction encodings (opcode 0x5B unless noted), from the Sail encdec
# clauses and cross-checked against the words in cheriot_revoke_basic,
# cheriot_rtos_cmove and cheriot_rtos_isequal:
#   cspecialr   ca0, mtdc          = .word 0x03D0055B  (funct7=0x01, SCR 29)
#   csetaddr    ca0, ca0, t0       = .word 0x2055055B  (funct7=0x10)
#   cgetperm    t1, ca0            = .word 0xFE05035B  (funct7=0x7F, rs2=0x00)
#   candperm    ca1, ca0, t0       = .word 0x1A5505DB  (funct7=0x0D)
#   cgettag     t1, ca1            = .word 0xFE45835B  (rs2=0x04)
#   cgetperm    t1, ca1            = .word 0xFE05835B
#   cspecialr   ca2, mtdc          = .word 0x03D0065B
#   csetaddr    ca2, ca2, t0       = .word 0x2056065B
#   cgetperm    t1, ca2            = .word 0xFE06035B
#   cspecialr   ca3, mtdc          = .word 0x03D006DB
#   csetaddr    ca3, ca3, t0       = .word 0x205686DB
#   candperm    ca3, ca3, t0       = .word 0x1A5686DB
#   cgetperm    t1, ca3            = .word 0xFE06835B
#   csc         ca2, 0(ca0)        = .word 0x00C53023  (STORE funct3=3)
#   csc         ca3, 8(ca0)        = .word 0x00D53423
#   csc         ca3, 16(ca0)       = .word 0x00D53823
#   csc         ca3, 24(ca0)       = .word 0x00D53C23
#   csc         ca5, 24(ca1)       = .word 0x00F5BC23
#   csc         ca2, 16(ca1)       = .word 0x00C5B823
#   clc         ca4, 0(ca0)        = .word 0x00053703  (LOAD funct3=3)
#   clc         ca4, 8(ca0)        = .word 0x00853703
#   clc         ca4, 16(ca0)       = .word 0x01053703
#   clc         ca4, 24(ca0)       = .word 0x01853703
#   clc         ca4, 0(ca1)        = .word 0x0005B703
#   clc         ca4, 8(ca1)        = .word 0x0085B703
#   cgettag     t1, ca4            = .word 0xFE47035B
#   cgetaddr    t1, ca4            = .word 0xFEF7035B  (rs2=0x0F)
#   cgetperm    t1, ca4            = .word 0xFE07035B
#   ccleartag   ca5, ca2           = .word 0xFEB607DB  (rs2=0x0B)
#   ccleartag   ca5, ca3           = .word 0xFEB687DB
#   cgettag     t1, ca5            = .word 0xFE47835B
#   csetequalexact t1, ca4, ca2    = .word 0x42C7035B  (funct7=0x21)
#   csetequalexact t1, ca4, ca3    = .word 0x42D7035B
#   csetequalexact t1, ca4, ca5    = .word 0x42F7035B
#   cspecialr   ct1, mepcc         = .word 0x03F0035B  (SCR 31)
#   cgetaddr    t1, ct1            = .word 0xFEF3035B
# Trap-vector install (from crt_cheriot.S, c6/t0):
#   cspecialr   c6, mtcc           = .word 0x03C0035B
#   csetaddr    c6, c6, t0         = .word 0x2053035B
#   cspecialw   mtcc, c6           = .word 0x03C3005B

# Point MTCC at a test-local vector. Clobbers t0 and c6 (t1).
.macro SET_TRAP_VECTOR label
    la      t0, \label
    .word   0x03C0035B              # cspecialr c6, mtcc
    .word   0x2053035B              # csetaddr  c6, c6, t0
    .word   0x03C3005B              # cspecialw mtcc, c6
.endm

    .text
    .globl main

# Test-local trap vectors: no memory access, no CSR access, no mret.
.balign 4
.Lvec_unexpected:
    j       .Lfail_test34
.balign 4
.Lvec_clc:
    j       .Lfail_test10
.balign 4
.Lvec_csc_untagged:
    j       .Lfail_test20
.balign 4
.Lvec_expected:
    j       .Ltrap_taken

main:
    csrsi   mstatus, 8              # set mstatus.MIE (bit 3)
    SET_TRAP_VECTOR .Lvec_unexpected

    # ── Setup: authorities ────────────────────────────────────────────────────
    la      t0, cap_slots           # integer address of slot 0 (8-byte aligned)
    .word   0x03D0055B              # cspecialr ca0, mtdc
    .word   0x2055055B              # csetaddr  ca0, ca0, t0   -> slot 0
    li      t0, 0x25                # GL SD LD: no MC
    .word   0x1A5505DB              # candperm  ca1, ca0, t0

    # ── Tests 1-3: authority permissions ──────────────────────────────────────
    .word   0xFE05035B              # cgetperm t1, ca0
    li      t2, 0x7F
    bne     t1, t2, .Lfail_test1
    .word   0xFE45835B              # cgettag  t1, ca1
    li      t2, 1
    bne     t1, t2, .Lfail_test2
    .word   0xFE05835B              # cgetperm t1, ca1
    li      t2, 0x25
    bne     t1, t2, .Lfail_test3

    # ── Setup: the capabilities to be stored ──────────────────────────────────
    li      t0, 0x80001230          # G
    .word   0x03D0065B              # cspecialr ca2, mtdc
    .word   0x2056065B              # csetaddr  ca2, ca2, t0   (global)
    li      t0, 0x80004560          # L
    .word   0x03D006DB              # cspecialr ca3, mtdc
    .word   0x205686DB              # csetaddr  ca3, ca3, t0
    li      t0, 0x7E                # clear GL
    .word   0x1A5686DB              # candperm  ca3, ca3, t0   (local)

    # ── Tests 4-5: stored-capability permissions ──────────────────────────────
    .word   0xFE06035B              # cgetperm t1, ca2
    li      t2, 0x7F
    bne     t1, t2, .Lfail_test4
    .word   0xFE06835B              # cgetperm t1, ca3
    li      t2, 0x7E
    bne     t1, t2, .Lfail_test5

    # ── Control stores through ca0 (MC present) ──────────────────────────────
    .word   0x00C53023              # csc ca2, 0(ca0)    slot 0 <- global
    .word   0x00D53423              # csc ca3, 8(ca0)    slot 1 <- local
    .word   0x00D53823              # csc ca3, 16(ca0)   slot 2 <- local (seed)
    .word   0x00D53C23              # csc ca3, 24(ca0)   slot 3 <- local (seed)

    # ── Tests 6-9: control loads through ca0 keep the tag ─────────────────────
    li      t2, 1
    .word   0x00053703              # clc     ca4, 0(ca0)
    .word   0xFE47035B              # cgettag t1, ca4
    bne     t1, t2, .Lfail_test6
    .word   0x42C7035B              # csetequalexact t1, ca4, ca2
    bne     t1, t2, .Lfail_test7
    .word   0x00853703              # clc     ca4, 8(ca0)
    .word   0xFE47035B              # cgettag t1, ca4
    bne     t1, t2, .Lfail_test8
    .word   0x42D7035B              # csetequalexact t1, ca4, ca3
    bne     t1, t2, .Lfail_test9

    # ── Tests 10-18: CLC through ca1 (no MC) strips the tag, nothing else ─────
    SET_TRAP_VECTOR .Lvec_clc       # test 10: any trap here is a failure

    .word   0x0005B703              # clc     ca4, 0(ca1)    global cap
    .word   0xFE47035B              # cgettag t1, ca4
    bnez    t1, .Lfail_test11
    .word   0xFEF7035B              # cgetaddr t1, ca4
    li      t2, 0x80001230
    bne     t1, t2, .Lfail_test12
    .word   0xFE07035B              # cgetperm t1, ca4
    li      t2, 0x7F
    bne     t1, t2, .Lfail_test13
    .word   0xFEB607DB              # ccleartag ca5, ca2
    .word   0x42F7035B              # csetequalexact t1, ca4, ca5
    li      t2, 1
    bne     t1, t2, .Lfail_test14

    .word   0x0085B703              # clc     ca4, 8(ca1)    local cap
    .word   0xFE47035B              # cgettag t1, ca4
    bnez    t1, .Lfail_test15
    .word   0xFEF7035B              # cgetaddr t1, ca4
    li      t2, 0x80004560
    bne     t1, t2, .Lfail_test16
    .word   0xFE07035B              # cgetperm t1, ca4
    li      t2, 0x7E
    bne     t1, t2, .Lfail_test17
    .word   0xFEB687DB              # ccleartag ca5, ca3
    .word   0x42F7035B              # csetequalexact t1, ca4, ca5
    li      t2, 1
    bne     t1, t2, .Lfail_test18

    # ── Tests 19-23: CSC of an UNTAGGED value through ca1 succeeds ────────────
    .word   0xFEB607DB              # ccleartag ca5, ca2     (address G)
    .word   0xFE47835B              # cgettag   t1, ca5
    bnez    t1, .Lfail_test19

    SET_TRAP_VECTOR .Lvec_csc_untagged  # test 20: a trap here is a failure
    .word   0x00F5BC23              # csc ca5, 24(ca1)       slot 3 <- untagged
    SET_TRAP_VECTOR .Lvec_unexpected

    .word   0x01853703              # clc     ca4, 24(ca0)
    .word   0xFE47035B              # cgettag t1, ca4
    bnez    t1, .Lfail_test21
    .word   0xFEF7035B              # cgetaddr t1, ca4
    li      t2, 0x80001230
    bne     t1, t2, .Lfail_test22
    .word   0x42F7035B              # csetequalexact t1, ca4, ca5
    li      t2, 1
    bne     t1, t2, .Lfail_test23

    # ── Tests 24-26: interrupt state, before the deliberate fault ─────────────
    csrr    t1, mstatus
    andi    t1, t1, 8
    beqz    t1, .Lfail_test24
    csrr    t1, mcause
    bnez    t1, .Lfail_test25
    csrr    t1, mip
    bnez    t1, .Lfail_test26

    # ── Tests 27-33: CSC of a TAGGED cap through ca1 traps ────────────────────
    SET_TRAP_VECTOR .Lvec_expected

.Lcsc_denied:
    .word   0x00C5B823              # csc ca2, 16(ca1)       DENIED: no MC
    j       .Lfail_test27           # reached only if the CSC did not trap

.Ltrap_taken:
    SET_TRAP_VECTOR .Lvec_unexpected
    csrr    t1, mcause
    li      t2, 28                  # CHERI fault
    bne     t1, t2, .Lfail_test28
    csrr    t1, mtval
    andi    t2, t1, 0x1F
    li      t0, 0x15                # Permit_Store_Capability violation
    bne     t2, t0, .Lfail_test29
    li      t2, 0x175               # (11 << 5) | 0x15: authority c11
    bne     t1, t2, .Lfail_test30
    .word   0x03F0035B              # cspecialr ct1, mepcc
    .word   0xFEF3035B              # cgetaddr  t1, ct1
    la      t2, .Lcsc_denied
    bne     t1, t2, .Lfail_test31

    li      t2, 1
    .word   0x01053703              # clc     ca4, 16(ca0)   slot 2
    .word   0xFE47035B              # cgettag t1, ca4
    bne     t1, t2, .Lfail_test32
    .word   0x42D7035B              # csetequalexact t1, ca4, ca3
    bne     t1, t2, .Lfail_test33

    li      a0, 0
    ret

.Lfail_test1:  li a0, 1;  ret
.Lfail_test2:  li a0, 2;  ret
.Lfail_test3:  li a0, 3;  ret
.Lfail_test4:  li a0, 4;  ret
.Lfail_test5:  li a0, 5;  ret
.Lfail_test6:  li a0, 6;  ret
.Lfail_test7:  li a0, 7;  ret
.Lfail_test8:  li a0, 8;  ret
.Lfail_test9:  li a0, 9;  ret
.Lfail_test10: li a0, 10; ret
.Lfail_test11: li a0, 11; ret
.Lfail_test12: li a0, 12; ret
.Lfail_test13: li a0, 13; ret
.Lfail_test14: li a0, 14; ret
.Lfail_test15: li a0, 15; ret
.Lfail_test16: li a0, 16; ret
.Lfail_test17: li a0, 17; ret
.Lfail_test18: li a0, 18; ret
.Lfail_test19: li a0, 19; ret
.Lfail_test20: li a0, 20; ret
.Lfail_test21: li a0, 21; ret
.Lfail_test22: li a0, 22; ret
.Lfail_test23: li a0, 23; ret
.Lfail_test24: li a0, 24; ret
.Lfail_test25: li a0, 25; ret
.Lfail_test26: li a0, 26; ret
.Lfail_test27: li a0, 27; ret
.Lfail_test28: li a0, 28; ret
.Lfail_test29: li a0, 29; ret
.Lfail_test30: li a0, 30; ret
.Lfail_test31: li a0, 31; ret
.Lfail_test32: li a0, 32; ret
.Lfail_test33: li a0, 33; ret
.Lfail_test34: li a0, 34; ret

    .data
    .balign 8
cap_slots:                          # slots 0-3 at +0, +8, +16, +24
    .space  32
