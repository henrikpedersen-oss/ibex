# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: debug_mret_umode -- ebreak, ecall, mret to U, a U-mode CSR access and dret at U,
# all inside one debug-mode session (RISC-V mode)
# =============================================================================
# REQ_DBG_01, REQ_DBG_04. One haltreq (rtl_test core_ibex_single_debug_pulse_test) starts the
# session; the handler then runs, in debug mode:
#   1. ebreak with dcsr.ebreakm set, data-independent timing and dummy instructions on
#      (cpuctrlsts, an ordinary CSR in RISC-V mode). Debug Spec 4.1: ebreak in debug mode halts
#      the hart again without updating dpc or dcsr (codes 13-15).
#   2. ecall.
#   3. mret with mstatus.MPP = U, to u_csr, which reads mstatus at U: an illegal instruction.
#   4. mret with MPP = U again, to u_dret, which executes dret at U.
#
# Where the expected values come from. Debug Spec 4.1 makes "almost all instructions that change
# the privilege mode" UNSPECIFIED in debug mode, naming ecall and mret; steps 2-4 are therefore
# not specified, and the expected values below come from the RTL, with the privileged spec's
# mret semantics for what mret does to mstatus:
#   - an exception in debug mode jumps to the debug exception address and updates no CSR (that
#     part is Debug Spec 4.1: "Exceptions don't update any registers. That includes cause, epc,
#     tval, dpc, and mstatus"), and it returns the hart to M (ibex_cs_registers.sv, "Any
#     exception, including debug mode, causes a switch to M-mode") -- codes 21-27, 32-38;
#   - mret in debug mode stays in debug mode and does what mret does outside it: pc := mepc,
#     priv := MPP (U), MIE := MPIE, MPIE := 1, MPP := U (ibex_controller.sv PC_ERET,
#     ibex_cs_registers.sv csr_restore_mret_i) -- codes 32-33;
#   - CSR privilege is checked against that lowered privilege (illegal_csr_priv uses
#     priv_lvl_q), so the U-mode mstatus read traps -- code 32;
#   - dret is legal in debug mode at any privilege (illegal_dret_insn = dret & ~debug_mode) and,
#     as REQ_DBG_04 states, returns to dpc with priv := dcsr.prv (M) -- codes 42, 50-52.
# If the specification later says that debug mode always runs at M, steps 3-4 become a finding
# (an mret in debug mode must not lower the privilege), not a test to adjust.
#
# Cosim off: Spike does not switch to M on an exception in debug mode (processor_t::take_trap),
# so it diverges from the RTL at step 3; the test is self-checking.
#
# Registers: the program uses x1-x15 only; the debug and trap handlers use x18-x25 (s2-s9) and
# save nothing, so every re-entry (ebreak, the two debug exceptions) is safe.
# PMP region 0 (NAPOT, RWX, unlocked) covers [0x80000000, 0x90000000): code, data and the
# signature address, so U-mode code can run; M-mode is not restricted by an unlocked region.
#
# Codes: 3 no debug request arrived; 10/11 haltreq entry dcsr.cause / dcsr.prv; 12 cpuctrlsts
# did not take DIT + dummy instructions; 13-15 ebreak in debug mode; 16 tselect != 0 at the
# haltreq entry; 20-27 ecall; 30-38 mret to U and the U-mode CSR access; 40-42 mret to U and
# dret at U; 50-52 back in the program;
# 90 unexpected trap outside debug mode; 91 unexpected debug entry; 95 unexpected debug exception.

#include "cheriot_dv.h"

#define G_FLAG          0
#define G_STAGE         4
#define G_DPC           8
#define G_DCSR          12
#define G_SNAP_MCAUSE   16
#define G_SNAP_MSTATUS  20
#define GLOBALS_SIZE    24

#define STG_EBREAK      1
#define STG_ECALL       2
#define STG_ECALL_DONE  3
#define STG_UCSR        4
#define STG_UCSR_DONE   5
#define STG_DRET        6

#define DCSR_EBREAKM    0x8000
#define CSR_CPUCTRLSTS  0x7c0
#define CPUCTRL_DIT_DUMMY 6        /* data_ind_timing | dummy_instr_en */
#define MSTATUS_MIE     0x8
#define MSTATUS_MPIE    0x80
#define MSTATUS_MPP     0x1800
#define MTVAL_SENTINEL  0x5EED

    .option norvc

    DV_VECTORS debug_entry, debug_exception
_start:
    j         main

    .text
