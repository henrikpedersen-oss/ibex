# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: juliet_cwe124_buf_underwrite — CWE-124 Buffer Underwrite (CHERIoT)
# =============================================================================
# CWE-124 (NIST Juliet Test Suite): Buffer Underwrite (write before start).
#
#   char buf[16];
#   *(buf - 4) = 0x42;        // writes before the buffer start
#
# CHERIoT-Sail (cheri_insts.sail CIncAddr -> incCapAddr, cheri_cap_common.sail)
# clears the tag iff the new address is not REPRESENTABLE: the bounds, decoded
# again with the new address, must equal the old ones. In CHERIoT the
# representable window for exponent E starts AT the base:
# [base, base + 2^(9+E)). So, unlike moving past top, moving the cursor even
# one byte below base is always unrepresentable, and CIncAddr clears the tag
# at once. (Worked for this capability, E = 0, B = 0: address 0x8007FFFC has
# a_mid = 0x1FC >= B, so it decodes against the 512-byte region below and
# gives base 0x8007FE00 != 0x80080000.) RTL agrees: ibex_cheriot_pkg.sv
# cheriot_set_address computes newptr - base in 33 bits; below base the borrow
# makes the high part non-zero and valid is cleared.
#
# The buffer is a 16-byte capability at buf = area + 16, derived from MTDC, in
# a .data area with a guard word just below it (area + 12).
#
# Integer results go to t0/t1/t2, never a0: aN and caN are the same register,
# so a result written to a0 would replace the capability under test.
#
#   Test 1  The 16-byte bounded capability is valid: CGetTag = 1.
#   Test 7  Control: CIncAddr(+4) then CIncAddr(-4), back to base, keeps
#           tag = 1. Shows a negative increment is not itself what clears the
#           tag -- only crossing below base does.
#   Test 8  Control: sw 0(ca0) (at base, in bounds) does not trap ...
#   Test 9  ... and the word is written.
#   Test 10 The underwrite itself: sw -4(ca0), cursor at base, so the access
#           address base - 4 is below base. It must trap (REQ_BND_01) --
#           reaching the next instruction is failure 10.
#   Tests 11-13  The trap is mcause = 28, mtval = 0x141 ((10 << 5) | 0x01:
#           bounds violation against c10), MEPCC address = the store.
#   Test 14 The guard word below the buffer is unchanged: nothing was written.
#   Test 15 A trap anywhere else in the test.
#   Test 2  CIncAddr(-4) from base (cursor base - 4 < base): CGetTag = 0.
#   Test 3  CGetAddr = base - 4: the arithmetic wrapped correctly; only the
#           tag is cleared.
#   Tests 4-6  mstatus.MIE = 1, mcause = 0, mip = 0: no interrupt taken,
#           checked before the expected trap (which clears MIE; no mret).
#
# Returns 0 on success, else the failing test number (1-15).
#
# RTL: check_rv32 in ibex_cheriot_ex.sv flags an access starting below
# base32 (addr_bound_vio), cheriot_violation_cause gives 0x01, and the LSU
# request is suppressed on error.
#
# Encodings (Sail encdec, opcode 0x5B; cross-checked against
# cheriot_perm_lc_sc.S):
#   cspecialr  ca0, mtdc     = .word 0x03D0055B  (CSpecialRW, SCR 29)
#   csetaddr   ca0, ca0, a1  = .word 0x20B5055B  (funct7=0x10)
#   csetbounds ca0, ca0, a1  = .word 0x10B5055B  (funct7=0x08)
#   cincaddr   ca0, ca0, a1  = .word 0x22B5055B  (funct7=0x11)
#   cgettag    t0, ca0       = .word 0xFE4502DB  (funct7=0x7F, rs2=0x04)
#   cgetaddr   t0, ca0       = .word 0xFEF502DB  (rs2=0x0F)
# =============================================================================
#   Also: cspecialr ca1, mtdc = 0x03D005DB; csetaddr ca0, ca0, t0 = 0x2055055B;
#   csetaddr ca1, ca1, t0 = 0x205585DB; cspecialr c6, mtcc = 0x03C0035B;
#   csetaddr c6, c6, t0 = 0x2053035B; cspecialw mtcc, c6 = 0x03C3005B;
#   cspecialr ct1, mepcc = 0x03F0035B; cgetaddr t1, ct1 = 0xFEF3035B.

