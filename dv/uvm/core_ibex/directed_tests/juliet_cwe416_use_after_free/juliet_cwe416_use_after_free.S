# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: juliet_cwe416_use_after_free — CWE-416 Use After Free (CHERIoT)
# =============================================================================
# CWE-416 (NIST Juliet Test Suite): Use After Free.
#
# In C without CHERIoT (bad):
#   char *data = (char *)malloc(100);
#   free(data);
#   /* FLAW: use data after free */
#   printLine(data);  ← undefined behaviour, likely crash or corruption
#
# In CHERIoT, freeing memory involves revoking all capabilities to it.
# The allocator calls CClearTag on the freed capability (and also sweeps
# the heap to revoke any other copies).  After revocation:
#   - cgettag(data) = 0  → the capability is no longer valid
#   - Any load/store through 'data' raises a CHERI exception
#
# This test simulates the CHERIoT use-after-free protection:
#   1. "Allocate": CSetBounds(MTDC, 64) → alloc_cap (tag=1)
#   2. "Free": CClearTag(alloc_cap) → alloc_cap (tag=0)
#   3. "Use after free": cgettag(alloc_cap) → 0 (the use would fault)
#
# The key property: CClearTag is the hardware-level revocation primitive.
# Once cleared, the capability cannot be reinstated; any use-after-free
# attempt is detected at the capability level, not via a software check.
#
# Extra checks:
#   - The integer address field (cursor) is unchanged after CClearTag.
#     A freed pointer still holds the same numeric address — but the tag=0
#     makes it unusable for any capability-checked operation.
#
#   Test 1 (tag=1 before free — allocation is valid)
#   Test 2 (tag=0 after CClearTag — allocation revoked)
#   Test 3 (CGetAddr = 0 after CClearTag — cursor unchanged, cap unusable)
#   Tests 4-6 (interrupt state — no interrupt expected)
#
# Adapted from Juliet CWE416_Use_After_Free (NIST/NSA).
# =============================================================================
#
# CClearTag ca0, ca0 (funct7=0x7F rs2=0x0B):
#   = 0xFEB5055B
#
# Tests:
#   1. tag=1 before free.
#   2. tag=0 after CClearTag (simulates free+revocation).
#   3. CGetAddr=0 after CClearTag (cursor unchanged, pointer unusable).
#   4. mstatus.MIE = 1.
#   5. mcause = 0.
#   6. mip = 0.

.globl main
main:
    csrsi   mstatus, 8              # set mstatus.MIE (bit 3)

    # Step 1: "Allocate" — create a 64-byte bounded capability (data = malloc(64)).
    .word   0x03D0055B              # cspecialr ca0, mtdc
    li      a1, 64
    .word   0x10B5055B              # csetbounds ca0, ca0, a1

    # ── Test 1: tag = 1 (allocation valid before free) ────────────────────────
    .word   0xFE45055B              # cgettag a0, ca0
    li      a1, 1
    bne     a0, a1, .Lfail_test1

    # Step 2: "Free" — revoke capability (free(data)).
    .word   0xFEB5055B              # ccleartag ca0, ca0  ← CHERIoT free() revocation

    # ── Test 2: tag = 0 (allocation revoked — use after free is now detectable) ─
    .word   0xFE45055B              # cgettag a0, ca0
    bne     a0, x0, .Lfail_test2   # tag must be 0

    # ── Test 3: cursor unchanged = 0 (pointer address preserved, but unusable) ──
    # The 'data' variable still holds a numeric address, but tag=0 means
    # any load/store through it would trigger a CHERI exception.
    .word   0xFEF5055B              # cgetaddr a0, ca0
    bne     a0, x0, .Lfail_test3

    # ── Interrupt state verification ───────────────────────────────────────────
    csrr    a0, mstatus
    andi    a1, a0, 8
    beq     a1, x0, .Lfail_test4
    csrr    a0, mcause
    bne     a0, x0, .Lfail_test5
    csrr    a0, mip
    bne     a0, x0, .Lfail_test6

    li      a0, 0
    ret

.Lfail_test1: li a0, 1; ret
.Lfail_test2: li a0, 2; ret
.Lfail_test3: li a0, 3; ret
.Lfail_test4: li a0, 4; ret
.Lfail_test5: li a0, 5; ret
.Lfail_test6: li a0, 6; ret
