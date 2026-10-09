# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_cjal_link_wrap -- CJAL at 2^32 - 2, where the link address wraps to 0
# =============================================================================
# REQ_BRA_08 (stimulus for cp_cheri_cjal_bound 0x0c1 and 0x0a2), REQ_CFI_02.
#
# A c.jal (CJAL cra) at 0xFFFFFFFE under PCC [0xFFFFFFFE, 2^32) links to pc + 2, which wraps to 0.
# Address 0 is outside that PCC's representable window, and CHERIoT-Sail's CJAL asserts that the
# link is always representable (cheri_insts.sail), so the model cannot follow either case:
# cheriot_fetch_bounds and cheriot_branch_self_loop leave them out, and this test runs with the
# cosim off (+disable_cosim=1) and checks the obligation the architecture leaves: no capability
# may gain authority. The link's address must be 0, and it must be untagged or, if tagged, carry
# exactly the PCC's bounds [0xFFFFFFFE, 2^32) and be a backward sentry. (The RTL clears the tag:
# cheriot_set_address takes 0 - 0xFFFFFFFE in 33 bits, high_delta != 0.)
#
#   phase 1, 0x0c1: c.jal -2 at 0xFFFFFFFE. The target 0xFFFFFFFC is below PCC.base: the CJAL
#            retires and the fetch of the target faults (mcause 28, mtval 0x401, MEPCC.address =
#            0xFFFFFFFC, MEPCC.tag = 0). MIE = 0, so a tagged link would be otype 4.
#   phase 2, 0x0a2: c.jal 0 at 0xFFFFFFFE, a jump to itself; only an interrupt ends it. Entered
#            by mret with MIE = 1 as in cheriot_branch_self_loop (same agent handshake and the
#            same minstret liveness count, see that test's header); a tagged link would be otype 5.
#
# Before each CJAL, cra holds MTDC with address 0x1234 (tagged, base 0): a CJAL that did not
# write its link leaves that, which fails the address check (and the bounds check, being tagged).
#
# NEEDS rtl_test core_ibex_cheriot_irq_test with +enable_irq_single_seq (phase 2), and both
# +disable_cosim=1 (Spike) and +disable_cheriot_sail=1 (the CHERIoT-Sail oracle). The bench
# memory answers every address, so the instruction is written at 0xFFFFFFFE with sh.
#
# Failure codes (a0):
#    1  setup: MTCC untagged             2  debug entry (never requested)
#    3  phase 1: the CJALR into the region fell through
#   10  PCC untagged after CSetBoundsExact (not exact)
#   11  ... after moving the cursor
#   20  phase 1: mcause != 28            21 mtval != 0x401
#   22  MEPCC.address != 0xFFFFFFFC      23 MEPCC tagged
#   24  phase 1 link address != 0        25 link tagged with base != 0xFFFFFFFE
#   26  link tagged with length != 2     27 link tagged with otype != 4
#   30  phase 2: synchronous exception   31 mcause not 0x80000003/7/B
#   32  mtval != 0                       33 MEPCC untagged
#   34  MEPCC.address != 0xFFFFFFFE      35 MEPCC.base != 0xFFFFFFFE
#   36  MEPCC.length != 2                37 minstret advanced by < 2 between the reads
#   38  link changed after 0 iterations (a CJAL ran that minstret did not count)
#   44  phase 2 link address != 0        45 link tagged with base != 0xFFFFFFFE
#   46  link tagged with length != 2     47 link tagged with otype != 5
#   A phase 2 loop that never runs is re-entered until the test times out.
#
# Register use: s0 = phase, s1 = signature capability, cra = the link, gp/tp = minstret before the
# mret / at handler entry. No x16-x31; every CHERI instruction comes from cheriot_dv.h.

#include "cheriot_dv.h"

#define LOOP_ADDR  0xFFFFFFFE
#define MIE_MASK   0x888        /* MEIE | MTIE | MSIE */

# Write the 2-byte template at offset \off at LOOP_ADDR. Clobbers a0, a1, t0, t1, t2.
.macro WRITE_INSN off
    DCAP_FAR  a0, templates, t0
    lhu       t1, \off(a0)
    cspecialr a1, SCR_MTDC
    li        t2, LOOP_ADDR
    csetaddr  a1, a1, t2
    sh        t1, 0(a1)
    fence.i
.endm

# a1 := MTCC with bounds [LOOP_ADDR, 2^32) and cursor LOOP_ADDR. Clobbers t0, t1.
.macro BUILD_PCC
    cspecialr a1, SCR_MTCC
    li        t0, LOOP_ADDR
    csetaddr  a1, a1, t0
    li        t1, 2
    csetboundsexact a1, a1, t1
    cgettag   t1, a1
    CHECK_EQI t1, 1, 10, t0
    li        t0, LOOP_ADDR
    csetaddr  a1, a1, t0
    cgettag   t1, a1
    CHECK_EQI t1, 1, 11, t0
.endm

# cra := MTDC with address 0x1234: tagged and recognisable, so an unwritten link is caught.
.macro PRESET_LINK
    cspecialr ra, SCR_MTDC
    li        t0, 0x1234
    csetaddr  ra, ra, t0
