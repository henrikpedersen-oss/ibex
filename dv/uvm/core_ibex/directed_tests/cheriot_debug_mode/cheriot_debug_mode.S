# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_debug_mode -- debug mode with cheriot_enable_i asserted
# =============================================================================
# REQ_DBG_01, REQ_DBG_02, REQ_DBG_03, REQ_DBG_04, REQ_DBG_05, REQ_SCR_01 (debug extension).
#
# Debug entry/exit, DEPCC and DScratchC0/1, ebreak with dcsr.ebreakm, single step, the
# debug-mode capability-check bypass, and the re-enabling of every check from the first fetch
# after dret. CHERIoT-Sail does not model debug mode (spec, REQ_DBG_03), so cosim is off and
# the pin is raised by +cheriot_enable_on_write, as for cheriot_enable_transition; the test is
# self-checking. rtl_test core_ibex_cheriot_debug_test sends the first debug request and, in
# phase 2, random debug requests (riscv-dv handshake: IN_DEBUG_MODE + WRITE_CSR dcsr).
#
# Debug ROM: the bench's DEBUG_MODE_HALT_ADDR is BOOT_ADDR (0x80000000) and the debug exception
# address BOOT_ADDR+8, so the two vector words below jump to debug_entry / debug_exception.
# debug_entry saves t0/t1 by swapping them into DScratchC0/1 (cspecialrw), so the interrupted
# capabilities keep their tags, and saves the rest with csc.
#
# Phase 1 (deterministic once the first request has arrived)
#   haltreq entry: dcsr.prv = M (100), DEPCC tagged (101), DEPCC.address = dpc (102),
#     DEPCC.perms = 0x1EB (103), DEPCC.address inside the wait loop (104); sets dcsr.ebreakm.
#     Bypass (REQ_DBG_03), each must complete without a debug exception (95):
#       110/111 sw/lw through an untagged integer pointer
#       112/113 sw/lw 8 bytes beyond the top of an 8-byte capability
#       114     sw through a capability with only LD|GL
#       115     sw through a sealed capability
#       116/117 clc through an untagged integer pointer returns the stored tagged capability
#   Back in normal mode the very same accesses fault (checks in force after dret), mcause 28
#   and mtval = (10 << 5) | capcause (ca0 is the authority), MEPCC = the access:
#       120-124 untagged (0x02)   125-129 bounds (0x01)   130-134 no SD (0x13)
#       135-139 clc untagged (0x02)   140-144 sealed (0x03)          (CHERIoT-Sail ext_data_get_addr)
#   ebreak (dcsr.ebreakm): dcsr.cause = 1 and dpc = the ebreak (150/151); after dret t0, t1,
#     a3, a4 still hold their capabilities (152-155: DScratchC0/1 and csc/clc preserved tags).
#   single step: 4 steps, dcsr.cause = 4, each dpc = the next instruction, the stepped
#     instructions' results right (160-167).
#   single step onto an ebreak (dcsr.ebreakm): ebreak outranks step (Debug Spec, dcsr.cause
#     priorities), so the stepped ebreak enters with dcsr.cause = 1 and dpc = the ebreak; the
#     instruction before it completed one step (156-159), and both stepped-over adds ran (168).
#   dret with an invalid DEPCC -- the first fetch must fault (REQ_DBG_03):
#     untagged          mcause 28, mtval 0x402, MEPCC.address = target, MEPCC untagged (170-174)
#     untagged, stepped the same dret with dcsr.step set (scenario 9): a stepped instruction that
#                       traps re-enters debug mode with the pc already at the trap handler (Debug
#                       Spec, dcsr.step), so one step entry, dcsr.cause = 4, dpc = MTCC.address
#                       (145-147); the handler then runs after dret and records the fault as
#                       above (105-109).
#     out of bounds     mcause 28, mtval 0x401, MEPCC.address = target, MEPCC untagged (175-179)
#                       (CHERIoT-Sail ext_fetch_check_pc / ext_handle_fetch_check_error)
#     sealed (sentry)   mcause 28, mtval[10:5] = 0x20 (PCC), MEPCC.address = target (180-183)
#     without EX        mcause 28, mtval[10:5] = 0x20, MEPCC.address = target       (184-187)
#     For the last two CHERIoT-Sail has no behaviour (it asserts PCC is never sealed or
#     non-executable), so only the parts the spec states -- a CHERI fault on PCC -- are checked.
#   DScratchC0/DScratchC1/DEPCC outside debug mode: illegal instruction (mcause 2) at the access
#     (188-196, REQ_SCR_01).
# Phase 2: CORE_STATUS IN_MACHINE_MODE tells the bench to send random debug requests while the
#   program runs CSC/CLC/CSeal work and checks it; >= 4 haltreq entries required (199).
# Other codes: 1-9 setup, 90-99 handler/bookkeeping (92-94: a DEPCC the handler built was not
#   the intended invalid capability -- a test construction error, not a DUT result).

