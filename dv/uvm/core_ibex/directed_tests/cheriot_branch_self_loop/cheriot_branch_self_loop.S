# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_branch_self_loop -- a taken branch or CJAL to itself, at PCC.base
# =============================================================================
# REQ_BRA_08 (stimulus for cp_cheri_branch_bound / cheriot_instr_branch_cross and
# cp_cheri_cjal_bound), REQ_INT_01.
#
# With a PCC of length 2 or 3 and the target at PCC.base, the only instruction that can execute
# is the 2-byte one at the base (a fetch needs pc + 2 <= PCC.top, CHERIoT-Sail inCapBounds(PCC,
# pc, 2)), so a taken branch or CJAL to that target is a jump to itself, and only an interrupt
# ends it. These are the cheriot_fetch_bounds cases gen_branch_bounds.py cannot generate:
#   c.beqz a4, . (a4 = 0)  0x022 [B, B+2), 0x032 [B, B+3), B = 0x80100000 in bench memory;
#                          0x0a2 [2^32-2, 2^32); 0x122 [0, 2); 0x132 [0, 3)
#   c.jal .  (CJAL cra)    0x022, 0x032 as above; 0x0c2 [2^32-4, 2^32); 0x122; 0x132
# CJAL 0x0a2 (c.jal at 2^32 - 2 under [2^32-2, 2^32)) is left out: its link address wraps to 0,
# which is not representable against that PCC, and CHERIoT-Sail's CJAL asserts that the link
# always is (cheri_insts.sail), so the model cannot follow it. cheriot_cjal_link_wrap runs it
# with the cosim off.
#
# NEEDS +far_code_windows=1 (CHERIoT-Sail maps [0, 0x1000) and up to 2^32; the instruction is
# written there with sh) and rtl_test core_ibex_cheriot_irq_test with +enable_irq_single_seq
# (one timer, external or software interrupt at a time, with the riscv-dv handshake).
#
# Flow. The trap handler is the test's state machine: it never resumes the loop it interrupted.
# For loop k it writes the instruction at the loop address (sh, then fence.i), builds the PCC
# (CSetBoundsExact on MTCC), puts it in MEPCC with the cursor at the loop, and mrets into it with
# MIE = 1. The agent raises the next interrupt 50..500 cycles after it sees that mret
# (irq_raise_single_seq, core_base_seq delay in [max_delay/10, max_delay], max_delay = 500).
# That is usually, not always, enough for the loop to run: after the mret the prefetch buffer
# drains up to two discarded fetches and the new fetch waits for gnt and rvalid (up to 10 and 20
# cycles each with the default memory agent delays), so the first instruction can take 60-70
# cycles to reach ID, and an interrupt pending by then is taken before the loop ran once, with
# MEPCC at the loop address all the same. The handler therefore counts the iterations (below) and,
# when there were none, enters the same loop again without advancing the loop index; a loop that
# never runs is entered until the test times out. Otherwise it checks the interrupt was taken
# inside the loop and sets up loop k+1. After the last one it mrets with MIE = 0 to the end of
# the test. Loop 0 is entered the same way from _start, right after the setup handshake.
#
# Liveness (that the loop instruction executed): minstret is read into gp just before every mret
# into a loop and into tp as the first instruction of the handler. Between the two reads exactly
# 2 instructions retire besides the loop iterations -- the `csrr gp, minstret` itself (a CSR
# read returns the count before its own retirement) and the mret; counted from the disassembly:
#     csrr gp, minstret / mret ... <trap_handler>: csrr tp, minstret
# and nothing else lies between them. The interrupted instruction retires in neither the RTL
# (ibex_wb_stage perf_instr_ret_wb: only ebreak/ecall/illegal/fetch-error/minstret-write/
# expanded instructions are left out, so mret counts) nor CHERIoT-Sail (riscv_step.sail:
# handle_interrupt returns RETIRE_FAIL). So tp - gp - 2 = the number of loop iterations, and it
# must be >= 1 for the loop to count. The cosim does not compare counter CSR reads (cheriot_sail_
# cosim_dpi.cc skips 0xB00-0xB9F/0xC00-0xC9F), but it does compare the `sub`: the model is
# stepped once per RTL retirement and increments its own minstret on each (retire_instruction),
# so the difference agrees whatever the absolute values are. The CJAL link check below is then a
# value check, not the proof of execution.
#
# Expected values (CHERIoT-Sail): an interrupt sets MEPCC = setCapAddr(PCC, pc) (cheri_sys_
# exceptions.sail handle_trap_extension), so MEPCC is tagged, has the loop PCC's bounds and the
# loop address; mtval = 0; MIE -> MPIE. CJAL with cd = cra writes PCC with address pc + 2, sealed
# as otype_sentry_bie (5) when MIE = 1 (cheri_insts.sail CJAL); cra is NULL before each loop, so
# with >= 1 iterations the link must be tagged, and with 0 it must still be NULL.
#
# Failure codes (a0, plus 256 x the loop index for the codes from 10 on):
#    1  setup: MTCC precondition       2  debug entry (never requested)
#   10  synchronous exception          11 mcause not 0x80000003/7/B     12 mtval != 0
#   13  mstatus.MIE != 0 in handler    14 MPIE != 1                     15 MPP != M
#   16  MEPCC untagged                 17 MEPCC.address != loop          18 MEPCC.base != base
#   19  MEPCC.length != length         20 CJAL link untagged (>= 1 iterations)
#   21  link address != pc+2           22 link otype != 5
#   23  minstret advanced by < 2 between the reads (the csrr or the mret did not retire)
#   24  CJAL link tagged after 0 iterations (a CJAL ran that minstret did not count)
#   25  loop PCC untagged after CSetBoundsExact (not exact)   26  ... after moving the cursor
#   30  liveness: the end was reached after != N_LOOPS loops
#   A loop that never runs has no code: the handler re-enters it until the test timeout.
#
# Register use: s0 = loop index, s1 = signature capability, a4 = 0 (the branch condition), a2/a3/
# a5 = the current loop's address, base and length (read by the handler), cra = CJAL link,
# gp/tp = minstret before the mret / at handler entry (link.ld defines no __global_pointer$, so
# nothing is gp-relaxed). No x16-x31; every CHERI instruction comes from cheriot_dv.h.