.endm

# The link in cra: address 0; untagged, or tagged with the PCC's bounds and otype \otype.
# Codes \code .. \code+3. Clobbers t1, t2.
.macro CHECK_LINK otype, code
    cgetaddr  t1, ra
    CHECK_EQI t1, 0, \code, t2
    cgettag   t1, ra
    beqz      t1, 9f
    cgetbase  t1, ra
    CHECK_EQI t1, LOOP_ADDR, (\code + 1), t2
    cgetlen   t1, ra
    CHECK_EQI t1, 2, (\code + 2), t2
    cgettype  t1, ra
    CHECK_EQI t1, \otype, (\code + 3), t2
9:
.endm

    .option norvc

    DV_VECTORS unexpected_debug, unexpected_debug
_start:
    SIG_INIT
    cspecialr t1, SCR_MTCC
    cgettag   t0, t1
    CHECK_EQI t0, 1, 1, t2

    # ── Phase 1 (0x0c1): c.jal -2 at 2^32 - 2, the target faults ─────────────
    li        s0, 1
    SET_VEC   fault_handler, t1, t0
    WRITE_INSN 0
    BUILD_PCC
    PRESET_LINK
    jalr      zero, 0(a1)             # CJALR into the region, no link
    li        a0, 3
    j         test_end

    .balign 4
fault_handler:
    csrr      t1, mcause
    CHECK_EQI t1, 28, 20, t2
    csrr      t1, mtval
    CHECK_EQI t1, 0x401, 21, t2
    cspecialr a1, SCR_MEPCC
    cgetaddr  t1, a1
    CHECK_EQI t1, 0xFFFFFFFC, 22, t2
    cgettag   t1, a1
    CHECK_EQI t1, 0, 23, t2
    CHECK_LINK 4, 24

    # ── Phase 2 (0x0a2): c.jal 0 at 2^32 - 2, ended by an interrupt ──────────
    li        s0, 2
    SET_VEC   irq_handler, t1, t0
    # mstatus.MPP := M, MPIE := 1 so that mret enables interrupts; mie := MEIE|MTIE|MSIE.
    li        t0, 0x1880
    csrs      mstatus, t0
    li        t0, MIE_MASK
    csrw      mie, t0
    WRITE_INSN 2
    BUILD_PCC
    cspecialw SCR_MEPCC, a1
    PRESET_LINK
    # Core setup handshake: the agent starts its first interrupt after this.
    SIG_CSR   0x300                   # mstatus
    SIG_CSR   0x304                   # mie
    SIG_STATUS ST_INITIALIZED
    csrr      gp, minstret            # liveness: the count before the mret
    mret

all_done:
    li        a0, 0
test_end:
    TEST_END_A0

unexpected_debug:
    li        a0, 2
    j         test_end

    .balign 4
irq_handler:
    csrr      tp, minstret            # first: only `csrr gp` and the mret retired since gp
    csrr      t0, mcause
    bltz      t0, 1f
    li        a0, 30
    j         test_end
1:  SIG_STATUS ST_HANDLING_IRQ
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
    li        a0, 31
    j         test_end
2:  csrr      t1, mtval
    CHECK_EQI t1, 0, 32, t2
    cspecialr a1, SCR_MEPCC
    cgettag   t1, a1
    CHECK_EQI t1, 1, 33, t2
    cgetaddr  t1, a1
    CHECK_EQI t1, LOOP_ADDR, 34, t2
    cgetbase  t1, a1
    CHECK_EQI t1, LOOP_ADDR, 35, t2
    cgetlen   t1, a1
    CHECK_EQI t1, 2, 36, t2
    # Iterations = minstret delta - 2 (the `csrr gp, minstret` and the mret).
    sub       tp, tp, gp
    li        t0, 2
    bgeu      tp, t0, 3f
    li        a0, 37
    j         test_end
3:  addi      tp, tp, -2
    bnez      tp, 4f
    # The loop never ran: the link must still be the preset, then enter the loop again.
    cgetaddr  t1, ra
    CHECK_EQI t1, 0x1234, 38, t2
    BUILD_PCC
    cspecialw SCR_MEPCC, a1
    j         5f
4:  CHECK_LINK 5, 44
    li        t0, 0x80                # done: mret with MIE = 0 to all_done
    csrc      mstatus, t0
    LA_FAR    t1, all_done, t0
    cspecialr a1, SCR_MTCC
    csetaddr  a1, a1, t1
    cspecialw SCR_MEPCC, a1
5:  SIG_STATUS ST_FINISHED_IRQ
    # The interrupt is level-sensitive: give the testbench time to drop the line it raised
    # before mret re-enables MIE.
    li        t1, 64
6:  addi      t1, t1, -1
    bnez      t1, 6b
    csrr      gp, minstret            # liveness: the count before the mret
    mret

# The CJAL instructions, copied to LOOP_ADDR (pc-relative, so position-independent).
    .balign 4
    .option push
    .option rvc
templates:
1:  c.jal     1b - 2                  # +0: CJAL cra 2 bytes back (0x0c1)
2:  c.jal     2b                      # +2: CJAL cra to itself (0x0a2)
    .option pop
