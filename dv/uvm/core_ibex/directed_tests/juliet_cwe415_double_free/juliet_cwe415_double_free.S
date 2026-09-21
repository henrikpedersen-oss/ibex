# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: juliet_cwe415_double_free — CWE-415 Double Free (CHERIoT)
# =============================================================================
# CWE-415 (NIST Juliet Test Suite): Double Free.
#
# In C without CHERIoT (bad):
#   char *data = (char *)malloc(100);
#   free(data);
#   free(data);  ← FLAW: double free corrupts the heap allocator's state
#
# In CHERIoT, the revocation primitive (CClearTag) is idempotent:
#   - First CClearTag: tag 1 → 0 (genuine revocation, simulates free())
#   - Second CClearTag: tag 0 → 0 (no-op; calling free() twice is harmless)
#
# The CHERIoT allocator checks the tag before freeing: if the capability's
# tag is already 0, the second free() can be detected and rejected safely.
# There is no heap corruption because the allocator's metadata is protected
# by its own capability.
#
# This test verifies the idempotency of CClearTag:
#   1. Create a valid bounded capability (simulates malloc()).
#   2. First CClearTag: tag becomes 0 (first free()).
#   3. Second CClearTag: tag stays 0 (second free() — idempotent, safe).
#   4. The cursor is unchanged throughout (pointer arithmetic unaffected).
#
#   Test 1 (tag=1 before any free)
#   Test 2 (tag=0 after first CClearTag)
#   Test 3 (tag=0 after second CClearTag — double free is idempotent)
#   Test 4 (cursor = 0 unchanged through both clears)
#   Tests 5-7 (interrupt state — no interrupt expected)
#
# Adapted from Juliet CWE415_Double_Free (NIST/NSA).
# =============================================================================
#
# Tests:
#   1. tag=1 before free.
#   2. tag=0 after first CClearTag.
#   3. tag=0 after second CClearTag (idempotent).
#   4. cursor=0 unchanged.
#   5. mstatus.MIE = 1.
#   6. mcause = 0.
#   7. mip = 0.

.globl main
main:
    csrsi   mstatus, 8              # set mstatus.MIE (bit 3)

    # Create a 128-byte bounded capability (simulates malloc(128)).
    .word   0x03D0055B              # cspecialr ca0, mtdc
    li      a1, 128
    .word   0x10B5055B              # csetbounds ca0, ca0, a1

    # ── Test 1: tag = 1 before any free ──────────────────────────────────────
    .word   0xFE45055B              # cgettag a0, ca0
    li      a1, 1
    bne     a0, a1, .Lfail_test1

    # Step: first free() — revoke the capability.
    .word   0xFEB5055B              # ccleartag ca0, ca0

    # ── Test 2: tag = 0 after first CClearTag ─────────────────────────────────
    .word   0xFE45055B              # cgettag a0, ca0
    bne     a0, x0, .Lfail_test2

    # Step: second free() — double free on an already-cleared capability.
    .word   0xFEB5055B              # ccleartag ca0, ca0  ← double free (safe)

    # ── Test 3: tag = 0 after second CClearTag (idempotent — no corruption) ───
    .word   0xFE45055B              # cgettag a0, ca0
    bne     a0, x0, .Lfail_test3

    # ── Test 4: cursor = 0 throughout (pointer field unchanged) ───────────────
    .word   0xFEF5055B              # cgetaddr a0, ca0
    bne     a0, x0, .Lfail_test4

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
