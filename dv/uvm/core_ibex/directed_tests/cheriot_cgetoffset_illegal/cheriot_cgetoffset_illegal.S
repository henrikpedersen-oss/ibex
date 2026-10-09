# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_cgetoffset_illegal -- CGetOffset must be an illegal instruction
# =============================================================================
# The CHERIoT ISA: "the CGetOffset and CSetOffset instructions are not present"
# (cheriot-sail-upstream/archdoc/chap-cheri-riscv.tex:28), and CHERIoT-Sail has no such
# instruction (src/cheri_insts.sail:1051-1064). So 0x5B / funct7 0x7F / rs2 6 must raise an
# illegal instruction (mcause 2, mtval 0, MEPCC at the encoding) in CHERIoT mode.
#
# This is an RTL finding, not a known gap (decision 2026-10-04): the RTL decodes it
# (ibex_decoder.sv:825-826, ibex_cheriot_ex.sv:310), so this test fails until the RTL drops the
# instruction, and it has no waiver. It was slot 0 of cheriot_illegal_sweep_sail_only, whose
# GAP-CS-3 waiver would otherwise hide it.
#
# Same mechanism as cheriot_illegal_sweep (illegal_sweep.h). Codes: 2000 + k for the slot
# (k = 0: executed instead of trapping), 1999 liveness.
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
    E32 0xfe6302db                          # cgetoffset t0, ct1
sweep_end:
    .option pop

# li t0, NSLOT must come after every SLOT: .set gives a symbol its value at that point in the
# file, so before the table it is 0 and the liveness check can never pass.
.Lload_nslot:
    li      t0, NSLOT
    j       .Lnslot_loaded
