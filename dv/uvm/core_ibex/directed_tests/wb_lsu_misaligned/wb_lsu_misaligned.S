# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: wb_lsu_misaligned — misaligned LW split access (hardware-handled)
# =============================================================================
# ibex_load_store_unit.sv handles misaligned word loads transparently in
# hardware via a two-beat split access (handle_misaligned_q state):
#   Beat 1: aligned word containing the low bytes
#   Beat 2: aligned word containing the high bytes
# The bytes are merged in rdata_w_ext.  No exception is raised; this is NOT
# a software-visible exception in CHERIoT-Ibex (unlike some other architectures).
#
# Scratch memory layout at 0x80010000 (little-endian):
#   addr+0: 0xEF, addr+1: 0xBE, addr+2: 0xAD, addr+3: 0xDE   (word = 0xDEADBEEF)
#   addr+4: 0x78, addr+5: 0x56, addr+6: 0x34, addr+7: 0x12   (word = 0x12345678)
#
#   Test 1: lw +1: bytes[1..4] = 0xBE,0xAD,0xDE,0x78 → 0x78DEADBE
#   Test 2: lw +2: bytes[2..5] = 0xAD,0xDE,0x78,0x56 → 0x5678DEAD
#   Test 3: lw +3: bytes[3..6] = 0xDE,0x78,0x56,0x34 → 0x345678DE
#   Tests 4-6: interrupt state unchanged (no exception raised).
#
# In CHERIoT mode, all memory accesses (lw/sw/lh/sh/lb/sb) check the
# capability in the base register.  Plain `li` clears the capability tag, so
# we must derive a capability from MTDC (full-range data cap at reset) via
# cspecialr + csetaddr before using the register as a memory base.
# =============================================================================

.globl main
main:
    csrsi   mstatus, 8

    # ── Derive scratch capability from MTDC ───────────────────────────────────
    # cspecialr a0, mtdc  (rd=x10, scr=29)
    .word   0x03D0055B              # ca0 = MTDC (full-range, tag=1)
    li      a1, 0x80010000
    .word   0x20B5055B              # csetaddr a0, a0, a1  (rs2=x11=a1; cursor=scratch)

    # ── Write two known words to scratch ──────────────────────────────────────
    li      a1, 0xDEADBEEF
    sw      a1, 0(a0)               # addr+0..+3  (ca0.tag=1, bounds OK)
    li      a2, 0x12345678
    sw      a2, 4(a0)               # addr+4..+7

    # ── Test 1: misaligned LW at +1 → 0x78DEADBE ─────────────────────────────
    lw      a3, 1(a0)               # split: beat1=[addr+0..+3] beat2=[addr+4..+7]
    li      a1, 0x78DEADBE          # bytes[1]=0xBE bytes[2]=0xAD bytes[3]=0xDE bytes[4]=0x78
    bne     a3, a1, .Lfail_test1

    # ── Test 2: misaligned LW at +2 → 0x5678DEAD ─────────────────────────────
    lw      a3, 2(a0)
    li      a1, 0x5678DEAD          # bytes[2]=0xAD bytes[3]=0xDE bytes[4]=0x78 bytes[5]=0x56
    bne     a3, a1, .Lfail_test2

    # ── Test 3: misaligned LW at +3 → 0x345678DE ─────────────────────────────
    lw      a3, 3(a0)
    li      a1, 0x345678DE          # bytes[3]=0xDE bytes[4]=0x78 bytes[5]=0x56 bytes[6]=0x34
    bne     a3, a1, .Lfail_test3

    # ── Tests 4-6: interrupt state (no exception from misaligned LW) ──────────
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
