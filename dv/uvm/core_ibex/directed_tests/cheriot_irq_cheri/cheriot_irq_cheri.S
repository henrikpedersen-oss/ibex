# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_irq_cheri -- interrupts taken while cheriot_enable_i is asserted
# =============================================================================
# REQ_INT_01, REQ_INT_02, REQ_INT_03, REQ_INT_06 (stimulus), REQ_INT_07, REQ_IBX_INT_01.
#
# Runs with +enable_cheriot_seq=1, so the pin is On from reset and the CHERIoT-Sail oracle
# steps every retired instruction and takes each interrupt from its own state
# (cheriot_sail_cosim_take_interrupt). The interrupts come from the UVM irq agent:
# rtl_test core_ibex_cheriot_irq_test (core_ibex_test_lib.sv) raises one timer, external or
# software interrupt at a time -- never NMI or fast, which CHERIoT-Sail does not model
# (legalize_mie keeps only MEIE/MTIE/MSIE) -- and checks the riscv-dv handshake below.
#
# The handler is CHERIoT-correct: MTCC is set with cspecialw, the trap stack comes from
# MScratchC (cspecialrw csp swap), every register is saved and restored with csc/clc so tags
# survive, and mret returns through MEPCC. That is exactly what riscv-dv's generated handler
# cannot do: it saves with sw through an integer kernel stack pointer, sets mtvec/mepc with
# csrw (illegal in CHERIoT mode), and writes signatures through li'd integer addresses.
#
# Handshake per interrupt (core_ibex_cheriot_irq_test::check_irq_handle):
#   CORE_STATUS HANDLING_IRQ, WRITE_CSR mstatus, mcause, mie, ... CORE_STATUS FINISHED_IRQ
# mip is deliberately not reported: the CHERIoT-Sail DPI has no mip push (only
# take_interrupt), so `csrr mip` would read the model's stale mip and mismatch.
#
# Workload, repeated until >= MIN_IRQS interrupts have been taken (fail 60 if MAX_ITER
# iterations pass first -- liveness: a run where no interrupt arrives cannot pass):
#   A  CSC/CLC bursts of tagged, bounded and sealed capabilities (interrupts during
#      CTX_WAIT_GNT1/GNT2/RESP: cheri_interrupt_cheri_cg.cp_csc_atomic_interrupt), each
#      reloaded value compared with CSEQX (address, metadata and tag).
#   B  misaligned lw/sw (WAIT_GNT_MIS/WAIT_RVALID_MIS/WAIT_RVALID_MIS_GNTS_DONE).
#   C  CJALR through an interrupt-disabling forward sentry (otype 2): MIE = 0 in the callee,
#      link otype 5, no interrupt taken during the callee, MIE = 1 again after cret. And
#      through an interrupt-enabling sentry (otype 3) called with MIE = 0: MIE = 1 inside,
#      link otype 4, MIE = 0 after cret (REQ_INT_07; CHERIoT-Sail CJALR).
#   D  register-only CSetBoundsExact / CAndPerm / CSeal / CUnseal round trip.
#   E  canary: tp and a5 still tagged and equal to their saved copies (the handler preserved
#      capability state), s1 still tagged.
#
# Checks in the handler (CHERIoT-Sail handle_trap_extension / trap_handler, REQ_INT_01):
#   90 a synchronous exception arrived (mcause[31] = 0) -- nothing here should trap
#   91 mtval != 0          92 mstatus.MIE != 0      93 mstatus.MPIE != 1   94 mstatus.MPP != M
#   95 MEPCC untagged      96 MEPCC sealed          97 MEPCC.perms != the PCC perms of the
#      interrupted code (0x1EB, the reset execution root, see cheriot_cap_perms)
#   98 MEPCC.address outside [irq_region_start, irq_region_end)
#   99 mcause not one of 0x80000003 / 0x80000007 / 0x8000000B
# Main-line codes: 1-9 setup, 10-29 workload A, 30-39 B, 40-49 C, 50-59 D/E, 60 liveness.
#
# No x16-x31 anywhere (RV32E, illegal_reg_16); every CHERI instruction comes from cheriot_dv.h
# (.insn, checked against llvm-mc).

#include "cheriot_dv.h"

#define MIN_IRQS  12
#define MAX_ITER  3000
#define MIE_MASK  0x888        /* MEIE | MTIE | MSIE */

