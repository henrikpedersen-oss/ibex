# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: juliet_cwe272_least_privilege — CWE-272 Least Privilege (CHERIoT)
# =============================================================================
# CWE-272 (NIST Juliet Test Suite): Least Privilege Violation.
#
# In C without CHERIoT:
#   // A component is granted write access it does not need (over-privileged).
#   // No mechanism prevents the component from using the write permission.
#
# In CHERIoT:
#   Capabilities carry an explicit permission set (CHERIoT perm word).
#   CAndPerm irreversibly narrows permissions — it is monotone by design.
#   The resulting capability has strictly fewer permissions.  Tag is preserved
#   because narrowing never increases authority.  If a component receives only
#   the narrowed capability, it cannot escalate back to the broader permissions.
#
# MTDC (the data memory root) resets with perms=0x07F (bits 0-6 set).
# CHERIoT permission bit 2 is SD (permit-store / write permission).
# After CAndPerm(mask=0x07B = 0b0111_1011), bit 2 is cleared: the capability
# can no longer authorise stores.  This enforces the principle of least privilege
# — the component only receives read authority, not write authority.
#
#   Test 1 (CGetPerm on MTDC = 0x07F — full data-root permissions)
#     Verifies the baseline: MTDC resets with the full data-root permission set
#     (0x07F = bits 0-6 set, EX=bit8 clear).  A wrong value means the SCR did
#     not reset correctly or CGetPerm is mis-decoding the perm field.
#
#   Test 2 (CGetPerm after CAndPerm(0x07B) has SD (bit 2) clear)
#     After masking: new perms = 0x07F & 0x07B = 0x07B.  Isolating bit 2
#     with andi must give 0.  A non-zero result means CAndPerm failed to apply
#     the mask, or CGetPerm is returning the pre-mask permission word.
#
#   Test 3 (tag = 1 after CAndPerm — tag preserved on unsealed caps)
#     CAndPerm on an unsealed capability always preserves the tag.  Narrowing
#     permissions is always a safe (monotone) operation.  A cleared tag here
#     would indicate a bug in the CAndPerm tag-preservation logic.
#
#   Tests 4-6 (interrupt state — no interrupt expected)
#     Machine-mode interrupts are enabled at the start of the test.
#     Test 4: mstatus.MIE still = 1.
#     Test 5: mcause = 0.
#     Test 6: mip = 0.
#
# Verification:
#   Two independent layers catch a faulty DUT:
#
#   1. Cosim (Spike vs ibex RTL, per instruction step):
#      cgetperm and cgettag write integer results; Spike and RTL are compared
#      on every step.  A wrong perm mask or unexpected tag clear diverges
#      immediately.
#
#   2. Self-check (bne against expected values, andi+bne for bit tests):
#      main() returns non-zero on any failure; UVM marks FAILED.
#
# Adapted from Juliet C Test Suite CWE272_Least_Privilege_Violated (NIST/NSA).
# =============================================================================
#
# CHERIoT MTDC permission bits (perms=0x07F = 0b0111_1111 at reset):
#   bit 0: GL  (global)           = 1
#   bit 1: LG  (load-global)      = 1
#   bit 2: SD  (permit-store)     = 1   ← this test strips this bit
#   bit 3: LM  (load-mutable)     = 1
#   bit 4: SL  (store-local)      = 1
#   bit 5: LD  (permit-load)      = 1
#   bit 6: MC  (permit-load-cap)  = 1
#   bit 8: EX  (permit-execute)   = 0   (MTDC is a data cap, not execute)
# Mask to strip SD (bit 2): 0x07B = 0b0111_1011
# After CAndPerm: perms = 0x07F & 0x07B = 0x07B (bit 2 cleared, rest intact)
#
# Instruction encodings (rd=a0=x10, cs1=ca0=x10, rs2=a1=x11 unless noted):
#
#   cspecialr ca0, mtdc   [funct7=0x01, rs2=29, rs1=x0, rd=x10]:
#     (0x01<<25)|(29<<20)|(0<<15)|(0<<12)|(10<<7)|0x5B = 0x03D0055B
#
#   cgetperm a0, ca0 [funct7=0x7F, rs2=0, rs1=x10, rd=x10]:
#     (0x7F<<25)|(0<<20)|(10<<15)|(0<<12)|(10<<7)|0x5B
#     = 0xFE000000|0|0x00050000|0|0x500|0x5B = 0xFE05055B
#
#   candperm ca0, ca0, a1 [funct7=0x0D, rs2=x11, rs1=x10, rd=x10]:
#     (0x0D<<25)|(11<<20)|(10<<15)|(0<<12)|(10<<7)|0x5B
#     = 0x1A000000|0x00B00000|0x00050000|0|0x500|0x5B = 0x1AB5055B
#
#   cgettag a0, ca0 [funct7=0x7F, rs2=4, rs1=x10, rd=x10]:
#     (0x7F<<25)|(4<<20)|(10<<15)|(0<<12)|(10<<7)|0x5B
#     = 0xFE000000|0x00400000|0x00050000|0|0x500|0x5B = 0xFE45055B
#
# Tests:
#   1. cgetperm on MTDC = 0x07F  (full data-root permission baseline).
#   2. cgetperm after candperm(0x07B) has bit 2 (SD) clear.
#   3. cgettag after candperm = 1  (tag preserved on unsealed cap).
#   4. mstatus.MIE = 1.
#   5. mcause = 0.
#   6. mip = 0.

.globl main
main:
    # Enable machine-mode interrupts for the duration of this test.
    csrsi   mstatus, 8              # set mstatus.MIE (bit 3)

    # Load MTDC (full-range data capability, perms=0x07F, tag=1).
    .word   0x03D0055B              # cspecialr ca0, mtdc

    # ── Test 1: MTDC perms = 0x07F (baseline — full data-root permissions) ────
    .word   0xFE05055B              # cgetperm a0, ca0
    li      a2, 0x07F
    bne     a0, a2, .Lfail_test1

    # Apply CAndPerm to strip SD (permit-store, bit 2).
    # mask = 0x07B = 0b0111_1011; result perms = 0x07F & 0x07B = 0x07B.
    # Rebuild the capability first: a0 and ca0 are the SAME register, so the
    # cgetperm above wrote an integer into it and cleared the tag. CAndPerm would
    # otherwise operate on a dead capability, which made test 2 pass for the
    # WRONG reason (SD reads clear because every permission does) and test 3
    # fail. Unnoticed because crt_cheriot.S reported TEST_PASS unconditionally
    # until 2026-09-18.
    .word   0x03D0055B              # cspecialr ca0, mtdc
    li      a1, 0x07B
    .word   0x1AB5055B              # candperm ca0, ca0, a1

    # ── Test 2: SD (bit 2) is now clear — write permission removed ───────────
    .word   0xFE05055B              # cgetperm a0, ca0
    andi    a1, a0, 0x4             # isolate SD (bit 2)
    bne     a1, x0, .Lfail_test2   # fail if SD still set

    # ── Test 3: tag = 1 — CAndPerm on unsealed cap preserves tag ─────────────
    # Rebuild again: the cgetperm in test 2 clobbered ca0 the same way.
    .word   0x03D0055B              # cspecialr ca0, mtdc
    li      a1, 0x07B
    .word   0x1AB5055B              # candperm ca0, ca0, a1
    .word   0xFE45055B              # cgettag a0, ca0
    li      a1, 1
    bne     a0, a1, .Lfail_test3

    # ── Interrupt state verification (no interrupt expected) ───────────────────
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
