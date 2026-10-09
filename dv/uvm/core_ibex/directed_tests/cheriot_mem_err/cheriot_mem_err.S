# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_mem_err -- bus errors and memory integrity errors in CHERIoT mode
# =============================================================================
# Targets the LSU error paths with cheriot_enable_i asserted, which no other test reaches:
# the misaligned split states with an error on either half, both beats of CLC/CSC
# (CTX_WAIT_GNT1/GNT2/RESP, cap_lsw_err_q) with a bus error, load-integrity errors on a word
# load and on each beat of a CLC (internal NMI, g_mem_ecc_asserts.MajorAlertOnDMemIntegrityErr),
# and fetch bus/integrity errors (MajorAlertOnIMemIntegrityErr).
#
# Errors are injected by address, not by timing: the testlist gives the memory agents fixed
# windows (ibex_mem_intf_response_seq: +dside_bus_err_lo/hi, +dside_intg_err_lo/hi,
# +iside_bus_err_lo/hi, +iside_intg_err_lo/hi), and the program decides which access touches
# them. The windows sit at fixed addresses in .text.init (.org below) so the testlist can name
# them:
#   dside bus error   [0x80000814, 0x8000081B]  words W1 = base+0x14, W2 = base+0x18
#   dside integrity   [0x8000082C, 0x80000833]  words W3 = base+0x2C, W4 = base+0x30 (reads)
#   iside bus error   [0x80000C00, 0x80000C03]  first word of ifetch_bus_poison
#   iside integrity   [0x80000D00, 0x80000D03]  first word of ifetch_intg_poison
#
# Cosim off (+disable_cosim=1, pin raised by +cheriot_enable_on_write): CHERIoT-Sail's memory
# never errors and it has no NMI, so it cannot follow any of these events, and no plusarg turns
# only that oracle off (same arrangement as cheriot_enable_transition). The test is
# self-checking; rtl_test core_ibex_cheriot_mem_err_test additionally requires a bus alert for
# every integrity error and no other alert.
#
# Expected values. CHERIoT-Sail has no bus errors, so these come from the RISC-V privileged
# spec (an access fault reports the faulting address in mtval; for a misaligned access, the
# address of the portion that faulted), ibex's documentation (doc/03_reference/
# exception_interrupts.rst: load integrity error = internal NMI, mcause 0xFFFFFFE0, mtval =
# faulting address, taken at most one instruction after the load) and the verification spec
# (REQ_IBX_INT_05, REQ_EXC_05: the faulting instruction is not retired, MEPCC.address = its pc):
#   probe                         mcause      mtval                    codes
#   lw   W1                       5           W1                       10-14
#   lw   W1-2 (2nd half faults)   5           W1 (word of the 2nd half) 15-19
#   lw   W2+2 (1st half faults)   5           W2+2                     20-24
#   sw   W1                       7           W1                       25-29
#   sw   W1-2 (2nd half)          7           W1                       30-34
#   sh   W1-1 (2nd half)          7           W1                       35-39
#   clc  W1-4 (2nd beat faults)   5           W1-4 or W1 (*)           40-45
#   clc  W2   (1st beat faults)   5           W2                       46-51
#   csc  W1-4 (2nd beat)          7           W1-4 or W1 (*)           52-56
#   csc  W2   (1st beat)          7           W2                       57-61
#   lw   W4 (bad integrity)       0xFFFFFFE0  W4, MEPCC in {pc+4,pc+8}, rd not written  62-67
#   clc  W3-4 (2nd beat bad intg) 0xFFFFFFE0  W3-4 or W3 (*), cd not written            68-73
#   fetch ifetch_bus_poison       1           its address, MEPCC.address = it          74-78
#   fetch ifetch_intg_poison      1           its address                              79-83
#   clc  W4 (1st beat bad intg)   0xFFFFFFE0  W4; cd not written -- see (**)            84-89
#   lw   W1+2 (both halves fault) 5           W1+2 or W2 (***)         100-105
#   lw   W1; cincaddrimm          5           W1; the CHERI op after the faulting load does
#                                             not execute (precise exception)    106-112
#   lw   W1; beq                  5           W1                       113-117
#   lw   W4 (bad intg); CHERI ops 0xFFFFFFE0  W4, MEPCC in {pc+4,pc+8}, rd not written,
#                                             exactly the ops before MEPCC executed   118-125
#     first op cincaddr reading the load's rd (load-hazard stall)
#   lw   W4 (bad intg); CHERI ops 0xFFFFFFE0  as above, every op independent of the load 126-133
#   lw   W1; cincaddr reading rd  5           W1; the CHERI op, held in ID by the load hazard
#                                             on rd, does not execute                 134-140
# The two CLC integrity probes also check MEPCC in {pc+4,pc+8} (codes 72, 88); a later MEPC
# inside the 8-nop sled is reported only at the end, so code 89 still runs (see NMI_MEPC). The
# two later word-load integrity probes do the same (codes 122, 130) inside a sled of CHERI ops.
# Probes 100-140 run before the lw W4 probe (62-67), whose late NMI ends the test at once.
# The two bus-error probes with a CHERI op in ID (106-112 independent, 134-140 reading rd) are
# the exception_stall_instr_cross Cheri bins: the op is unstalled or never stalled (None) when
# the error response arrives, or load-hazard stalled (LdHz); which of None u0/u1 is seen depends
# on the memory agent's response delay. Cheri with a Mem stall is impossible there (the stall
# drops in the response cycle, fcov mem_stall_illegal).
# Each faulting probe also checks: exactly one trap (code base+0 = none, see the table),
# MEPCC tag = 1, and the destination register unchanged (rd/cd untouched by a faulted load).
#
# (*) For a capability access the privileged spec allows either the access address or the
#     address of the word that faulted; neither CHERIoT-Sail nor the spec pins it down, so both
#     are accepted and nothing else is.
# (**) A word load with bad integrity does not write rd (lsu_rdata_valid_o is gated by
#     data_intg_err). For CLC that gate sees only the second beat's response, so a bad first
#     beat may still deliver a tagged capability. This probe requires the conservative
#     behaviour -- a load whose data failed its integrity check writes no capability -- which is
#     an extension of the word-load rule, not a statement of CHERIoT-Sail or the spec. It runs
#     last so every other result is in before it; code 89 is the open question, not a
#     testbench error.
# (***) Both portions of the access fault; the privileged spec reports the address of the portion
#     that faulted, so the address of either portion is accepted and nothing else is.
#
# Codes 1-9 setup, 90-99 handler/bookkeeping.