// Offsets into `globals` (capability in a5)
#define G_IRQ_COUNT 0
#define G_SEALROOT  8
#define G_CANARY    16
#define G_MIS       24
#define G_BUF       40
#define GLOBALS_SIZE 128

    .option norvc

    DV_VECTORS unexpected_debug, unexpected_debug
_start:
    # Every symbol address is taken with LA_FAR / DCAP_FAR / SET_VEC (cheriot_dv.h): GNU `la`
    # is AUIPC-based, and AUIPCC shifts by 11, so `la` is wrong whenever %pcrel_hi != 0.
    SET_VEC   trap_handler, t1, t0
    SIG_INIT
    # a5 := globals capability, bounded to the globals block.
    DCAP_FAR  a5, globals, t0
    li        t0, GLOBALS_SIZE
    csetboundsexact a5, a5, t0
    cgettag   t0, a5
    CHECK_EQI t0, 1, 1, t1
    # Keep the reset sealing root (MScratchC) before MScratchC becomes the trap stack.
    cspecialr t1, SCR_MSCRATCHC
    cgettag   t0, t1
    CHECK_EQI t0, 1, 2, t2
    csc       t1, a5, G_SEALROOT
    # MScratchC := [trap_stack, +512), cursor at the top (INIT_TRAP_STACK with DCAP_FAR).
    DCAP_FAR  t1, trap_stack, t0
    li        t0, 512
    csetboundsexact t1, t1, t0
    cincaddrimm t1, t1, 512
    cspecialw SCR_MSCRATCHC, t1
    # mstatus.MPP := M (CHERIoT is M-mode only), mie := MEIE|MTIE|MSIE.
    li        t0, 0x1800
    csrs      mstatus, t0
    li        t0, MIE_MASK
    csrw      mie, t0
    # Canary capability in tp, a copy in memory.
    cmove     tp, a5
    cincaddrimm tp, tp, G_BUF
    li        t0, 64
    csetboundsexact tp, tp, t0
    csc       tp, a5, G_CANARY
    li        s0, 0                  # iteration counter
    # Core setup handshake (core_ibex_debug_intr_basic_test::wait_for_core_setup).
    SIG_CSR   0x300                  # mstatus
    SIG_CSR   0x304                  # mie
    SIG_STATUS ST_INITIALIZED
    j         irq_region_start

# ---- Everything interruptible lives between these labels (handler check 98): MIE is set by the
# ---- first instruction here and cleared by the last one, so no interrupt can be taken outside.
    .text
    .balign 4
irq_region_start:
    csrsi     mstatus, 8