#include "cheriot_dv.h"

#define G_FLAG       0
#define G_SCEN       4
#define G_LASTCAUSE  8
#define G_EBK_DPC    12
#define G_STEPCNT    16
#define G_HALTS      20
#define G_RESUME     24
#define G_TRAPS      28
#define G_MCAUSE     32
#define G_MTVAL      36
#define G_MEPC_ADDR  40
#define G_MEPC_TAG   44
#define G_STEPLOG    48      /* 4 words */
#define G_SEALROOT   64
#define G_CAPSLOT    72
#define G_CAN0       80
#define G_CAN1       88
#define G_BUF        96      /* 32 bytes */
#define G_BYPWORD    128
#define GLOBALS_SIZE 160

#define DCSR_EBREAKM 0x8000
#define DCSR_STEP    0x4

    .option norvc

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
    # Every symbol address is taken with LA_FAR / DCAP_FAR / SET_VEC (cheriot_dv.h): GNU `la`
    # is AUIPC-based, and AUIPCC shifts by 11, so `la` is wrong whenever %pcrel_hi != 0.
    SET_VEC   trap_handler, t1, t0
    SIG_INIT
    DCAP_FAR  a5, globals, t0
    li        t0, GLOBALS_SIZE
    csetboundsexact a5, a5, t0
    cspecialr t1, SCR_MSCRATCHC
    csc       t1, a5, G_SEALROOT
    # MScratchC := [trap_stack, +512), cursor at the top (INIT_TRAP_STACK with DCAP_FAR).
    DCAP_FAR  t1, trap_stack, t0
    li        t0, 512
    csetboundsexact t1, t1, t0
    cincaddrimm t1, t1, 512
    cspecialw SCR_MSCRATCHC, t1
    csc       a5, a5, G_CAPSLOT          # a tagged capability for the debug-mode clc probe
    li        t0, 0x1800
    csrs      mstatus, t0
    SIG_CSR   0x300
    SIG_CSR   0x304
    SIG_STATUS ST_INITIALIZED

    # ── Phase 1: wait for the bench's debug request ──────────────────────────
    li        s0, 400000
wait_start:
    lw        t0, G_FLAG(a5)
    bnez      t0, wait_done
    addi      s0, s0, -1
    bnez      s0, wait_start
wait_end:
    li        a0, 3                       # no debug request arrived
    j         test_end
wait_done:

# Arm the trap handler (resume at \resume) and clear the trap record. Clobbers t0, t1.
.macro ARM resume
    LA_FAR    t0, \resume, t1
    sw        t0, G_RESUME(a5)
    sw        zero, G_TRAPS(a5)
    li        t0, -1
    sw        t0, G_MCAUSE(a5)
    sw        t0, G_MTVAL(a5)
.endm

