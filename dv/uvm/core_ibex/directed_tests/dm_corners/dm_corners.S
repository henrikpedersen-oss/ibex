# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: dm_corners / dm_corners_cheriot -- debug-mode corner cases through the real debug module
# =============================================================================
# REQ_DBG_03, REQ_DBG_04, REQ_DBG_05, REQ_SCR_01 (debug extension); the core-level form of the
# EG2 rows chip_eg2_rv_dm_cap_bypass and chip_eg2_rv_dm_priv.
#
# Needs the DM build of the testbench (make uvm-test-xlm TEST=dm_corners_cheriot DM=1). The
# debugger is rtl_test core_ibex_dm_corners_test (tests/core_ibex_dm_corners_test.sv), which
# drives pulp_riscv_dbg's dm_top over DMI and makes the debug-mode checks (cmderr, registers read
# with abstract commands, memory). This program makes the checks that need the core running
# again (traps after dret, the tags of capabilities stored in debug mode). Cosim off: neither
# Spike nor CHERIoT-Sail models the debug module's ROM, and CHERIoT-Sail has no debug mode.
#
# dm_corners_cheriot (DM_CHERIOT, +enable_cheriot_seq=1), in order:
#   S   outside debug mode, CSpecialRW of SCRs 24, 25, 26 (read and write): illegal instruction,
#       mcause 2, MEPCC at the access (REQ_SCR_01, REQ_DBG_03)
#   A   halted in the wait loop. The program's PCC and MTCC are bounded to [0x80000000, +0x2000),
#       so every instruction of the program buffer and debug ROM is fetched outside them. The
#       debugger runs program buffers that load, store, CLC and CSC through
#         a5  tagged, bounds [G+0x40, +16): every access is beyond the top
#         a4  untagged, cursor G+0x68
#         a3  tagged, bounds [G+0x80, +24), GL its only permission (no LD, SD, MC, LM, LG)
#       and reads and writes DEPCC, DScratchC0 and DScratchC1 (SCRs 24-26). After resume the
#       program checks that each CSC stored a5 with its tag and each SW its word.
#   C1  DEPCC := gp untagged (ccleartag in the program buffer), then dret: the fetch at
#       landing_c1 faults, mcause 28, mtval 0x402 (PCC, tag violation; CHERIoT-Sail
#       ext_fetch_check_pc), MEPCC.address = landing_c1
#   C2  DEPCC := tp, sealed (otype 7), then dret: mcause 28, mtval[10:5] = 0x20 (PCC)
#   C3  DEPCC := ra, without EX, then dret: mcause 28, mtval[10:5] = 0x20 (PCC)
#       (CHERIoT-Sail has no behaviour for a sealed or non-executable PCC: it asserts neither
#       can happen, so only what REQ_DBG_03 states -- a CHERI fault on PCC -- is checked.)
#   D0-D3 the debugger writes dcsr.prv = 0, 1, 2, 3 in turn, checks the value read back, and
#       puts it in the mailbox; after dret the program executes ecall: mcause 8 if the mailbox
#       says U, 11 if M (REQ_DBG_04: dret returns to dcsr.prv). In CHERIoT mode only M exists.
# dm_corners (RISC-V mode) runs D0-D3 only; U-mode exists there, and PMP entry 0 grants U-mode
# access to everything so the U-mode fetches after dret do not fault.
#
# Layout shared with core_ibex_dm_corners_test (keep in step): globals at G = 0x80000100,
#   +0x00 phase the program waits in (the debugger polls it), +0x04.. trap record,
#   +0x50 / +0x68 / +0x80 the words loaded through a5 / a4 / a3 (W_OOB, W_UT, W_NP),
#   +0x54 / +0x6C / +0x84 the words stored there (ST_A1..3, from t2),
#   +0x58 / +0x70 / +0x88 tagged capabilities the CLCs load (G's capability, cursor = the slot),
#   +0x60 / +0x78 / +0x90 the CSC targets (a5).
# Mailbox a2: the program leaves a wait loop once a2[31:8] = 0xD0D0C0; a2[7:0] is the phase
# data (0x0A after phase A, the dcsr.prv read back after D0-D3).
#
# Exit codes (a0; 0 = pass)
#   1  CHERIoT mode is not on               2-7  setup (capability construction)
#   40-63 phase S: 40+4k the k-th SCR access did not trap, 41+4k..43+4k trap count, mcause, MEPCC
#   70 phase A never released by the debugger; 71-76 a CSC in debug mode did not store a5 with
#      its tag (71/72 a5, 73/74 a4, 75/76 a3); 77-79 an SW in debug mode did not store t2;
#      80 a5 lost its tag, 81 a4 gained one
#   90/100/110 phase C1/C2/C3 never halted; 91/101/111 the fetch through the bad DEPCC did not
#      fault; 92-94/102-104/112-114 trap count, mcause, MEPCC.address; 95/105/115 mtval
#   120+10v phase Dv never released; 121+10v the ecall did not trap; 122+10v trap count,
#      123+10v the mailbox holds a privilege the core does not implement, 124+10v mcause
#      (privilege after dret), 125+10v MEPC
#   98 unexpected trap; 99 reached the riscv-dv debug vectors (no real DM in the build?)

