# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: wb_cheri_sentry_cjalr — CJALR through a forward sentry (otype=1)
# =============================================================================
# CHERIoT sentries (cheri_pkg.sv: OTYPE_SENTRY=1) are sealed execute capabilities
# used to enforce control-flow integrity.  CJALR into a sentry:
#   1. Unseals the target capability → new PCC (execute, bounds inherited)
#   2. Writes the return address to rd as a sealed backward sentry:
#      rd.integer = PC+4 (link address)
#      rd.capability = seal_cap(link_cap, OTYPE_SENTRY_IE_BKWD=5) if MIE=1
#
# Capability construction:
#   Step 1  auipc  a0, 0        — get PCC (unsealed, EX bit set, tag=1)
#   Step 2  la a1,.Ltarget;
#           csetaddr ca0,ca0,a1 — set PCC cursor to jump target
#   Step 3  cspecialr a1,mscratchc — get seal root (SE+US permissions)
#   Step 4  li t0,1; csetaddr a1,a1,t0 — cursor=1 selects OTYPE_SENTRY=1
#   Step 5  cseal ca0,ca0,a1    — create sentry: ca0.otype=1, tag=1
#   Step 6  cjalr ra, ca0       — jump to .Ltarget via sentry
#
# At .Ltarget:
#   ra.capability.otype = 5 (OTYPE_SENTRY_IE_BKWD) because MIE=1 at jump
#   ra.capability.tag   = 1 (valid backward sentry)
#
# Return convention:
#   CJALR overwrites ra with a new backward sentry (cursor = PC+4 of CJALR).
#   To return to the original caller, we save the caller's backward sentry
#   in s0 (x8) before the CJALR and restore it to ra after tests at .Ltarget.
#     cmove s0, c1   = 0xFEA0845B  (funct7=0x7F rs2=0x0A rs1=x1 rd=x8)
#     cmove c1, c8   = 0xFEA400DB  (funct7=0x7F rs2=0x0A rs1=x8 rd=x1)
#
# Encodings:
#   auipc  a0, 0         = 0x00000517  (AUIPCC/AUIPC, rd=x10, imm=0)
#   csetaddr ca0,ca0,a1  = .word 0x20B5055B  (funct7=0x10 rs2=x11 rs1=x10 rd=x10)
#   cspecialr a1,mscratchc = .word 0x03E005DB  (rd=x11, scr=30)
#   csetaddr a1,a1,t0    = .word 0x205585DB  (funct7=0x10 rs2=x5 rs1=x11 rd=x11)
#   cseal ca0,ca0,a1     = .word 0x16B5055B  (funct7=0x0B rs2=x11 rs1=x10 rd=x10)
#   cjalr ra, ca0        = .word 0x000500E7  (OPCODE_JALR=0x67, imm12=0, rs1=x10, rd=x1)
#   cgettype a0, ca0     = .word 0xFE15055B  (funct7=0x7F rs2=1 rs1=x10 rd=x10)
#   cgettag  a0, ca0     = .word 0xFE45055B
#   cgettype a0, ra      = .word 0xFE10855B  (funct7=0x7F rs2=1 rs1=x1 rd=x10)
#   cgettag  a0, ra      = .word 0xFE40855B  (funct7=0x7F rs2=4 rs1=x1 rd=x10)
# =============================================================================

.globl main
main:
    csrsi   mstatus, 8              # MIE=1 (so CJALR creates IE backward sentry)

    # ── Step 1: get current PCC (unsealed execute cap) via AUIPCC ─────────────
    auipc   a0, 0                   # ca0 = PCC with cursor=PC (AUIPCC in CHERIoT)

    # ── Step 2: redirect cursor to .Ltarget ───────────────────────────────────
    la      a1, .Ltarget
    .word   0x20B5055B              # csetaddr ca0, ca0, a1

    # ── Step 3: get MScratchC (seal root: SE+US permissions, full range) ──────
    .word   0x03E005DB              # cspecialr a1, mscratchc  (rd=x11)

    # ── Step 4: set seal cap cursor to 1 (OTYPE_SENTRY = 1) ──────────────────
    li      t0, 1
    .word   0x205585DB              # csetaddr a1, a1, t0  (rs2=x5=t0)

    # ── Step 5: CSeal → create forward sentry (otype=1) ──────────────────────
    .word   0x16B5055B              # cseal ca0, ca0, a1

    # ── Test 1: sealed capability has tag=1 ──────────────────────────────────
    # Use t0 (x5) as rd so ca0 (x10) is not clobbered before Test 2 and CJALR.
    .word   0xFE4502DB              # cgettag t0, ca0  (rd=x5, rs1=x10)
    li      a2, 1
    bne     t0, a2, .Lfail_test1

    # ── Test 2: otype = 1 (OTYPE_SENTRY) ────────────────────────────────────
    # Same: use t0 as rd to preserve ca0 for the CJALR below.
    .word   0xFE1502DB              # cgettype t0, ca0  (rd=x5, rs1=x10)
    li      a2, 1
    bne     t0, a2, .Lfail_test2

    # ── Step 6: CJALR ra, ca0 — jump through sentry to .Ltarget ─────────────
    # Save caller's return sentry to s0 before CJALR overwrites ra.
    .word   0xFEA0845B              # cmove s0, c1  (rd=x8=s0, rs1=x1=ra)
    .word   0x000500E7              # cjalr ra, ca0  (OPCODE_JALR=0x67, imm=0, rs1=x10, rd=x1=ra)
    # Execution continues at .Ltarget (code below is unreachable)
    li      a0, 99
    ret

    # ── .Ltarget: post-sentry-jump checks ────────────────────────────────────
    .align 2
.Ltarget:
    # ── Test 3: ra.cap.otype = 5 (OTYPE_SENTRY_IE_BKWD, MIE=1 at jump time) ─
    .word   0xFE10855B              # cgettype a0, ra  (rs1=x1=ra)
    li      a2, 5
    bne     a0, a2, .Lfail_test3

    # ── Test 4: ra.cap.tag = 1 (valid backward sentry) ───────────────────────
    .word   0xFE40855B              # cgettag a0, ra   (rs1=x1=ra)
    li      a2, 1
    bne     a0, a2, .Lfail_test4

    # ── Tests 5-7: interrupt state ────────────────────────────────────────────
    csrr    a0, mstatus
    andi    a1, a0, 8
    beq     a1, x0, .Lfail_test5
    csrr    a0, mcause
    bne     a0, x0, .Lfail_test6
    csrr    a0, mip
    bne     a0, x0, .Lfail_test7

    li      a0, 0
    j       .Lreturn

    # .Lfail_test1/.Lfail_test2: before CJALR, ra still holds caller's sentry
.Lfail_test1: li a0, 1; ret
.Lfail_test2: li a0, 2; ret
    # .Lfail_test3-7: after CJALR, restore ra from s0 before returning
.Lfail_test3: li a0, 3; j .Lreturn
.Lfail_test4: li a0, 4; j .Lreturn
.Lfail_test5: li a0, 5; j .Lreturn
.Lfail_test6: li a0, 6; j .Lreturn
.Lfail_test7: li a0, 7; j .Lreturn

    # Restore the caller's backward sentry from s0 into ra, then return.
.Lreturn:
    .word   0xFEA400DB              # cmove c1, c8  (rd=x1=ra, rs1=x8=s0)
    ret