#include "cheriot_dv.h"

#define G_RESUME     0
#define G_TRAPS      4
#define G_MCAUSE     8
#define G_MTVAL      12
#define G_MEPC_ADDR  16
#define G_MEPC_TAG   20
#define G_CAP        24      /* 8-byte aligned capability slot */
#define G_LATE_NMI   32      /* first late-NMI code (72 or 88), reported once every probe has run */
#define GLOBALS_SIZE 64

#define W1  0x14
#define W2  0x18
#define W3  0x2C
#define W4  0x30
#define POISON_BASE 0x80000800

    .option norvc

    DV_VECTORS unexpected_debug, unexpected_debug
_start:
    ENABLE_CHERIOT_VIA_TRIGGER
    j         main

    # Data block with the dside windows. Initialised (part of the image), so no read of it is
    # an uninitialised access.
    .org 0x800
dpoison:
    .fill 16, 4, 0x5a5a5a5a

    # Fetch windows. Nothing falls through into them: they are only ever jumped to.
    .org 0xC00
ifetch_bus_poison:
    li        a0, 76            # executed: the fetch did not fault
    j         test_end
    .org 0xD00
ifetch_intg_poison:
    li        a0, 81
    j         test_end

    .text
main:
    # Every symbol address is taken with LA_FAR / DCAP_FAR / SET_VEC (cheriot_dv.h): GNU `la`
    # is AUIPC-based, and AUIPCC shifts by 11, so `la` is wrong whenever %pcrel_hi != 0.
    SET_VEC   trap_handler, t1, t0
    SIG_INIT
    # MScratchC := [trap_stack, +512), cursor at the top (INIT_TRAP_STACK with DCAP_FAR).
    DCAP_FAR  t1, trap_stack, t0
    li        t0, 512
    csetboundsexact t1, t1, t0
    cincaddrimm t1, t1, 512
    cspecialw SCR_MSCRATCHC, t1
    DCAP_FAR  a5, globals, t0
    li        t0, GLOBALS_SIZE
    csetboundsexact a5, a5, t0
    # a4 := capability over the 64-byte dpoison block.
    DCAP_FAR  a4, dpoison, t0
    li        t0, 64
    csetboundsexact a4, a4, t0
    cgettag   t0, a4
    CHECK_EQI t0, 1, 1, t1
    LA_FAR    t0, dpoison, t1
    li        t1, POISON_BASE
    CHECK_EQ  t0, t1, 2               # the testlist windows assume this address
    li        t0, 0x1800
    csrs      mstatus, t0
    # Tagged capabilities in the two integrity-window slots (stores are not poisoned).
    csc       a5, a4, W3-4
    csc       a5, a4, W4
    SIG_CSR   0x300
    SIG_CSR   0x304
    SIG_STATUS ST_INITIALIZED