# One trap, mcause \cause, mtval \mtval, MEPCC.address = \pc, MEPCC.tag = \tag (or skip the
# tag check with tag = 2). Codes \code .. \code+4. Clobbers t0, t1, t2.
.macro EXPECT_TRAP cause, mtval, pc, tag, code
    lw        t0, G_TRAPS(a5)
    CHECK_EQI t0, 1, \code, t1
    lw        t0, G_MCAUSE(a5)
    CHECK_EQI t0, \cause, \code+1, t1
    lw        t0, G_MTVAL(a5)
    CHECK_EQI t0, \mtval, \code+2, t1
    lw        t0, G_MEPC_ADDR(a5)
    LA_FAR    t1, \pc, t2
    CHECK_EQ  t0, t1, \code+3
.if \tag != 2
    lw        t0, G_MEPC_TAG(a5)
    CHECK_EQI t0, \tag, \code+4, t1
.endif
.endm

    # ── Normal mode: the accesses the debugger made must fault here ──────────
    li        a2, 0x5EED
    ARM       n1r
    LA_FAR    a0, globals+G_BYPWORD, t0   # integer address, no tag
n1: sw        a2, 0(a0)
    li        a0, 120
    j         test_end
n1r: EXPECT_TRAP MCAUSE_CHERI, (10 << 5) | 0x02, n1, 1, 120

    ARM       n2r
    DCAP_FAR  a0, globals, t0
    cincaddrimm a0, a0, G_BUF
    csetboundsimm a0, a0, 8
n2: sw        a2, 16(a0)
    li        a0, 125
    j         test_end
n2r: EXPECT_TRAP MCAUSE_CHERI, (10 << 5) | 0x01, n2, 1, 125

    ARM       n3r
    DCAP_FAR  a0, globals, t0
    cincaddrimm a0, a0, G_BUF
    li        t0, 0x21                     # LD | GL
    candperm  a0, a0, t0
n3: sw        a2, 0(a0)
    li        a0, 130
    j         test_end
n3r: EXPECT_TRAP MCAUSE_CHERI, (10 << 5) | 0x13, n3, 1, 130

    ARM       n4r
    LA_FAR    a0, globals+G_CAPSLOT, t0
n4: clc       a2, a0, 0
    li        a0, 135
    j         test_end
n4r: EXPECT_TRAP MCAUSE_CHERI, (10 << 5) | 0x02, n4, 1, 135

    ARM       n5r
    DCAP_FAR  a0, globals, t0
    cincaddrimm a0, a0, G_BUF
    clc       a1, a5, G_SEALROOT
    li        t0, 9
    csetaddr  a1, a1, t0
    cseal     a0, a0, a1
n5: sw        a2, 0(a0)
    li        a0, 140
    j         test_end
n5r: EXPECT_TRAP MCAUSE_CHERI, (10 << 5) | 0x03, n5, 1, 140

    # ── ebreak into debug mode, capability registers preserved ───────────────
    cmove     t0, a5
    csetboundsimm t0, t0, 16
    auipc     t1, 0
    cmove     a3, s1
    cmove     a4, a5
    csc       t0, a5, G_CAN0
    csc       t1, a5, G_CAN1
    li        a2, 1
    sw        a2, G_SCEN(a5)
ebreak_pt1:
    ebreak
    clc       a0, a5, G_CAN0
    cseqx     a1, a0, t0
    clc       a0, a5, G_CAN1
    cseqx     a2, a0, t1
    CHECK_EQI a1, 1, 152, t2
    CHECK_EQI a2, 1, 153, t2
    cseqx     a1, a3, s1
    CHECK_EQI a1, 1, 154, t2
    cseqx     a1, a4, a5
    CHECK_EQI a1, 1, 155, t2
    lw        t0, G_LASTCAUSE(a5)
    CHECK_EQI t0, 1, 150, t1
    lw        t0, G_EBK_DPC(a5)
    LA_FAR    t1, ebreak_pt1, t2
    CHECK_EQ  t0, t1, 151

    # ── single step ──────────────────────────────────────────────────────────
    li        a2, 2
    sw        a2, G_SCEN(a5)
    sw        zero, G_STEPCNT(a5)
    li        a1, 0