#include "cheriot_dv.h"

#define N_LOOPS   10
#define MIE_MASK  0x888        /* MEIE | MTIE | MSIE */

# ---- Loop k: instruction, PCC, MEPCC ---------------------------------------------------------
# From loop_table[s0]: a2 = loop address, a3 = PCC base, a5 = PCC length, and the instruction's
# offset in the templates. Writes the instruction at a2, MEPCC := MTCC with bounds [a3, a3 + a5)
# and cursor a2, cra := NULL. Clobbers a0, a1, t0, t1.
.macro PREP_LOOP
    DCAP_FAR  a1, loop_table, t0
    slli      t1, s0, 4              # 16 bytes per loop_table entry
    cincaddr  a1, a1, t1
    lw        a2, 0(a1)
    lw        a3, 4(a1)
    lw        a5, 8(a1)
    lw        t1, 12(a1)
    DCAP_FAR  a0, loop_templates, t0
    cincaddr  a0, a0, t1
    lhu       t1, 0(a0)
    cspecialr a1, SCR_MTDC
    csetaddr  a1, a1, a2
    sh        t1, 0(a1)
    fence.i
    cspecialr a1, SCR_MTCC
    csetaddr  a1, a1, a3
    csetboundsexact a1, a1, a5
    cgettag   t1, a1
    CHECK_EQI t1, 1, 25, t0
    csetaddr  a1, a1, a2
    cgettag   t1, a1
    CHECK_EQI t1, 1, 26, t0
    cspecialw SCR_MEPCC, a1
    cmove     ra, zero
.endm

    .option norvc

    DV_VECTORS unexpected_debug, unexpected_debug
_start:
    SET_VEC   trap_handler, t1, t0
    SIG_INIT
    cspecialr t1, SCR_MTCC
    cgettag   t0, t1
    li        s0, 0
    CHECK_EQI t0, 1, 1, t2
    # mstatus.MPP := M (CHERIoT is M-mode only), MPIE := 1 so that mret enables interrupts;
    # mie := MEIE|MTIE|MSIE. MIE stays 0 until the first loop.
    li        t0, 0x1880
    csrs      mstatus, t0
    li        t0, MIE_MASK
    csrw      mie, t0
    li        a4, 0
    PREP_LOOP
    # Core setup handshake (core_ibex_debug_intr_basic_test::wait_for_core_setup): the agent
    # starts its first interrupt after this, and the mret right behind it enters loop 0.
    SIG_CSR   0x300                  # mstatus
    SIG_CSR   0x304                  # mie
    SIG_STATUS ST_INITIALIZED
    csrr      gp, minstret           # liveness: the count before the mret (see the header)
    mret

all_done:
    li        t0, N_LOOPS
    li        a0, 30
    bne       s0, t0, test_end
    li        a0, 0
test_end:
    beqz      a0, 1f
    slli      t1, s0, 8              # failure: add 256 x the loop index
    add       a0, a0, t1
1:  TEST_END_A0

unexpected_debug:
    li        a0, 2
    j         test_end

# ---- Trap handler (MTCC) ----------------------------------------------------------------------
    .balign 4
trap_handler:
    csrr      tp, minstret            # first: nothing but `csrr gp, minstret` and the mret
                                      # retired between this read and the one before the mret
    csrr      t0, mcause
    bltz      t0, 1f
    li        a0, 10                  # synchronous exception: nothing here should trap
    j         test_end
