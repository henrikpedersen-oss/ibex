# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_mshwm -- stack high water mark CSRs (mshwm 0xBC1, mshwmb 0xBC2)
# =============================================================================
# Expected behaviour, CHERIoT ISA (archdoc/chap-cheri-riscv.tex, section "Stack high
# water mark", lines 773-791) and CHERIoT-Sail (dv/cosim/cheriot-sail-model/src):
#   - Both CSRs have bits [3:0] hardwired to 0; a write is legalised by rounding down
#     (ISA 778-779; cheri_sys_regs.sail:98-100 legalize_mshwm, 118-119 ext_write_CSR,
#     applied to the CSRRW/CSRRS/CSRRC result, sail-riscv riscv_insts_zicsr.sail:231-238).
#   - On every memory write, the address of the write (its lowest byte) is compared:
#     mshwmb <= addr < mshwm sets mshwm := addr rounded down to 16 bytes (ISA 781-782;
#     cheri_addr_checks.sail:222-231 ext_check_phys_mem_write, called once per store
#     with the store's start address, for every store width and for CSC). Loads never
#     update it. A store that faults before reaching memory (a CHERI check) does not
#     write and so does not update it. Only the start address counts: a misaligned
#     store starting below mshwmb leaves mshwm unchanged even though it writes bytes
#     above mshwmb (ISA 787-791).
#   - Access needs PCC.SR. ISA text line 777 says that without SR an access is a
#     Reserved Instruction exception, but the same document's general rule (lines
#     127-129) and CHERIoT-Sail raise an SR violation: ext_check_CSR
#     (cheri_addr_checks.sail:241-257) allows only the counter reads without SR, and
#     ext_check_CSR_fail raises capcause 0x18 against PCC: mcause 28, mtval 0x418.
#     This test follows Sail; the RTL raises the same (ibex_controller.sv
#     csr_cheriot_asr_err). With cheriot_enable_i Off the CSRs do not exist (that half
#     is in cheriot_illegal_rv_mode).
#   - Reset value: not stated by the ISA. The Sail C model initialises both to 0
#     (generated_definitions/c/riscv_rvfi_model_RV32.c, zMSHWM = 0 in model init) and
#     the RTL resets them to 0 (ibex_cs_registers.sv u_mshwm_csr/u_mshwmb_csr
#     ResetValue '0). crt_cheriot.S performs no store before main, and with both at 0
#     the window is empty, so the values are still the reset values when main reads them.
#
# Window used by the update checks: B = win (64-aligned), mshwmb = B, mshwm = B + 0x100
# unless a check says otherwise. Every store goes through ca1 = MTDC @ B.
#
# Checks and failure codes (main returns 0 or the first failing code)
#   1/2   reset: mshwm = 0, mshwmb = 0
#   Legalisation
#   3   csrw mshwmb, 0x8000123F       -> 0x80001230
#   4   csrw mshwm, 0xFFFFFFFF        -> 0xFFFFFFF0
#   5/6 csrrs t, mshwm, (0xF)         -> rd 0xFFFFFFF0, mshwm 0xFFFFFFF0
#   7   csrrc mshwm, (0x10)           -> 0xFFFFFFE0
#   8/9 csrrwi t, mshwm, 0x1F         -> rd 0xFFFFFFE0, mshwm 0x10
#   10  csrrsi mshwmb, 7              -> 0x80001230 (unchanged)
#   11  csrrci mshwmb, 0x10           -> 0x80001220
#   12  csrw mshwmb, 0xF              -> 0
#   13  csrrw t, mshwmb, 0x5A5A5A5A    -> rd 0, mshwmb 0x5A5A5A50 (14)
#   Update rule (mshwm read back after each access)
#   21  sw   at B+0x84                -> B+0x80
#   22  sw   at B+0x90 (>= mshwm)     -> unchanged B+0x80
#   23  sb   at B+0x7F                -> B+0x70
#   24  sh   at B+0x62                -> B+0x60
#   25  csc  (untagged) at B+0x58     -> B+0x50
#   26  csc  (tagged) at B+0x48       -> B+0x40
#   27  sw   at B-4 (below mshwmb)    -> unchanged B+0x40
#   28  lw   at B+0x10                -> unchanged
#   29  clc  at B+0x10                -> unchanged
#   30  sb   at B+0x40 (= mshwm)      -> unchanged
#   31  sb   at B+0x3F (= mshwm - 1)  -> B+0x30
#   32  sw   at B (= mshwmb)          -> B
#   33  sw   at B again (window now empty) -> B
#   34  c.sw at B+0x24 (mshwm reset to B+0x100) -> B+0x20
#   35  c.csc at B+0x18               -> B+0x10
#   Every store kind on both sides of the window [B+0x40, B+0x100), mshwm stays B+0x100:
#   64  sb at B+0x10, 65 sh at B+0x20, 66 csc at B+0x30 (below mshwmb)
#   67  sh at B+0x100, 68 csc at B+0x108 (at/above mshwm)
#   Faulting store outside the window [B+0x40, B+0x100) (CHERI bounds violation, capcause
#   0x01 against ca4 = [B+0x80, B+0x90), mtval 0x1C1), each: no trap / mcause / mtval /
#   MEPCC.address / mshwm changed:
#   70-74  sw at B+0x30 (below mshwmb)       75-79  sw at B+0x100 (at mshwm)
#   36  inverted window (mshwmb = B+0x80 > mshwm = B+0x40), sw at B+0x60 -> unchanged
#   37  misaligned sw at B+0x3E with mshwmb = B+0x40 (starts below, writes into the
#       window)                       -> unchanged B+0x100 (ISA 787-791, Sail: start
#       address only). Everything from here on runs only if 37 passes; 64-68 and 70-79
#       are placed before it so they do not depend on the misaligned-store split.
#   38  misaligned sw at B+0x7E       -> B+0x70
#   39  sw at B+0xF0 from a PCC without SR (the update is not SR-gated) -> B+0xF0
#   Faulting store inside the window [B, B+0x100), the same ca4:
#   40 no trap, 41 mcause != 28, 42 mtval != 0x1C1 (c14), 43 MEPCC.address, 44 mshwm changed
#   SR gating (from a PCC without SR, 0x16B; Sail ext_check_CSR -> mtval 0x418):
#   50-53  csrr t1, mshwm:      no trap / mcause / mtval / MEPCC.address; 54 rd written
#   55-58  csrw mshwmb, t2:     no trap / mcause / mtval / MEPCC.address; 59 mshwmb changed
#   60-63  csrrs t1, mshwm, x0 (a read): no trap / mcause / mtval / MEPCC.address
#   80-83  csrw mshwm, t2:      no trap / mcause / mtval / MEPCC.address; 84 mshwm changed
#   85-88  csrr t1, mshwmb:     no trap / mcause / mtval / MEPCC.address; 89 rd written
#   250 unexpected trap;  251 liveness (fewer checks executed than assembled)
#
# Register use: x0-x15 only; s1 check count; t0/t1/t2/s0 integer scratch; ca1 store
# authority MTDC @ B; ca2 store data; ca0, ca3-ca5 capability scratch. No cget* result
# goes into a live capability register (aN and caN are the same register).

