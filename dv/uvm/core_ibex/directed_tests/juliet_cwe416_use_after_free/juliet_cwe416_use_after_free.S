# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: juliet_cwe416_use_after_free -- named after CWE-416 Use After Free; it
#       is a register-level CClearTag check, not a use-after-free fault test
# =============================================================================
# CWE-416 (NIST Juliet Test Suite): Use After Free.
#
#   char *data = (char *)malloc(64);
#   free(data);
#   printLine(data);          // FLAW: use after free
#
# In CHERIoT the defence is revocation: the allocator's free() invalidates the
# freed capability and the revoker sweeps memory for copies, so a later load or
# store through 'data' takes a tag violation. This test models only the
# register half of that: "free" is a CClearTag of the allocation capability.
#
# What this test checks (results go to t0, so ca0 keeps the capability under
# test -- aN and caN are the same register):
#
#   Test 1  "malloc": MTDC, cursor moved to the address of a .data object,
#           CSetBounds(.., 64) gives a tagged capability: CGetTag = 1.
#   Test 2  "free": CClearTag of that capability gives tag 0.
#   Test 3  CClearTag changes nothing but the tag: CGetAddr is still the
#           object's address (non-zero, so a CClearTag that zeroed the
#           address would be caught). CHERIoT-Sail: CClearTag = clearTag(cs1).
#   Tests 4-6  mstatus.MIE = 1, mcause = 0, mip = 0 (no interrupt taken).
#
# What it does not do: it never frees or revokes anything, performs no load or
# store and takes no trap, so it is not evidence that using a freed capability
# faults (that is cheriot_revoke_basic's LW through a scrubbed pointer).
#
# Returns 0 on success, else the failing test number (1-6).
#
# Encodings (Sail encdec, opcode 0x5B; cross-checked against
# cheriot_perm_lc_sc.S):
#   cspecialr  ca0, mtdc     = .word 0x03D0055B  (CSpecialRW, SCR 29)
#   csetaddr   ca0, ca0, a1  = .word 0x20B5055B  (funct7=0x10)
#   csetbounds ca0, ca0, a1  = .word 0x10B5055B  (funct7=0x08)
#   cgettag    t0, ca0       = .word 0xFE4502DB  (funct7=0x7F, rs2=0x04)
#   ccleartag  ca0, ca0      = .word 0xFEB5055B  (rs2=0x0B)
#   cgetaddr   t0, ca0       = .word 0xFEF502DB  (rs2=0x0F)
# =============================================================================

.globl main
main:
    csrsi   mstatus, 8              # set mstatus.MIE (bit 3)

    # "Allocate": data = malloc(64) -- a 64-byte capability to heap_obj.
    la      a1, heap_obj            # integer address (never dereferenced)
    .word   0x03D0055B              # cspecialr ca0, mtdc
    .word   0x20B5055B              # csetaddr ca0, ca0, a1
    li      a1, 64
    .word   0x10B5055B              # csetbounds ca0, ca0, a1

    # ── Test 1: tag = 1 (allocation valid before free) ────────────────────────
    .word   0xFE4502DB              # cgettag t0, ca0 (t0: keep ca0 intact)
    li      t1, 1
    bne     t0, t1, .Lfail_test1

    # "Free": clear the tag of the allocation capability.
    .word   0xFEB5055B              # ccleartag ca0, ca0

    # ── Test 2: tag = 0 after CClearTag ───────────────────────────────────────
    .word   0xFE4502DB              # cgettag t0, ca0
    bnez    t0, .Lfail_test2

    # ── Test 3: cursor unchanged = &heap_obj ──────────────────────────────────
    .word   0xFEF502DB              # cgetaddr t0, ca0
    la      t1, heap_obj
    bne     t0, t1, .Lfail_test3

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

    .data
    .balign 8
heap_obj:                           # the "allocation"; never accessed
    .space  64