ebreak_pt2:
    ebreak
step_0: addi  a1, x0, 1
step_1: addi  a1, a1, 1
step_2: cincaddrimm a2, a5, 8
step_3: addi  a1, a1, 1
step_4: nop
    lw        t0, G_STEPCNT(a5)
    CHECK_EQI t0, 4, 160, t1
    lw        t0, G_STEPLOG+0(a5)
    LA_FAR    t1, step_1, t2
    CHECK_EQ  t0, t1, 161
    lw        t0, G_STEPLOG+4(a5)
    LA_FAR    t1, step_2, t2
    CHECK_EQ  t0, t1, 162
    lw        t0, G_STEPLOG+8(a5)
    LA_FAR    t1, step_3, t2
    CHECK_EQ  t0, t1, 163
    lw        t0, G_STEPLOG+12(a5)
    LA_FAR    t1, step_4, t2
    CHECK_EQ  t0, t1, 164
    CHECK_EQI a1, 3, 165, t1
    cgetaddr  t0, a2
    LA_FAR    t1, globals+8, t2
    CHECK_EQ  t0, t1, 166
    lw        t0, G_LASTCAUSE(a5)
    CHECK_EQI t0, 4, 167, t1

    # ── single step onto an ebreak ───────────────────────────────────────────
    li        a2, 8
    sw        a2, G_SCEN(a5)
    sw        zero, G_STEPCNT(a5)
    li        a1, 0
ebreak_pt3:
    ebreak                                  # dbg_ebreak sets dcsr.step
step_e0: addi a1, a1, 1                     # one step entry, dpc = step_e1
step_e1: ebreak                             # stepped: cause ebreak, dbg_ebreak clears dcsr.step
step_e2: addi a1, a1, 1
    lw        t0, G_STEPCNT(a5)
    CHECK_EQI t0, 1, 156, t1
    lw        t0, G_STEPLOG+0(a5)
    LA_FAR    t1, step_e1, t2
    CHECK_EQ  t0, t1, 157
    lw        t0, G_LASTCAUSE(a5)
    CHECK_EQI t0, 1, 158, t1
    lw        t0, G_EBK_DPC(a5)
    LA_FAR    t1, step_e1, t2
    CHECK_EQ  t0, t1, 159
    CHECK_EQI a1, 2, 168, t1

    # ── dret with an untagged DEPCC ──────────────────────────────────────────
    ARM       f3r
    li        a2, 3
    sw        a2, G_SCEN(a5)
    ebreak
f3: li        a0, 170                       # must not execute: its fetch faults
    j         test_end
f3r: EXPECT_TRAP MCAUSE_CHERI, 0x402, f3, 0, 170

    # ── dret with an untagged DEPCC, single-stepped ──────────────────────────
    ARM       f9r
    sw        zero, G_STEPCNT(a5)
    li        a2, 9
    sw        a2, G_SCEN(a5)
    ebreak                                  # dbg_ebreak: DEPCC untagged and dcsr.step set
f9: li        a0, 105                       # must not execute: its fetch faults
    j         test_end
f9r: EXPECT_TRAP MCAUSE_CHERI, 0x402, f9, 0, 105
    lw        t0, G_STEPCNT(a5)
    CHECK_EQI t0, 1, 145, t1                # one step entry, with the pc at the trap handler
    lw        t0, G_STEPLOG+0(a5)
    LA_FAR    t1, trap_handler, t2
    CHECK_EQ  t0, t1, 146
    lw        t0, G_LASTCAUSE(a5)
    CHECK_EQI t0, 4, 147, t1

    # ── dret with DEPCC whose bounds exclude dpc ─────────────────────────────
    ARM       f4r
    li        a2, 4
    sw        a2, G_SCEN(a5)
    ebreak
    # DEPCC bounds: [f4_bounds, f4_bounds + 16), so f4 is exactly at the top: out of bounds but
    # representable. A CHERIoT capability's representable window starts at its base
    # ([base, base + 2^(E+9))), so a dpc below the base would decode to another base and
    # CSetAddr would clear the tag (code 92); f4 must sit above the region, not below it.
    # Never executed: dret goes straight to DEPCC.address = f4.
