# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_revoke_load_barrier — the revoked arm of TRVK (REQ_TMP_01)
# =============================================================================
# A CLC of a tagged capability whose BASE lies in a revoked heap granule must
# return it untagged, every other field intact; SE/US/U0 (sealing) capabilities
# are exempt; a base outside TRVK's bitmap window is never looked up. Expected
# values come from CHERIoT-Sail (cheri_insts.sail LoadCapImm, cheri_mem.sail
# mem_read_cap_revoked), which the cosim also runs on the same bitmap.
#
# Needs the testlist plusargs (ibex_revbm_pkg.sv): without them nothing is
# revoked and test 2 fails, which is the negative control.
#   +revbm_mode=range +revbm_heap_base=80000000
#   +revbm_revoke_list=80018000:40,80018080:8,8001fff8:8,80000000:8
#   +revbm_err_list=80019000:100
# With heap base H = 0x80000000 TRVK's window is [H, H+128 KiB): granule
# g = (base-H)>>3 is bit g[4:0] of bitmap word g>>5 (512 words).
#   0x80018000..0x8001803F  word 0x180 bits 0-7    revoked
#   0x80018080              word 0x180 bit  16     revoked (bit_mid bin)
#   0x8001FFF8              word 0x1FF bit  31     revoked (last word, top bit)
#   0x80000000              word 0x000 bit  0      revoked (first granule)
#   0x80019000..0x800190FF  word 0x190, all bits   bitmap ERROR (data 0)
# TRVK treats a bitmap error as revoked (ibex_trvk.sv revbm_revoked); the TB
# requires alert_major_bus in that cycle (RevbmInjectedErrRaisesBusAlert) and
# allows it there only (NoAlertsTriggered). The same .S runs as
# cheriot_revoke_load_barrier_intg with +revbm_err_kind=intg (bad ECC instead
# of trvk_revbm_err_i).
#
# How each check can fail
# -----------------------
#   Test 1  CGetTag(ca0) = 1. Precondition: the slot authority is valid.
# Revoked arm (all built from MTDC, so not sealing caps):
#   Test 2  base 0x80018000 len 8: tag 0.
#           Fails if: no lookup is made (revbm_req_required), the bitmap word
#           or bit is mis-addressed, or upstream_tag_o ignores the verdict.
#           Also what fails when the plusargs are missing.
#   Test 3  ...address word = 0x80018000 (integer half delivered).
#   Test 4  ...CSetEqualExact(loaded, CClearTag(stored)) = 1: only the tag
#           differs. Fails if revocation corrupts bounds/perms/otype.
#   Test 5  base 0x80018038 (bit 7): tag 0. Bit select within a byte.
#   Test 6  base 0x80018004 len 4: tag 0. A base inside a granule selects
#           that granule (Sail align_down; TRVK >>3).
#   Test 7  base 0x80018000 len 0x100, cursor 0x800180C0 (a live granule):
#           tag 0. Fails if the lookup uses the address instead of the base.
#   Test 8  ...address word = 0x800180C0.
#   Test 9  base 0x80018080 (bit 16): tag 0.
#   Test 10 base 0x8001FFF8 (word 511, bit 31): tag 0. Top of the window.
#   Test 11 base 0x80000000 (word 0, bit 0): tag 0. Bottom of the window.
# Live arm (same words, neighbouring bits):
#   Test 12 base 0x80018040 (bit 8, next to the revoked byte): tag 1.
#           Fails if: the bit select is off by one / byte-granular, or the
#           revoked verdict is sticky across lookups.
#   Test 13 ...CSetEqualExact(loaded, stored) = 1.
#   Test 14 base 0x80018078 (bit 15): tag 1.
#   Test 15 base 0x80018088 (bit 17): tag 1.
#   Test 16 base 0x80017FC0 len 0x80, cursor 0x80018000 (bounds cover the
#           revoked granule, base does not): tag 1.
#   Test 17 base 0x80000008 (word 0, bit 1): tag 1.
# Out of range: no lookup (revbm_out_of_range), never revoked. Each base
# ALIASES a revoked bit if the range check were missing:
#   Test 18 full-range MTDC, base 0 (below the heap; wraps to word 0 bit 0).
#   Test 19 base 0x80020000 (one past the window; word 0x200 -> 0, bit 0).
#   Test 20 base 0x7FFFFFF8 (one granule below; word 0x1FF bit 31).
# Sealing exemption (cp_trvk_sealing_cap): MScratchC-derived, base
# 0x80018000 (revoked). TRVK cheriot_is_sealing_cap = cperms[4:3]==0 &&
# |cperms[2:0]; Sail isSealingCap = permit_seal | permit_unseal | perm_user0.
#   Test 21 CGetPerm = 0xE01 (GL + perm bits 9,10,11). Precondition.
#   Test 22 ...tag 1.
#   Test 23 CGetPerm = 0x801 (only bit 11). Precondition.
#   Test 24 ...tag 1.
#   Test 25 CGetPerm = 0x401 (only bit 10). Precondition.
#   Test 26 ...tag 1.
#   Test 27 CGetPerm = 0x201 (only bit 9). Precondition.
#   Test 28 ...tag 1.
#   Test 29 CGetPerm = 0x001 (none of the three). Precondition.
#   Test 30 ...tag 0: not a sealing capability, so revoked.
# Sealed is not sealing:
#   Test 31 CGetType(CSeal(data cap @0x80018000, otype 9)) = 9. Precondition.
#   Test 32 ...reloaded: tag 0. Fails if "sealed" is confused with "sealing".
# Bitmap error (word 0x190):
#   Test 33 base 0x80019000: tag 0 (error revokes although the data bit is 0).
#   Test 34 base 0x800190F8 (last granule of the word): tag 0.
#   Test 35 base 0x80019100 (next word, no error): tag 1.
# Back to back (lookup serialisation, cp_trvk_outstanding):
#   Test 36 CLC of the revoked cap, then immediately CLC of a live one:
#           first tag 0.
#   Test 37 ...second tag 1. Fails if the second load reuses the first
#           verdict or its lookup is dropped.
#   Test 38 Any trap: the test-local vector was entered.
#
# Trap handling and register use as in cheriot_perm_lc_sc: MTCC points at a
# test-local vector that jumps to a failure label; no mret. ca0 = slot
# authority (MTDC, cursor at cap_slots), ca2 = capability under test, ca3 =
# second capability, ca4/ca5 = loaded values / CClearTag reference. Integer
# scratch only t0, t1, t2 (c6 is the MTCC install scratch). No x16-x31.
#
# Instruction encodings (opcode 0x5B unless noted), computed from the Sail
# encdec fields with a formula that reproduces 29 words already used in
# cheriot_perm_lc_sc / cheriot_cseal_cunseal / cheriot_cap_type:
#   cspecialr   ca0, mtdc          = .word 0x03D0055B  (known)
#   csetaddr    ca0, ca0, t0       = .word 0x2055055B  (known)
#   cgettag     t1, ca0            = .word 0xFE45035B
#   cspecialr   ca2, mtdc          = .word 0x03D0065B  (known)
#   cspecialr   ca2, mscratchc     = .word 0x03E0065B  (known)
#   csetaddr    ca2, ca2, t0       = .word 0x2056065B  (known)
#   csetbounds  ca2, ca2, t0       = .word 0x1056065B  (funct7=0x08)
#   candperm    ca2, ca2, t0       = .word 0x1A56065B  (funct7=0x0D)
#   cgetperm    t1, ca2            = .word 0xFE06035B  (known)
#   cgettype    t1, ca2            = .word 0xFE16035B  (rs2=0x01)
#   cspecialr   ca3, mtdc          = .word 0x03D006DB  (known)
#   csetaddr    ca3, ca3, t0       = .word 0x205686DB  (known)
#   csetbounds  ca3, ca3, t0       = .word 0x105686DB
#   cspecialr   ca5, mscratchc     = .word 0x03E007DB
#   csetaddr    ca5, ca5, t0       = .word 0x205787DB
#   cseal       ca2, ca3, ca5      = .word 0x16F6865B  (funct7=0x0B)
#   csc         ca2, 0(ca0)        = .word 0x00C53023  (known, STORE f3=3)
#   csc         ca3, 8(ca0)        = .word 0x00D53423  (known)
#   clc         ca4, 0(ca0)        = .word 0x00053703  (known, LOAD f3=3)
#   clc         ca5, 8(ca0)        = .word 0x00853783
#   cgettag     t1, ca4            = .word 0xFE47035B  (known)
#   cgettag     t1, ca5            = .word 0xFE47835B  (known)
#   cgetaddr    t1, ca4            = .word 0xFEF7035B  (known)
#   ccleartag   ca5, ca2           = .word 0xFEB607DB  (known)
#   csetequalexact t1, ca4, ca2    = .word 0x42C7035B  (known)
#   csetequalexact t1, ca4, ca5    = .word 0x42F7035B  (known)
# Trap-vector install (crt_cheriot.S): 0x03C0035B, 0x2053035B, 0x03C3005B.