main_loop:
    # ── A: CSC/CLC bursts ──────────────────────────────────────────────────────
    # a1 := bounded data capability over buf[0..32)
    cmove     a1, a5
    cincaddrimm a1, a1, G_BUF
    li        t0, 32
    csetboundsexact a1, a1, t0
    # a2 := a1 sealed with data otype 9
    clc       a3, a5, G_SEALROOT
    li        t0, 9
    csetaddr  a3, a3, t0
    cseal     a2, a1, a3
    cgettype  t0, a2
    CHECK_EQI t0, 9, 10, t1
    # a4 := PCC-derived code capability
    auipc     a4, 0
    csc       a1, a5, G_BUF+0
    csc       a2, a5, G_BUF+8
    csc       a4, a5, G_BUF+16
    csc       a5, a5, G_BUF+24
    csc       a2, a5, G_BUF+32
    csc       a1, a5, G_BUF+40
    clc       a0, a5, G_BUF+0
    cseqx     t0, a0, a1
    CHECK_EQI t0, 1, 11, t1
    clc       a0, a5, G_BUF+8
    cseqx     t0, a0, a2
    CHECK_EQI t0, 1, 12, t1
    clc       a0, a5, G_BUF+16
    cseqx     t0, a0, a4
    CHECK_EQI t0, 1, 13, t1
    clc       a0, a5, G_BUF+24
    cseqx     t0, a0, a5
    CHECK_EQI t0, 1, 14, t1
    clc       a0, a5, G_BUF+32
    cseqx     t0, a0, a2
    CHECK_EQI t0, 1, 15, t1
    clc       a0, a5, G_BUF+40
    cseqx     t0, a0, a1
    CHECK_EQI t0, 1, 16, t1
    # Back-to-back store/load pairs with no check in between.
    csc       a4, a5, G_BUF+48
    clc       a3, a5, G_BUF+48
    csc       a3, a5, G_BUF+56
    clc       a0, a5, G_BUF+56
    cseqx     t0, a0, a4
    CHECK_EQI t0, 1, 17, t1
    # An integer store over half a capability clears its tag (REQ_TAG_*), interrupts or not.
    sw        zero, G_BUF+56(a5)
    clc       a0, a5, G_BUF+56
    cgettag   t0, a0
    CHECK_EQI t0, 0, 18, t1

    # ── B: misaligned integer accesses ─────────────────────────────────────────
    li        t0, 0x33221100
    sw        t0, G_MIS+0(a5)
    li        t0, 0x77665544
    sw        t0, G_MIS+4(a5)
    lw        t1, G_MIS+1(a5)
    CHECK_EQI t1, 0x44332211, 30, t2
    lw        t1, G_MIS+3(a5)
    CHECK_EQI t1, 0x66554433, 31, t2
    lh        t1, G_MIS+3(a5)
    CHECK_EQI t1, 0x4433, 32, t2
    li        t0, 0xA5B6C7D8
    sw        t0, G_MIS+2(a5)
    lw        t1, G_MIS+0(a5)
    CHECK_EQI t1, 0xC7D81100, 33, t2
    lw        t1, G_MIS+4(a5)
    CHECK_EQI t1, 0x7766A5B6, 34, t2
    sh        t0, G_MIS+7(a5)
    lw        t1, G_MIS+4(a5)
    CHECK_EQI t1, 0xD866A5B6, 35, t2
    lbu       t1, G_MIS+8(a5)
    CHECK_EQI t1, 0xC7, 36, t2

    # ── C: sentries ────────────────────────────────────────────────────────────
    # Interrupt-disabling forward sentry (otype 2), called with MIE = 1.
    auipc     a0, 0
    LA_FAR    t0, callee_id, t1
    csetaddr  a0, a0, t0
    clc       a3, a5, G_SEALROOT
    li        t0, 2
    csetaddr  a3, a3, t0
    cseal     a0, a0, a3
    cgettype  t0, a0
    CHECK_EQI t0, 2, 40, t1
    jalr      ra, 0(a0)
    csrr      t0, mstatus
    andi      t0, t0, 8
    CHECK_EQI t0, 8, 41, t1
    # Interrupt-enabling forward sentry (otype 3), called with MIE = 0.
    auipc     a0, 0
    LA_FAR    t0, callee_ie, t1
    csetaddr  a0, a0, t0
    clc       a3, a5, G_SEALROOT
    li        t0, 3
    csetaddr  a3, a3, t0
    cseal     a0, a0, a3
    csrci     mstatus, 8
    jalr      ra, 0(a0)
    csrr      t0, mstatus
    andi      t0, t0, 8
    CHECK_EQI t0, 0, 42, t1
    csrsi     mstatus, 8

    # ── D: register-only CHERI operations ──────────────────────────────────────
    cmove     a1, a5
    cincaddrimm a1, a1, G_BUF+64
    li        t0, 16
    csetboundsexact a1, a1, t0
    cgetlen   t0, a1
    CHECK_EQI t0, 16, 50, t1
    # CAndPerm is monotonic: the result's permissions are a subset of both the source's and the
    # mask. The compressed permission format may drop more than the mask asks, so equality with
    # perms & mask is deliberately not required (CHERIoT-Sail CAndPerm).
    li        t2, 0x7D
    candperm  a2, a1, t2
    cgettag   t0, a2
    CHECK_EQI t0, 1, 57, t1
    cgetperm  t0, a2
    cgetperm  t1, a1
    not       t1, t1
    and       t1, t1, t0
    CHECK_EQI t1, 0, 51, a0
    not       t1, t2
    and       t1, t1, t0
    CHECK_EQI t1, 0, 58, a0
    clc       a3, a5, G_SEALROOT
    li        t0, 11
    csetaddr  a3, a3, t0
    cseal     a4, a2, a3
    cgettype  t0, a4
    CHECK_EQI t0, 11, 52, t1
    cunseal   a4, a4, a3
    cseqx     t0, a4, a2
    CHECK_EQI t0, 1, 53, t1

    # ── E: canaries ────────────────────────────────────────────────────────────
    clc       a0, a5, G_CANARY
    cseqx     t0, a0, tp
    CHECK_EQI t0, 1, 54, t1
    cgettag   t0, a5
    CHECK_EQI t0, 1, 55, t1
    cgettag   t0, s1
    CHECK_EQI t0, 1, 56, t1

    # ── loop control ───────────────────────────────────────────────────────────
    addi      s0, s0, 1
    lw        t0, G_IRQ_COUNT(a5)
    li        t1, MIN_IRQS
    bgeu      t0, t1, 1f
    li        t1, MAX_ITER
    bltu      s0, t1, main_loop
    li        a0, 60                  # interrupts never (or too rarely) arrived
    j         test_end
