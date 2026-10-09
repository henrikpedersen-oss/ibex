# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cov_expr_cheriot_dbg -- MTCC at address 0; null DEPCC and an exception in debug mode
# =============================================================================
# CHERIoT mode: boots in RISC-V mode and the bench raises cheriot_enable_i
# (+cheriot_enable_on_write=80200000), as cheriot_debug_mode does. Cosim off (CHERIoT-Sail has no
# debug mode, and the trap handler lives at address 0); self-checking. rtl_test
# core_ibex_stall_events_test raises debug_req_i on the store to DOORBELL (+dbg_req_on_write).
#
# Expression-coverage targets (merged regression after UNR, 2026-10-09):
#   ibex_if_stage.sv EXC_PC_EXC, CHERIoT arm `{csr_mtvec_i[31:2], 2'b00}` = 0: an exception
#     taken with MTCC.address = 0.
#   ibex_cs_registers.sv gen_scr:
#     `cheriot_csr_rdata_o = debug_mode_i ? depc_q : '0` and
#     `cheriot_csr_rcap_o = debug_mode_i ? depc_cap : NULL_CAP`, rows debug_mode = 1 with
#     DEPCC = 0 / NULL: DEPCC read in debug mode after writing the null capability to it;
#     `(cheriot_enable_i == On) && csr_save_cause_i && ~debug_csr_save_i && ~debug_mode_i`, row
#     debug_mode = 1: an exception taken in debug mode with CHERIoT on.
#
# Expected behaviour (not taken from the RTL):
#   - CHERIoT ISA: a trap jumps to MTCC (PCC := MTCC); MTCC.address 0 is legal (4-byte aligned),
#     and the handler there returns with MEPCC + 4 and mret.
#   - DEPCC is a debug-mode SCR: writing the null capability (from a register holding integer 0;
#     CSpecialRW with cs1 = c0 is a read and writes nothing) and reading it back gives tag 0,
#     address 0 (CHERIoT ISA, CSpecialRW; spec REQ_SCR_01).
#   - RISC-V Debug Spec 4.1 (Ibex doc/03_reference/debug.rst): an exception in debug mode jumps
#     to the debug exception address (dm_exception_addr = BOOT_ADDR + 8) and updates no CSR:
#     mcause and MEPCC are unchanged.
#
# Failure: exit code (TEST_END_A0, a0):
#   1  the handler at address 0 did not run      2  mcause after it not 3 (breakpoint)
#   3  no debug entry (timeout)                   4  debug entries != 1
#   5  DEPCC read back tagged after writing NULL  6  ... with a non-zero address
#   7  no debug exception                         8  mcause changed by it   9  MEPCC changed
#   10 an unexpected trap (mcause in the log via trap_handler)

#include "cheriot_dv.h"

#define DOORBELL     0x80100100     /* +dbg_req_on_write=80100100 */
#define G_FLAG       0              /* debug entries */
#define G_DEXC       4              /* debug exceptions */
#define G_TAG        8
#define G_ADDR       12
#define G_MCAUSE_A   16
#define G_MCAUSE_B   20
#define G_MEPC_A     24
#define G_MEPC_B     28
#define GLOBALS_SIZE 32

    .option norvc
    .option norelax

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
    SIG_INIT
    DCAP_FAR  a5, globals, t0

    # ---- Part A: a trap through MTCC.address = 0 ----
    # Copy the 5-word handler to address 0 through MTDC with its cursor at 0.
    DCAP_FAR  a3, vec0_code, t0
    cspecialr a4, SCR_MTDC
    csetaddr  a4, a4, zero
    li        t2, 5
1:  lw        t0, 0(a3)
    sw        t0, 0(a4)
    cincaddrimm a3, a3, 4
    cincaddrimm a4, a4, 4
    addi      t2, t2, -1
    bnez      t2, 1b
    fence.i
    cspecialr a2, SCR_MTCC             # keep the real MTCC
    csetaddr  a3, a2, zero
    cspecialw SCR_MTCC, a3
    li        a1, 0
    ebreak                             # dcsr.ebreakm = 0: breakpoint exception -> address 0
    cspecialw SCR_MTCC, a2
    li        t0, 0x5a
    CHECK_EQ  a1, t0, 1
    csrr      t0, mcause
    CHECK_EQI t0, MCAUSE_BREAKPOINT, 2, t1

    # ---- Part B: one debug session (doorbell) ----
    cspecialr a4, SCR_MTDC
    li        t0, DOORBELL
    csetaddr  a4, a4, t0
    sw        zero, 0(a4)
    li        t2, 400000