.macro SET_TRAP_VECTOR label
    la      t0, \label
    .word   0x03C0035B              # cspecialr c6, mtcc
    .word   0x2053035B              # csetaddr  c6, c6, t0
    .word   0x03C3005B              # cspecialw mtcc, c6
.endm

# ca2 <- MTDC bounded to [base, base+len), cursor = base.
.macro MKCAP base, len
    .word   0x03D0065B              # cspecialr  ca2, mtdc
    li      t0, \base
    .word   0x2056065B              # csetaddr   ca2, ca2, t0
    li      t0, \len
    .word   0x1056065B              # csetbounds ca2, ca2, t0
.endm

# ca2 <- MScratchC (seal root) bounded to [base, base+8), perms & mask.
.macro MKSEAL base, mask
    .word   0x03E0065B              # cspecialr  ca2, mscratchc
    li      t0, \base
    .word   0x2056065B              # csetaddr   ca2, ca2, t0
    li      t0, 8
    .word   0x1056065B              # csetbounds ca2, ca2, t0
    li      t0, \mask
    .word   0x1A56065B              # candperm   ca2, ca2, t0
.endm

# ca2 -> slot 0 -> ca4, then require CGetTag(ca4) = tag.
.macro EXPECT_TAG tag, code
    .word   0x00C53023              # csc     ca2, 0(ca0)
    .word   0x00053703              # clc     ca4, 0(ca0)
    .word   0xFE47035B              # cgettag t1, ca4
    li      t2, \tag
    bne     t1, t2, .Lfail_test\code