f4_bounds:
    nop
    nop
    nop
    nop
f4: li        a0, 175
    j         test_end
f4r: EXPECT_TRAP MCAUSE_CHERI, 0x401, f4, 0, 175

    # ── dret with a sealed DEPCC ─────────────────────────────────────────────
    ARM       f5r
    li        a2, 5
    sw        a2, G_SCEN(a5)
    ebreak
f5: li        a0, 180
    j         test_end
f5r: lw       t0, G_TRAPS(a5)
    CHECK_EQI t0, 1, 180, t1
    lw        t0, G_MCAUSE(a5)
    CHECK_EQI t0, MCAUSE_CHERI, 181, t1
    lw        t0, G_MTVAL(a5)
    srli      t0, t0, 5
    CHECK_EQI t0, 0x20, 182, t1
    lw        t0, G_MEPC_ADDR(a5)
    LA_FAR    t1, f5, t2
    CHECK_EQ  t0, t1, 183

    # ── dret with a DEPCC without EX ─────────────────────────────────────────
    ARM       f6r
    li        a2, 6
    sw        a2, G_SCEN(a5)
    ebreak
f6: li        a0, 184
    j         test_end
f6r: lw       t0, G_TRAPS(a5)
    CHECK_EQI t0, 1, 184, t1
    lw        t0, G_MCAUSE(a5)
    CHECK_EQI t0, MCAUSE_CHERI, 185, t1
    lw        t0, G_MTVAL(a5)
    srli      t0, t0, 5
    CHECK_EQI t0, 0x20, 186, t1
    lw        t0, G_MEPC_ADDR(a5)
    LA_FAR    t1, f6, t2
    CHECK_EQ  t0, t1, 187

    # ── debug SCRs outside debug mode are illegal ────────────────────────────
    ARM       s7r
s7: cspecialr a2, SCR_DSCRATCHC0
    li        a0, 188
    j         test_end
s7r: lw       t0, G_TRAPS(a5)
    CHECK_EQI t0, 1, 188, t1
    lw        t0, G_MCAUSE(a5)
    CHECK_EQI t0, 2, 189, t1
    lw        t0, G_MEPC_ADDR(a5)
    LA_FAR    t1, s7, t2
    CHECK_EQ  t0, t1, 190
    ARM       s8r
s8: cspecialw SCR_DSCRATCHC1, a5
    li        a0, 191
    j         test_end
s8r: lw       t0, G_TRAPS(a5)
    CHECK_EQI t0, 1, 191, t1
    lw        t0, G_MCAUSE(a5)
    CHECK_EQI t0, 2, 192, t1
    lw        t0, G_MEPC_ADDR(a5)
    LA_FAR    t1, s8, t2
    CHECK_EQ  t0, t1, 193
    ARM       s9r
s9: cspecialr a2, SCR_DEPCC
    li        a0, 194
    j         test_end
s9r: lw       t0, G_TRAPS(a5)
    CHECK_EQI t0, 1, 194, t1
    lw        t0, G_MCAUSE(a5)
    CHECK_EQI t0, 2, 195, t1
    lw        t0, G_MEPC_ADDR(a5)
    LA_FAR    t1, s9, t2
    CHECK_EQ  t0, t1, 196

    # ── Phase 2: random debug requests over CHERI work ───────────────────────
    li        a2, 7
    sw        a2, G_SCEN(a5)
    sw        zero, G_HALTS(a5)
    sw        zero, G_TRAPS(a5)
    SIG_STATUS ST_IN_MACHINE_MODE
    cmove     tp, a5
    csetboundsimm tp, tp, 32
    li        s0, 0
