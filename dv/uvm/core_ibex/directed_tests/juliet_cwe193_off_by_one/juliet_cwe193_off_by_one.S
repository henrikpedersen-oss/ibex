# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: juliet_cwe193_off_by_one — CWE-193 Off-by-One Error (CHERIoT)
# =============================================================================
# CWE-193 (NIST Juliet Test Suite): Off-by-One Error.
#
#   char buf[16];
#   for (int i = 0; i <= 16; i++) buf[i] = 0;   // i == 16 writes past the end
#
# CHERI bounds are half-open, [base, top). A cursor AT top is the ordinary C
# one-past-the-end pointer and is legal to form: CHERIoT-Sail (cheri_insts.sail
# CIncAddr -> incCapAddr) clears the tag only if the new address is
# unrepresentable, and for this capability (E = 0) the representable window is
# [base, base + 512), so cursor = top keeps tag 1. The off-by-one is stopped at
# the DEREFERENCE: the byte store at top fails inCapBounds(cap, top, 1)
# (top + 1 > top) and raises a CHERI bounds violation (CapEx_BoundsViolation =
# 0x01); the byte store at top-1 (buf[15]) passes.
#
# The buffer is in .data, followed by a guard word, not at a fixed address:
# 0x80080000 is the bottom of the stack/TLS area, and this test really stores.
# buf = area[0..15]; area[16..19] is the guard word the off-by-one would hit.
#
# How each check can fail
# -----------------------
#   Test 1  CSetBounds(&area, 16): tag = 1.  CSetBounds cleared the tag.
#   Test 2  CIncAddr(+16), cursor = top: tag STILL 1.
#           Fails if CIncAddr clears the tag on reaching top (a [base, top)
#           check) instead of on leaving the representable window.
#   Test 7  ...and CGetAddr = &area + 16: the cursor really is at top.
#   Test 3  Fresh capability, CIncAddr(+15), cursor = top-1: tag = 1.
#   Test 8  sb through that cursor (buf[15]) did NOT trap (control: the last
#           element is writable). Fails if the top check is off by one the
#           other way, which would also make the deliberate fault meaningless.
#   Test 9  ...and area[15] now holds the stored byte.
#   Tests 4-6  mstatus.MIE = 1, mcause = 0, mip = 0 -- checked here, before
#           the deliberate fault, because taking a trap clears MIE and sets
#           mcause.
#   Test 10 sb through the cursor-at-top capability (buf[16]) traps (reaching
#           the next instruction means it did not). Fails if the rv32 LSU top
#           check (ibex_cheriot_ex.sv check_rv32: chkaddr > top33 - 1) accepts
#           an access starting at top.
#   Test 11 mcause = 28 (CHERI fault).
#   Test 12 mtval = (10 << 5) | 0x01 = 0x141: bounds violation against the
#           authority c10.
#   Test 13 MEPCC address = the faulting sb.
#   Test 14 The guard word area[16..19] still holds its seed: the denied store
#           wrote nothing.
#   Test 15 Any other trap (setup, controls, interrupt checks): the generic
#           test-local vector was entered. mcause/mtval in the trace say why.
#
# Trap handling
# -------------
# As in cheriot_revoke_basic / juliet_cwe131_fault / cheriot_perm_lc_sc:
# crt_cheriot.S's trap_entry cannot return under CHERIoT, so MTCC is pointed
# at 4-byte-aligned test-local vectors that jump straight to a label. A vector
# does no memory or CSR access and never executes mret.
#
# Register use: ca0 = buf capability, ca1 = full-range MTDC capability to the
# area (seeding and read-back). ca0/ca1 are never an integer destination after
# setup -- aN and caN are the same register. Integer scratch is t0, t1, t2
# only (c6 is the MTCC install scratch, as in crt). No x16-x31.
#
# Returns 0 on success, else the failing test number (1-15).
#
# Encodings (Sail encdec, opcode 0x5B; cross-checked against
# cheriot_perm_lc_sc.S):
#   cspecialr  ca0, mtdc     = .word 0x03D0055B  (CSpecialRW, SCR 29)
#   cspecialr  ca1, mtdc     = .word 0x03D005DB
#   csetaddr   ca0, ca0, t0  = .word 0x2055055B  (funct7=0x10)
#   csetaddr   ca1, ca1, t0  = .word 0x205585DB
#   csetbounds ca0, ca0, t0  = .word 0x1055055B  (funct7=0x08)
#   cincaddr   ca0, ca0, t0  = .word 0x2255055B  (funct7=0x11)
#   cgettag    t0, ca0       = .word 0xFE4502DB  (funct7=0x7F, rs2=0x04)
#   cgetaddr   t0, ca0       = .word 0xFEF502DB  (rs2=0x0F)
#   cspecialr  ct1, mepcc    = .word 0x03F0035B  (SCR 31)
#   cgetaddr   t1, ct1       = .word 0xFEF3035B
# Trap-vector install (from crt_cheriot.S, c6/t0):
#   cspecialr  c6, mtcc      = .word 0x03C0035B
#   csetaddr   c6, c6, t0    = .word 0x2053035B
#   cspecialw  mtcc, c6      = .word 0x03C3005B
# =============================================================================