1:
    SIG_STATUS ST_HANDLING_IRQ
    SIG_CSR   0x300                   # mstatus
    SIG_CSR   0x342                   # mcause
    SIG_CSR   0x304                   # mie
    csrr      t1, mcause
    li        t2, 0x80000003
    beq       t1, t2, 2f
    li        t2, 0x80000007
    beq       t1, t2, 2f
    li        t2, 0x8000000B
    beq       t1, t2, 2f
    li        a0, 11
    j         test_end
2:  csrr      t1, mtval
    CHECK_EQI t1, 0, 12, t2
    csrr      t1, mstatus
    andi      t2, t1, 8
    CHECK_EQI t2, 0, 13, t0
    andi      t2, t1, 0x80
    CHECK_EQI t2, 0x80, 14, t0
    li        t0, 0x1800
    and       t2, t1, t0
    CHECK_EQ  t2, t0, 15
    # The interrupt was taken in the loop: MEPCC = the loop PCC with the loop address.
    cspecialr a1, SCR_MEPCC
    cgettag   t1, a1
    CHECK_EQI t1, 1, 16, t2
    cgetaddr  t1, a1
    CHECK_EQ  t1, a2, 17
    cgetbase  t1, a1
    CHECK_EQ  t1, a3, 18
    cgetlen   t1, a1
    CHECK_EQ  t1, a5, 19
    # Loop iterations = minstret delta - 2 (the `csrr gp, minstret` and the mret, counted from
    # the disassembly; the interrupted instruction does not retire). The cosim compares the sub.
    sub       tp, tp, gp
    li        t0, 2
    bgeu      tp, t0, 7f
    li        a0, 23
    j         test_end
7:  addi      tp, tp, -2              # tp = iterations
    # CJAL loops (the second half of loop_table): the link is NULL before the loop, so after
    # >= 1 iterations it is the sealed sentry to pc + 2, and after 0 it is still NULL.
    li        t0, N_LOOPS / 2
    bltu      s0, t0, 3f
    cgettag   t1, ra
    bnez      tp, 8f
    CHECK_EQI t1, 0, 24, t2
    j         3f
8:  CHECK_EQI t1, 1, 20, t2
    cgetaddr  t1, ra
    addi      t2, a2, 2
    CHECK_EQ  t1, t2, 21
    cgettype  t1, ra
    CHECK_EQI t1, 5, 22, t2           # otype_sentry_bie: MIE was 1
3:  beqz      tp, 10f                 # the loop never ran: enter the same loop again
    addi      s0, s0, 1
    li        t0, N_LOOPS
    bgeu      s0, t0, 4f
10: PREP_LOOP
    j         5f
4:  li        t0, 0x80                # last loop done: mret with MIE = 0 to all_done
    csrc      mstatus, t0
    LA_FAR    t1, all_done, t0
    cspecialr a1, SCR_MTCC
    csetaddr  a1, a1, t1
    cspecialw SCR_MEPCC, a1
5:  SIG_STATUS ST_FINISHED_IRQ
    # The interrupt is level-sensitive: give the testbench time to drop the line it raised
    # (core_ibex_debug_intr_basic_test::send_irq_stimulus_end) before mret re-enables MIE.
    li        t1, 64
6:  addi      t1, t1, -1
    bnez      t1, 6b
    csrr      gp, minstret            # liveness: the count before the mret (see the header)
    mret

# The self-loop instructions, copied to each loop's address (both are pc-relative with offset 0).
    .balign 4
    .option push
    .option rvc
loop_templates:
1:  c.beqz    a4, 1b                  # +0: taken branch to itself (a4 = 0)
2:  c.jal     2b                      # +2: CJAL cra to itself
    .option pop

# ---- Data ---------------------------------------------------------------------------------

    .data
    .balign 4
# {loop address, PCC base, PCC length, template offset}; branch loops first, then CJAL loops
# (the handler checks the link for s0 >= N_LOOPS / 2).
loop_table:
    .word 0x80100000, 0x80100000, 2, 0    # c.beqz 0x022
    .word 0x80100000, 0x80100000, 3, 0    # c.beqz 0x032
    .word 0xFFFFFFFE, 0xFFFFFFFE, 2, 0    # c.beqz 0x0a2
    .word 0x00000000, 0x00000000, 2, 0    # c.beqz 0x122
    .word 0x00000000, 0x00000000, 3, 0    # c.beqz 0x132
    .word 0x80100000, 0x80100000, 2, 2    # CJAL   0x022
    .word 0x80100000, 0x80100000, 3, 2    # CJAL   0x032
    .word 0xFFFFFFFC, 0xFFFFFFFC, 4, 2    # CJAL   0x0c2
    .word 0x00000000, 0x00000000, 2, 2    # CJAL   0x122
    .word 0x00000000, 0x00000000, 3, 2    # CJAL   0x132