.endm

.macro EXPECT_PERM perm, code
    .word   0xFE06035B              # cgetperm t1, ca2
    li      t2, \perm
    bne     t1, t2, .Lfail_test\code
.endm

    .text
    .globl main

.balign 4
.Lvec_unexpected:
    j       .Lfail_test38

main:
    SET_TRAP_VECTOR .Lvec_unexpected

    la      t0, cap_slots
    .word   0x03D0055B              # cspecialr ca0, mtdc
    .word   0x2055055B              # csetaddr  ca0, ca0, t0   -> slot 0
    .word   0xFE45035B              # cgettag   t1, ca0
    li      t2, 1
    bne     t1, t2, .Lfail_test1

    # ── Revoked arm ──────────────────────────────────────────────────────────
    MKCAP   0x80018000, 8
    EXPECT_TAG 0, 2
    .word   0xFEF7035B              # cgetaddr t1, ca4
    li      t2, 0x80018000
    bne     t1, t2, .Lfail_test3
    .word   0xFEB607DB              # ccleartag ca5, ca2
    .word   0x42F7035B              # csetequalexact t1, ca4, ca5
    li      t2, 1
    bne     t1, t2, .Lfail_test4

    MKCAP   0x80018038, 8
    EXPECT_TAG 0, 5
    MKCAP   0x80018004, 4
    EXPECT_TAG 0, 6

    MKCAP   0x80018000, 0x100
    li      t0, 0x800180C0
    .word   0x2056065B              # csetaddr ca2, ca2, t0   (cursor in a live granule)
    EXPECT_TAG 0, 7
    .word   0xFEF7035B              # cgetaddr t1, ca4
    li      t2, 0x800180C0
    bne     t1, t2, .Lfail_test8

    MKCAP   0x80018080, 8
    EXPECT_TAG 0, 9
    MKCAP   0x8001FFF8, 8
    EXPECT_TAG 0, 10
    MKCAP   0x80000000, 8
    EXPECT_TAG 0, 11

    # ── Live arm ─────────────────────────────────────────────────────────────
    MKCAP   0x80018040, 8
    EXPECT_TAG 1, 12
    .word   0x42C7035B              # csetequalexact t1, ca4, ca2
    li      t2, 1
    bne     t1, t2, .Lfail_test13
    MKCAP   0x80018078, 8
    EXPECT_TAG 1, 14
    MKCAP   0x80018088, 8
    EXPECT_TAG 1, 15
    MKCAP   0x80017FC0, 0x80
    li      t0, 0x80018000
    .word   0x2056065B              # csetaddr ca2, ca2, t0   (cursor in the revoked granule)
    EXPECT_TAG 1, 16
    MKCAP   0x80000008, 8
    EXPECT_TAG 1, 17

    # ── Out of range ─────────────────────────────────────────────────────────
    .word   0x03D0065B              # cspecialr ca2, mtdc     (base 0, full range)
    EXPECT_TAG 1, 18
    MKCAP   0x80020000, 8
    EXPECT_TAG 1, 19
    MKCAP   0x7FFFFFF8, 8
    EXPECT_TAG 1, 20

    # ── Sealing exemption (base in revoked granule 0x80018000) ───────────────
    MKSEAL  0x80018000, 0xE01
    EXPECT_PERM 0xE01, 21
    EXPECT_TAG 1, 22
    MKSEAL  0x80018000, 0x801
    EXPECT_PERM 0x801, 23
    EXPECT_TAG 1, 24
    MKSEAL  0x80018000, 0x401
    EXPECT_PERM 0x401, 25
    EXPECT_TAG 1, 26
    MKSEAL  0x80018000, 0x201
    EXPECT_PERM 0x201, 27
    EXPECT_TAG 1, 28
    MKSEAL  0x80018000, 0x001
    EXPECT_PERM 0x001, 29
    EXPECT_TAG 0, 30

    # ── Sealed (otype 9) data capability is still revoked ────────────────────
    .word   0x03D006DB              # cspecialr  ca3, mtdc
    li      t0, 0x80018000
    .word   0x205686DB              # csetaddr   ca3, ca3, t0
    li      t0, 8
    .word   0x105686DB              # csetbounds ca3, ca3, t0
    .word   0x03E007DB              # cspecialr  ca5, mscratchc
    li      t0, 9
    .word   0x205787DB              # csetaddr   ca5, ca5, t0   (otype 9)
    .word   0x16F6865B              # cseal      ca2, ca3, ca5
    .word   0xFE16035B              # cgettype   t1, ca2
    li      t2, 9
    bne     t1, t2, .Lfail_test31
    EXPECT_TAG 0, 32

    # ── Bitmap error word ────────────────────────────────────────────────────
    MKCAP   0x80019000, 8
    EXPECT_TAG 0, 33
    MKCAP   0x800190F8, 8
    EXPECT_TAG 0, 34
    MKCAP   0x80019100, 8
    EXPECT_TAG 1, 35

    # ── Back-to-back lookups ─────────────────────────────────────────────────
    MKCAP   0x80018000, 8           # ca2: revoked
    .word   0x03D006DB              # cspecialr  ca3, mtdc
    li      t0, 0x80018040
    .word   0x205686DB              # csetaddr   ca3, ca3, t0
    li      t0, 8
    .word   0x105686DB              # csetbounds ca3, ca3, t0   (ca3: live)
    .word   0x00C53023              # csc ca2, 0(ca0)
    .word   0x00D53423              # csc ca3, 8(ca0)
    .word   0x00053703              # clc ca4, 0(ca0)
    .word   0x00853783              # clc ca5, 8(ca0)
    .word   0xFE47035B              # cgettag t1, ca4
    bnez    t1, .Lfail_test36
    .word   0xFE47835B              # cgettag t1, ca5
    li      t2, 1
    bne     t1, t2, .Lfail_test37

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
.Lfail_test35: li a0, 35; ret
.Lfail_test36: li a0, 36; ret
.Lfail_test37: li a0, 37; ret
.Lfail_test38: li a0, 38; ret

    .data
    .balign 8
cap_slots:                          # slots 0-1 at +0, +8
    .space  16
