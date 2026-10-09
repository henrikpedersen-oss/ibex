# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_cdbg_ctrl_illegal -- cdbg_ctrl (0xBC4) must be an illegal CSR in CHERIoT mode
# =============================================================================
# REQ_ISA_11: in CHERIoT mode every CSR outside the CHERIoT-Sail platform raises an illegal
# instruction (mcause 2, mtval 0, MEPCC at the encoding, no other state change); the
# requirement names cdbg_ctrl. CHERIoT-Sail has no CSR 0xBC4 (sail-riscv/model/
# riscv_sys_control.sail), and the CHERIoT ISA defines none.
#
# This is an RTL finding, not a known gap (decision 2026-10-07): the RTL implemented cdbg_ctrl
# as a read/write CSR in CHERIoT mode (ibex_cs_registers.sv, u_cdbg_ctrl_csr; bit 0 made
# tag-clearing results fault instead, ibex_cheriot_ex.sv csr_dbg_tclr_fault_i). So this test
# has no waiver and fails on an RTL that still has the CSR. It was the last slot of
# cheriot_illegal_sweep_sail_only, whose GAP-CS-3 waiver would otherwise hide it.
#
# Every CSR instruction form is swept, reads and writes, register and immediate: an RTL that
# rejects only some forms (e.g. writes but not reads) still fails. rs1 is a5 (0); rd is t0 or
# x0, as illegal_sweep.h requires.
#
# Same mechanism as cheriot_illegal_sweep (illegal_sweep.h), running with the root PCC (which
# has SR, so the access is not stopped earlier by the REQ_PER_06 PCC.SR check). Codes:
# 2000 + 4 * slot + k (k = 0: executed instead of trapping; 1 mcause, 2 mtval, 3 MEPCC wrong),
# 1999 liveness. Slots, from 0:
#   0 csrr t0          1 csrw a5          2 csrrw t0, a5     3 csrrs t0, a5     4 csrrc t0, a5
#   5 csrs a5          6 csrc a5          7 csrrwi t0, 1     8 csrrsi t0, 1     9 csrrci t0, 1
#include "cheriot_dv.h"
#include "cheriot_illegal_sweep/illegal_sweep.h"
    .option norelax
    .text
    .globl main
main:
    li        a5, 0                         # ca5: integer, untagged
    SWEEP     sweep_start, sweep_end, 2000
    csrw      mscratch, a3                  # failure count, for the log
    bnez      a4, .Lret_a4
    j        .Lload_nslot             # NSLOT is final only after the table (gas .set)
.Lnslot_loaded:
    li        a0, 1999                      # liveness
    bne       s1, t0, .Lexit
    li        a0, 0
    j         .Lexit
.Lret_a4:
    mv        a0, a4
.Lexit:
    ret

    .option push
    .option norvc
    .balign 8
sweep_start:
    E32 0xbc4022f3                          # csrrs  t0,   cdbg_ctrl, zero  (csrr)
    E32 0xbc479073                          # csrrw  zero, cdbg_ctrl, a5    (csrw)
    E32 0xbc4792f3                          # csrrw  t0,   cdbg_ctrl, a5
    E32 0xbc47a2f3                          # csrrs  t0,   cdbg_ctrl, a5
    E32 0xbc47b2f3                          # csrrc  t0,   cdbg_ctrl, a5
    E32 0xbc47a073                          # csrrs  zero, cdbg_ctrl, a5    (csrs)
    E32 0xbc47b073                          # csrrc  zero, cdbg_ctrl, a5    (csrc)
    E32 0xbc40d2f3                          # csrrwi t0,   cdbg_ctrl, 1
    E32 0xbc40e2f3                          # csrrsi t0,   cdbg_ctrl, 1
    E32 0xbc40f2f3                          # csrrci t0,   cdbg_ctrl, 1
sweep_end:
    .option pop

# li t0, NSLOT must come after every SLOT: .set gives a symbol its value at that point in the
# file, so before the table it is 0 and the liveness check can never pass.
.Lload_nslot:
    li      t0, NSLOT
    j       .Lnslot_loaded
