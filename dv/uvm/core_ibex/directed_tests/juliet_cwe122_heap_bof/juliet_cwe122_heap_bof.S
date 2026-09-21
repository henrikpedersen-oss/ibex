# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: juliet_cwe122_heap_bof — CWE-122 Heap Buffer Overflow (CHERIoT)
# =============================================================================
# CWE-122 (NIST Juliet Test Suite): Heap-Based Buffer Overflow.
#
# In C without CHERIoT:
#   char *data = (char *)malloc(256);
#   memcpy(data + 512, src, N);  ← overflows past the 256-byte allocation
#
# In CHERIoT, malloc() returns a capability bounded to the allocation size.
# Any pointer arithmetic that takes the cursor beyond the allocation's top
# produces a tag=0 capability, causing a CHERI fault on the next access.
#
# This test uses MTDC as the "heap region" authority and CSetBounds to
# simulate a 256-byte malloc().  Then it demonstrates:
#   (a) A safe in-bounds access (cursor+64, cursor<top) → tag=1.
#   (b) An unsafe overflow access (cursor+512, cursor>top) → tag=0.
#
# Difference from CWE121: the allocation is larger (256 vs 64 bytes) and
# the "heap" framing.  The CHERIoT mechanism is identical — CSetBounds
# bounds the capability at allocation time.
#
#   Test 1 (CGetLen = 256 after CSetBounds(MTDC, 256))
#     The allocation is correctly bounded to 256 bytes.
#
#   Test 2 (tag = 1 after CSetBounds)
#     The derived bounded capability is valid (region ⊆ full MTDC range).
#
#   Test 3 (in-bounds: CIncAddr +64 → tag=1)
#     data+64 is inside [0, 256) — a legitimate heap access.
#
#   Test 4 (out-of-bounds: CIncAddr +512 from cursor=0 → tag=0)
#     CSetBounds again for a fresh cap, then cursor+512 > top=256 → tag=0.
#     This is the CWE-122 flaw: writing heap+512 overflows the allocation.
#     CHERIoT denies the access; the tag-0 capability causes a CHERI fault.
#
#   Tests 5-7 (interrupt state — no interrupt expected)
#
# Adapted from Juliet CWE122_Heap_Based_Buffer_Overflow (NIST/NSA).
# =============================================================================
#
# Tests:
#   1. CGetLen = 256.
#   2. tag = 1 after CSetBounds.
#   3. CIncAddr +64 → tag=1 (in-bounds).
#   4. CIncAddr +512 (fresh bounded cap, cursor=0+512=512 > top=256) → tag=0.
#   5. mstatus.MIE = 1.
#   6. mcause = 0.
#   7. mip = 0.

.globl main
main:
    csrsi   mstatus, 8              # set mstatus.MIE (bit 3)

    # Simulate: data = malloc(256) — 256-byte heap allocation capability.
    .word   0x03D0055B              # cspecialr ca0, mtdc
    li      a1, 256
    .word   0x10B5055B              # csetbounds ca0, ca0, a1

    # ── Test 1: length = 256 ──────────────────────────────────────────────────
    .word   0xFE35055B              # cgetlen a0, ca0
    li      a2, 256
    bne     a0, a2, .Lfail_test1

    # ── Test 2: tag = 1 (valid heap capability) ───────────────────────────────
    # Rebuild the capability first: a0 and ca0 are the SAME register, so the
    # cgetlen above wrote an integer into it and cleared the tag. cgettag then
    # read a dead capability and returned 0. Unnoticed because crt_cheriot.S
    # reported TEST_PASS unconditionally until 2026-09-18.
    .word   0x03D0055B              # cspecialr ca0, mtdc
    li      a1, 256
    .word   0x10B5055B              # csetbounds ca0, ca0, a1
    .word   0xFE45055B              # cgettag a0, ca0
    li      a1, 1
    bne     a0, a1, .Lfail_test2

    # ── Test 3: in-bounds access data+64 → tag=1 ─────────────────────────────
    # Rebuild again: the cgettag in test 2 clobbered ca0 the same way, so the
    # cincaddr below would otherwise advance a dead capability.
    .word   0x03D0055B              # cspecialr ca0, mtdc
    li      a1, 256
    .word   0x10B5055B              # csetbounds ca0, ca0, a1
    li      a1, 64
    .word   0x22B5055B              # cincaddr ca0, ca0, a1  (cursor: 0 → 64)
    .word   0xFE45055B              # cgettag a0, ca0
    li      a1, 1
    bne     a0, a1, .Lfail_test3

    # ── Test 4: out-of-bounds overflow data+512 → tag=0 ──────────────────────
    # Reload a fresh bounded cap (cursor=0) for the overflow test.
    .word   0x03D0055B              # cspecialr ca0, mtdc
    li      a1, 256
    .word   0x10B5055B              # csetbounds ca0, ca0, a1
    # Advance by 512 — well past top(256).
    li      a1, 512
    .word   0x22B5055B              # cincaddr ca0, ca0, a1  (cursor: 0 → 512)
    .word   0xFE45055B              # cgettag a0, ca0
    bne     a0, x0, .Lfail_test4   # tag must be 0

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