#include "cheriot_dv.h"

    .option norelax

#define CSR_MSHWM  0xBC1
#define CSR_MSHWMB 0xBC2

# mshwm == B + \off  (s0 = B)
.macro EXPECT_HWM off, code
    csrr      t0, CSR_MSHWM
    li        t1, \off
    add       t1, t1, s0
    EXPECT_EQ t0, t1, \code
.endm

# mshwmb := B + \blo, mshwm := B + \hi
.macro WINDOW blo, hi
    li        t0, \blo
    add       t0, t0, s0
    csrw      CSR_MSHWMB, t0
    li        t0, \hi
    add       t0, t0, s0
    csrw      CSR_MSHWM, t0
.endm

# Jump to \label running from PCC = MTCC without SR (ca0). Clobbers t0, ca5.
.macro ENTER_NOSR label
    LA_FAR    t0, \label, a5
    csetaddr  a5, a0, t0
    jalr      zero, 0(a5)
.endm


# After a deliberate CHERI fault at \pc: mcause 28, mtval, MEPCC.address.
.macro CHERI_FAULT mtval, pc, c_cause, c_tval, c_pc
    csrr      t1, mcause
    EXPECT_EQI t1, 28, \c_cause
    csrr      t1, mtval
    EXPECT_EQI t1, \mtval, \c_tval
    cspecialr a3, SCR_MEPCC
    cgetaddr  t1, a3
    LA_FAR    t0, \pc, a3
    EXPECT_EQ t1, t0, \c_pc
