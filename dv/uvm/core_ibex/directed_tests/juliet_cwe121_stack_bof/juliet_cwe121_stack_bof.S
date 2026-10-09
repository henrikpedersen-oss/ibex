# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: juliet_cwe121_stack_bof — CWE-121 Stack Buffer Overflow (CHERIoT)
# =============================================================================
# CWE-121 (NIST Juliet Test Suite): Stack-Based Buffer Overflow.
#
#   char buf[64];
#   buf[160] = x;             // overflows into adjacent stack memory
#
# In CHERIoT the pointer to 'buf' is a capability bounded to 64 bytes. Moving
# its cursor past the end does NOT clear the tag: CHERIoT-Sail (cheri_insts.sail
# CIncAddr -> incCapAddr, cheri_cap_common.sail) clears it only if the new
# address is unrepresentable, and for this capability (E = 0) the representable
# window is [base, base + 512), so cursor base+160 keeps tag 1. The overflow is
# stopped at the DEREFERENCE: the store through the out-of-bounds cursor fails
# inCapBounds and raises a CHERI bounds violation (Sail ext_data_get_addr:
# CapEx_BoundsViolation = 0x01), and nothing is written.
#
# The "stack frame" is a .data buffer, not a fixed address: 0x80080000 is the
# bottom of the stack/TLS area, and this test really stores. frame[0..63] is
# 'buf'; frame[64..255] is the "adjacent stack memory" the overflow would hit.
#
# How each check can fail
# -----------------------
#   Test 1  CGetLen(buf) = 64.            CSetBounds installed the wrong length.
#   Test 2  CGetBase(buf) = &frame.       CSetBounds did not take the cursor as base.
#   Test 3  CGetTag(buf) = 1.             CSetBounds cleared the tag.
#   Test 4  CIncAddr +32: tag = 1.        In-bounds cursor move cleared the tag.
#   Test 9  sw through buf+32 did NOT trap (control: in-bounds store is legal).
#           Fails if every store through this capability faults, which would
#           make the deliberate fault below meaningless.
#   Test 10 ...and frame[32] now holds the stored value.
#   Test 5  CIncAddr +128 (cursor 32 -> 160, past top 64): tag STILL 1.
#           Fails if CIncAddr clears the tag on leaving [base, top) instead of
#           on leaving the representable window.
#   Test 11 CGetAddr = &frame + 160: the cursor really moved.
#   Tests 6-8  mstatus.MIE = 1, mcause = 0, mip = 0 -- checked here, before
#           the deliberate fault, because taking a trap clears MIE and sets
#           mcause.
#   Test 12 sw through buf+160 traps (reaching the next instruction means it
#           did not). Fails if the rv32 LSU bounds check (ibex_cheriot_ex.sv
#           check_rv32: rv32_top_vio) misses an access above top.
#   Test 13 mcause = 28 (CHERI fault).
#   Test 14 mtval = (10 << 5) | 0x01 = 0x141: bounds violation against the
#           authority c10. Fails if a different cause or register is reported.
#   Test 15 MEPCC address = the faulting sw.
#   Test 16 frame[160] still holds its seed: the denied store wrote nothing
#           (ibex_load_store_unit.sv gates the request on lsu_cheriot_err_i).
#   Test 17 Any other trap (setup, controls, interrupt checks): the generic
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
# frame (seeding and read-back). ca0/ca1 are never an integer destination
# after setup -- aN and caN are the same register. Integer scratch is t0, t1,
# t2 only (c6 is the MTCC install scratch, as in crt). No x16-x31.
#
# Returns 0 on success, else the failing test number (1-17).
#
# Encodings (Sail encdec, opcode 0x5B; cross-checked against
# cheriot_perm_lc_sc.S):
#   cspecialr  ca0, mtdc     = .word 0x03D0055B  (CSpecialRW, SCR 29)
#   cspecialr  ca1, mtdc     = .word 0x03D005DB
#   csetaddr   ca0, ca0, t0  = .word 0x2055055B  (funct7=0x10)
#   csetaddr   ca1, ca1, t0  = .word 0x205585DB
#   csetbounds ca0, ca0, t0  = .word 0x1055055B  (funct7=0x08)
#   cincaddr   ca0, ca0, t0  = .word 0x2255055B  (funct7=0x11)
#   cgetlen    t0, ca0       = .word 0xFE3502DB  (funct7=0x7F, rs2=0x03)
#   cgetbase   t0, ca0       = .word 0xFE2502DB  (rs2=0x02)
#   cgettag    t0, ca0       = .word 0xFE4502DB  (rs2=0x04)
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

    .text
    .globl main

# Test-local trap vectors: no memory access, no CSR access, no mret.
.balign 4
.Lvec_unexpected:
    j       .Lfail_test17
