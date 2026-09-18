# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: wb_cheri_clc_csc — CLC two-beat cap_rx_fsm + tag revocation via SW
# =============================================================================
# CLC (Capability Load, opcode=0x03 funct3=3) triggers the cap_rx_fsm in
# ibex_load_store_unit.sv:
#   CRX_IDLE → CRX_WAIT_RESP1 (data beat 1) → CRX_WAIT_RESP2 (metadata beat 2)
# Both beats must complete before lsu_rcap_o is valid.
#
# CSC (Capability Store, opcode=0x23 funct3=3) stores the capability and sets
# the 1-bit tag SRAM entry via data_tag_o=1.  A subsequent integer SW to the
# same address writes data_tag_o=0, revoking the capability tag — this is the
# CHERIoT temporal safety guarantee.  A following CLC then reads tag=0.
#
# Scratch address: 0x80010000 (8-byte aligned; within SRAM [0x80000000,0x80080000))
#
#   Test 1: CSC MTCC → CLC → cgettag = 1 (round-trip preserves tag)
#   Test 2: back-to-back CLC (exercises consecutive cap_rx_fsm cycles)
#   Test 3: SW to same address (integer write), then CLC → cgettag = 0 (revoked)
#   Tests 4-6: interrupt state unchanged.
#
# Encodings (rd=a0=x10, rs1=ca0=x10, rs2=ca1=x11):
#   cspecialr ca0, mtdc  = .word 0x03D0055B
#   csetaddr  ca0,ca0,a1 = .word 0x20B5055B  (rs2=a1=x11)
#   cspecialr ca1, mtcc  = .word 0x03C005DB  (rd=x11)
#   sc  ca1, 0(ca0)      = .word 0x00B53023  (CSC: opcode=0x23 funct3=3 rs2=x11 rs1=x10 imm=0)
#   lc  a1,  0(ca0)      = .word 0x00053583  (CLC: opcode=0x03 funct3=3 rd=x11 rs1=x10 imm=0)
#   cgettag t0, ca1      = .word 0xFE4582DB  (funct7=0x7F rs2=4 rs1=x11=ca1 rd=x5=t0)
# NOTE: cgettag uses rd=t0 (not a0) to avoid clearing ca0.tag.
#       cgettag writes an integer to rd, which clears the tag of crd.
#       Using rd=a0 would clear ca0.tag → subsequent lc/sc via ca0 would CHERI-fault.
# =============================================================================

.globl main
main:
    csrsi   mstatus, 8

    # Set up ca0 = MTDC with cursor at scratch address (data pointer)
    .word   0x03D0055B              # cspecialr ca0, mtdc  (full-range data cap)
    li      a1, 0x80010000          # scratch: 8-byte aligned, in testbench SRAM
    .word   0x20B5055B              # csetaddr ca0, ca0, a1

    # Load MTCC into ca1 (the capability we will store/load)
    .word   0x03C005DB              # cspecialr ca1, mtcc  (rd=x11)

    # ── CSC ca1 to scratch ────────────────────────────────────────────────────
    .word   0x00B53023              # sc ca1, 0(ca0)   (CSC)

    # ── CLC back into ca1 (two-beat cap_rx_fsm) ───────────────────────────────
    .word   0x00053583              # lc a1, 0(ca0)    (CLC: rd=x11)

    # ── Test 1: tag = 1 after CSC/CLC round trip ─────────────────────────────
    # Use rd=t0 (not a0) so cgettag does not clear ca0.tag.
    .word   0xFE4582DB              # cgettag t0, ca1  (rd=x5=t0; rs1=x11=ca1)
    li      a2, 1
    bne     t0, a2, .Lfail_test1

    # ── Test 2: back-to-back CLC (consecutive cap_rx_fsm cycles) ─────────────
    .word   0x00053583              # lc a1, 0(ca0)    (CLC again, no gap; ca0.tag still 1)
    .word   0xFE4582DB              # cgettag t0, ca1  (rd=x5=t0)
    bne     t0, a2, .Lfail_test2

    # ── Integer SW revokes tag at scratch address ──────────────────────────────
    # In CHERIoT mode sw checks the capability in the base register.
    # li a4, addr clears ca4.tag; must reuse ca0 (MTDC+csetaddr, tag=1) as base.
    li      a3, 0xDEADBEEF
    sw      a3, 0(a0)               # integer store via ca0 (tag=1): data_tag_o=0 → revoked

    # ── CLC after revocation ──────────────────────────────────────────────────
    .word   0x00053583              # lc a1, 0(ca0)    (CLC: should read tag=0; ca0.tag still 1)

    # ── Test 3: tag = 0 (temporal safety — SW revoked the tag) ───────────────
    .word   0xFE4582DB              # cgettag t0, ca1  (rd=x5=t0)
    bne     t0, x0, .Lfail_test3   # tag must be 0

    # ── Tests 4-6: interrupt state ────────────────────────────────────────────
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