.macro SET_TRAP_VECTOR label
    la      t0, \label
    .word   0x03C0035B              # cspecialr c6, mtcc
    .word   0x2053035B              # csetaddr  c6, c6, t0
    .word   0x03C3005B              # cspecialw mtcc, c6
.endm

    .text
.balign 4
.Lvec_unexpected:
    j       .Lfail_test15
.balign 4
.Lvec_ctl_store:
    j       .Lfail_test8
.balign 4
.Lvec_expected:
    j       .Ltrap_taken

.globl main
main:
    csrsi   mstatus, 8              # set mstatus.MIE (bit 3)
    SET_TRAP_VECTOR .Lvec_unexpected

    # Seed the guard word and the first buffer word through a full-range cap.
    la      t0, area
    .word   0x03D005DB              # cspecialr ca1, mtdc
    .word   0x205585DB              # csetaddr  ca1, ca1, t0   -> &area
    li      t1, 0x5A5A5A5A
    sw      t1, 12(a1)              # guard word, just below buf
    sw      t1, 16(a1)              # buf[0]

    # buf: 16-byte capability at area + 16.
    .word   0x03D0055B              # cspecialr ca0, mtdc  (full-range data cap)
    la      t0, area + 16
    .word   0x2055055B              # csetaddr ca0, ca0, t0  (cursor -> buf)
    li      a1, 16
    .word   0x10B5055B              # csetbounds ca0, ca0, a1
    .word   0xFE4502DB              # cgettag t0, ca0 (t0: keep ca0 intact)
    li      t1, 1
    bne     t0, t1, .Lfail_test1

    li      a1, 4
    .word   0x22B5055B              # cincaddr ca0, ca0, a1  (cursor -> base+4)
    li      a1, -4
    .word   0x22B5055B              # cincaddr ca0, ca0, a1  (cursor -> base)
    .word   0xFE4502DB              # cgettag t0, ca0
    bne     t0, t1, .Lfail_test7    # t1 = 1

    # Control: an in-bounds store at base.
    SET_TRAP_VECTOR .Lvec_ctl_store # test 8: a trap here is a failure
    li      t2, 0x0000C0DE
    sw      t2, 0(a0)               # buf[0] = 0xC0DE: in bounds
    SET_TRAP_VECTOR .Lvec_unexpected
    la      t0, area
    .word   0x03D005DB              # cspecialr ca1, mtdc
    .word   0x205585DB              # csetaddr  ca1, ca1, t0   -> &area
    lw      t1, 16(a1)
    bne     t1, t2, .Lfail_test9

    # No interrupt taken so far (checked before the expected trap, which
    # clears MIE and sets mcause; the test never executes mret).
    csrr    t0, mstatus
    andi    t0, t0, 8
    beqz    t0, .Lfail_test4
    csrr    t0, mcause
    bnez    t0, .Lfail_test5
    csrr    t0, mip
    bnez    t0, .Lfail_test6

    # The underwrite: address base - 4 < base.
    SET_TRAP_VECTOR .Lvec_expected
    li      t2, 0xDEADBEEF
.Lstore_denied:
    sw      t2, -4(a0)              # DENIED: below [base, base+16)
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
    la      t0, area
    .word   0x03D005DB              # cspecialr ca1, mtdc
    .word   0x205585DB              # csetaddr  ca1, ca1, t0   -> &area
    lw      t1, 12(a1)              # guard word
    li      t2, 0x5A5A5A5A
    bne     t1, t2, .Lfail_test14   # must still hold the seed

    # Moving the cursor below base clears the tag (unrepresentable).
    li      t1, 1
    li      a1, -4
    .word   0x22B5055B              # cincaddr ca0, ca0, a1  (cursor -> base-4)
    .word   0xFE4502DB              # cgettag t0, ca0
    bnez    t0, .Lfail_test2        # tag must be 0
    .word   0xFEF502DB              # cgetaddr t0, ca0
    la      t1, area + 12
    bne     t0, t1, .Lfail_test3

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
    .balign 16
area:                               # area[12..15] = guard, buf = area[16..31]
    .space  48
