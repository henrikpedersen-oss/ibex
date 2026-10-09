# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_ccleartag — CClearTag clears the tag and nothing else
# =============================================================================
# CHERIoT-Sail (cheri_insts.sail, CClearTag): C(cd) = clearTag(C(cs1)) -- the
# result is cs1 with tag := 0; address, bounds, perms and otype are unchanged.
# RTL: ibex_cheriot_ex.sv, CCLEAR_TAG: result_cap_o = cs1 with valid = 0,
# result_data_o = cs1's address.
#
# The capability under test is MTCC, read with cspecialr. Its address at main()
# is NOT 0: crt_cheriot.S installs trap_entry in MTCC before calling main, so
# the cursor is trap_entry's address. The test therefore records the address
# before CClearTag and compares against that, rather than a constant.
#
# Integer results go to t0 and s0, never a0: aN and caN are the same register,
# so `cgettag a0, ca0` would overwrite the capability under test with an
# integer and every later query would read that integer instead.
#
#   Test 1  Before CClearTag, CGetTag(MTCC copy) = 1. Rules out a tag that was
#           already 0.
#   Test 7  Before CClearTag, CGetAddr is non-zero (it is trap_entry). A
#           precondition: it makes test 3 able to tell "address kept" from
#           "address zeroed".
#   Test 2  After CClearTag, CGetTag = 0. Fails if CClearTag is not decoded or
#           the tag clear is not written back.
#   Test 3  After CClearTag, CGetAddr = the address recorded before. Fails if
#           CClearTag alters or zeroes the address.
#   Tests 4-6  mstatus.MIE = 1, mcause = 0, mip = 0 (no interrupt taken).
#
# Returns 0 on success, else the failing test number (1-7).
#
# Encodings (Sail encdec, opcode 0x5B; cross-checked against
# cheriot_perm_lc_sc.S):
#   cspecialr ca0, mtcc   = .word 0x03C0055B  (CSpecialRW, SCR 28)
#   cgettag   t0, ca0     = .word 0xFE4502DB  (funct7=0x7F, rs2=0x04)
#   cgetaddr  t0, ca0     = .word 0xFEF502DB  (funct7=0x7F, rs2=0x0F)
#   cgetaddr  s0, ca0     = .word 0xFEF5045B
#   ccleartag ca0, ca0    = .word 0xFEB5055B  (funct7=0x7F, rs2=0x0B)
# =============================================================================

.globl main
main:
    # Enable machine-mode interrupts for the duration of this test.
    csrsi   mstatus, 8              # set mstatus.MIE (bit 3)

    # Load MTCC (tag=1, full range, cursor = trap_entry).
    .word   0x03C0055B              # cspecialr ca0, mtcc

    # ── Test 1: tag = 1 before CClearTag ──────────────────────────────────────
    .word   0xFE4502DB              # cgettag t0, ca0 (t0: keep ca0 intact)
    li      t1, 1
    bne     t0, t1, .Lfail_test1

    # ── Test 7: record the address; it must be non-zero ───────────────────────
    .word   0xFEF5045B              # cgetaddr s0, ca0
    beqz    s0, .Lfail_test7

    # Apply CClearTag.
    .word   0xFEB5055B              # ccleartag ca0, ca0

    # ── Test 2: tag = 0 after CClearTag ───────────────────────────────────────
    .word   0xFE4502DB              # cgettag t0, ca0
    bnez    t0, .Lfail_test2        # tag must be 0

    # ── Test 3: address unchanged ─────────────────────────────────────────────
    .word   0xFEF502DB              # cgetaddr t0, ca0
    bne     t0, s0, .Lfail_test3

    # ── Interrupt state verification ───────────────────────────────────────────
    csrr    t0, mstatus
    andi    t0, t0, 8
    beqz    t0, .Lfail_test4
    csrr    t0, mcause
    bnez    t0, .Lfail_test5
    csrr    t0, mip
    bnez    t0, .Lfail_test6

    li      a0, 0
    ret

.Lfail_test1: li a0, 1; ret
.Lfail_test2: li a0, 2; ret
.Lfail_test3: li a0, 3; ret
.Lfail_test4: li a0, 4; ret
.Lfail_test5: li a0, 5; ret
.Lfail_test6: li a0, 6; ret
.Lfail_test7: li a0, 7; ret