main:
    la        t0, trap_handler
    csrw      mtvec, t0
    li        s1, SIG_ADDR_VAL
    la        a5, globals
    li        t0, 0x21FFFFFF                # NAPOT [0x80000000, +256 MiB)
    csrw      pmpaddr0, t0
    li        t0, 0x1F                      # NAPOT | X | W | R, unlocked
    csrw      pmpcfg0, t0
    li        t0, MSTATUS_MPP               # MPP = M: the bench reads the boot privilege from this
    csrs      mstatus, t0
    SIG_CSR   0x300
    SIG_CSR   0x304
    SIG_STATUS ST_INITIALIZED

    li        s0, 400000
wait_start:
    lw        t0, G_FLAG(a5)
    bnez      t0, wait_done
    addi      s0, s0, -1
    bnez      s0, wait_start
    li        a0, 3                         # no debug request arrived
    j         test_end
wait_done:
    # ── back in the program: dret at U returned here at M ─────────────────────
    lw        t0, G_STAGE(a5)
    CHECK_EQI t0, STG_DRET, 50, t1
    CHECK_EQI s9, 2, 51, t1                 # u_dret ran (s9 is the handlers' marker)
    csrr      t0, mstatus                   # illegal unless the hart is at M (trap: code 52)
    li        a0, 0
test_end:
    TEST_END_A0

# ---- Debug halt address: the haltreq entry and the ebreak re-entry ----------------------------
    .balign 4
debug_entry:
    la        s2, globals
    lw        s3, G_STAGE(s2)
    li        s4, STG_EBREAK
    beq       s3, s4, dbg_ebreak_back
    beqz      s3, 1f
    li        a0, 91
    j         test_end
1:  csrr      s4, dcsr
    srli      s5, s4, 6
    andi      s5, s5, 7
    CHECK_EQI s5, 3, 10, s6                 # dcsr.cause = haltreq
    andi      s5, s4, 3
    CHECK_EQI s5, 3, 11, s6                 # dcsr.prv = M
    csrr      s5, dpc
    sw        s5, G_DPC(s2)
    csrr      s5, tselect                   # a read-only tselect access in debug mode
    CHECK_EQI s5, 0, 16, s6                 # reset value; nothing in this test writes it

    # ── 1. ebreak in debug mode ──────────────────────────────────────────────
    li        s5, DCSR_EBREAKM
    csrs      dcsr, s5
    csrsi     CSR_CPUCTRLSTS, CPUCTRL_DIT_DUMMY
    csrr      s5, CSR_CPUCTRLSTS
    andi      s5, s5, CPUCTRL_DIT_DUMMY
    CHECK_EQI s5, CPUCTRL_DIT_DUMMY, 12, s6 # SecureIbex: both features present
    csrr      s5, dcsr
    sw        s5, G_DCSR(s2)
    li        s3, STG_EBREAK
    sw        s3, G_STAGE(s2)
    ebreak                                  # re-enters at debug_entry
    li        a0, 13
    j         test_end
dbg_ebreak_back:
    csrci     CSR_CPUCTRLSTS, CPUCTRL_DIT_DUMMY
    csrr      s5, dpc
    lw        s6, G_DPC(s2)
    CHECK_EQ  s5, s6, 14
    csrr      s5, dcsr
    lw        s6, G_DCSR(s2)
    CHECK_EQ  s5, s6, 15

    # ── 2. ecall in debug mode ───────────────────────────────────────────────
    # Values an ecall would overwrite outside debug mode: mepc (its pc), mcause (11), mtval (0),
    # mstatus (MPP := M, MPIE := MIE). mepc is already the target of the mret in step 3.
    la        s5, u_csr
    csrw      mepc, s5
    li        s5, MSTATUS_MPP
    csrc      mstatus, s5                   # MPP := U
    li        s5, MSTATUS_MPIE
    csrs      mstatus, s5                   # MPIE := 1
    csrci     mstatus, MSTATUS_MIE          # MIE := 0
    li        s5, MTVAL_SENTINEL
    csrw      mtval, s5
    csrr      s5, mcause
    sw        s5, G_SNAP_MCAUSE(s2)
    csrr      s5, mstatus
    sw        s5, G_SNAP_MSTATUS(s2)
    li        s3, STG_ECALL
    sw        s3, G_STAGE(s2)
    ecall                                   # to debug_exception
    li        a0, 20
    j         test_end

