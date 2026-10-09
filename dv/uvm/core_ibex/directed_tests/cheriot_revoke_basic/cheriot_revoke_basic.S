# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_revoke_basic — integer stores revoke, stale pointers fault
# =============================================================================
# CHERIoT temporal safety rests on two properties of the core:
#
#   (a) Any non-capability store that touches an 8-byte capability granule
#       clears that granule's tag. This is how memory is scrubbed of pointers,
#       and how the allocator's zeroing of a freed object kills every
#       capability stored inside it.
#   (b) A capability whose tag is clear cannot authorise an access. A stale
#       pointer reloaded from scrubbed memory still carries its address and
#       bounds, but dereferencing it raises a CHERI tag violation.
#
# What this test does NOT cover
# -----------------------------
# The TRVK load barrier's *revoked* verdict (REQ_TMP_01: a CLC whose base lies
# in a granule marked in the revocation bitmap must return tag=0) cannot be
# stimulated in this testbench. ibex_revbm_responder.sv returns an all-zero
# bitmap word with valid integrity bits for every lookup, and
# core_ibex_tb_top.sv ties trvk_revbm_err_i to 0, so TRVK can only ever say
# "live". A check that expects a revoked verdict could never pass, and one that
# expects "live" is what test 1 below already does. The revoked path belongs to
# the Sonata SoC layer (cheri_tbre), where an allocator writes the bitmap.
#
# The TRVK lookup itself IS on the path of every tagged CLC here, so test 1
# fails when TRVK clears the tag of a live capability.
#
# How each check can fail
# -----------------------
# The testbench keeps tags in ibex_tag_mem.sv, which writes
#   tag = data_tag_o && (be == 4'b1111)
# on every accepted write. So for word-wide writes (SW, CSC) the stored tag is
# whatever the RTL drives on data_tag_o, but for SH/SB (be != 4'b1111) the model
# clears the tag by itself. Tests 4-5 therefore only catch an RTL that sends the
# narrow store to the wrong granule or drops it; the tag-clearing decision for
# sub-word stores is the memory's, not the core's.
#
#   Test 1  CSC then CLC gives tag=1.
#           Fails if: CSC does not drive data_tag_o=1, the LSU drops data_tag_i
#           on the CLC, or TRVK wrongly revokes a live capability.
#   Test 2  SW to the low word clears the tag.
#           Fails if: the LSU drives data_tag_o=1 on an integer word store (for
#           example a stale tag left over from the preceding CSC).
#   Test 3  SW to the high word (offset 4) clears the tag.
#           Same bug on the second word of the granule.
#   Test 4  SH (offset 2) clears the tag.     See the note above.
#   Test 5  SB (offset 7) clears the tag.     See the note above.
#   Test 6  CSC of an UNTAGGED register over a tagged slot clears the tag.
#           Fails if: CSC drives data_tag_o=1 regardless of the source tag,
#           which would forge a capability out of an integer.
#   Test 7  A SW to the neighbouring granule leaves this granule tagged.
#           Fails if: the store is issued to the wrong address.
#   Test 8  ...and does clear the neighbouring granule itself.
#   Tests 9-11  interrupt state (no interrupt expected).
#   Test 12 The pointer reloaded after the scrub is untagged.
#   Test 13 ...and still holds the object's address, so the fault in test 14
#           is a tag check, not a bounds or null-pointer check.
#   Test 14 An LW through that stale pointer traps.
#           Fails if: the LSU authorises an integer load through an untagged
#           capability (tag check missing on the RV32 load path).
#   Test 15 mcause = 28 (CHERI fault).
#   Test 16 mtval[4:0] = 0x02 (tag violation), not some other CHERI cause.
#   Test 17 mtval = 0x1A2: cause 0x02 reported against register c13 (a3).
#   Test 18 MEPCC points at the faulting LW, so the trap came from it.
#
# The stale pointer is reloaded from a slot that held MTCC's metadata (tag,
# full bounds, LD permission) with its low word overwritten by the slot's own
# address. Only the tag is missing, so tag violation is the only possible cause.
#
# Trap handling
# -------------
# Same technique as juliet_cwe131_fault: crt_cheriot.S's trap_entry cannot
# return from a trap under CHERIoT (it accesses mepc, an illegal CSR once
# cheriot_enable_i is set), so MTCC is pointed at a local vector that jumps
# straight back into the test. Control does not resume at the faulting
# instruction and mstatus.MIE stays cleared, which is why the interrupt-state
# checks run before the fault.
#
# Register use: ca0 = authority for slot A, ca1 = authority for slot B,
# ca2 = MTCC (the capability stored), ca3 = reloaded capability, t1 = result,
# t2 = expected value. ca0/ca1 are never a destination after setup: a0 and
# ca0 are the same register, and an integer write would clear its tag.
#
# Instruction encodings (opcode 0x5B unless noted):
#   cspecialr   ca0, mtdc      = .word 0x03D0055B
#   csetaddr    ca0, ca0, t0   = .word 0x2055055B  (funct7=0x10)
#   cincaddrimm ca1, ca0, 8    = .word 0x008515DB  (funct3=1)
#   cspecialr   ca2, mtcc      = .word 0x03C0065B
#   csc         ca2, 0(ca0)    = .word 0x00C53023  (STORE funct3=3)
#   csc         ca2, 0(ca1)    = .word 0x00C5B023
#   csc         cs0, 0(ca0)    = .word 0x00853023
#   clc         ca3, 0(ca0)    = .word 0x00053683  (LOAD funct3=3)
#   clc         ca3, 0(ca1)    = .word 0x0005B683
#   cgettag     t1, ca3        = .word 0xFE46835B  (funct7=0x7F, rs2=0x04)
#   cgetaddr    t1, ca3        = .word 0xFEF6835B  (funct7=0x7F, rs2=0x0F)
#   cspecialr   ct1, mepcc     = .word 0x03F0035B  (SCR 31)
#   cgetaddr    t1, ct1        = .word 0xFEF3035B
# Trap-vector install (from crt_cheriot.S, c6/t0):
#   cspecialr   c6, mtcc       = .word 0x03C0035B
#   csetaddr    c6, c6, t0     = .word 0x2053035B
#   cspecialw   mtcc, c6       = .word 0x03C3005B

    .text
    .globl main