2:  lw        t0, G_FLAG(a5)
    bnez      t0, 3f
    addi      t2, t2, -1
    bnez      t2, 2b
    li        a0, 3
    j         test_end
3:
    lw        t0, G_FLAG(a5)
    CHECK_EQI t0, 1, 4, t1
    lw        t0, G_TAG(a5)
    CHECK_EQI t0, 0, 5, t1
    lw        t0, G_ADDR(a5)
    CHECK_EQI t0, 0, 6, t1
    lw        t0, G_DEXC(a5)
    CHECK_EQI t0, 1, 7, t1
    lw        t0, G_MCAUSE_A(a5)
    lw        t1, G_MCAUSE_B(a5)
    CHECK_EQ  t0, t1, 8
    lw        t0, G_MEPC_A(a5)
    lw        t1, G_MEPC_B(a5)
    CHECK_EQ  t0, t1, 9

    li        a0, 0
test_end:
    TEST_END_A0

# ---- Copied to address 0: MEPCC += 4, a1 := 0x5a, mret (uses t0 and a1 only) ----
    .balign 4
vec0_code:
    cspecialr t0, SCR_MEPCC
    cincaddrimm t0, t0, 4
    cspecialw SCR_MEPCC, t0
    li        a1, 0x5a
    mret

# ---- Any other trap ends the test ----
    .balign 4
trap_handler:
    li        a0, 10
    j         test_end

# ---- Debug handler: uses a0-a4 (the program waits in a loop on t0/t2/a5 only); t0 and t1 are
# parked in DScratchC0/1. a4 = capability to globals (MTDC-derived, so the handler does not rely
# on the debug-mode check bypass).
    .balign 4
debug_entry:
    cspecialrw t0, SCR_DSCRATCHC0, t0
    cspecialrw t1, SCR_DSCRATCHC1, t1
    DCAP_FAR  a4, globals, a3
    lw        a3, G_FLAG(a4)
    addi      a3, a3, 1
    sw        a3, G_FLAG(a4)
    # DEPCC := NULL, read it back. NULL comes from a1, not c0: CSpecialRW with cs1 = c0 does not
    # write the SCR (cspecialr is that form; cheri_insts.sail CSpecialRW `if (cs1 != zeros())`).
    # An integer write leaves the null capability with that address in the register.
    cspecialr a0, SCR_DEPCC
    li        a1, 0
    cspecialw SCR_DEPCC, a1
    cspecialr a1, SCR_DEPCC
    cgettag   a2, a1
    sw        a2, G_TAG(a4)
    cgetaddr  a2, a1
    sw        a2, G_ADDR(a4)
    # An exception in debug mode: no CSR may change.
    csrr      a2, mcause
    sw        a2, G_MCAUSE_A(a4)
    cspecialr a1, SCR_MEPCC
    cgetaddr  a2, a1
    sw        a2, G_MEPC_A(a4)
    ecall
dbg_after_exc:
    csrr      a2, mcause
    sw        a2, G_MCAUSE_B(a4)
    cspecialr a1, SCR_MEPCC
    cgetaddr  a2, a1
    sw        a2, G_MEPC_B(a4)
    cspecialw SCR_DEPCC, a0
    cspecialr t1, SCR_DSCRATCHC1
    cspecialr t0, SCR_DSCRATCHC0
    dret

# Debug exception (BOOT_ADDR + 8): count, continue after the ecall (a4 = globals, set above).
debug_exception:
    lw        a3, G_DEXC(a4)
    addi      a3, a3, 1
    sw        a3, G_DEXC(a4)
    j         dbg_after_exc

    .data
    .balign 8
globals:
    .fill GLOBALS_SIZE / 4, 4, 0
