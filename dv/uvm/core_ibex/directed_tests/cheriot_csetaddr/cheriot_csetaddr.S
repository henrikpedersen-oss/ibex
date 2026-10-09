# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_csetaddr — CSetAddr moves the cursor of a full-range capability
# =============================================================================
# CSetAddr (funct7=0x10) replaces the cursor of cs1 with the integer rs2.
# CHERIoT-Sail (cheri_insts.sail, CSetAddr -> setCapAddr in
# cheri_cap_common.sail): the tag is cleared iff cs1 is sealed or the new
# address is not REPRESENTABLE, i.e. decoding the bounds with the new address
# no longer gives the same base and top. Representability, not [base, top), is
# the criterion: for exponent E the representable window is
# [base, base + 2^(9+E)). RTL: ibex_cheriot_pkg.sv cheriot_set_address clears
# valid iff (newptr - base) >> (9+E) != 0 (no clear at the full-range exponent).
#
# The capability is MTCC (base 0, top 2^32, unsealed): every 32-bit address is
# representable, so the tag must survive every CSetAddr here. The cursor on
# entry to main() is trap_entry (crt_cheriot.S installs it), not 0.
#
# Integer results go to t0, never a0: aN and caN are the same register, so a
# result written to a0 would replace the capability under test with an integer.
#
#   Test 1  After CSetAddr(0x1000), CGetAddr = 0x1000.
#   Test 2  CGetBase is still 0: CSetAddr does not move the base.
#   Test 3  CGetTag is still 1: 0x1000 is representable in a full-range cap.
#   Test 4  After a second CSetAddr(0) on the same capability, CGetAddr = 0:
#           the cursor is not stuck at the first value.
#   Tests 5-7  mstatus.MIE = 1, mcause = 0, mip = 0 (no interrupt taken).
#
# Returns 0 on success, else the failing test number (1-7).
#
# Encodings (Sail encdec, opcode 0x5B; cross-checked against
# cheriot_perm_lc_sc.S):
#   cspecialr ca0, mtcc     = .word 0x03C0055B  (CSpecialRW, SCR 28)
#   csetaddr  ca0, ca0, a1  = .word 0x20B5055B  (funct7=0x10)
#   cgetaddr  t0, ca0       = .word 0xFEF502DB  (funct7=0x7F, rs2=0x0F)
#   cgetbase  t0, ca0       = .word 0xFE2502DB  (rs2=0x02)
#   cgettag   t0, ca0       = .word 0xFE4502DB  (rs2=0x04)
# =============================================================================

.globl main
main:
    # Enable machine-mode interrupts for the duration of this test.
    csrsi   mstatus, 8              # set mstatus.MIE (bit 3)

    # Load MTCC (base=0, top=2^32, tag=1).
    .word   0x03C0055B              # cspecialr ca0, mtcc

    # Set cursor to 0x1000.
    li      a1, 0x1000
    .word   0x20B5055B              # csetaddr ca0, ca0, a1

    # ── Test 1: cursor is now 0x1000 ──────────────────────────────────────────
    .word   0xFEF502DB              # cgetaddr t0, ca0 (t0: keep ca0 intact)
    li      t1, 0x1000
    bne     t0, t1, .Lfail_test1

    # ── Test 2: base unchanged = 0 ────────────────────────────────────────────
    .word   0xFE2502DB              # cgetbase t0, ca0
    bnez    t0, .Lfail_test2

    # ── Test 3: tag = 1 (0x1000 representable in full-range MTCC) ─────────────
    .word   0xFE4502DB              # cgettag t0, ca0
    li      t1, 1
    bne     t0, t1, .Lfail_test3

    # Set cursor back to 0 (same capability, no re-derivation).
    li      a1, 0
    .word   0x20B5055B              # csetaddr ca0, ca0, a1

    # ── Test 4: cursor back to 0 ──────────────────────────────────────────────
    .word   0xFEF502DB              # cgetaddr t0, ca0
    bnez    t0, .Lfail_test4

    # ── Interrupt state verification ───────────────────────────────────────────
    csrr    t0, mstatus
    andi    t0, t0, 8
    beqz    t0, .Lfail_test5
    csrr    t0, mcause
    bnez    t0, .Lfail_test6
    csrr    t0, mip
    bnez    t0, .Lfail_test7

    li      a0, 0
    ret

.Lfail_test1: li a0, 1; ret
.Lfail_test2: li a0, 2; ret
.Lfail_test3: li a0, 3; ret
.Lfail_test4: li a0, 4; ret
.Lfail_test5: li a0, 5; ret
.Lfail_test6: li a0, 6; ret
.Lfail_test7: li a0, 7; ret
