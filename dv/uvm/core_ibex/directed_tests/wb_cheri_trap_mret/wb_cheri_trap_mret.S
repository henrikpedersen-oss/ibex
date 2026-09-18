# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: wb_cheri_trap_mret — ECALL trap entry and MRET controller wakeup path
# =============================================================================
# The ibex_controller state machine handles trap entry and exit via the same
# paths used for WFI wakeup (CTRL_FSM_IDLE → FLUSH → DECODE).  ECALL in M-mode
# causes an exception (mcause=11=0xB, mepc=PC of ECALL instruction) and triggers
# controller flush + jump to mtvec.  MRET restores privilege state and resumes
# at mepc+4.  This exercises the controller wakeup state machine without needing
# an external interrupt source.
#
# mtvec alignment: mtvec must be 256-byte aligned for Spike cosim agreement
# (ibex WARL accepts 4-byte alignment but Spike uses 256-byte granularity).
# .align 8 (2^8 = 256) is inserted before the trap handler label.
#
#   Test 1: trap was taken (t4 flag set by handler = 1)
#   Test 2: mcause = 11 (EXCE_ECALL_MMODE)
#   Test 3: mepc = address of ECALL instruction
#   Test 4: MIE restored by MRET (mstatus.MIE=1 after MRET)
#   Test 5: mip = 0 (no pending interrupt)
#
# MTCC installation: in CHERIoT mode `csrw mtvec, rs` does not update
# MTCC.cursor — the integer CSR path is inactive for SCRs.  Must use
# cspecialr + csetaddr + cspecialrw to install a tagged capability as MTCC.
#
# Encodings:
#   auipc a0, 0             = 0x00000517    (CAUIPCC: ca0=PCC, tag=1, cursor=PC)
#   csetaddr a0, a0, t0     = .word 0x2055055B  (rs2=x5=t0; set cursor)
#   cspecialrw x0, a0, mtcc  = .word 0x03C5005B  (scr=28; write MTCC, rd=x0)
#   cspecialrw x0, a0, mepcc = .word 0x03F5005B  (scr=31; write MEPCC, rd=x0)
# Note: CAUIPCC is used instead of cspecialr+mtcc/mepcc because csrw mtvec/mepc
# in CHERIoT-Sail updates MTCC/MEPCC with an integer-derived cap (tag may be 0).
# Reading that back via cspecialr then propagating tag=0 through csetaddr and
# writing to MTCC/MEPCC leaves ibex with a null-cap SCR, causing "failed to step"
# in CHERIoT-Sail cosim.  PCC (from CAUIPCC) always has tag=1 and is identical
# in both ibex and CHERIoT-Sail, so no cosim divergence occurs.
# =============================================================================

.globl main
main:
    csrsi   mstatus, 8              # MIE=1

    # Install trap handler.
    # csrw mtvec updates Spike/integer mtvec (understood by ISS); ibex CHERIoT RTL
    # ignores integer mtvec writes for MTCC.  Build a tagged MTCC capability from
    # PCC via CAUIPCC (auipc a0, 0) — PCC always has tag=1 and the same value in
    # both ibex and CHERIoT-Sail, avoiding divergence from reading MTCC which may
    # have tag=0 in CHERIoT-Sail after the integer csrw mtvec.
    # Encodings:
    #   auipc a0, 0           = 0x00000517  (CAUIPCC in CHERIoT: ca0=PCC, cursor=PC)
    #   csetaddr a0, a0, t0   = .word 0x2055055B  (rs2=x5=t0; cursor=handler)
    #   cspecialrw x0, a0, mtcc = .word 0x03C5005B  (write MTCC; rd=x0 write-only)
    la      t0, .Ltrap_handler
    csrw    mtvec, t0               # ISS: update integer mtvec (no-op for ibex MTCC)
    auipc   a0, 0                   # CHERIoT: CAUIPCC → ca0=PCC (tag=1, bounds=code)
    .word   0x2055055B              # CHERIoT: csetaddr a0, a0, t0  (cursor=handler)
    .word   0x03C5005B              # CHERIoT: cspecialrw x0, a0, mtcc

    # ── ECALL: M-mode exception → jumps to .Ltrap_handler ────────────────────
    li      t4, 0                   # trap_taken flag: handler sets to 1
    ecall
.Lafter_ecall:
    # Execution resumes here after MRET from handler

    # ── Test 1: trap was taken ────────────────────────────────────────────────
    beq     t4, x0, .Lfail_test1

    # ── Test 2: mcause = 11 (E-call from M-mode) ─────────────────────────────
    csrr    a0, mcause
    li      a1, 11
    bne     a0, a1, .Lfail_test2

    # ── Test 3: mepc was set to address of ecall ──────────────────────────────
    # The handler saved the original mepc (= &ecall) into s1 before advancing it.
    # Reading mepc now gives ECALL+4 (what the handler wrote), not the original.
    la      a1, .Lafter_ecall
    addi    a1, a1, -4              # a1 = &ecall (= .Lafter_ecall - 4)
    bne     s1, a1, .Lfail_test3   # s1 = original mepc saved by handler

    # ── Test 4: MIE restored by MRET (MRET sets MIE = MPIE = 1) ─────────────
    csrr    a0, mstatus
    andi    a1, a0, 8               # isolate MIE
    beq     a1, x0, .Lfail_test4

    # ── Test 5: mip = 0 ───────────────────────────────────────────────────────
    csrr    a0, mip
    bne     a0, x0, .Lfail_test5

    li      a0, 0
    ret

    # ── Trap handler (256-byte aligned for mtvec cosim agreement) ─────────────
    # In CHERIoT mode, mret uses MEPCC.cursor as the return address; integer
    # csrw mepc is a no-op for ibex MEPCC.  Build a tagged MEPCC capability from
    # PCC via CAUIPCC (tag=1, same in ibex and CHERIoT-Sail), then csetaddr
    # to cursor=ECALL+4, then cspecialrw to install MEPCC.
    # Encodings:
    #   auipc a0, 0             = 0x00000517  (CAUIPCC: ca0=PCC, tag=1)
    #   csetaddr a0, a0, t0     = .word 0x2055055B  (rs2=x5=t0; cursor=ECALL+4)
    #   cspecialrw x0, a0, mepcc = .word 0x03F5005B  (scr=31, write-only)
    .align 8
.Ltrap_handler:
    li      t4, 1                   # signal: trap fired
    csrr    s1, mepc                # s1 = original MEPCC.cursor (= &ecall)
    addi    t0, s1, 4               # t0 = ECALL+4 (return address)
    auipc   a0, 0                   # CHERIoT: CAUIPCC → ca0=PCC (tag=1, bounds=code)
    .word   0x2055055B              # CHERIoT: csetaddr a0, a0, t0  (cursor=ECALL+4)
    .word   0x03F5005B              # CHERIoT: cspecialrw x0, a0, mepcc  (scr=31)
    mret

.Lfail_test1: li a0, 1; ret
.Lfail_test2: li a0, 2; ret
.Lfail_test3: li a0, 3; ret
.Lfail_test4: li a0, 4; ret
.Lfail_test5: li a0, 5; ret