.endm

    .text
    .globl main
main:
    li        s1, 0
    # ── 1-2: reset values (first CSR access of the test) ─────────────────────
    csrr      t0, CSR_MSHWM
    EXPECT_EQ t0, zero, 1
    csrr      t0, CSR_MSHWMB
    EXPECT_EQ t0, zero, 2
    SET_VEC   .Lunexpected, t0, t1

    # ── 3-14: legalisation ───────────────────────────────────────────────────
    li        t0, 0x8000123F
    csrw      CSR_MSHWMB, t0
    csrr      t0, CSR_MSHWMB
    EXPECT_EQI t0, 0x80001230, 3
    li        t0, 0xFFFFFFFF
    csrw      CSR_MSHWM, t0
    csrr      t0, CSR_MSHWM
    EXPECT_EQI t0, 0xFFFFFFF0, 4
    li        t1, 0xF
    csrrs     t0, CSR_MSHWM, t1
    EXPECT_EQI t0, 0xFFFFFFF0, 5
    csrr      t0, CSR_MSHWM
    EXPECT_EQI t0, 0xFFFFFFF0, 6
    li        t1, 0x10
    csrrc     zero, CSR_MSHWM, t1
    csrr      t0, CSR_MSHWM
    EXPECT_EQI t0, 0xFFFFFFE0, 7
    csrrwi    t0, CSR_MSHWM, 0x1F
    EXPECT_EQI t0, 0xFFFFFFE0, 8
    csrr      t0, CSR_MSHWM
    EXPECT_EQI t0, 0x10, 9
    csrrsi    zero, CSR_MSHWMB, 7
    csrr      t0, CSR_MSHWMB
    EXPECT_EQI t0, 0x80001230, 10
    csrrci    zero, CSR_MSHWMB, 0x10
    csrr      t0, CSR_MSHWMB
    EXPECT_EQI t0, 0x80001220, 11
    li        t0, 0xF
    csrw      CSR_MSHWMB, t0
    csrr      t0, CSR_MSHWMB
    EXPECT_EQ t0, zero, 12
    li        t1, 0x5A5A5A5A
    csrrw     t0, CSR_MSHWMB, t1
    EXPECT_EQ t0, zero, 13
    csrr      t0, CSR_MSHWMB
    EXPECT_EQI t0, 0x5A5A5A50, 14

    # ── 21-35: update rule (64-68 and 70-79 follow, then 36-39) ─────────────
    LA_FAR    s0, win, t0                   # s0 = B
    cspecialr a1, SCR_MTDC
    csetaddr  a1, a1, s0                    # ca1 = MTDC @ B: store authority
    li        a2, 0x11223344                # ca2 = integer store data (untagged)
    WINDOW    0, 0x100
    sw        a2, 0x84(a1)
    EXPECT_HWM 0x80, 21
    sw        a2, 0x90(a1)
    EXPECT_HWM 0x80, 22
    sb        a2, 0x7F(a1)
    EXPECT_HWM 0x70, 23
    sh        a2, 0x62(a1)
    EXPECT_HWM 0x60, 24
    csc       a2, a1, 0x58
    EXPECT_HWM 0x50, 25
    csc       a1, a1, 0x48                  # tagged capability store
    EXPECT_HWM 0x40, 26
    sw        a2, -4(a1)
    EXPECT_HWM 0x40, 27
    lw        t2, 0x10(a1)
    EXPECT_HWM 0x40, 28
    clc       a3, a1, 0x10
    EXPECT_HWM 0x40, 29
    sb        a2, 0x40(a1)
    EXPECT_HWM 0x40, 30
    sb        a2, 0x3F(a1)
    EXPECT_HWM 0x30, 31
    sw        a2, 0(a1)
    EXPECT_HWM 0, 32
    sw        a2, 0(a1)
    EXPECT_HWM 0, 33
    WINDOW    0, 0x100
    c.sw      a2, 0x24(a1)
    EXPECT_HWM 0x20, 34
    .half     0xE990                        # c.csc ca2, 16(ca1) -> B+0x10 (llvm-mc)
    EXPECT_HWM 0x10, 35

    # 64-68 and 70-79 run here, ahead of 36/37: they do not depend on the misaligned-store
    # split that 37 checks, so they still run on an RTL where 37 fails. Each block sets its
    # own window, and 36/37 set theirs again below, so the order does not change any result.

    # ── 64-68: byte, half and capability stores below and at/above the window ─
    WINDOW    0x40, 0x100
    sb        a2, 0x10(a1)
    EXPECT_HWM 0x100, 64
    sh        a2, 0x20(a1)
    EXPECT_HWM 0x100, 65
    csc       a2, a1, 0x30
    EXPECT_HWM 0x100, 66
    sh        a2, 0x100(a1)
    EXPECT_HWM 0x100, 67
    csc       a2, a1, 0x108
    EXPECT_HWM 0x100, 68

    # ── 70-79: a store that faults outside the window does not update ────────
    addi      t0, s0, 0x80
    csetaddr  a4, a1, t0
    li        t0, 0x10
    csetboundsexact a4, a4, t0              # ca4 = [B+0x80, B+0x90); kept for 40-44
    WINDOW    0x40, 0x100
    SET_VEC   .Ltrap_stb, t0, t1
