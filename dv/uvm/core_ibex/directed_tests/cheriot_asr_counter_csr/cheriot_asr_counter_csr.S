# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_asr_counter_csr — counter CSRs are readable without ASR
# =============================================================================
# ext_check_CSR() in the CHERIoT Sail model (cheri_addr_checks.sail) lists ten
# CSRs that may be READ while PCC lacks the access-system-registers permission,
# and requires ASR for any write:
#
#   0xB00 mcycle   0xB02 minstret   0xB80 mcycleh   0xB82 minstreth
#   0xC00 cycle    0xC01 time       0xC02 instret
#   0xC80 cycleh   0xC81 timeh      0xC82 instreth
#
# ibex_decoder.sv's csr_cheriot_always_ok_o safe-list originally covered only
# 0xC00-0xC9F, omitting the four 0xB machine-mode counters. Every "csrr rd,
# mcycle" from a compartment without ASR therefore raised
# PermitAccessSystemRegistersViolation. CHERIoT RTOS times each test with
# exactly that instruction, so the Sonata test suite hung in an endless
# violation loop, re-faulting at the same PC forever.
#
# Running this needs ASR actually absent from PCC, which is awkward because
# CAndPerm is monotone -- nothing can hand the permission back. The crt's exit
# path needs ASR too (it does "cspecialr c10, mtdc" to reach tohost), so simply
# dropping ASR and continuing would strand the test.
#
# A CJALR excursion solves it. Per cheriot_cjalr_sentry, a CJALR with rd=ra
# always mints a backward sentry in ra sealed from the PCC *at the call site* --
# which still holds ASR, because the jump has not happened yet. So:
#
#   main (ASR=1) --CJALR--> .Lno_asr (ASR=0) --jalr x0,ra--> back in main (ASR=1)
#
# The counter read happens inside .Lno_asr, and the return restores a
# fully-permissioned PCC so the crt can still exit.
#
# Permission bit positions are perms_t in ibex_cheriot_pkg.sv:
#   [8] EX execute   [7] SR access-system-registers   [6] MC   [5] LD   [0] GL
# MTCC carries perms 0x1EB (EX=1, SR=1). Masking with 0xF7F clears SR alone,
# giving 0x16B -- EX still set, so the derived capability is still executable.
#
# Tests:
#   1. The derived capability has SR (bit 7) clear.
#   2. It still has EX (bit 8) set, so the excursion is actually executable
#      and test 4 cannot pass vacuously.
#   3. mcycle reads back without trapping while PCC lacks ASR.
#   4. The excursion really ran (marker set inside .Lno_asr).
#   5. ASR is restored after the return -- "cspecialr ca0, mtcc" would trap if
#      it were not, and the crt needs it to exit.

