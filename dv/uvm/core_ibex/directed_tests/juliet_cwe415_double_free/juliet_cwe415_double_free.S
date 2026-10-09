# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: juliet_cwe415_double_free -- named after CWE-415 Double Free; it does
#       NOT test double-free, revocation, or a fault on an untagged capability
# =============================================================================
# What this test checks (results go to t0, so ca0 keeps the capability under
# test -- aN and caN are the same register):
#
#   Test 1  CSetBounds(MTDC, 128) gives a tagged capability: CGetTag = 1.
#   Test 2  CClearTag of that capability gives tag 0 ("free").
#   Test 3  A second CClearTag of the already-cleared capability leaves tag 0
#           ("double free" of the register copy is harmless).
#   Test 4  CClearTag changes nothing but the tag: CGetAddr is still 0, the
#           cursor of the bounded MTDC derivative.
#   Tests 5-7  mstatus.MIE = 1, mcause = 0, mip = 0 (no interrupt taken).
#
# What it does not do: it never frees or revokes anything (CClearTag is a
# register operation; the bench's ibex_revbm_responder never reports a granule
# revoked anyway), it performs no load or store, and it takes no trap -- so it
# is not evidence that using a freed/revoked capability faults (that is
# cheriot_revoke_basic's LW through a scrubbed pointer, mtval 0x1A2).
#
# =============================================================================

.globl main
main:
    csrsi   mstatus, 8              # set mstatus.MIE (bit 3)

    # Create a 128-byte bounded capability (simulates malloc(128)).
    .word   0x03D0055B              # cspecialr ca0, mtdc
    li      a1, 128
    .word   0x10B5055B              # csetbounds ca0, ca0, a1

    # ── Test 1: tag = 1 before any free ──────────────────────────────────────
    .word   0xFE4502DB              # cgettag t0, ca0 (t0: keep ca0 intact)
    li      a1, 1
    bne     t0, a1, .Lfail_test1

    # Step: first free() — revoke the capability.
    .word   0xFEB5055B              # ccleartag ca0, ca0

    # ── Test 2: tag = 0 after first CClearTag ─────────────────────────────────
    .word   0xFE4502DB              # cgettag t0, ca0 (t0: keep ca0 intact)
    bne     t0, x0, .Lfail_test2

    # Step: second free() — double free on an already-cleared capability.
    .word   0xFEB5055B              # ccleartag ca0, ca0  ← double free (safe)

    # ── Test 3: tag = 0 after second CClearTag (idempotent — no corruption) ───
    .word   0xFE4502DB              # cgettag t0, ca0 (t0: keep ca0 intact)
    bne     t0, x0, .Lfail_test3

    # ── Test 4: cursor = 0 throughout (pointer field unchanged) ───────────────
    .word   0xFEF502DB              # cgetaddr t0, ca0
    bne     t0, x0, .Lfail_test4

    # ── Interrupt state verification ───────────────────────────────────────────
    csrr    a0, mstatus
    andi    a1, a0, 8
    beq     a1, x0, .Lfail_test5
    csrr    a0, mcause
    bne     a0, x0, .Lfail_test6
    csrr    a0, mip
    bne     a0, x0, .Lfail_test7

    li      a0, 0
    ret

.Lfail_test1: li a0, 1; ret
.Lfail_test2: li a0, 2; ret
.Lfail_test3: li a0, 3; ret
.Lfail_test4: li a0, 4; ret
.Lfail_test5: li a0, 5; ret
.Lfail_test6: li a0, 6; ret
.Lfail_test7: li a0, 7; ret