.Lfault_stb:
    sw        a2, -0x50(a4)                 # B+0x30: below mshwmb and ca4's base
    li        a0, 70
    j         .Lexit
    .balign 4
.Ltrap_stb:
    SET_VEC   .Lunexpected, t0, t1
    CHERI_FAULT 0x1C1, .Lfault_stb, 71, 72, 73
    EXPECT_HWM 0x100, 74
    RESUME    .Lnext_stb, a3, t0
.Lnext_stb:
    SET_VEC   .Ltrap_sta, t0, t1
.Lfault_sta:
    sw        a2, 0x80(a4)                  # B+0x100: at mshwm, past ca4's top
    li        a0, 75
    j         .Lexit
    .balign 4
.Ltrap_sta:
    SET_VEC   .Lunexpected, t0, t1
    CHERI_FAULT 0x1C1, .Lfault_sta, 76, 77, 78
    EXPECT_HWM 0x100, 79
    RESUME    .Lnext_sta, a3, t0
.Lnext_sta:

    # ── 36-38: inverted window, misaligned stores ────────────────────────────
    WINDOW    0x80, 0x40                    # inverted
    sw        a2, 0x60(a1)
    EXPECT_HWM 0x40, 36
    WINDOW    0x40, 0x100
    sw        a2, 0x3E(a1)                  # misaligned, starts below mshwmb
    EXPECT_HWM 0x100, 37
    sw        a2, 0x7E(a1)                  # misaligned, starts inside
    EXPECT_HWM 0x70, 38

    # ── 39: a store from a PCC without SR still updates mshwm ────────────────
    cspecialr a0, SCR_MTCC
    li        t0, 0xF7F                     # clear SR (bit 7)
    candperm  a0, a0, t0                    # ca0 = MTCC without SR (0x16B)
    WINDOW    0, 0x100
    LA_FAR    t0, .Lnosr_store_back, a3
    cspecialr a3, SCR_MTCC
    csetaddr  a3, a3, t0                    # ca3 = way back, with SR (built before leaving SR)
    ENTER_NOSR .Lnosr_store
.Lnosr_store:
    sw        a2, 0xF4(a1)
    jalr      zero, 0(a3)
.Lnosr_store_back:
    EXPECT_HWM 0xF0, 39

    # ── 40-44: a store that faults does not update (ca4 built before 70) ─────
    WINDOW    0, 0x100
    SET_VEC   .Ltrap_st, t0, t1
