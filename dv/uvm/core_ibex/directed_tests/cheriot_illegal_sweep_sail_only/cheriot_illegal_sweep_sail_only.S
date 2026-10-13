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
# CHERIoT-Sail, the reference model, has no instruction or CSR there. A slot that executes
# instead fails the test with the code 2000 + 4 * index + k of the first divergence
# (k = 0: executed), and the number of failed checks in mscratch. Every slot is run, but only
# the program's own checks see them all: the CHERIoT-Sail comparison stops the run at the
# first disagreement (the handler's mcause read), and a larger +max_quit_count only adds the
# PC cascade that follows. For a per-slot verdict run with +disable_cheriot_sail=1.
# The test is to the model; each class is reported as an RTL/Sail disagreement.
# Paths: Sail = dv/cosim/cheriot-sail-model, RTL = rtl/.
#
# Classes, in table order (slot index i = the i-th E32 line, from 0). These are the
# GAP-CS-3 items. Encodings that left the table, and how the codes moved:
#   CGetOffset: the ISA says it is not present, so it is an RTL finding with its own, unwaived
#     test (cheriot_cgetoffset_illegal). It was slot 0, so every code moved down by 4 on
#     2026-10-04.
#   cdbg_ctrl: REQ_ISA_11 names it, so it is an RTL finding with its own test
#     (cheriot_cdbg_ctrl_illegal, 2026-10-07); it was the last slot, so no code moved.
#   Zcb (c.lbu, c.lhu, c.lh, c.sb, c.sh, c.zext.b, c.sext.b, c.zext.h, c.sext.h, c.not,
#     c.mul): ratified, implemented by the RTL in CHERIoT mode, and since 2026-10-10 by
#     CHERIoT-Sail too (riscv_insts_zcb.sail, VENDORED_FROM), so no longer illegal; the
#     positive test is cheriot_zcb. The eleven slots were the first ones, so every code moved
#     down by 44 on 2026-10-10. The reserved Zcb encodings stay in cheriot_illegal_sweep.
#
#   2000-2103  Draft bit-manipulation instructions outside the ratified
#     Zba/Zbb/Zbc/Zbs/Zbkb/Zbkx that Sail implements (slots 0-25): sloi, shfli,
#     crc32[c].b/h/w, fsri, sroi, grevi, gorci, unshfli (immediates other than the
#     zip/unzip/rev8/brev8/orc.b aliases), cmix, cmov, fsl, fsr, packu, bfp, grev, gorc, shfl,
#     unshfl, xperm.h, slo, sro. Since lowRISC/ibex#2459 the RTL implements only the ratified
#     set (RV32BOTEarlGrey is gone), so these are illegal there too and pass; they stay in the
#     table so that none comes back. rd = t0.
#   1999  liveness: fewer slots processed than assembled (NSLOT)
#
# Also left the table, 2026-10-12: the 17 CSRs the RTL implements (mconfigptr, mcounteren,
# menvcfg[h], mhpmevent3, [m]hpmcounter3[h], tdata1-3, m/ms/scontext, cpuctrlsts, secureseed).
# CHERIoT-Sail's platform implements them as Ibex does since 2026-10-09
# (sail-riscv/c_emulator/ibex_platform_csrs.c); regression seed 17265 confirmed it, all 17
# executing on both sides with no CHERIoT-Sail mismatch. They were the last slots, so no code
# moved. Every slot left is expected to pass, so the test carries no waiver.
#
# Encodings generated from the field layouts and cross-checked with llvm-mc (riscv32
# with Zbb/Zbkb, and riscv32cheriot, which rejects all of them).

#include "cheriot_dv.h"
#include "cheriot_illegal_sweep/illegal_sweep.h"

    .option norelax

    .text
    .globl main
main:
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
sweep_end:
    .option pop

# li t0, NSLOT must come after every SLOT: .set gives a symbol its value at that point in the
# file, so before the table it is 0 and the liveness check can never pass.
.Lload_nslot:
    li      t0, NSLOT
    j       .Lnslot_loaded
