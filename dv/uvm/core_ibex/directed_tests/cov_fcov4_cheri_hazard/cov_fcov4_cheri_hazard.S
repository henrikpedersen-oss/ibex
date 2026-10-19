# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cov_fcov4_cheri_hazard -- a CHERI instruction in ID with IF empty and idle
# =============================================================================
# CHERIoT mode: boots in RISC-V mode and the bench raises cheriot_enable_i
# (+cheriot_enable_on_write=80200000). Cosim off (CHERIoT-Sail has no fetch-enable or bus-timing
# model); self-checking. Targets the one CHERIoT bin of the UVM regression's last 7 covergroup
# holes (combined coverage of 2026-10-18 20:47, UNR-excluded view):
#   pipe_cross {Cheri, IF EmptyAndIdle, ID FullAndStalled, WB FullAndStalled}
# The RISC-V ones are in cov_fcov4_rv_hazard.
#
# rtl_test core_ibex_stall_events_test with +gnt_trig_lo/hi = [TRIG, TRIG + 0xff]: offset T_FOFF
# turns fetch_enable_i off from the second cycle after the access's grant for 40 cycles
# (+gnt_fetch_off_cycles); +mem_mode_on_write = MEMMODE sets the memory agents' delays.
#
# Why it reaches the bin: cov_fcov3_rv_hazard section D's arrangement (IF_EMPTY there), in
# CHERIoT mode. IF EmptyAndIdle needs fetch_enable_i off (IF req_i low) with nothing fetched
# behind X in ID, and X must be in ID before fetching stops (fetch_enable_i off holds halt_if):
# X enters ID in the cycle after the grant of the T_FOFF load L just before it, and fetching is
# off from the cycle after that. The icache fetches whole 64-bit lines and makes no new lookup
# while three fill buffers are busy, so with no instruction-side delays and IF stuck on one word
# exactly that word's line and the two after it are fetched; the store Q switches the
# instruction side to responses 60..124 cycles apart (M_IFE) once its own response is in, so
# every word up to the end of the fourth line arrives at once and every later one late (the
# reasoning, and why PADS = 0, 2, 4, 6, 8, are in cov_fcov3_rv_hazard section D). From the
# second cycle after L's grant IF is EmptyAndIdle, X waits in ID (FullAndStalled: on L's
# outstanding access, Mem, or LdHz for the op that reads L's destination) and L waits in WB for
# its response (FullAndStalled), 3..10 cycles after its grant. X: CIncAddrImm independent of L,
# and CIncAddr reading L's destination.
#
# Failure codes (TEST_END_A0, a0): 1 setup, 10 trap with an unexpected mcause, 11 trap where none
# was expected, 40 traps taken != expected, 44 cases run != assembled, 50 debug exception, 51 a
# debug entry (none expected).

#include "cheriot_dv.h"

#define TRIG          0x80100000          /* +gnt_trig_lo/hi = 80100000 / 801000ff */
#define T_FOFF        0x40
#define MEMMODE       0x80100104          /* +mem_mode_on_write=80100104 */
#define M_SLOW10      0x10a               /* data responses 10..24 cycles after the grant */
#define M_IFE         0x3c0003            /* data 3..10, instruction responses 60..124 apart */

# Registers (x0-x15 only)
#   s0 resume point (integer)  s1 traps taken  gp traps expected  tp cases run
#   a0 capability at TRIG  a1 capability at ok_buf  a3 the trap cause expected next (0: none)
#   a2, t2 the DIV's operands and the CHERI ops' results   s1 traps taken
#   t0, t1 scratch (the trap handler uses them)

    .option norvc
    .option norelax

    .set NCASES, 0

# cd := MTDC with its cursor at the constant address \addr. \tmp must differ from \cd.
.macro DCAP_ABS cd, addr, tmp
    cspecialr \cd, SCR_MTDC
    li        \tmp, \addr
    csetaddr  \cd, \cd, \tmp
.endm

# Store \v to the +mem_mode_on_write address; the load and nops after it keep the next case's
# access out of the change-over.
.macro MEM_MODE v
    DCAP_ABS  t0, MEMMODE, t1
    li        t1, \v
    sw        t1, 0(t0)
    lw        t1, 0(a1)
    .rept 8
    nop
    .endr
.endm

# One attempt: \pads nops between Q1 and L, then X = \insn (cov_fcov3_rv_hazard IF_EMPTY, with
# the DIV's operands in a2 / t2 and MEMMODE through a capability in a4). Runs in M_SLOW10 and
# leaves it set for the next attempt.
.macro IF_EMPTY pads, insn:vararg
    .set NCASES, NCASES + 1
    addi      tp, tp, 1
    LA_FAR    s0, .Lres\@, t1
    li        a3, 0
    DCAP_ABS  a4, MEMMODE, t1
    li        t1, M_IFE
    li        a2, 1000
    li        t2, 3
    .balign 8
    nop
    div       a2, a2, t2                    # line offset 4
    sw        t1, 0(a4)                     # Q, line offset 0
    sw        zero, 8(a1)                   # Q1
  .rept \pads
    nop
  .endr
    lw        t0, T_FOFF(a0)                # L
    \insn                                   # X
.Lres\@:
    MEM_MODE  M_SLOW10
.endm

# The two CHERI ops: independent of L (Mem stall), and reading its destination (LdHz).
#define OP_INDEP cincaddrimm t2, a1, 4
#define OP_DEP   cincaddr a2, a1, t0

    DV_VECTORS debug_entry_v, debug_exception_v
_start:
    ENABLE_CHERIOT_VIA_TRIGGER
    j         main
debug_entry_v:
    j         debug_entry
debug_exception_v:
    j         debug_exception

    .text
main:
    SET_VEC   trap_handler, t1, t0
    DCAP_ABS  a0, TRIG, t0
    DCAP_FAR  a1, ok_buf, t0
    cgettag   t0, a1
    beqz      t0, setup_fail
    li        s1, 0
    li        gp, 0
    li        tp, 0
    li        a3, 0

    # ---- {Cheri, IF EmptyAndIdle, ID FullAndStalled, WB FullAndStalled} ----
    MEM_MODE  M_SLOW10
    .irp pads, 0, 2, 4, 6, 8
    IF_EMPTY  \pads, OP_INDEP
    .endr
    .irp pads, 0, 2, 4, 6, 8
    IF_EMPTY  \pads, OP_DEP
    .endr
    MEM_MODE  0

    # ---- Totals ----
    beq       s1, gp, 3f
    li        a0, 40
    j         test_end
3:  li        t0, NCASES
    beq       tp, t0, 5f
    li        a0, 44
    j         test_end
5:  li        a0, 0
    j         test_end

setup_fail:
    li        a0, 1
test_end:
    SIG_INIT
    TEST_END_A0

# ---- Traps (CHERIoT: every trap at MTCC). None is expected: an exception must be the one
# expected (a3), and resumes at s0 through an MTCC-derived MEPCC. Uses t0, t1.
    .balign 4
trap_handler:
    csrr      t0, mcause
    bnez      a3, 2f
    li        a0, 11
    j         test_end
2:  beq       t0, a3, 3f
    li        a0, 10
    j         test_end
3:  addi      s1, s1, 1
    li        a3, 0
    cspecialr t1, SCR_MTCC
    csetaddr  t1, t1, s0
    cspecialw SCR_MEPCC, t1
    mret

# ---- Debug: no entry is expected ----
    .balign 4
debug_entry:
    li        a0, 51
    j         test_end

debug_exception:
    li        a0, 50
    j         test_end

    .data
    .balign 16
ok_buf:
    .fill 4, 4, 0
