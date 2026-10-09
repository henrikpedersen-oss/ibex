# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_illegal_sweep_sail_only -- encodings CHERIoT-Sail rejects and the RTL
#                                          executes, in CHERIoT mode
# =============================================================================
# Same mechanism as cheriot_illegal_sweep (illegal_sweep.h): every encoding below must
# raise an illegal instruction (mcause 2, mtval 0, MEPCC at the encoding), because
# CHERIoT-Sail, the reference model, has no instruction or CSR there. On the current
# RTL each one executes instead, so this test is expected to fail, with the code
# 2000 + 4 * index + k of the first divergence (k = 0: executed) and the number of
# failed checks in mscratch; every slot is still run, so the log shows all of them.
# The test is to the model; each class is reported as an RTL/Sail disagreement.
# Paths: Sail = dv/cosim/cheriot-sail-model, RTL = rtl/.
#
# Classes, in table order (slot index i = the i-th E32/E16 line, from 0). These are the
# GAP-CS-3 items, waived by signature in waivers/known_gaps.yaml. CGetOffset is not here: the
# ISA says it is not present, so it is an RTL finding with its own, unwaived test
# (cheriot_cgetoffset_illegal). It was slot 0, so every code below is 4 lower than before
# 2026-10-04. cdbg_ctrl is not here either: REQ_ISA_11 names it, so it is an RTL finding with its
# own test (cheriot_cdbg_ctrl_illegal, 2026-10-07); it was the last slot, so no code moved.
#   Zcb (c.lbu, c.lhu, c.lh, c.sb, c.sh, c.zext.b, c.sext.b, c.zext.h, c.sext.h,
#     c.not, c.mul): Sail has no Zcb (no riscv_insts_zcb.sail in the Makefile's
#     SAIL_DEFAULT_INST), so each is C_ILLEGAL; the opentitan configuration has
#     RV32ZC = RV32ZcaZcbZcmp and ibex_compressed_decoder.sv:266-321, 462-509 accepts
#     them with cheriot_enable_i On (Zcmp is rejected in CHERIoT mode, cdec:615-620,
#     Zcb is not). Operands are ca5 (an integer, so an executed load/store takes a tag
#     fault rather than touching memory).
#   Draft bit-manipulation instructions outside the ratified Zba/Zbb/Zbc/Zbs/Zbkb/Zbkx that
#     Sail implements: sloi, shfli, crc32[c].b/h/w, fsri, sroi, grevi, gorci, unshfli
#     (immediates other than the zip/unzip/rev8/brev8/orc.b aliases), cmix, cmov, fsl, fsr,
#     packu, bfp, grev, gorc, shfl, unshfl, xperm.h, slo, sro. Since lowRISC/ibex#2459 the RTL
#     implements only the ratified set (RV32BOTEarlGrey is gone), so these are illegal there
#     too and pass; they stay in the table so that none comes back. rd = t0.
#   CSRs that exist in the RTL but not in the CHERIoT-Sail platform: mconfigptr,
#     mcounteren, menvcfg, menvcfgh, mhpmevent3, mhpmcounter3, mhpmcounter3h,
#     hpmcounter3, hpmcounter3h, tdata1-3, mcontext, mscontext, scontext, cpuctrlsts,
#     secureseed (sail-riscv/model/riscv_sys_control.sail:17-99 with no U/S mode, no HPM
#     counters, only tselect of the trigger CSRs; ibex_cs_registers.sv). Several are implementation-defined CSRs the
#     model's platform simply omits; whether the RTL or the model's configuration should
#     change is a decision, not something this test can settle. Reads, rd = t0.
#   1999  liveness: fewer slots processed than assembled (NSLOT)
#
# Encodings generated from the field layouts and cross-checked with llvm-mc (riscv32
# with Zcb/Zbb/Zbkb, and riscv32cheriot, which rejects all of them).

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
    # Zcb, operands ca5
    E16 0x839c                              # c.lbu a5, 0(a5)
    E16 0x879c                              # c.lhu a5, 0(a5)
    E16 0x87dc                              # c.lh a5, 0(a5)
    E16 0x8b9c                              # c.sb a5, 0(a5)
    E16 0x8f9c                              # c.sh a5, 0(a5)
    E16 0x9fe1                              # c.zext.b a5
    E16 0x9fe5                              # c.sext.b a5
    E16 0x9fe9                              # c.zext.h a5
    E16 0x9fed                              # c.sext.h a5
    E16 0x9ff5                              # c.not a5
    E16 0x9fdd                              # c.mul a5, a5
    # draft bit-manipulation, rd t0, rs1 t1
    E32 0x20131293                          # sloi t0, t1, 1
    E32 0x08131293                          # shfli t0, t1, 1
    E32 0x61031293                          # crc32.b
    E32 0x61131293                          # crc32.h
    E32 0x61231293                          # crc32.w
    E32 0x61831293                          # crc32c.b
    E32 0x61931293                          # crc32c.h
    E32 0x61a31293                          # crc32c.w
    E32 0x04135293                          # fsri t0, t1, x0, 1
    E32 0x20135293                          # sroi t0, t1, 1
    E32 0x68135293                          # grevi t0, t1, 1
    E32 0x28135293                          # gorci t0, t1, 1
    E32 0x08135293                          # unshfli t0, t1, 1
    E32 0x067312b3                          # cmix t0, t1, t2, x0
    E32 0x067352b3                          # cmov t0, t1, t2, x0
    E32 0x047312b3                          # fsl t0, t1, t2, x0
    E32 0x047352b3                          # fsr t0, t1, t2, x0
    E32 0x487342b3                          # packu
    E32 0x487372b3                          # bfp
    E32 0x687352b3                          # grev
    E32 0x287352b3                          # gorc
    E32 0x087312b3                          # shfl
    E32 0x087352b3                          # unshfl
    E32 0x287362b3                          # xperm.h
    E32 0x207312b3                          # slo
    E32 0x207352b3                          # sro
    # CSRs present in the RTL, absent from the CHERIoT-Sail platform (csrr t0, csr)
    E32 0xf15022f3                          # mconfigptr
    E32 0x306022f3                          # mcounteren
    E32 0x30a022f3                          # menvcfg
    E32 0x31a022f3                          # menvcfgh
    E32 0x323022f3                          # mhpmevent3
    E32 0xb03022f3                          # mhpmcounter3
    E32 0xb83022f3                          # mhpmcounter3h
    E32 0xc03022f3                          # hpmcounter3
    E32 0xc83022f3                          # hpmcounter3h
    E32 0x7a1022f3                          # tdata1
    E32 0x7a2022f3                          # tdata2
    E32 0x7a3022f3                          # tdata3
    E32 0x7a8022f3                          # mcontext
    E32 0x7aa022f3                          # mscontext
    E32 0x5a8022f3                          # scontext
    E32 0x7c0022f3                          # cpuctrlsts
    E32 0x7c1022f3                          # secureseed
sweep_end:
    .option pop

# li t0, NSLOT must come after every SLOT: .set gives a symbol its value at that point in the
# file, so before the table it is 0 and the liveness check can never pass.
.Lload_nslot:
    li      t0, NSLOT
    j       .Lnslot_loaded