# Test-local trap vector: no memory access, no CSR access, no mret.
# MTCC's address must be 4-byte aligned or the write clears its tag.
.balign 4
.Ltrap_local:
    j       .Ltrap_taken

main:
    csrsi   mstatus, 8              # set mstatus.MIE (bit 3)

    # ── Setup ─────────────────────────────────────────────────────────────────
    la      t0, cap_slots           # integer address of slot A (8-byte aligned)
    .word   0x03D0055B              # cspecialr   ca0, mtdc
    .word   0x2055055B              # csetaddr    ca0, ca0, t0   -> slot A
    .word   0x008515DB              # cincaddrimm ca1, ca0, 8    -> slot B
    .word   0x03C0065B              # cspecialr   ca2, mtcc      (tag=1)
    li      t2, 1

    # ── Test 1: CSC then CLC -> tag=1 ─────────────────────────────────────────
    .word   0x00C53023              # csc     ca2, 0(ca0)
    .word   0x00053683              # clc     ca3, 0(ca0)
    .word   0xFE46835B              # cgettag t1, ca3
    bne     t1, t2, .Lfail_test1

    # ── Test 2: SW to the low word revokes ────────────────────────────────────
    sw      x0, 0(a0)
    .word   0x00053683              # clc     ca3, 0(ca0)
    .word   0xFE46835B              # cgettag t1, ca3
    bnez    t1, .Lfail_test2

    # ── Test 3: SW to the high word revokes ───────────────────────────────────
    .word   0x00C53023              # csc     ca2, 0(ca0)   (restore)
    sw      x0, 4(a0)
    .word   0x00053683              # clc     ca3, 0(ca0)
    .word   0xFE46835B              # cgettag t1, ca3
    bnez    t1, .Lfail_test3

    # ── Test 4: SH inside the granule revokes ─────────────────────────────────
    .word   0x00C53023              # csc     ca2, 0(ca0)   (restore)
    sh      x0, 2(a0)
    .word   0x00053683              # clc     ca3, 0(ca0)
    .word   0xFE46835B              # cgettag t1, ca3
    bnez    t1, .Lfail_test4

    # ── Test 5: SB at the last byte of the granule revokes ────────────────────
    .word   0x00C53023              # csc     ca2, 0(ca0)   (restore)
    sb      x0, 7(a0)
    .word   0x00053683              # clc     ca3, 0(ca0)
    .word   0xFE46835B              # cgettag t1, ca3
    bnez    t1, .Lfail_test5

    # ── Test 6: CSC of an untagged value clears the tag ───────────────────────
    .word   0x00C53023              # csc     ca2, 0(ca0)   (restore)
    li      s0, 0x12345678          # integer write: cs0 is untagged
    .word   0x00853023              # csc     cs0, 0(ca0)
    .word   0x00053683              # clc     ca3, 0(ca0)
    .word   0xFE46835B              # cgettag t1, ca3
    bnez    t1, .Lfail_test6

    # ── Tests 7-8: a store to slot B affects slot B only ──────────────────────
    .word   0x00C53023              # csc     ca2, 0(ca0)
    .word   0x00C5B023              # csc     ca2, 0(ca1)
    sw      x0, 0(a1)               # integer store to slot B
    .word   0x00053683              # clc     ca3, 0(ca0)   (slot A)
    .word   0xFE46835B              # cgettag t1, ca3
    bne     t1, t2, .Lfail_test7
    .word   0x0005B683              # clc     ca3, 0(ca1)   (slot B)
    .word   0xFE46835B              # cgettag t1, ca3
    bnez    t1, .Lfail_test8

    # ── Tests 9-11: interrupt state, before the deliberate fault ──────────────
    csrr    t1, mstatus
    andi    t1, t1, 8
    beqz    t1, .Lfail_test9
    csrr    t1, mcause
    bnez    t1, .Lfail_test10
    csrr    t1, mip
    bnez    t1, .Lfail_test11

    # ── Tests 12-13: scrub a stored pointer, reload it ────────────────────────
    .word   0x00C53023              # csc     ca2, 0(ca0)
    sw      a0, 0(a0)               # scrub: low word <- slot address, tag cleared
    .word   0x00053683              # clc     ca3, 0(ca0)   (stale pointer)
    .word   0xFE46835B              # cgettag t1, ca3
    bnez    t1, .Lfail_test12
    .word   0xFEF6835B              # cgetaddr t1, ca3
    bne     t1, a0, .Lfail_test13

    # ── Tests 14-18: dereferencing the stale pointer faults ───────────────────
    la      t0, .Ltrap_local
    .word   0x03C0035B              # cspecialr c6, mtcc
    .word   0x2053035B              # csetaddr  c6, c6, t0
    .word   0x03C3005B              # cspecialw mtcc, c6

.Lstale_load:
    lw      t2, 0(a3)               # DENIED: ca3 is untagged
    j       .Lfail_test14           # reached only if the load did not trap

.Ltrap_taken:
    csrr    t1, mcause
    li      t2, 28                  # CHERI fault
    bne     t1, t2, .Lfail_test15
    csrr    t1, mtval
    andi    t2, t1, 0x1F
    li      t0, 0x02                # tag violation
    bne     t2, t0, .Lfail_test16
    li      t2, 0x1A2               # (13 << 5) | 0x02
    bne     t1, t2, .Lfail_test17
    .word   0x03F0035B              # cspecialr ct1, mepcc
    .word   0xFEF3035B              # cgetaddr  t1, ct1
    la      t2, .Lstale_load
    bne     t1, t2, .Lfail_test18

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
.Lfail_test18: li a0, 18; ret

    .data
    .balign 8
cap_slots:                          # slot A at +0, slot B at +8
    .space  16