1:  j         all_done

# MIE = 0 throughout: no interrupt may be taken here (irq_count constant).
callee_id:
    csrr      t0, mstatus
    andi      t0, t0, 8
    CHECK_EQI t0, 0, 43, t1
    cgettype  t0, ra
    CHECK_EQI t0, 5, 44, t1           # otype_sentry_bie: MIE was 1 at the call
    lw        t2, G_IRQ_COUNT(a5)
    li        t1, 150
2:  addi      t1, t1, -1
    bnez      t1, 2b
    lw        t0, G_IRQ_COUNT(a5)
    CHECK_EQ  t0, t2, 45
    ret

# MIE = 1 inside: interrupts may be taken here and must return here.
callee_ie:
    csrr      t0, mstatus
    andi      t0, t0, 8
    CHECK_EQI t0, 8, 46, t1
    cgettype  t0, ra
    CHECK_EQI t0, 4, 47, t1           # otype_sentry_bid: MIE was 0 at the call
    li        t1, 150
2:  addi      t1, t1, -1
    bnez      t1, 2b
    ret

all_done:
    li        a0, 0
test_end:                             # also reached with MIE = 1 from a failed check
    csrci     mstatus, 8
irq_region_end:
    TEST_END_A0

unexpected_debug:
    li        a0, 9
    j         test_end

# ---- Trap handler (MTCC) -------------------------------------------------------------------
    .balign 4
trap_handler:
    SAVE_CTX
    csrr      t0, mcause
    bltz      t0, 1f
    li        a0, 90                  # synchronous exception: nothing in this test traps
    j         test_end
1:
    SIG_STATUS ST_HANDLING_IRQ
    SIG_CSR   0x300                   # mstatus
    SIG_CSR   0x342                   # mcause
    SIG_CSR   0x304                   # mie
    csrr      t1, mtval
    CHECK_EQI t1, 0, 91, t2
    csrr      t1, mstatus
    andi      t2, t1, 8
    CHECK_EQI t2, 0, 92, t0
    andi      t2, t1, 0x80
    CHECK_EQI t2, 0x80, 93, t0
    li        t0, 0x1800
    and       t2, t1, t0
    CHECK_EQ  t2, t0, 94
    cspecialr a1, SCR_MEPCC
    cgettag   t1, a1
    CHECK_EQI t1, 1, 95, t2
    cgettype  t1, a1
    CHECK_EQI t1, 0, 96, t2
    cgetperm  t1, a1
    CHECK_EQI t1, 0x1EB, 97, t2
    cgetaddr  t1, a1
    LA_FAR    t2, irq_region_start, t0
    bltu      t1, t2, 2f
    LA_FAR    t2, irq_region_end, t0
    bltu      t1, t2, 3f
2:  li        a0, 98
    j         test_end
3:  csrr      t1, mcause
    li        t2, 0x80000003
    beq       t1, t2, 4f
    li        t2, 0x80000007
    beq       t1, t2, 4f
    li        t2, 0x8000000B
    beq       t1, t2, 4f
    li        a0, 99
    j         test_end
4:  DCAP_FAR  a2, globals, t2
    lw        t1, G_IRQ_COUNT(a2)
    addi      t1, t1, 1
    sw        t1, G_IRQ_COUNT(a2)
    SIG_STATUS ST_FINISHED_IRQ
    # The interrupt is level-sensitive: give the testbench time to drop the line it raised
    # (core_ibex_debug_intr_basic_test::send_irq_stimulus_end) before mret re-enables MIE.
    li        t1, 64
5:  addi      t1, t1, -1
    bnez      t1, 5b
    RESTORE_CTX
    mret

# ---- Data ---------------------------------------------------------------------------------

    .data
    .balign 512
trap_stack:
    .fill 64, 8, 0
    .balign 8
globals:
    .fill GLOBALS_SIZE / 4, 4, 0