p2_loop:
    cmove     a1, a5
    cincaddrimm a1, a1, G_BUF
    csetboundsimm a1, a1, 16
    clc       a3, a5, G_SEALROOT
    li        t0, 10
    csetaddr  a3, a3, t0
    cseal     a2, a1, a3
    csc       a1, a5, G_BUF
    csc       a2, a5, G_BUF+8
    csc       tp, a5, G_BUF+16
    clc       a0, a5, G_BUF
    cseqx     t0, a0, a1
    CHECK_EQI t0, 1, 197, t1
    clc       a0, a5, G_BUF+8
    cunseal   a0, a0, a3
    cseqx     t0, a0, a1
    CHECK_EQI t0, 1, 198, t1
    clc       a0, a5, G_BUF+16
    cseqx     t0, a0, tp
    CHECK_EQI t0, 1, 197, t1
    lw        t0, G_TRAPS(a5)
    CHECK_EQI t0, 0, 98, t1               # nothing may trap in phase 2
    addi      s0, s0, 1
    lw        t0, G_HALTS(a5)
    li        t1, 4
    bltu      t0, t1, 1f
    li        t1, 32
    bgeu      s0, t1, p2_done
1:  li        t1, 20000
    bltu      s0, t1, p2_loop
    li        a0, 199
    j         test_end
p2_done:
    li        a0, 0
test_end:
    TEST_END_A0

# ---- Trap handler: record, resume at G_RESUME ------------------------------------------------
    .balign 4
trap_handler:
    SAVE_CTX
    DCAP_FAR  a1, globals, t0
    lw        t0, G_TRAPS(a1)
    addi      t0, t0, 1
    sw        t0, G_TRAPS(a1)
    li        t1, 4
    bltu      t0, t1, 1f
    li        a0, 90
    j         test_end
1:  csrr      t0, mcause
    sw        t0, G_MCAUSE(a1)
    csrr      t0, mtval
    sw        t0, G_MTVAL(a1)
    cspecialr a2, SCR_MEPCC
    cgetaddr  t0, a2
    sw        t0, G_MEPC_ADDR(a1)
    cgettag   t0, a2
    sw        t0, G_MEPC_TAG(a1)
    lw        t0, G_RESUME(a1)
    cspecialr a2, SCR_MTCC
    csetaddr  a2, a2, t0
    cspecialw SCR_MEPCC, a2
    RESTORE_CTX
    mret

# ---- Debug handler ----------------------------------------------------------------------------
# Registers: t0/t1 parked in DScratchC0/1; ra, tp, t2, s0, a0-a5 saved with csc in dbg_save;
# s1 (signature capability) and sp are not touched.
    .balign 4
debug_entry:
    cspecialrw t0, SCR_DSCRATCHC0, t0
    cspecialrw t1, SCR_DSCRATCHC1, t1
    LA_FAR    t1, dbg_save, t0
    cspecialr t0, SCR_MTDC
    csetaddr  t0, t0, t1
    csc       ra, t0, 0
    csc       tp, t0, 8
    csc       t2, t0, 16
    csc       s0, t0, 24
    csc       a0, t0, 32
    csc       a1, t0, 40
    csc       a2, t0, 48
    csc       a3, t0, 56
    csc       a4, t0, 64
    csc       a5, t0, 72
    DCAP_FAR  a5, globals, a0
    csrr      a0, dcsr
    srli      a1, a0, 6
    andi      a1, a1, 7
    sw        a1, G_LASTCAUSE(a5)
    li        a2, 3
    beq       a1, a2, dbg_haltreq
    li        a2, 1
    beq       a1, a2, dbg_ebreak
    li        a2, 4
    beq       a1, a2, dbg_step
    li        a0, 91                      # unexpected dcsr.cause
    j         test_end