.Lfault_st:
    sw        a2, -0x10(a4)                 # B+0x70: below ca4's base
    li        a0, 40
    j         .Lexit
    .balign 4
.Ltrap_st:
    SET_VEC   .Lunexpected, t0, t1
    CHERI_FAULT 0x1C1, .Lfault_st, 41, 42, 43
    EXPECT_HWM 0x100, 44
    RESUME    .Lnext_st, a3, t0
.Lnext_st:

    # ── 50-63: CSR access without SR ─────────────────────────────────────────
    li        t1, 0xDEADBEEF
    SET_VEC   .Ltrap_r, t0, t2
    ENTER_NOSR .Lfault_r
.Lfault_r:
    csrr      t1, CSR_MSHWM
    li        a0, 50
    j         .Lexit
    .balign 4
.Ltrap_r:
    SET_VEC   .Lunexpected, t0, t2
    mv        s0, t1                        # rd as it was after the fault
    CHERI_FAULT 0x418, .Lfault_r, 51, 52, 53
    EXPECT_EQI s0, 0xDEADBEEF, 54
    RESUME    .Lnext_r, a3, t0
.Lnext_r:
    csrr      s0, CSR_MSHWMB                # value before the denied write
    li        t2, 0x80002000
    SET_VEC   .Ltrap_w, t0, t1
    ENTER_NOSR .Lfault_w
.Lfault_w:
    csrw      CSR_MSHWMB, t2
    li        a0, 55
    j         .Lexit
    .balign 4
.Ltrap_w:
    SET_VEC   .Lunexpected, t0, t1
    CHERI_FAULT 0x418, .Lfault_w, 56, 57, 58
    csrr      t0, CSR_MSHWMB
    EXPECT_EQ t0, s0, 59
    RESUME    .Lnext_w, a3, t0
.Lnext_w:
    SET_VEC   .Ltrap_rs, t0, t1
    ENTER_NOSR .Lfault_rs
.Lfault_rs:
    csrrs     t1, CSR_MSHWM, zero
    li        a0, 60
    j         .Lexit
    .balign 4
.Ltrap_rs:
    SET_VEC   .Lunexpected, t0, t1
    CHERI_FAULT 0x418, .Lfault_rs, 61, 62, 63
    RESUME    .Lnext_rs, a3, t0
.Lnext_rs:
    csrr      s0, CSR_MSHWM                 # value before the denied write
    li        t2, 0x80003000
    SET_VEC   .Ltrap_wm, t0, t1
    ENTER_NOSR .Lfault_wm
.Lfault_wm:
    csrw      CSR_MSHWM, t2
    li        a0, 80
    j         .Lexit
    .balign 4
.Ltrap_wm:
    SET_VEC   .Lunexpected, t0, t1
    CHERI_FAULT 0x418, .Lfault_wm, 81, 82, 83
    csrr      t0, CSR_MSHWM
    EXPECT_EQ t0, s0, 84
    RESUME    .Lnext_wm, a3, t0
.Lnext_wm:
    li        t1, 0xDEADBEEF
    SET_VEC   .Ltrap_rb, t0, t2
    ENTER_NOSR .Lfault_rb
.Lfault_rb:
    csrr      t1, CSR_MSHWMB
    li        a0, 85
    j         .Lexit
    .balign 4
.Ltrap_rb:
    SET_VEC   .Lunexpected, t0, t2
    mv        s0, t1                        # rd as it was after the fault
    CHERI_FAULT 0x418, .Lfault_rb, 86, 87, 88
    EXPECT_EQI s0, 0xDEADBEEF, 89
    RESUME    .Lnext_rb, a3, t0
.Lnext_rb:

    CHECK_LIVENESS 251
    li        a0, 0
    j         .Lexit

    .balign 4
.Lunexpected:
    li        a0, 250
.Lexit:                                     # may run without SR: no CSR access here
    ret

    .data
    .balign 256
win_below:
    .space  64
win:
    .space  512                             # checks 67/68 store at B+0x100..B+0x10F