.globl main
main:
    # jalr ra below clobbers ra, so save the crt's return capability first.
    # CMove preserves the tag; a plain mv would clear it.
    .word   0xFEA083DB              # cmove ct2, cra

    # ── Build an ASR-stripped executable capability aimed at .Lno_asr ────────
    .word   0x03C0055B              # cspecialr ca0, mtcc      (tag=1,EX=1,SR=1)
    la      a1, .Lno_asr
    .word   0x20B5055B              # csetaddr ca0, ca0, a1
    li      a1, 0xF7F               # every permission except SR (bit 7)
    .word   0x1AB5055B              # candperm ca0, ca0, a1

    # ── Test 1/2: confirm SR really went and EX really stayed ───────────────
    # cgetperm writes an integer into a0, which clears ca0's tag, so the
    # capability is rebuilt afterwards. cheriot_andperm documents this exact
    # trap: checking perms in place made its test 2 pass for the wrong reason.
    .word   0xFE05055B              # cgetperm a0, ca0
    andi    a1, a0, 0x080           # isolate SR (bit 7)
    bnez    a1, .Lfail_test1        # SR must be clear
    andi    a1, a0, 0x100           # isolate EX (bit 8)
    beqz    a1, .Lfail_test2        # EX must still be set

    # Rebuild the capability the perm check just destroyed.
    .word   0x03C0055B              # cspecialr ca0, mtcc
    la      a1, .Lno_asr
    .word   0x20B5055B              # csetaddr ca0, ca0, a1
    li      a1, 0xF7F
    .word   0x1AB5055B              # candperm ca0, ca0, a1

    li      t1, 0                   # marker: excursion not yet entered
    jalr    ra, a0, 0               # CJALR: PCC <- ASR-stripped cap,
                                    # ra <- backward sentry sealed from the
                                    # current (ASR-bearing) PCC

    # ── back in main, ASR restored ──────────────────────────────────────────
    # ── Test 3/4: how did the excursion end? t1 carries the verdict out, as
    #    the excursion cannot branch to the exit table directly -- it has to
    #    return through the sentry to get ASR back first. ────────────────────
    li      a2, 3
    beq     t1, a2, .Lfail_test3    # ran, but mcycle never advanced
    li      a2, 1
    bne     t1, a2, .Lfail_test4    # never completed at all

    # ── Test 5: ASR is back -- this traps if it is not ──────────────────────
    .word   0x03C0055B              # cspecialr ca0, mtcc
    .word   0xFE45055B              # cgettag a0, ca0
    li      a2, 1
    bne     a0, a2, .Lfail_test5

    j       .Lpass

.Lno_asr:
    # PCC here has SR=0. Per the Sail allow-list these reads must all succeed;
    # before the decoder fix the first one raised
    # PermitAccessSystemRegistersViolation.
    # Destination registers must be x0-x15. This block originally used t3-t6,
    # which are x28-x31: ibex_decoder.sv's illegal_reg_16 makes ANY access to
    # x16-x31 illegal once cheriot_enable_i is asserted, and it checks rd as
    # well as the source fields. So `csrr t3, minstret` raised an illegal
    # instruction because of its *destination*, not because of the CSR -- the
    # exact opposite of what this test is trying to prove. Worse, the crt's trap
    # handler then reads mepc, which is itself illegal in CHERIoT mode
    # (REQ_SCR_07), so the first fault became a 1000-deep double-fault storm and
    # the test reported a decoder failure that was never there.
    #
    # The destinations are never read; only the absence of a trap is under test.
    # t2 is deliberately avoided -- the crt keeps its return capability in ct2
    # (see .Lfail_test3_fixup below).
    csrr    t0, mcycle              # 0xB00 -- the instruction CHERIoT RTOS hung on
    csrr    s0, minstret            # 0xB02
    csrr    s1, mcycleh             # 0xB80
    csrr    a5, minstreth           # 0xB82
    csrr    s0, cycle               # 0xC00 -- already covered by the old safe-list
    csrr    a3, instret             # 0xC02

    # ── Test 3: mcycle actually produced a value. mcycle is free-running, so
    # a second read must differ from the first; a trapping read would leave t0
    # untouched and the difference would be zero.
    csrr    a4, mcycle
    beq     a4, t0, .Lfail_test3_fixup

    li      t1, 1                   # marker: excursion ran to completion
    jalr    x0, ra, 0               # CJALR return via the backward sentry

# Failure inside the excursion cannot simply "ret" -- ra is the backward
# sentry, and the crt's return capability is in ct2. Return through the sentry
# with the marker left clear, and test 4 reports it.
.Lfail_test3_fixup:
    li      t1, 3
    jalr    x0, ra, 0

.Lpass:       li a0, 0; j .Lexit
.Lfail_test1: li a0, 1; j .Lexit
.Lfail_test2: li a0, 2; j .Lexit
.Lfail_test3: li a0, 3; j .Lexit
.Lfail_test4: li a0, 4; j .Lexit
.Lfail_test5: li a0, 5

.Lexit:
    .word   0xFEA380DB              # cmove cra, ct2 -- restore the crt's real
                                    # return capability before returning.
    ret