dbg_haltreq:
    # riscv-dv handshake: IN_DEBUG_MODE, then WRITE_CSR dcsr.
    li        a2, (ST_IN_DEBUG_MODE << 8) | SIG_CORE_STATUS
    sw        a2, 0(s1)
    lw        a2, G_FLAG(a5)
    bnez      a2, dbg_haltreq_p2
    li        a2, (0x7b0 << 8) | SIG_WRITE_CSR
    sw        a2, 0(s1)
    sw        a0, 0(s1)
    andi      a2, a0, 3
    CHECK_EQI a2, 3, 100, a3
    cspecialr a2, SCR_DEPCC
    cgettag   a3, a2
    CHECK_EQI a3, 1, 101, a4
    cgetaddr  a3, a2
    csrr      a4, dpc
    CHECK_EQ  a3, a4, 102
    cgetperm  a4, a2
    CHECK_EQI a4, 0x1EB, 103, a1
    LA_FAR    a4, wait_start, a1
    bltu      a3, a4, 1f
    LA_FAR    a4, wait_end, a1
    bltu      a3, a4, 2f
1:  li        a0, 104
    j         test_end
2:
    # ── bypass probes: none may raise a debug exception ──
    li        a2, 0xC0FFEE
    LA_FAR    a3, globals+G_BYPWORD, a1   # untagged integer pointer
    sw        a2, 0(a3)
    lw        a4, 0(a3)
    CHECK_EQ  a4, a2, 110
    cgettag   a4, a3
    CHECK_EQI a4, 0, 111, a1
    DCAP_FAR  a3, globals, a1
    cincaddrimm a3, a3, G_BUF
    csetboundsimm a3, a3, 8
    sw        a2, 16(a3)                  # 8 bytes past the top
    lw        a4, 16(a3)
    CHECK_EQ  a4, a2, 112
    cgetlen   a4, a3
    CHECK_EQI a4, 8, 113, a1
    DCAP_FAR  a3, globals, a1
    cincaddrimm a3, a3, G_BUF
    li        a1, 0x21
    candperm  a3, a3, a1
    sw        a2, 4(a3)                   # no SD
    lw        a4, G_BUF+4(a5)
    CHECK_EQ  a4, a2, 114
    clc       a1, a5, G_SEALROOT
    li        a4, 9
    csetaddr  a1, a1, a4
    DCAP_FAR  a3, globals, a4
    cincaddrimm a3, a3, G_BUF
    cseal     a3, a3, a1
    li        a2, 0xBADC0DE
    sw        a2, 8(a3)                   # sealed authority
    lw        a4, G_BUF+8(a5)
    CHECK_EQ  a4, a2, 115
    LA_FAR    a3, globals+G_CAPSLOT, a4   # untagged integer pointer
    clc       a2, a3, 0
    cgettag   a4, a2
    CHECK_EQI a4, 1, 116, a1
    clc       a1, a5, G_CAPSLOT
    cseqx     a4, a2, a1
    CHECK_EQI a4, 1, 117, a1
    # From now on ebreak enters debug mode.
    li        a2, DCSR_EBREAKM
    csrs      dcsr, a2
    li        a2, 1
    sw        a2, G_FLAG(a5)
    j         dbg_spin_exit

dbg_haltreq_p2:
    lw        a2, G_HALTS(a5)
    addi      a2, a2, 1
    sw        a2, G_HALTS(a5)
dbg_spin_exit:
    # Outlast the 75-cycle request pulse, so one request is one entry.
    li        a2, 100
3:  addi      a2, a2, -1
    bnez      a2, 3b
    j         dbg_exit