#include "cheriot_dv.h"

#define G_BASE      0x80000100
#define G_SIZE      0x100
#define G_PHASE     0x00
#define G_TRAPS     0x04
#define G_MCAUSE    0x08
#define G_MTVAL     0x0C
#define G_MEPC      0x10
#define G_MEPCTAG   0x14
#define G_RESUME    0x18
#define G_SEALROOT  0x20
#define G_CODECAP   0x28
#define G_BUF       0x40
#define G_OOB_W     0x50
#define G_OOB_SW    0x54
#define G_OOB_C     0x58
#define G_OOB_CS    0x60
#define G_UT        0x68
#define G_UT_SW     0x6C
#define G_UT_C      0x70
#define G_UT_CS     0x78
#define G_NP        0x80
#define G_NP_SW     0x84
#define G_NP_C      0x88
#define G_NP_CS     0x90

#define W_OOB       0x0B0B0001
#define W_UT        0x0B0B0002
#define W_NP        0x0B0B0003
#define ST_A1       0x570000A1
#define ST_A2       0x570000A2
#define ST_A3       0x570000A3

#define PH_A        0x01
#define PH_C1       0x11
#define PH_C2       0x12
#define PH_C3       0x13
#define PH_D0       0x20

#define MAGIC_HI    0xD0D0C0
#define LOOP_MAX    400000
#define CODE_BASE   0x80000000
#define CODE_LEN    0x2000
#define SEAL_OTYPE  7
#define MSTATUS_MPP 0x1800
#define CAUSE_ILLEGAL 2
#define CAUSE_ECALL_U 8
#define CAUSE_ECALL_M 11

    .option norvc
    .option norelax

# Arm the trap handler: the next trap is recorded and resumes at \resume. Clobbers t0, t1.
.macro ARM resume
    LA_FAR    t0, \resume, t1
    sw        t0, G_RESUME(sp)
    sw        zero, G_TRAPS(sp)
    li        t0, -1
    sw        t0, G_MCAUSE(sp)
    sw        t0, G_MTVAL(sp)
    sw        t0, G_MEPC(sp)
.endm

# Exactly one trap since ARM, with mcause \cause at \pc. Codes \code..\code+2. Clobbers t0-t2.
.macro EXPECT_TRAP cause, pc, code
    lw        t0, G_TRAPS(sp)
    CHECK_EQI t0, 1, \code, t1
    lw        t0, G_MCAUSE(sp)
    CHECK_EQI t0, \cause, \code+1, t1
    lw        t0, G_MEPC(sp)
    LA_FAR    t1, \pc, t2
    CHECK_EQ  t0, t1, \code+2
.endm

# Publish phase \ph and spin until the debugger puts MAGIC_HI in a2[31:8]. Only register
# instructions in the loop, so it runs at U as well as M. Code \code if it never happens.
.macro WAIT ph, code
    li        a2, 0
    li        a1, LOOP_MAX
    li        t1, MAGIC_HI
    li        t0, \ph
    sw        t0, G_PHASE(sp)