# Arm the handler: resume at \resume, clear the trap record. Clobbers t0, t1.
.macro ARM resume
    LA_FAR    t0, \resume, t1
    sw        t0, G_RESUME(a5)
    sw        zero, G_TRAPS(a5)
    li        t0, -1
    sw        t0, G_MCAUSE(a5)
    sw        t0, G_MTVAL(a5)
.endm

# One trap with mcause \cause, mtval \mtval (an address expression), MEPCC = (\pc, tag 1).
# Codes \code+0 .. \code+4. Clobbers t0, t1, a1.
.macro EXPECT_SYNC cause, mtval_reg, pc, code
    lw        t0, G_TRAPS(a5)
    CHECK_EQI t0, 1, \code, t1
    lw        t0, G_MCAUSE(a5)
    CHECK_EQI t0, \cause, \code+1, t1
    lw        t0, G_MTVAL(a5)
    CHECK_EQ  t0, \mtval_reg, \code+2
    lw        t0, G_MEPC_ADDR(a5)
    LA_FAR    t1, \pc, a1
    CHECK_EQ  t0, t1, \code+3
    lw        t0, G_MEPC_TAG(a5)
    CHECK_EQI t0, 1, \code+4, t1
.endm

# MEPC after a load-integrity NMI. Ibex takes it "at most one instruction after the faulting
# load" (doc/03_reference/exception_interrupts.rst:87): MEPC is \pc+4 or \pc+8. A later MEPC
# that is still inside the probe's nop sled (up to \pc_late) breaks that bound but leaves every
# other check meaningful, so it is recorded in G_LATE_NMI and reported at the end, after the
# remaining probes (code 89 in particular) have run. Outside the sled: fail with \code at once.
# Clobbers t0, t1, a1.
.macro NMI_MEPC pc, code
    lw        t0, G_MEPC_ADDR(a5)
    LA_FAR    t1, \pc+4, a1
    beq       t0, t1, 3f
    LA_FAR    t1, \pc+8, a1
    beq       t0, t1, 3f
    LA_FAR    t1, \pc+4, a1
    bltu      t0, t1, 2f
    LA_FAR    t1, \pc\()_late, a1
    bgtu      t0, t1, 2f
    lw        t1, G_LATE_NMI(a5)
    bnez      t1, 3f                  # keep the first
    li        t1, \code
    sw        t1, G_LATE_NMI(a5)
    j         3f
2:  li        a0, \code
    j         test_end
3:
.endm

# a0 must still hold the integer canary 0x1234 (an untagged value).
.macro RD_UNTOUCHED code
    li        t1, 0x1234
    CHECK_EQ  a0, t1, \code
.endm
# a0 must still be the capability canary copied in a3.
.macro CD_UNTOUCHED code
    cseqx     t0, a0, a3
    CHECK_EQI t0, 1, \code, t1
.endm

    # ── lw W1 ────────────────────────────────────────────────────────────────
    ARM       r1
    li        a0, 0x1234
p1: lw        a0, W1(a4)
    li        a0, 10
    j         test_end
r1: li        t2, POISON_BASE+W1
    EXPECT_SYNC MCAUSE_LOAD_ACC, t2, p1, 10
    RD_UNTOUCHED 14

    # ── lw W1-2: second half faults ──────────────────────────────────────────
    ARM       r2
    li        a0, 0x1234
p2: lw        a0, W1-2(a4)
    li        a0, 15
    j         test_end
r2: li        t2, POISON_BASE+W1
    EXPECT_SYNC MCAUSE_LOAD_ACC, t2, p2, 15
    RD_UNTOUCHED 19

    # ── lw W2+2: first half faults ───────────────────────────────────────────
    ARM       r3
    li        a0, 0x1234
