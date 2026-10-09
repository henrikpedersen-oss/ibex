# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: dm_basic / dm_basic_cheriot -- the real debug module halts, inspects, modifies and
# resumes this program over DMI
# =============================================================================
# Needs the DM build of the testbench (make uvm-test-xlm TEST=dm_basic,dm_basic_cheriot DM=1):
# the core's debug entry points are the debug ROM of vendor/pulp_riscv_dbg's dm_top at
# 0x1A11_0800 / 0x1A11_0810, and debug requests come from dm_top, driven over its DMI port by
# rtl_test core_ibex_dm_test (tests/core_ibex_dm_test.sv), which also lists what it checks.
#
# dm_basic runs in RISC-V mode. dm_basic_cheriot is this file with DM_CHERIOT defined, run with
# cheriot_enable_i asserted from reset (+enable_cheriot_seq=1), so the DM uses its CHERIoT ROM,
# CSpecialRW scratch handling and 64-bit capability register access.
#
# Self-checking, cosim off (+cosim_off=1): neither Spike nor
# CHERIoT-Sail models the real debug module's ROM and abstract-command memory. The checks are the
# debugger's (DMI read-back against the values below and the images in dm_expect) and this
# program's (after resume, every register the debugger wrote or had to leave alone).
#
# Shared with core_ibex_dm_test (keep in step):
#   dm_expect = 0x8000_0040 (ExpBase): +0x00 csc s1, +0x08 csc a5 (CHERIoT), +0x10 / +0x14 the
#     wait loop's bounds [dm_loop, dm_loop_end), +0x18 the program's csc of a4 after resume
#   registers before the halt
#     RISC-V:  s0 0x5A5A0808, s1 0x8FFFFFFC, a0 0x5A5A0A0A, a1 0x5A5A0B0B, a2 0, a4 0x5A5A0E0E,
#              a5 dm_expect, x16 0x5A5A1010, x31 0x5A5A1F1F, x20 0
#     CHERIoT: s1 signature capability (MTDC at 0x8FFFFFFC), a5 MTDC bounded to [dm_expect, +0x40),
#              s0 = a5 (tagged), a0 = a5 + 8 (tagged), a1, a2, a4 as above
#     s0 and a0 are the registers every abstract command borrows (dscratch0/1, DScratchC0/1 in
#     CHERIoT mode), so they are the ones whose restore after resume says most.
#   the debugger: a1 += 0x111 (program buffer), RISC-V x20 := 0x2020D0D0, CHERIoT a4 := untagged
#     capability {s1's metadata, 0x80001234} (64-bit write), then a2 := 0xD0D0C0DE (mailbox)
#
# Exit codes (a0; 0 = pass)
#   code 1:  CHERIoT mode is not on (dm_basic_cheriot without +enable_cheriot_seq=1)
#   code 2:  the debugger never wrote the mailbox (wait loop ran out)
#   code 10: a0 changed (RISC-V) / a0 lost its tag (CHERIoT); code 11: CHERIoT a0 address changed
#   code 12: s0 changed (RISC-V) / s0 lost its tag (CHERIoT); code 13: CHERIoT s0 != a5 (cseqx)
#   code 14: a1 is not 0x5A5A0B0B + 0x111 (the program buffer did not run, or ran twice)
#   code 15: RISC-V a4 changed / CHERIoT a4 is tagged (a capability written over DMI cannot be)
#   code 16: RISC-V x20 not written / CHERIoT a4 address is not 0x80001234
#   code 17: RISC-V x16 changed / CHERIoT a4 metadata (via csc) is not s1's
#   code 18: RISC-V x31 changed / CHERIoT a4 address (via csc) is not 0x80001234
#   code 19: a5 changed (RISC-V) / a5 lost its tag (CHERIoT)
#   code 20: the wait-loop counter a3 is 0
#   code 90: reached the riscv-dv debug vectors at BOOT_ADDR (the build has no real DM?)
#   code 91: unexpected trap

#include "cheriot_dv.h"

#define DM_MAGIC     0xD0D0C0DE
#define X20_WRITE    0x2020D0D0
#define A4_CAP_ADDR  0x80001234
#define A1_INIT      0x5A5A0B0B
#define PROGBUF_ADD  0x111
#define LOOP_MAX     200000