1:  srli      t0, a2, 8
    beq       t0, t1, 2f
    addi      a1, a1, -1
    bnez      a1, 1b
    li        a0, \code
    j         test_end
2:
.endm

    .section .text.init, "ax"
    .globl _start
dm_base:
    # BOOT_ADDR + 0 / + 8: the riscv-dv debug vectors of the normal build. With the real DM the
    # core never comes here on a debug request.
    j         bad_vector
    .org 8
    j         bad_vector
    .org 0x80
_start:                                 # BOOT_ADDR + 0x80, the reset PC
    j         main

    .org G_BASE - CODE_BASE
    .globl dm_globals
dm_globals:
    .fill     G_SIZE / 4, 4, 0

    .org 0x200
main:
#ifdef DM_CHERIOT
    SIG_INIT
    auipc     t1, 0                     # AUIPCC: tagged iff CHERIoT mode is on
    cgettag   t2, t1
    li        a0, 1
    beqz      t2, test_end
    # sp := globals capability [G, G + G_SIZE)
    cspecialr sp, SCR_MTDC
    li        t0, G_BASE
    csetaddr  sp, sp, t0
    li        t0, G_SIZE
    csetboundsexact sp, sp, t0
    cspecialr t1, SCR_MSCRATCHC         # the sealing root, as reset leaves it
    csc       t1, sp, G_SEALROOT
    # t1 := code capability [CODE_BASE, + CODE_LEN); MTCC and PCC are derived from it, so the
    # debug memory at 0x1A110000 is outside both.
    cspecialr t1, SCR_MTCC
    li        t0, CODE_BASE
    csetaddr  t1, t1, t0
    li        t0, CODE_LEN
    csetboundsexact t1, t1, t0
    cgettag   t0, t1
    li        a0, 2
    beqz      t0, test_end
    csc       t1, sp, G_CODECAP
    LA_FAR    t0, trap_handler, t2
    csetaddr  t2, t1, t0
    cspecialw SCR_MTCC, t2
    LA_FAR    t0, bounded, t2
    csetaddr  t2, t1, t0
    jalr      x0, 0(t2)                 # CJALR: PCC := the bounded code capability
bounded:
    # a5: tagged, [G + G_BUF, +16)
    cmove     a5, sp
    cincaddrimm a5, a5, G_BUF
    csetboundsimm a5, a5, 16
    cgettag   t0, a5
    li        a0, 3
    beqz      t0, test_end
    cgetlen   t0, a5
    CHECK_EQI t0, 16, 3, t1
    # a4: untagged, cursor G + G_UT
    cmove     a4, sp
    cincaddrimm a4, a4, G_UT
    ccleartag a4, a4
    cgettag   t0, a4
    CHECK_EQI t0, 0, 4, t1
    # a3: tagged, [G + G_NP, +24), GL only
    cmove     a3, sp
    cincaddrimm a3, a3, G_NP
    csetboundsimm a3, a3, 24
    li        t0, 0x1
    candperm  a3, a3, t0
    cgettag   t0, a3
    CHECK_EQI t0, 1, 5, t1
    cgetperm  t0, a3
    andi      t0, t0, 0x7E              # LG, SD, LM, SL, LD, MC
    CHECK_EQI t0, 0, 5, t1
    # the words the debugger loads
    li        t0, W_OOB
    sw        t0, G_OOB_W(sp)
    li        t0, W_UT
    sw        t0, G_UT(sp)
    li        t0, W_NP
    sw        t0, G_NP(sp)
    # the tagged capabilities the debugger's CLCs load: G's capability with its cursor on the slot
    cincaddrimm t0, sp, G_OOB_C
    csc       t0, sp, G_OOB_C
    cincaddrimm t0, sp, G_UT_C
    csc       t0, sp, G_UT_C
    cincaddrimm t0, sp, G_NP_C
    csc       t0, sp, G_NP_C
    # DEPCC candidates: gp (made untagged in the program buffer), tp sealed, ra without EX
    clc       t1, sp, G_CODECAP
    LA_FAR    t0, landing_c1, t2
    csetaddr  gp, t1, t0
    LA_FAR    t0, landing_c2, t2
    csetaddr  tp, t1, t0
    clc       t2, sp, G_SEALROOT
    li        t0, SEAL_OTYPE
    csetaddr  t2, t2, t0
    cseal     tp, tp, t2
    cgettag   t0, tp
    CHECK_EQI t0, 1, 6, t1
    cgettype  t0, tp
    CHECK_EQI t0, SEAL_OTYPE, 6, t1
    clc       t1, sp, G_CODECAP
    LA_FAR    t0, landing_c3, t2
    csetaddr  ra, t1, t0
    li        t0, 0xEFF                 # all but EX
    candperm  ra, ra, t0
    cgettag   t0, ra
    CHECK_EQI t0, 1, 7, t1
    cgetperm  t0, ra
    andi      t0, t0, 0x100
    CHECK_EQI t0, 0, 7, t1