dbg_ecall_back:
    li        s3, STG_ECALL_DONE            # a CSR access below trapping means the hart is not
    sw        s3, G_STAGE(s2)               # at M (code 27)
    csrr      s5, mepc
    la        s6, u_csr
    CHECK_EQ  s5, s6, 21
    csrr      s5, mcause
    lw        s6, G_SNAP_MCAUSE(s2)
    CHECK_EQ  s5, s6, 22
    csrr      s5, mtval
    li        s6, MTVAL_SENTINEL
    CHECK_EQ  s5, s6, 23
    csrr      s5, mstatus
    lw        s6, G_SNAP_MSTATUS(s2)
    CHECK_EQ  s5, s6, 24
    csrr      s5, dpc
    lw        s6, G_DPC(s2)
    CHECK_EQ  s5, s6, 25
    csrr      s5, dcsr
    lw        s6, G_DCSR(s2)
    CHECK_EQ  s5, s6, 26

    # ── 3. mret to U in debug mode, then a U-mode CSR access ─────────────────
    li        s9, 0
    li        s3, STG_UCSR
    sw        s3, G_STAGE(s2)
    mret                                    # to u_csr at U, still in debug mode
    li        a0, 30
    j         test_end

dbg_ucsr_back:
    li        s3, STG_UCSR_DONE             # as for STG_ECALL_DONE (code 38)
    sw        s3, G_STAGE(s2)
    CHECK_EQI s9, 1, 32, s4                 # u_csr ran at U and its first CSR access trapped
    csrr      s5, mstatus
    li        s6, MSTATUS_MPP | MSTATUS_MPIE | MSTATUS_MIE
    and       s5, s5, s6
    CHECK_EQI s5, MSTATUS_MPIE | MSTATUS_MIE, 33, s6 # mret: MPP = U, MPIE = 1, MIE = old MPIE
    csrr      s5, mepc
    la        s6, u_csr
    CHECK_EQ  s5, s6, 34
    csrr      s5, mtval
    li        s6, MTVAL_SENTINEL
    CHECK_EQ  s5, s6, 35
    csrr      s5, mcause
    lw        s6, G_SNAP_MCAUSE(s2)
    CHECK_EQ  s5, s6, 36
    csrr      s5, dpc
    lw        s6, G_DPC(s2)
    CHECK_EQ  s5, s6, 37

    # ── 4. mret to U again, then dret at U ───────────────────────────────────
    la        s5, u_dret
    csrw      mepc, s5
    li        s5, MSTATUS_MPP | MSTATUS_MPIE
    csrc      mstatus, s5                   # MPP := U, MPIE := 0: MIE stays 0 after the mret
    csrci     mstatus, MSTATUS_MIE
    # Outlast the 75-cycle request pulse, so one request is one entry.
    li        s5, 100
2:  addi      s5, s5, -1
    bnez      s5, 2b
    li        s3, STG_DRET
    sw        s3, G_STAGE(s2)
    li        s3, 1
    sw        s3, G_FLAG(s2)
    mret                                    # to u_dret at U, still in debug mode
    li        a0, 40
    j         test_end

# ---- Debug exception address --------------------------------------------------------------------
    .balign 4
debug_exception:
    la        s2, globals
    lw        s3, G_STAGE(s2)
    li        s4, STG_ECALL
    beq       s3, s4, dbg_ecall_back
    li        s4, STG_UCSR
    beq       s3, s4, dbg_ucsr_back
    li        a0, 27
    li        s4, STG_ECALL_DONE
    beq       s3, s4, test_end
    li        a0, 38
    li        s4, STG_UCSR_DONE
    beq       s3, s4, test_end
    li        a0, 42                        # dret at U raised an exception
    li        s4, STG_DRET
    beq       s3, s4, test_end
    li        a0, 95
    j         test_end

# ---- Code run at U inside debug mode ------------------------------------------------------------
    .balign 4
u_csr:
    addi      s9, x0, 1
    csrr      s8, mstatus                   # illegal at U: to debug_exception
    li        a0, 31                        # the access did not trap
    j         test_end

u_dret:
    addi      s9, x0, 2
    dret                                    # resume the program at dpc, at dcsr.prv = M
    li        a0, 41
    j         test_end

# ---- Trap handler: nothing may trap outside debug mode ------------------------------------------
# After the session the only trap possible is the mstatus read in wait_done, from below M.
    .balign 256
trap_handler:
    la        s2, globals
    lw        s3, G_STAGE(s2)
    li        a0, 52                        # dret left the hart below M
    li        s4, STG_DRET
    beq       s3, s4, test_end
    li        a0, 90
    j         test_end

    .data
    .balign 8
globals:
    .fill GLOBALS_SIZE / 4, 4, 0