# Point MTCC at a test-local vector. Clobbers t0 and c6 (t1).
.macro SET_TRAP_VECTOR label
    la      t0, \label
    .word   0x03C0035B              # cspecialr c6, mtcc
    .word   0x2053035B              # csetaddr  c6, c6, t0
    .word   0x03C3005B              # cspecialw mtcc, c6
.endm

# ca0 <- 16-byte capability [&area, &area+16), cursor at base. Clobbers t0.
.macro MAKE_BUF16
    .word   0x03D0055B              # cspecialr ca0, mtdc
    la      t0, area
    .word   0x2055055B              # csetaddr  ca0, ca0, t0
    li      t0, 16
    .word   0x1055055B              # csetbounds ca0, ca0, t0
.endm

    .text
    .globl main

# Test-local trap vectors: no memory access, no CSR access, no mret.
.balign 4
.Lvec_unexpected:
    j       .Lfail_test15
.balign 4
.Lvec_ctl_store:
    j       .Lfail_test8
.balign 4
.Lvec_expected:
    j       .Ltrap_taken

main:
    csrsi   mstatus, 8              # set mstatus.MIE (bit 3)
    SET_TRAP_VECTOR .Lvec_unexpected

    # ── Setup: full-range capability to the area; seed buf[12..15] and guard ──
    la      t0, area
    .word   0x03D005DB              # cspecialr ca1, mtdc
    .word   0x205585DB              # csetaddr  ca1, ca1, t0   -> &area
    sw      zero, 12(a1)            # buf[12..15] = 0
    li      t1, 0x5A5A5A5A
    sw      t1, 16(a1)              # guard word area[16..19]

    # ── Test 1: the 16-byte buffer capability is valid ────────────────────────
    MAKE_BUF16
    .word   0xFE4502DB              # cgettag t0, ca0 (t0: keep ca0 intact)
    li      t1, 1
    bne     t0, t1, .Lfail_test1

    # ── Test 2: cursor = top keeps tag = 1 (one-past-the-end is legal) ────────
    li      t0, 16
    .word   0x2255055B              # cincaddr ca0, ca0, t0   (cursor -> top)
    .word   0xFE4502DB              # cgettag t0, ca0
    bne     t0, t1, .Lfail_test2    # t1 = 1

    # ── Test 7: the cursor is &area + 16 ──────────────────────────────────────
    .word   0xFEF502DB              # cgetaddr t0, ca0
    la      t2, area + 16
    bne     t0, t2, .Lfail_test7

    # ── Test 3: fresh capability, cursor = top-1 keeps tag = 1 ────────────────
    MAKE_BUF16
    li      t0, 15
    .word   0x2255055B              # cincaddr ca0, ca0, t0   (cursor -> top-1)
    .word   0xFE4502DB              # cgettag t0, ca0
    bne     t0, t1, .Lfail_test3    # t1 = 1

    # ── Tests 8-9: control -- buf[15] (last element) is writable ──────────────
    SET_TRAP_VECTOR .Lvec_ctl_store # test 8: a trap here is a failure
    li      t2, 0xA5
    sb      t2, 0(a0)               # buf[15] = 0xA5: in bounds
    SET_TRAP_VECTOR .Lvec_unexpected
    lbu     t1, 15(a1)              # read back through the full-range cap
    bne     t1, t2, .Lfail_test9

    # ── Tests 4-6: interrupt state, before the deliberate fault ───────────────
    csrr    t1, mstatus
    andi    t1, t1, 8
    beqz    t1, .Lfail_test4
    csrr    t1, mcause
    bnez    t1, .Lfail_test5
    csrr    t1, mip
    bnez    t1, .Lfail_test6

    # ── Tests 10-14: buf[16] = x traps with a bounds violation ────────────────
    MAKE_BUF16
    li      t0, 16
    .word   0x2255055B              # cincaddr ca0, ca0, t0   (cursor -> top)
    SET_TRAP_VECTOR .Lvec_expected
    li      t2, 0xEE

.Lstore_denied:
    sb      t2, 0(a0)               # DENIED: buf[16], the byte at top
    j       .Lfail_test10           # reached only if the store did not trap

.Ltrap_taken:
    SET_TRAP_VECTOR .Lvec_unexpected
    csrr    t1, mcause
    li      t2, 28                  # CHERI fault
    bne     t1, t2, .Lfail_test11
    csrr    t1, mtval
    li      t2, 0x141               # (10 << 5) | 0x01: bounds violation, c10
    bne     t1, t2, .Lfail_test12
    .word   0x03F0035B              # cspecialr ct1, mepcc
    .word   0xFEF3035B              # cgetaddr  t1, ct1
    la      t2, .Lstore_denied
    bne     t1, t2, .Lfail_test13
    lw      t1, 16(a1)              # guard word through the full-range cap
    li      t2, 0x5A5A5A5A
    bne     t1, t2, .Lfail_test14   # must still hold the seed

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

    .data
    .balign 8
area:                               # buf = area[0..15]; area[16..19] = guard word
    .space  24