dbg_ebreak:
    csrr      a2, dpc
    sw        a2, G_EBK_DPC(a5)
    cspecialr a2, SCR_DEPCC
    cincaddrimm a2, a2, 4                 # resume after the ebreak
    lw        a3, G_SCEN(a5)
    li        a4, 2
    beq       a3, a4, 3f
    li        a4, 8
    bne       a3, a4, 4f
    csrr      a3, dpc                     # scenario 8: ebreak_pt3 starts the steps, the stepped
    LA_FAR    a4, step_e1, a1             # ebreak at step_e1 ends them
    bne       a3, a4, 3f
    li        a4, DCSR_STEP
    csrc      dcsr, a4
    j         dbg_set_depcc
3:  li        a4, DCSR_STEP               # scenarios 2 and 8: single-step from here
    csrs      dcsr, a4
    j         dbg_set_depcc
4:  li        a4, 3
    bne       a3, a4, 2f
    ccleartag a2, a2                      # scenario 3: untagged
    j         dbg_set_depcc
2:  li        a4, 9
    bne       a3, a4, 5f
    ccleartag a2, a2                      # scenario 9: untagged, and single-stepped
    li        a4, DCSR_STEP
    csrs      dcsr, a4
    j         dbg_set_depcc
5:  li        a4, 4
    bne       a3, a4, 6f
    LA_FAR    a3, f4_bounds, a4           # scenario 4: bounds [f4_bounds, +16) exclude f4
    csetaddr  a2, a2, a3
    csetboundsimm a2, a2, 16
    LA_FAR    a3, f4, a4
    csetaddr  a2, a2, a3
    cgettag   a4, a2
    CHECK_EQI a4, 1, 92, a3               # construction: must still be a valid capability
    j         dbg_set_depcc
6:  li        a4, 5
    bne       a3, a4, 7f
    clc       a3, a5, G_SEALROOT          # scenario 5: seal as a sentry (otype 1)
    li        a4, 1
    csetaddr  a3, a3, a4
    cseal     a2, a2, a3
    cgettype  a4, a2
    CHECK_EQI a4, 1, 93, a3               # construction: sealed as a sentry
    j         dbg_set_depcc
7:  li        a4, 6
    bne       a3, a4, dbg_set_depcc
    li        a4, 0xEFF                   # scenario 6: drop EX
    candperm  a2, a2, a4
    cgetperm  a4, a2
    andi      a4, a4, 0x100
    CHECK_EQI a4, 0, 94, a3               # construction: EX really gone
dbg_set_depcc:
    cspecialw SCR_DEPCC, a2
    j         dbg_exit

dbg_step:
    lw        a2, G_STEPCNT(a5)
    slli      a3, a2, 2
    cincaddr  a3, a5, a3
    csrr      a4, dpc
    sw        a4, G_STEPLOG(a3)
    addi      a2, a2, 1
    sw        a2, G_STEPCNT(a5)
    lw        a3, G_SCEN(a5)
    li        a4, 9
    beq       a3, a4, 8f                  # scenario 9: one step, which ends in the trap handler
    li        a3, 4
    bltu      a2, a3, dbg_exit
8:  li        a3, DCSR_STEP
    csrc      dcsr, a3

dbg_exit:
    LA_FAR    t1, dbg_save, t0
    cspecialr t0, SCR_MTDC
    csetaddr  t0, t0, t1
    clc       ra, t0, 0
    clc       tp, t0, 8
    clc       t2, t0, 16
    clc       s0, t0, 24
    clc       a0, t0, 32
    clc       a1, t0, 40
    clc       a2, t0, 48
    clc       a3, t0, 56
    clc       a4, t0, 64
    clc       a5, t0, 72
    cspecialr t1, SCR_DSCRATCHC1
    cspecialr t0, SCR_DSCRATCHC0
    dret

debug_exception:
    li        a0, 95                      # a debug-mode access faulted
    j         test_end

    .data
    .balign 512
trap_stack:
    .fill 64, 8, 0
    .balign 8
globals:
    .fill GLOBALS_SIZE / 4, 4, 0
    .balign 8
dbg_save:
    .fill 10, 8, 0