#define EXP_S1       0x00
#define EXP_A5       0x08
#define EXP_LOOP_LO  0x10
#define EXP_LOOP_HI  0x14
#define EXP_A4       0x18
#define EXP_SIZE     0x40

    .option norvc
    .option norelax

    .section .text.init, "ax"
    .globl _start
    # BOOT_ADDR + 0 / + 8: the riscv-dv debug vectors of the normal build. With the real DM the
    # core never comes here on a debug request.
    j         bad_vector
    .org 8
    j         bad_vector
    .org 0x40
    .globl dm_expect
dm_expect:                              # 0x80000040, core_ibex_dm_test ExpBase
    .fill     EXP_SIZE / 4, 4, 0
    .org 0x80
_start:                                 # BOOT_ADDR + 0x80, the reset PC
#ifdef DM_CHERIOT
    SIG_INIT                            # s1 := signature capability
    auipc     t1, 0                     # AUIPCC: tagged iff CHERIoT mode is on
    cgettag   t2, t1
    li        a0, 1
    beqz      t2, test_end
    SET_VEC   trap_fail, t1, t0
    DCAP_FAR  a5, dm_expect, t0
    li        t0, EXP_SIZE
    csetboundsexact a5, a5, t0
    cmove     s0, a5                    # tagged capability in s0
    cincaddrimm a0, a5, 8               # tagged capability in a0
    csc       s1, a5, EXP_S1            # the images the debugger's 64-bit reads must match
    csc       a5, a5, EXP_A5
#else
    li        s1, SIG_ADDR_VAL
    la        t0, trap_fail
    csrw      mtvec, t0
    la        a5, dm_expect
    li        s0, 0x5A5A0808
    li        a0, 0x5A5A0A0A
    li        x16, 0x5A5A1010
    li        x31, 0x5A5A1F1F
    li        x20, 0
#endif
    li        a1, A1_INIT
    li        a4, 0x5A5A0E0E
    li        a2, 0
    LA_FAR    t0, dm_loop, t1
    sw        t0, EXP_LOOP_LO(a5)
    LA_FAR    t0, dm_loop_end, t1
    sw        t0, EXP_LOOP_HI(a5)
    SIG_STATUS ST_INITIALIZED           # core_ibex_dm_test starts debugging after this
    li        a3, 0
    li        t2, LOOP_MAX
    li        t1, DM_MAGIC

    # The debugger halts the hart in here (dpc in [dm_loop, dm_loop_end)), and the program
    # leaves once the debugger has put DM_MAGIC in a2.
dm_loop:
    addi      a3, a3, 1
    beq       a2, t1, dm_resumed
    bltu      a3, t2, dm_loop
dm_loop_end:
    li        a0, 2
    j         test_end

dm_resumed:
#ifdef DM_CHERIOT
    cgettag   t0, a0
    CHECK_EQI t0, 1, 10, t1
    cgetaddr  t0, a0
    cgetaddr  t1, a5
    addi      t1, t1, 8
    CHECK_EQ  t0, t1, 11
    cgettag   t0, s0
    CHECK_EQI t0, 1, 12, t1
    cseqx     t0, s0, a5
    CHECK_EQI t0, 1, 13, t1
    li        t0, A1_INIT + PROGBUF_ADD
    CHECK_EQ  a1, t0, 14
    cgettag   t0, a4
    CHECK_EQI t0, 0, 15, t1
    cgetaddr  t0, a4
    CHECK_EQI t0, A4_CAP_ADDR, 16, t1
    csc       a4, a5, EXP_A4
    lw        t0, EXP_A4 + 4(a5)
    lw        t1, EXP_S1 + 4(a5)
    CHECK_EQ  t0, t1, 17
    lw        t0, EXP_A4(a5)
    CHECK_EQI t0, A4_CAP_ADDR, 18, t1
    cgettag   t0, a5
    CHECK_EQI t0, 1, 19, t1
#else
    CHECK_EQI a0, 0x5A5A0A0A, 10, t1
    CHECK_EQI s0, 0x5A5A0808, 12, t1
    li        t0, A1_INIT + PROGBUF_ADD
    CHECK_EQ  a1, t0, 14
    CHECK_EQI a4, 0x5A5A0E0E, 15, t1
    CHECK_EQI x20, X20_WRITE, 16, t1
    CHECK_EQI x16, 0x5A5A1010, 17, t1
    CHECK_EQI x31, 0x5A5A1F1F, 18, t1
    la        t0, dm_expect
    CHECK_EQ  a5, t0, 19
#endif
    li        a0, 20
    beqz      a3, test_end
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
    li        a0, 90
    j         test_end

    .balign 4
trap_fail:
    li        a0, 91
    j         test_end
