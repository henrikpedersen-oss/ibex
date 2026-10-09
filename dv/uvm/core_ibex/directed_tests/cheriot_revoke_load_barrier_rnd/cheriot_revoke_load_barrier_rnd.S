# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_revoke_load_barrier_rnd — TRVK against a random bitmap
# =============================================================================
# The bitmap is drawn per seed (+revbm_mode=random, ibex_revbm_pkg.sv), so the
# program cannot know which granules are revoked. The per-load verdict is
# checked by the CHERIoT-Sail cosim, which is given the same bitmap and decides
# each CLC itself (cd_wtag compare in cheriot_sail_cosim_step). The program
# checks what it CAN know independently of the bitmap:
#
#   Test 1  CGetTag(ca0) = 1. Precondition.
#   Test 2  A load that kept its tag is CSetEqualExact to what was stored.
#   Test 3  A load that lost its tag is CSetEqualExact to CClearTag(stored):
#           revocation changes the tag and nothing else.
#   Test 4  At least one of the 256 loads was revoked. Fails if no lookup is
#           made or the responder is in mode off (revoke_pct=50: P(none) =
#           2^-256 even before error words).
#   Test 5  At least one of the 256 loads kept its tag (same argument).
#   Test 6  Sealing capabilities (MScratchC-derived, perms 0xE01) over the
#           same 256 bases always keep their tag, whatever the bitmap says.
#   Test 7  Capabilities based in [0x80020000, +2 KiB), just past the window
#           (they alias words 0-7 if the range check were missing), always
#           keep their tag.
#   Test 8  Any trap.
#
# Bases: 0x80018000 + 8*i, i = 0..255 (bitmap words 0x180-0x187, every bit
# position). Needs +revbm_heap_base=80000000 for tests 6/7's window maths.
# With +revbm_gnt_delay_max/+revbm_rsp_delay_max the bitmap port also sees
# backpressure and latency (cp_trvk_revbm_handshake).
#
# Register use: ca0 = slot authority, ca2 = stored cap, ca4 = loaded,
# ca5 = CClearTag reference, a1 = revoked count, a3 = current base (integer
# only, never used as a capability), t0-t2 scratch. No x16-x31.
# Encodings as in cheriot_revoke_load_barrier, plus
#   csetaddr ca2, ca2, a3 = .word 0x20D6065B (funct7=0x10, rs2=x13)

.macro SET_TRAP_VECTOR label
    la      t0, \label
    .word   0x03C0035B              # cspecialr c6, mtcc
    .word   0x2053035B              # csetaddr  c6, c6, t0
    .word   0x03C3005B              # cspecialw mtcc, c6
.endm

# ca2 <- root (cspecialr word) with cursor a3, bounds [a3, a3+8); store; reload to ca4.
.macro ROUNDTRIP root_word
    .word   \root_word
    .word   0x20D6065B              # csetaddr   ca2, ca2, a3
    li      t0, 8
    .word   0x1056065B              # csetbounds ca2, ca2, t0
    .word   0x00C53023              # csc        ca2, 0(ca0)
    .word   0x00053703              # clc        ca4, 0(ca0)
    .word   0xFE47035B              # cgettag    t1, ca4
.endm

    .text
    .globl main

.balign 4
.Lvec_unexpected:
    j       .Lfail_test8

main:
    SET_TRAP_VECTOR .Lvec_unexpected

    la      t0, cap_slots
    .word   0x03D0055B              # cspecialr ca0, mtdc
    .word   0x2055055B              # csetaddr  ca0, ca0, t0
    .word   0xFE45035B              # cgettag   t1, ca0
    li      t2, 1
    bne     t1, t2, .Lfail_test1

    # ── Data capabilities: verdict checked by the cosim ──────────────────────
    li      a1, 0
    li      a3, 0x80018000
.Lloop_data:
    ROUNDTRIP 0x03D0065B            # cspecialr ca2, mtdc
    beqz    t1, .Lrevoked
    .word   0x42C7035B              # csetequalexact t1, ca4, ca2
    beqz    t1, .Lfail_test2
    j       .Lnext_data
.Lrevoked:
    addi    a1, a1, 1
    .word   0xFEB607DB              # ccleartag ca5, ca2
    .word   0x42F7035B              # csetequalexact t1, ca4, ca5
    beqz    t1, .Lfail_test3
.Lnext_data:
    addi    a3, a3, 8
    li      t2, 0x80018800
    bltu    a3, t2, .Lloop_data
    beqz    a1, .Lfail_test4
    li      t2, 256
    beq     a1, t2, .Lfail_test5

    # ── Sealing capabilities: exempt ─────────────────────────────────────────
    li      a3, 0x80018000
.Lloop_seal:
    ROUNDTRIP 0x03E0065B            # cspecialr ca2, mscratchc
    beqz    t1, .Lfail_test6
    addi    a3, a3, 8
    li      t2, 0x80018800
    bltu    a3, t2, .Lloop_seal

    # ── Just past the window: never looked up ────────────────────────────────
    li      a3, 0x80020000
.Lloop_oor:
    ROUNDTRIP 0x03D0065B            # cspecialr ca2, mtdc
    beqz    t1, .Lfail_test7
    addi    a3, a3, 8
    li      t2, 0x80020800
    bltu    a3, t2, .Lloop_oor

    li      a0, 0
    ret

.Lfail_test1: li a0, 1; ret
.Lfail_test2: li a0, 2; ret
.Lfail_test3: li a0, 3; ret
.Lfail_test4: li a0, 4; ret
.Lfail_test5: li a0, 5; ret
.Lfail_test6: li a0, 6; ret
.Lfail_test7: li a0, 7; ret
.Lfail_test8: li a0, 8; ret

    .data
    .balign 8
cap_slots:
    .space  8