p3: lw        a0, W2+2(a4)
    li        a0, 20
    j         test_end
r3: li        t2, POISON_BASE+W2+2
    EXPECT_SYNC MCAUSE_LOAD_ACC, t2, p3, 20
    RD_UNTOUCHED 24

    # ── sw W1 ────────────────────────────────────────────────────────────────
    ARM       r4
p4: sw        zero, W1(a4)
    li        a0, 25
    j         test_end
r4: li        t2, POISON_BASE+W1
    EXPECT_SYNC MCAUSE_STORE_ACC, t2, p4, 25

    # ── sw W1-2: second half faults ──────────────────────────────────────────
    ARM       r5
p5: sw        zero, W1-2(a4)
    li        a0, 30
    j         test_end
r5: li        t2, POISON_BASE+W1
    EXPECT_SYNC MCAUSE_STORE_ACC, t2, p5, 30

    # ── sh W1-1: second half faults ──────────────────────────────────────────
    ARM       r6
p6: sh        zero, W1-1(a4)
    li        a0, 35
    j         test_end
r6: li        t2, POISON_BASE+W1
    EXPECT_SYNC MCAUSE_STORE_ACC, t2, p6, 35

    # ── clc W1-4: second beat faults ─────────────────────────────────────────
    ARM       r7
    cmove     a0, a5
    cmove     a3, a5
p7: clc       a0, a4, W1-4
    li        a0, 40
    j         test_end
r7: lw        t0, G_TRAPS(a5)
    CHECK_EQI t0, 1, 40, t1
    lw        t0, G_MCAUSE(a5)
    CHECK_EQI t0, MCAUSE_LOAD_ACC, 41, t1
    lw        t0, G_MTVAL(a5)
    li        t1, POISON_BASE+W1-4
    beq       t0, t1, 1f
    li        t1, POISON_BASE+W1
    CHECK_EQ  t0, t1, 42
1:  lw        t0, G_MEPC_ADDR(a5)
    LA_FAR    t1, p7, a1
    CHECK_EQ  t0, t1, 43
    lw        t0, G_MEPC_TAG(a5)
    CHECK_EQI t0, 1, 44, t1
    CD_UNTOUCHED 45

    # ── clc W2: first beat faults ────────────────────────────────────────────
    ARM       r8
    cmove     a0, a5
    cmove     a3, a5
p8: clc       a0, a4, W2
    li        a0, 46
    j         test_end
r8: li        t2, POISON_BASE+W2
    EXPECT_SYNC MCAUSE_LOAD_ACC, t2, p8, 46
    CD_UNTOUCHED 51

    # ── csc W1-4: second beat faults ─────────────────────────────────────────
    ARM       r9
p9: csc       a5, a4, W1-4
    li        a0, 52
    j         test_end
r9: lw        t0, G_TRAPS(a5)
    CHECK_EQI t0, 1, 52, t1
    lw        t0, G_MCAUSE(a5)
    CHECK_EQI t0, MCAUSE_STORE_ACC, 53, t1
    lw        t0, G_MTVAL(a5)
    li        t1, POISON_BASE+W1-4
    beq       t0, t1, 1f
    li        t1, POISON_BASE+W1
    CHECK_EQ  t0, t1, 54
1:  lw        t0, G_MEPC_ADDR(a5)
    LA_FAR    t1, p9, a1
    CHECK_EQ  t0, t1, 55
    lw        t0, G_MEPC_TAG(a5)
    CHECK_EQI t0, 1, 56, t1

    # ── csc W2: first beat faults ────────────────────────────────────────────
    ARM       r10
p10: csc      a5, a4, W2
    li        a0, 57
    j         test_end
r10: li       t2, POISON_BASE+W2
    EXPECT_SYNC MCAUSE_STORE_ACC, t2, p10, 57

    # ── lw W1+2: both halves fault ───────────────────────────────────────────
    ARM       r16
    li        a0, 0x1234
p16: lw       a0, W1+2(a4)
    li        a0, 100
    j         test_end
r16: lw       t0, G_TRAPS(a5)
    CHECK_EQI t0, 1, 100, t1
    lw        t0, G_MCAUSE(a5)
    CHECK_EQI t0, MCAUSE_LOAD_ACC, 101, t1
    lw        t0, G_MTVAL(a5)
    li        t1, POISON_BASE+W1+2
    beq       t0, t1, 1f
    li        t1, POISON_BASE+W2
    CHECK_EQ  t0, t1, 102