.balign 4
.Lvec_ctl_store:
    j       .Lfail_test9
.balign 4
.Lvec_expected:
    j       .Ltrap_taken

main:
    csrsi   mstatus, 8              # set mstatus.MIE (bit 3)
    SET_TRAP_VECTOR .Lvec_unexpected

    # ── Setup: full-range capability to the frame; seed the target words ──────
    la      t0, frame
    .word   0x03D005DB              # cspecialr ca1, mtdc
    .word   0x205585DB              # csetaddr  ca1, ca1, t0   -> &frame
    li      t1, 0x5A5A5A5A
    sw      t1, 32(a1)              # frame[32]  (buf[32], control target)
    sw      t1, 160(a1)             # frame[160] (overflow target)

    # ── Setup: char buf[64] -- 64-byte capability at &frame ───────────────────
    .word   0x03D0055B              # cspecialr ca0, mtdc
    la      t0, frame
    .word   0x2055055B              # csetaddr  ca0, ca0, t0
    li      t0, 64
    .word   0x1055055B              # csetbounds ca0, ca0, t0  ([&frame, &frame+64))

    # ── Test 1: length = 64 ───────────────────────────────────────────────────
    .word   0xFE3502DB              # cgetlen t0, ca0 (t0: keep ca0 intact)
    li      t1, 64
    bne     t0, t1, .Lfail_test1

    # ── Test 2: base = &frame ─────────────────────────────────────────────────
    .word   0xFE2502DB              # cgetbase t0, ca0
    la      t1, frame
    bne     t0, t1, .Lfail_test2

    # ── Test 3: tag = 1 ───────────────────────────────────────────────────────
    .word   0xFE4502DB              # cgettag t0, ca0
    li      t1, 1
    bne     t0, t1, .Lfail_test3

    # ── Test 4: buf+32 (in bounds) keeps tag = 1 ──────────────────────────────
    li      t0, 32
    .word   0x2255055B              # cincaddr ca0, ca0, t0   (cursor 0 -> 32)
    .word   0xFE4502DB              # cgettag t0, ca0
    bne     t0, t1, .Lfail_test4    # t1 = 1

    # ── Tests 9-10: control -- an in-bounds store through buf is legal ────────
    SET_TRAP_VECTOR .Lvec_ctl_store # test 9: a trap here is a failure
    li      t2, 0x0000C0DE
    sw      t2, 0(a0)               # buf[32] = 0xC0DE: in bounds
    SET_TRAP_VECTOR .Lvec_unexpected
    lw      t1, 32(a1)              # read back through the full-range cap
    bne     t1, t2, .Lfail_test10

    # ── Test 5: buf+160 (past top, representable) keeps tag = 1 ───────────────
    li      t0, 128
    .word   0x2255055B              # cincaddr ca0, ca0, t0   (cursor 32 -> 160)
    .word   0xFE4502DB              # cgettag t0, ca0
    li      t1, 1
    bne     t0, t1, .Lfail_test5

    # ── Test 11: the cursor is &frame + 160 ───────────────────────────────────
    .word   0xFEF502DB              # cgetaddr t0, ca0
    la      t1, frame + 160
    bne     t0, t1, .Lfail_test11

    # ── Tests 6-8: interrupt state, before the deliberate fault ───────────────
    csrr    t1, mstatus
    andi    t1, t1, 8
    beqz    t1, .Lfail_test6
    csrr    t1, mcause
    bnez    t1, .Lfail_test7
    csrr    t1, mip
    bnez    t1, .Lfail_test8

    # ── Tests 12-16: the overflowing store traps with a bounds violation ──────
    SET_TRAP_VECTOR .Lvec_expected
    li      t2, 0xDEADBEEF

.Lstore_denied:
    sw      t2, 0(a0)               # DENIED: buf[160], outside [base, base+64)
    j       .Lfail_test12           # reached only if the store did not trap

.Ltrap_taken:
    SET_TRAP_VECTOR .Lvec_unexpected
    csrr    t1, mcause
    li      t2, 28                  # CHERI fault
    bne     t1, t2, .Lfail_test13
    csrr    t1, mtval
    li      t2, 0x141               # (10 << 5) | 0x01: bounds violation, c10
    bne     t1, t2, .Lfail_test14
    .word   0x03F0035B              # cspecialr ct1, mepcc
    .word   0xFEF3035B              # cgetaddr  t1, ct1
    la      t2, .Lstore_denied
    bne     t1, t2, .Lfail_test15
    lw      t1, 160(a1)             # frame[160] through the full-range cap
    li      t2, 0x5A5A5A5A
    bne     t1, t2, .Lfail_test16   # must still hold the seed

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

    .data
    .balign 8
frame:                              # buf = frame[0..63]; frame[64..255] = adjacent
    .space  256