#else
    li        s1, SIG_ADDR_VAL
    li        sp, G_BASE
    LA_FAR    t0, trap_handler, t1
    csrw      mtvec, t0
    li        t0, -1                    # NAPOT, the whole address space
    csrw      pmpaddr0, t0
    li        t0, 0x1F                  # NAPOT | X | W | R, unlocked: U-mode may run anywhere
    csrw      pmpcfg0, t0
#endif
    li        t0, MSTATUS_MPP
    csrs      mstatus, t0
    SIG_STATUS ST_INITIALIZED           # core_ibex_dm_corners_test starts debugging after this

#ifdef DM_CHERIOT
    # ── S: SCRs 24-26 outside debug mode are illegal instructions ────────────────────────────
    ARM       s0r
s0a: cspecialr t0, SCR_DEPCC
    li        a0, 40
    j         test_end
s0r: EXPECT_TRAP CAUSE_ILLEGAL, s0a, 41
    ARM       s1r
s1a: cspecialr t0, SCR_DSCRATCHC0
    li        a0, 44
    j         test_end
s1r: EXPECT_TRAP CAUSE_ILLEGAL, s1a, 45
    ARM       s2r
s2a: cspecialr t0, SCR_DSCRATCHC1
    li        a0, 48
    j         test_end
s2r: EXPECT_TRAP CAUSE_ILLEGAL, s2a, 49
    ARM       s3r
s3a: cspecialw SCR_DEPCC, a5
    li        a0, 52
    j         test_end
s3r: EXPECT_TRAP CAUSE_ILLEGAL, s3a, 53
    ARM       s4r
s4a: cspecialw SCR_DSCRATCHC0, a5
    li        a0, 56
    j         test_end
s4r: EXPECT_TRAP CAUSE_ILLEGAL, s4a, 57
    ARM       s5r
s5a: cspecialw SCR_DSCRATCHC1, a5
    li        a0, 60
    j         test_end
s5r: EXPECT_TRAP CAUSE_ILLEGAL, s5a, 61

    # ── A: capability checks bypassed in the program buffer ──────────────────────────────────
    WAIT      PH_A, 70
    clc       t0, sp, G_OOB_CS
    cgettag   t1, t0
    CHECK_EQI t1, 1, 71, t2
    cseqx     t1, t0, a5
    CHECK_EQI t1, 1, 72, t2
    clc       t0, sp, G_UT_CS
    cgettag   t1, t0
    CHECK_EQI t1, 1, 73, t2
    cseqx     t1, t0, a5
    CHECK_EQI t1, 1, 74, t2
    clc       t0, sp, G_NP_CS
    cgettag   t1, t0
    CHECK_EQI t1, 1, 75, t2
    cseqx     t1, t0, a5
    CHECK_EQI t1, 1, 76, t2
    lw        t0, G_OOB_SW(sp)
    CHECK_EQI t0, ST_A1, 77, t1
    lw        t0, G_UT_SW(sp)
    CHECK_EQI t0, ST_A2, 78, t1
    lw        t0, G_NP_SW(sp)
    CHECK_EQI t0, ST_A3, 79, t1
    cgettag   t0, a5
    CHECK_EQI t0, 1, 80, t1
    cgettag   t0, a4
    CHECK_EQI t0, 0, 81, t1

    # ── C1-C3: dret through a DEPCC the fetch checks reject ──────────────────────────────────
    ARM       c1r
    WAIT      PH_C1, 90
