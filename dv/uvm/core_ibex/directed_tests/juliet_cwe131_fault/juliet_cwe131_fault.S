# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: juliet_cwe131_fault — CWE-131 buffer size miscalculation, enforcement
# =============================================================================
# Replaces the retired juliet_cwe131_buf_size_calc, which asserted that CIncAddr
# past the end of a buffer clears the tag. It does not, and that is not how
# CHERIoT denies the overflow. The cursor may legitimately leave the bounds --
# CIncAddr clears the tag only when the result is UNREPRESENTABLE, which is a
# different mechanism covered by juliet_cwe131_repr. Enforcement happens at
# DEREFERENCE, which is what this test exercises.
#
# In C without CHERIoT:
#   char *buf = malloc(4);        // wrong size computed
#   buf[8] = 0x41;                // silent heap overflow
#
# Under CHERIoT the store is denied by hardware.
#
# Why this test installs its own trap vector
# ------------------------------------------
# crt_cheriot.S's trap_entry saves registers before dispatching, using a base
# register materialised by the compiler's ordinary auipc+addi idiom. Under
# CHERIoT the addi is an integer op, so it CLEARS the tag, and the save itself
# faults -- the handler cannot run, and any test that takes a trap double-faults
# (see wb_cheri_clc_csc and the tickets). Overriding the weak handle_trap does
# not help: the fault happens in trap_entry, upstream of the call.
#
# So this test points MTCC at its own handler, using the same three-instruction
# sequence crt_cheriot.S uses to install trap_entry (cspecialr/csetaddr/cspecialw
# with c6/t0, encodings copied verbatim from there). The handler performs NO
# memory access and NO CSR access:
#
#   - No memory access, because a store needs a tagged base capability and
#     materialising one is the very idiom that breaks trap_entry.
#   - No CSR access, because mepc is an ILLEGAL CSR once cheriot_enable_i is
#     asserted (MEPCC supersedes it), so reading it would fault again.
#
# It therefore does not return via mret at all -- it jumps straight to a label in
# the test. Control never resumes at the faulting instruction, so nothing needs
# to skip it. The consequence is that mstatus.MIE stays cleared by the trap, so
# this test does not check interrupt state the way the non-faulting tests do.
#
#   Test 1: bounded 4-byte capability is valid (tag = 1)
#   Test 2: store at offset 8 traps  (reaching .Lno_trap means it did not)
#   Test 3: the denied store left memory unmodified
#
# Encodings (rd = ca0, cs1 = ca0, rs2 = a1 unless noted):
#   cspecialr  ca0, mtdc   = .word 0x03D0055B
#   csetaddr   ca0,ca0,a1  = .word 0x20B5055B
#   csetbounds ca0,ca0,a1  = .word 0x10B5055B
#   cgettag    a0, ca0     = .word 0xFE45055B
# Trap-vector install (from crt_cheriot.S, c6/t0):
#   cspecialr  c6, mtcc    = .word 0x03C0035B
#   csetaddr   c6, c6, t0  = .word 0x2053035B
#   cspecialw  mtcc, c6    = .word 0x03C3005B
#
# Returns 0 on success; 1=cap invalid, 2=no trap, 3=memory was modified.

    .section .text
    .globl main

# ---------------------------------------------------------------------------
# Test-local trap handler. No memory access, no CSR access, no mret -- see the
# header. Jumps into the test at the point that expects the fault.
# ---------------------------------------------------------------------------
# MUST be 4-byte aligned: ibex_cheriot_ex.sv:483 clears MTCC's tag on write unless
# the address is 4-byte aligned, has EX permission and is unsealed. An unaligned
# vector is accepted silently at install time and then, on the first trap,
# cheriot_fatal_err fires (cs_registers.sv:2222, "trap taken with invalid MTCC")
# and raises alert_major_internal -- which trips NoAlertsTriggered in the TB.
.balign 4
.Ltrap_local:
    j       .Ltrap_taken

main:
    # Seed the target word with a known value so an unwanted write is visible.
    # A full-range MTDC capability is used, so this store is legal.
    .word   0x03D0055B              # cspecialr ca0, mtdc
    li      a1, 0x80080000
    .word   0x20B5055B              # csetaddr ca0, ca0, a1
    li      a2, 0x5A5A5A5A
    sw      a2, 8(a0)

    # ── Test 1: the undersized (4-byte) capability is valid ─────────────────
    .word   0x03D0055B              # cspecialr ca0, mtdc
    li      a1, 0x80080000
    .word   0x20B5055B              # csetaddr ca0, ca0, a1
    li      a1, 4
    .word   0x10B5055B              # csetbounds ca0, ca0, a1   ([0x80080000,0x80080004))
    .word   0xFE45055B              # cgettag a0, ca0
    li      a1, 1
    bne     a0, a1, .Lfail_test1

    # Redirect traps to the local handler above, bypassing crt_cheriot.S's
    # trap_entry. t0 holds the handler address as an integer; the capability it
    # is grafted onto comes from MTCC, so the tag and EX permission survive.
    la      t0, .Ltrap_local
    .word   0x03C0035B              # cspecialr c6, mtcc
    .word   0x2053035B              # csetaddr  c6, c6, t0
    .word   0x03C3005B              # cspecialw mtcc, c6

    # ── Test 2: store past the end must trap ────────────────────────────────
    # Rebuild (the cgettag above clobbered ca0 -- a0 and ca0 are the same
    # register) and store 8 bytes in, outside [base, base+4). The capability is
    # still tagged; this is a genuine bounds check at dereference.
    .word   0x03D0055B              # cspecialr ca0, mtdc
    li      a1, 0x80080000
    .word   0x20B5055B              # csetaddr ca0, ca0, a1
    li      a1, 4
    .word   0x10B5055B              # csetbounds ca0, ca0, a1
    li      a2, 0xDEADBEEF
    sw      a2, 8(a0)               # DENIED: offset 8 is outside the 4-byte bounds

.Lno_trap:
    # Reached only if the store did NOT fault, which is the failure this test
    # exists to catch.
    li      a0, 2
    ret

.Ltrap_taken:
    # ── Test 3: the denied store did not modify memory ──────────────────────
    .word   0x03D0055B              # cspecialr ca0, mtdc
    li      a1, 0x80080000
    .word   0x20B5055B              # csetaddr ca0, ca0, a1
    lw      a2, 8(a0)               # full-range cap: legal read
    li      a3, 0x5A5A5A5A
    bne     a2, a3, .Lfail_test3   # must still hold the seed value

    li      a0, 0
    ret

.Lfail_test1: li a0, 1; ret
.Lfail_test3: li a0, 3; ret