1:  lw        t0, G_MEPC_ADDR(a5)
    LA_FAR    t1, p16, a1
    CHECK_EQ  t0, t1, 103
    lw        t0, G_MEPC_TAG(a5)
    CHECK_EQI t0, 1, 104, t1
    RD_UNTOUCHED 105

    # ── lw W1, then a CHERI op that does not depend on it ────────────────────
    ARM       r17
    li        a0, 0x1234
    cmove     a2, a5
p17: lw       a0, W1(a4)
    cincaddrimm a2, a2, 4            # flushed by the load's fault, never executed
    li        a0, 106
    j         test_end
r17: li       t2, POISON_BASE+W1
    EXPECT_SYNC MCAUSE_LOAD_ACC, t2, p17, 106
    RD_UNTOUCHED 111
    cseqx     t0, a2, a5
    CHECK_EQI t0, 1, 112, t1

    # ── lw W1, then a branch that does not depend on it ──────────────────────
    ARM       r18
p18: lw       a0, W1(a4)
    beq       x0, x0, 1f
1:  li        a0, 113
    j         test_end
r18: li       t2, POISON_BASE+W1
    EXPECT_SYNC MCAUSE_LOAD_ACC, t2, p18, 113

    # ── lw W1, then a CHERI op that reads the load's rd (load-hazard stall) ──
    ARM       r21
    li        a0, 0x1234
    cmove     a2, a5
p21: lw       a0, W1(a4)
    cincaddr  a2, a2, a0             # held in ID by the hazard on a0; flushed by the fault
    li        a0, 134
    j         test_end
r21: li       t2, POISON_BASE+W1
    EXPECT_SYNC MCAUSE_LOAD_ACC, t2, p21, 134
    RD_UNTOUCHED 139
    cseqx     t0, a2, a5
    CHECK_EQI t0, 1, 140, t1

# After a word-load integrity NMI at \pc: the ops in the sled after the load each add 4 to a2
# (copied from a5 before the load), so a2.address must be a5.address + (MEPC - (\pc + 4)) --
# exactly the ops before MEPCC executed -- and a2 still tagged. Codes \code, \code+1.
# Clobbers t0, t1, a1.
.macro NMI_SLED_DONE pc, code
    lw        t0, G_MEPC_ADDR(a5)
    LA_FAR    t1, \pc+4, a1
    sub       t0, t0, t1
    cgetaddr  t1, a5
    add       t0, t0, t1
    cgetaddr  t1, a2
    CHECK_EQ  t1, t0, \code
    cgettag   t0, a2
    CHECK_EQI t0, 1, \code+1, t1
.endm

    # ── lw W4 with bad integrity, then CHERI ops, the first reading its rd ───
    ARM       r19
    cmove     a2, a5
    li        a0, 4                  # canary, and the step the first op adds
p19: lw       a0, W4(a4)
    cincaddr  a2, a2, a0             # load-hazard stall on a0
    .rept 7
    cincaddrimm a2, a2, 4
    .endr
p19_late:
    li        a0, 118                # the NMI was not taken within the sled
    j         test_end
r19: lw       t0, G_TRAPS(a5)
    CHECK_EQI t0, 1, 119, t1
    lw        t0, G_MCAUSE(a5)
    CHECK_EQI t0, MCAUSE_NMI_INTG, 120, t1
    lw        t0, G_MTVAL(a5)
    CHECK_EQI t0, POISON_BASE+W4, 121, t1
    NMI_MEPC  p19, 122
    CHECK_EQI a0, 4, 123, t1         # rd not written by a load with bad integrity
    NMI_SLED_DONE p19, 124

    # ── lw W4 with bad integrity, then CHERI ops independent of it ───────────
    ARM       r20
    cmove     a2, a5
    li        a0, 0x1234
p20: lw       a0, W4(a4)
    .rept 8
    cincaddrimm a2, a2, 4
    .endr
p20_late:
    li        a0, 126
    j         test_end
r20: lw       t0, G_TRAPS(a5)
    CHECK_EQI t0, 1, 127, t1
    lw        t0, G_MCAUSE(a5)
    CHECK_EQI t0, MCAUSE_NMI_INTG, 128, t1
    lw        t0, G_MTVAL(a5)
    CHECK_EQI t0, POISON_BASE+W4, 129, t1
    NMI_MEPC  p20, 130
    RD_UNTOUCHED 131
    NMI_SLED_DONE p20, 132

    # ── lw W4 with bad integrity: internal NMI ───────────────────────────────
    ARM       r11
    li        a0, 0x1234