landing_c1:
    li        a0, 91
    j         test_end
c1r: EXPECT_TRAP MCAUSE_CHERI, landing_c1, 92
    lw        t0, G_MTVAL(sp)
    CHECK_EQI t0, 0x402, 95, t1

    ARM       c2r
    WAIT      PH_C2, 100
landing_c2:
    li        a0, 101
    j         test_end
c2r: EXPECT_TRAP MCAUSE_CHERI, landing_c2, 102
    lw        t0, G_MTVAL(sp)
    srli      t0, t0, 5
    CHECK_EQI t0, 0x20, 105, t1

    ARM       c3r
    WAIT      PH_C3, 110
landing_c3:
    li        a0, 111
    j         test_end
c3r: EXPECT_TRAP MCAUSE_CHERI, landing_c3, 112
    lw        t0, G_MTVAL(sp)
    srli      t0, t0, 5
    CHECK_EQI t0, 0x20, 115, t1
#endif

    # ── D0-D3: dcsr.prv, then dret ───────────────────────────────────────────────────────────
.macro PRV_PHASE v
    ARM       d\v\()r
    WAIT      PH_D0 + \v, 120 + 10 * \v
d\v\()e:
    ecall
    li        a0, 121 + 10 * \v
    j         test_end
d\v\()r:
    lw        t0, G_TRAPS(sp)
    CHECK_EQI t0, 1, 122 + 10 * \v, t1
    andi      t2, a2, 0xFF              # the dcsr.prv the debugger read back
    li        t1, CAUSE_ECALL_U
    beqz      t2, 3f
    li        t1, CAUSE_ECALL_M
    li        t0, 3
    beq       t2, t0, 3f
    li        a0, 123 + 10 * \v
    j         test_end
3:  lw        t0, G_MCAUSE(sp)
    CHECK_EQ  t0, t1, 124 + 10 * \v
    lw        t0, G_MEPC(sp)
    LA_FAR    t1, d\v\()e, t2
    CHECK_EQ  t0, t1, 125 + 10 * \v
.endm
    PRV_PHASE 0
    PRV_PHASE 1
    PRV_PHASE 2
    PRV_PHASE 3

    li        a0, 0
test_end:
    TEST_END_A0

    .balign 4
bad_vector:
#ifdef DM_CHERIOT
    SIG_INIT
#else
    li        s1, SIG_ADDR_VAL
#endif
    li        a0, 99
    j         test_end

# ---- Trap handler: record the trap, return to M at G_RESUME ----------------------------------
# One trap per ARM: the handler disarms itself, so a second trap is unexpected (code 98).
    .balign 256
trap_handler:
    lw        t0, G_RESUME(sp)
    bnez      t0, 1f
    li        a0, 98
    j         test_end
1:  lw        t0, G_TRAPS(sp)
    addi      t0, t0, 1
    sw        t0, G_TRAPS(sp)
    csrr      t0, mcause
    sw        t0, G_MCAUSE(sp)
    csrr      t0, mtval
    sw        t0, G_MTVAL(sp)
#ifdef DM_CHERIOT
    cspecialr t1, SCR_MEPCC
    cgetaddr  t0, t1
    sw        t0, G_MEPC(sp)
    cgettag   t0, t1
    sw        t0, G_MEPCTAG(sp)
#else
    csrr      t0, mepc
    sw        t0, G_MEPC(sp)
#endif
    li        t0, MSTATUS_MPP           # return to M whatever the trap came from
    csrs      mstatus, t0
    lw        t0, G_RESUME(sp)
    sw        zero, G_RESUME(sp)
#ifdef DM_CHERIOT
    clc       t1, sp, G_CODECAP
    csetaddr  t1, t1, t0
    cspecialw SCR_MEPCC, t1
#else
    csrw      mepc, t0
#endif
    mret
dm_code_end:                            # must stay below CODE_BASE + CODE_LEN (riscv32-unknown-elf-nm)
