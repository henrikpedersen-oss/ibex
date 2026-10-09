# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_fatal_err_mtcc -- a trap taken while MTCC is untagged
# =============================================================================
# RTL block targeted: ibex_cs_registers.sv gen_scr, `cheriot_fatal_err_q <= 1'b1` (a trap,
# csr_save_cause_i, while mtvec_cap.valid == 0), which drives alert_major_internal_o through
# ibex_core.sv (cheriot_fatal_err) and ibex_top.sv.
#
# Expected behaviour and where it comes from:
#   - REQ_PER_03: MTCC may be written with an untagged value; the obligation the spec states is
#     that it reads back untagged (checks 1-2 below, self-checked).
#   - What happens on the trap itself the spec leaves undefined ("A trap through such an MTCC has
#     no defined outcome": every fetch fault vectors to the same untagged MTCC, CHERIoT-Sail
#     stops with not_implemented). The RTL's stated design intent (ibex_cs_registers.sv gen_scr:
#     "fatal error condition (unrecoverable, need external reset)") is a sticky fatal error on
#     alert_major_internal_o. THAT is what the bench checks; the spec has no requirement for it
#     yet, so a failure of the alert check is a question for the spec as much as for the RTL.
#
# The program cannot report anything once the trap is taken -- PCC becomes the untagged MTCC and
# no further instruction can be fetched -- so the verdict is the testbench's
# (core_ibex_cheriot_fatal_err_test, core_ibex_test_lib.sv). The program announces the trap with
# CORE_STATUS HANDLING_EXCEPTION, waits 32 instructions, and executes ecall. The bench requires:
# no alert before the announcement; the first trap after it is the ecall (mcause 11) with
# alert_major_internal_o still low; the alert within 4 cycles of the trap; the alert held for
# 2000 cycles; never a minor or bus alert. The bench then ends the run. The program never writes
# TEST_PASS, so the run cannot pass through the signature handshake.
#
# Cosim: none. CHERIoT-Sail has no defined behaviour after this trap (above), so the test boots
# in RISC-V mode and the bench raises the pin on the write to 0x80200000
# (+cheriot_enable_on_write, as cheriot_debug_mode does); +disable_cosim=1 relaxes Spike.
#
# Program failure codes (TEST_RESULT TEST_FAIL, a0 in the CORE_STATUS word; the bench reports a
# failed handshake as UVM_FATAL):
#   1   MTCC untagged before the test changed it (the reset/SET_VEC MTCC must be tagged, or the
#       trap below would not be the first through an untagged MTCC)
#   2   MTCC read back tagged after CSpecialRW of an untagged value (REQ_PER_03)
#   10  ecall did not trap
#   11  the instruction at the untagged MTCC's address executed (fetch from an untagged PCC)
#   249 debug entry, 250 unexpected trap before the arming point, 251 liveness
#
# Register use: x0-x15 only (RV32E). s1 = signature capability (cheriot_dv.h), s0 = check count.

#include "cheriot_dv.h"

.set NCHK, 0
.macro CHK a, b, code
  .set      NCHK, NCHK + 1
  addi      s0, s0, 1
  beq       \a, \b, 9f
  li        a0, \code
  j         test_end
9:
.endm
.macro CHKI a, imm, code
  li        t2, \imm
  CHK       \a, t2, \code
.endm

    .option norvc

    DV_VECTORS unexpected_debug, unexpected_debug
_start:
    ENABLE_CHERIOT_VIA_TRIGGER
    j         main

    .text
main:
    # Every symbol address is taken with LA_FAR / SET_VEC (cheriot_dv.h), never GNU `la`.
    SET_VEC   .Lunexpected, t1, t0
    SIG_INIT
    li        s0, 0

    # 1: MTCC is tagged before the test clears it.
    cspecialr a1, SCR_MTCC
    cgettag   t1, a1
    CHKI      t1, 1, 1

    # MTCC := MTCC with its cursor at fatal_vector, tag cleared.
    SET_VEC   fatal_vector, t1, t0
    cspecialr a1, SCR_MTCC
    ccleartag a1, a1
    cspecialw SCR_MTCC, a1

    # 2: it reads back untagged (REQ_PER_03). From here on any trap is the fatal one.
    cspecialr a2, SCR_MTCC
    cgettag   t1, a2
    CHK       t1, zero, 2

    li        t0, NCHK
    li        a0, 251
    bne       s0, t0, test_end

    # Arming point: the bench treats the next trap as the one under test.
    SIG_STATUS ST_HANDLING_EXCEPTION
    .rept 32
    nop
    .endr
    ecall
    li        a0, 10                        # ecall did not trap
    j         test_end

test_end:
    TEST_END_A0

unexpected_debug:
    li        a0, 249
    j         test_end

    .balign 4
.Lunexpected:
    li        a0, 250
    j         test_end

    # The untagged MTCC points here. Nothing at this address may execute: PCC is untagged.
    .balign 4
fatal_vector:
    li        a0, 11
    j         test_end