p11: lw       a0, W4(a4)
    nop                              # may execute before the NMI (exception_interrupts.rst)
p11_late:
    li        a0, 62                 # the NMI was not taken within one instruction
    j         test_end
r11: lw       t0, G_TRAPS(a5)
    CHECK_EQI t0, 1, 63, t1
    lw        t0, G_MCAUSE(a5)
    CHECK_EQI t0, MCAUSE_NMI_INTG, 64, t1
    lw        t0, G_MTVAL(a5)
    CHECK_EQI t0, POISON_BASE+W4, 65, t1
    lw        t0, G_MEPC_ADDR(a5)
    LA_FAR    t1, p11+4, a1
    beq       t0, t1, 1f
    LA_FAR    t1, p11_late, a1
    CHECK_EQ  t0, t1, 66
1:  RD_UNTOUCHED 67

    # ── clc W3-4: second beat has bad integrity ──────────────────────────────
    ARM       r12
    cmove     a3, a4                 # canary: differs from the stored capability (a5)
    cmove     a0, a4
p12: clc      a0, a4, W3-4
    .rept 8                   # sled: a late NMI must not reach the canary in a0
    nop
    .endr
p12_late:
    li        a0, 68
    j         test_end
r12: lw       t0, G_TRAPS(a5)
    CHECK_EQI t0, 1, 69, t1
    lw        t0, G_MCAUSE(a5)
    CHECK_EQI t0, MCAUSE_NMI_INTG, 70, t1
    lw        t0, G_MTVAL(a5)
    li        t1, POISON_BASE+W3-4
    beq       t0, t1, 1f
    li        t1, POISON_BASE+W3
    CHECK_EQ  t0, t1, 71
1:  NMI_MEPC  p12, 72
    CD_UNTOUCHED 73

    # ── fetch from ifetch_bus_poison ─────────────────────────────────────────
    ARM       r13
    jal       ra, ifetch_bus_poison
    li        a0, 74
    j         test_end
r13: li       t2, 0x80000C00
    EXPECT_SYNC MCAUSE_IFETCH_ACC, t2, ifetch_bus_poison, 74

    # ── fetch from ifetch_intg_poison ────────────────────────────────────────
    ARM       r14
    jal       ra, ifetch_intg_poison
    li        a0, 79
    j         test_end
r14: li       t2, 0x80000D00
    EXPECT_SYNC MCAUSE_IFETCH_ACC, t2, ifetch_intg_poison, 79

    # ── clc W4: first beat has bad integrity (see (**) in the header) ────────
    ARM       r15
    cmove     a3, a4
    cmove     a0, a4
p15: clc      a0, a4, W4
    .rept 8                   # sled: a late NMI must not reach the canary in a0
    nop
    .endr
p15_late:
    li        a0, 84
    j         test_end
r15: lw       t0, G_TRAPS(a5)
    CHECK_EQI t0, 1, 85, t1
    lw        t0, G_MCAUSE(a5)
    CHECK_EQI t0, MCAUSE_NMI_INTG, 86, t1
    lw        t0, G_MTVAL(a5)
    CHECK_EQI t0, POISON_BASE+W4, 87, t1
    NMI_MEPC  p15, 88
    CD_UNTOUCHED 89

    lw        a0, G_LATE_NMI(a5)        # 0, or a late NMI (72/88) seen by an earlier probe
test_end:
    TEST_END_A0

unexpected_debug:
    li        a0, 9
    j         test_end

# ---- Trap handler: record the trap, resume at G_RESUME through an MTCC-derived MEPCC ----------
    .balign 4
trap_handler:
    SAVE_CTX
    DCAP_FAR  a1, globals, t0
    lw        t0, G_TRAPS(a1)
    addi      t0, t0, 1
    sw        t0, G_TRAPS(a1)
    li        t1, 4
    bltu      t0, t1, 1f
    li        a0, 90                 # trap storm: something keeps faulting
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

    .data
    .balign 512
trap_stack:
    .fill 64, 8, 0
    .balign 8
globals:
    .fill GLOBALS_SIZE / 4, 4, 0
