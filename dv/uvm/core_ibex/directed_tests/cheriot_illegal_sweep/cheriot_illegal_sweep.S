# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_illegal_sweep -- every reserved encoding class raises an illegal
#                                instruction in CHERIoT mode
# =============================================================================
# Each encoding below is illegal in CHERIoT-Sail and must trap with mcause 2,
# mtval 0, MEPCC at the encoding; the sweep mechanism, failure codes and the source
# of those values are in illegal_sweep.h. Encodings on which the RTL and Sail
# currently disagree are in cheriot_illegal_sweep_sail_only instead, so that this
# test guards the agreed behaviour. Paths: Sail = dv/cosim/cheriot-sail-model
# (src/cheri_insts.sail "ci", src/cheri_insts_cext.sail "cci", sail-riscv/model/
# riscv_insts_{base,cext,hints,zicsr}.sail, riscv_sys_control.sail "sysctl");
# RTL = rtl/ibex_decoder.sv "dec", ibex_compressed_decoder.sv "cdec",
# ibex_cs_registers.sv "csr", ibex_cheriot_ex.sv "cex".
#
# Classes, in table order (failure code = 1000 + 4 * index + k; slot index i is the
# i-th E32/E16 line of the table, counting from 0):
#    opcode 0x5B, funct3 0, funct7 0x7F, rs2 sub-opcode not defined
#            (Sail defines only 00-04, 08-0B, 0F, 17, 18: ci:1051-1064; dec:839)
#   opcode 0x5B, funct3 0, funct7 not defined (ci:1083-1101; dec:871)
#   opcode 0x5B, funct3 3-7 (dec:887-888)
#   CSpecialRW with SCR 0, 1, 23, 24, 25, 26, 27 outside debug mode
#            (ci:406-416 handle_illegal before the SR check; cex:858-859)
#   LOAD funct3 6, 7 (lwu/ldu: base:300; dec:438-439, 454-456)
#   STORE funct3 4-7 (base:376; dec:399-400)
#   JALR funct3 1, 2, 7 (ci:1142, base:91; dec:350-351)
#   BRANCH funct3 2, 3 (base:111; dec:382)
#   MISC-MEM funct3 2, 3, 4, 7 (dec:724-725)
#   SYSTEM: ecall/ebreak/mret/wfi with rd or rs1 != 0, funct12 3, funct3 4,
#            uret, sret, sinval.vma, hfence.vvma, hfence.gvma, dret outside debug mode
#            (base:684-761, zicsr:15-22; dec:751-758, 773; ibex_id_stage.sv:604)
#   opcodes with no instruction in this configuration: 07 (FLW), 27 (FSW),
#            2F (AMO, LR), 43/47/4B/4F (FMA), 53 (OP-FP), 57 (OP-V), 1B/3B (RV64
#            OP-32), 0B/2B (custom), 5F, 6B, 77, 7F, 3F, 1F, and 0xFFFFFFFF (dec:912-914)
#   slli/srai with shamt[5] = 1; bcompress/bdecompress (Full only, not
#            OTEarlGrey); unused OP funct7 (base:209-211; dec:502, 545, 649-650, 693-694)
#   instructions naming x16-x31 (CHERIoT is RV32E: cheri_regs.sail:106,149
#            and riscv_regs.sail:73,113 reject the register; dec:237-245, 1466)
#   CSRs that do not exist in CHERIoT mode or are read-only: mtvec, mepc
#            (sysctl:33,41; csr:479-494), pmpcfg0, pmpaddr0 (no PMP: sysctl:47-53;
#            csr:717-726), mseccfg(h), satp, sstatus, medeleg, mideleg, time(h), fflags,
#            fcsr, dcsr, dpc, dscratch0/1 (debug mode only), tinfo, a read of seed;
#            writes to mhartid, mvendorid, marchid, mimpid, mconfigptr, cycle
#            (sysctl:17-142; csr:412-414, 712-714)
#   the legacy CHERI-RISC-V capability control CSRs uccsr (0x8C0), sccsr (0x9C0) and
#            mccsr (0xBC0), read and written: CHERIoT drops them (spec GAP-MF-1); the
#            last six slots
#   16-bit: 0x0000, c.addi4spn/c.cincaddr4cspn with 0, c.fld, c.fsd, c.fldsp,
#            c.fsdsp, c.lui with 0, c.addi16sp/c.cincaddr16csp with 0, c.srli/c.srai/
#            c.slli with shamt[5], c.subw, c.addw, c.zext.w, the reserved Q1 and Q0
#            funct3 100 subcodes, c.lwsp x0, c.clcsp c0 (cci:116), c.jr x0, the Zcmp
#            push/pop/mv encodings (illegal in CHERIoT mode in the RTL, no Zcmp in
#            Sail), and HINT forms naming x16-x31 (cext:31-494, cci:116-228,
#            hints:47-118; cdec:239-620)
#   999  liveness: fewer slots processed than assembled (NSLOT)
#
# Encodings were generated from the field layouts and cross-checked with llvm-mc
# (riscv32cheriot and riscv32 with every relevant extension) by the review of the
# CHERIoT-Ibex testplan; each is commented with its meaning. A wrongly executed
# encoding writes at most t0 or a5.

#include "cheriot_dv.h"
#include "cheriot_illegal_sweep/illegal_sweep.h"

    .option norelax

    .text
    .globl main
main:
    SWEEP     sweep_start, sweep_end, 1000
    csrw      mscratch, a3                  # failure count, for the log
    bnez      a4, .Lret_a4
    j        .Lload_nslot             # NSLOT is final only after the table (gas .set)
.Lnslot_loaded:
    li        a0, 999                       # liveness
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
    # 0x5B funct7 0x7F, rs2 = 05 07 0C 0D 0E 10 16 19 1F (rd t0, cs1 ct1)
    E32 0xfe5302db
    E32 0xfe7302db
    E32 0xfec302db
    E32 0xfed302db
    E32 0xfee302db
    E32 0xff0302db
    E32 0xff6302db
    E32 0xff9302db
    E32 0xfff302db
    # 0x5B funct3 0, funct7 = 00 02 07 0E 0F 12 13 15 1D 1F 22 7E
    E32 0x007302db
    E32 0x047302db
    E32 0x0e7302db
    E32 0x1c7302db
    E32 0x1e7302db
    E32 0x247302db
    E32 0x267302db
    E32 0x2a7302db
    E32 0x3a7302db
    E32 0x3e7302db
    E32 0x447302db
    E32 0xfc7302db
    # 0x5B funct3 3-7
    E32 0x000332db
    E32 0x000342db
    E32 0x000352db
    E32 0x000362db
    E32 0x000372db
    # cspecialr ct0, scr 0 / 1 / 23 / 24 / 25 / 26 / 27
    E32 0x020002db
    E32 0x021002db
    E32 0x037002db
    E32 0x038002db
    E32 0x039002db
    E32 0x03a002db
    E32 0x03b002db
    # LOAD funct3 6, 7 (rd t0, rs1 x0)
    E32 0x00006283
    E32 0x00007283
    # STORE funct3 4-7 (rs1 x0)
    E32 0x00004023
    E32 0x00005023
    E32 0x00006023
    E32 0x00007023
    # JALR funct3 1, 2, 7
    E32 0x00001067
    E32 0x00002067
    E32 0x00007067
    # BRANCH funct3 2, 3 (offset +4)
    E32 0x00002263
    E32 0x00003263
    # MISC-MEM funct3 2 (cbo.*), 3, 4, 7
    E32 0x0000200f
    E32 0x0000300f
    E32 0x0000400f
    E32 0x0000700f
    # SYSTEM
    E32 0x000002f3                          # ecall, rd = t0
    E32 0x00030073                          # ecall, rs1 = t1
    E32 0x001002f3                          # ebreak, rd = t0
    E32 0x30230073                          # mret, rs1 = t1
    E32 0x105002f3                          # wfi, rd = t0
    E32 0x00300073                          # funct12 = 3
    E32 0x000042f3                          # funct3 = 4
    E32 0x00200073                          # uret
    E32 0x10200073                          # sret
    E32 0x16000073                          # sinval.vma
    E32 0x22000073                          # hfence.vvma
    E32 0x62000073                          # hfence.gvma
    E32 0x7b200073                          # dret outside debug mode
    # opcodes with no instruction in this configuration
    E32 0x00002287                          # flw t0, 0(x0)
    E32 0x00002027                          # fsw
    E32 0x000022af                          # amoadd.w
    E32 0x100022af                          # lr.w
    E32 0x000002c3                          # fmadd
    E32 0x000002c7                          # fmsub
    E32 0x000002cb                          # fnmsub
    E32 0x000002cf                          # fnmadd
    E32 0x000002d3                          # fadd
    E32 0x000072d7                          # vsetvli
    E32 0x0000029b                          # addiw
    E32 0x000002bb                          # addw
    E32 0x0000028b                          # custom-0
    E32 0x000002ab                          # custom-1
    E32 0x000002df                          # opcode 0x5F
    E32 0x000002eb                          # opcode 0x6B
    E32 0x000002f7                          # opcode 0x77
    E32 0x000002ff                          # opcode 0x7F (>= 80-bit prefix)
    E32 0x000002bf                          # opcode 0x3F (48-bit prefix)
    E32 0x0000029f                          # opcode 0x1F (48-bit prefix)
    E32 0xffffffff
    # OP-IMM / OP
    E32 0x02031293                          # slli t0, t1, 32 (shamt[5])
    E32 0x42035293                          # srai t0, t1, 32
    E32 0x087362b3                          # bcompress (RV32BFull only)
    E32 0x487362b3                          # bdecompress (RV32BFull only)
    E32 0x047302b3                          # OP funct7 0x02, funct3 0
    E32 0xf87302b3                          # OP funct7 0x7C, funct3 0
    E32 0x407312b3                          # OP funct7 0x20, funct3 1
    # x16-x31 (illegal since CHERIoT mode is RV32E)
    E32 0x00000813                          # addi x16, x0, 0
    E32 0x00080293                          # addi t0, x16, 0
    E32 0x010002b3                          # add t0, x0, x16
    E32 0x00000fb7                          # lui x31, 0
    E32 0x00080263                          # beq x16, x0, +4
    E32 0x0040086f                          # jal x16, +4
    E32 0x34002873                          # csrr x16, mscratch
    E32 0x03e0085b                          # cspecialr c16, mscratchc
    E32 0x0000087b                          # auicgp c16, 0
    # CSRs: reads (rd t0)
    E32 0x305022f3                          # mtvec
    E32 0x341022f3                          # mepc
    E32 0x3a0022f3                          # pmpcfg0
    E32 0x3b0022f3                          # pmpaddr0
    E32 0x747022f3                          # mseccfg
    E32 0x757022f3                          # mseccfgh
    E32 0x180022f3                          # satp
    E32 0x100022f3                          # sstatus
    E32 0x302022f3                          # medeleg
    E32 0x303022f3                          # mideleg
    E32 0xc01022f3                          # time
    E32 0xc81022f3                          # timeh
    E32 0x001022f3                          # fflags
    E32 0x003022f3                          # fcsr
    E32 0x7b0022f3                          # dcsr (debug mode only)
    E32 0x7b1022f3                          # dpc
    E32 0x7b2022f3                          # dscratch0
    E32 0x7b3022f3                          # dscratch1
    E32 0x7a4022f3                          # tinfo
    E32 0x015022f3                          # seed, read-only access
    # CSRs: writes to read-only CSRs
    E32 0xf1401073                          # csrw mhartid, x0
    E32 0xf1101073                          # csrw mvendorid, x0
    E32 0xf1201073                          # csrw marchid, x0
    E32 0xf1301073                          # csrw mimpid, x0
    E32 0xf1501073                          # csrw mconfigptr, x0
    E32 0xc0001073                          # csrw cycle, x0
    E32 0xf14322f3                          # csrrs t0, mhartid, t1
    E32 0xc000e2f3                          # csrrsi t0, cycle, 1
    # 16-bit
    E16 0x0000                              # all zero
    E16 0x0004                              # c.addi4spn / c.cincaddr4cspn, 0
    E16 0x2000                              # c.fld
    E16 0xa000                              # c.fsd
    E16 0x2282                              # c.fldsp
    E16 0xa002                              # c.fsdsp
    E16 0x6281                              # c.lui t0, 0
    E16 0x6101                              # c.addi16sp / c.cincaddr16csp, 0
    E16 0x6001                              # c.lui x0, 0
    E16 0x9001                              # c.srli, shamt[5]
    E16 0x9401                              # c.srai, shamt[5]
    E16 0x1282                              # c.slli, shamt[5]
    E16 0x9c01                              # c.subw
    E16 0x9c21                              # c.addw
    E16 0x9c71                              # c.zext.w
    E16 0x9c79                              # Q1 reserved
    E16 0x9c7d                              # Q1 reserved
    E16 0x8c40                              # Q0 funct3 100 reserved
    E16 0x9000                              # Q0 funct3 100 reserved
    E16 0x4002                              # c.lwsp x0
    E16 0x6002                              # c.clcsp c0
    E16 0x8002                              # c.jr x0 / c.cjr c0
    E16 0xb842                              # cm.push
    E16 0xba42                              # cm.pop
    E16 0xbc42                              # cm.popretz
    E16 0xbe42                              # cm.popret
    E16 0xac26                              # cm.mvsa01
    E16 0xac66                              # cm.mva01s
    E16 0x0a01                              # c.addi x20, 0 (HINT form, x20)
    E16 0x8816                              # c.mv x16, t0
    E16 0x4802                              # c.lwsp x16
    # Legacy CHERI-RISC-V capability control CSRs, dropped by CHERIoT (spec GAP-MF-1): reads and
    # writes. The cosim model defines none of them since 2026-10-04 (VENDORED_FROM); appended
    # last so the codes of every earlier slot are unchanged.
    E32 0x8c0022f3                          # csrr t0, uccsr
    E32 0x9c0022f3                          # csrr t0, sccsr
    E32 0xbc0022f3                          # csrr t0, mccsr
    E32 0x8c001073                          # csrw uccsr, x0
    E32 0x9c001073                          # csrw sccsr, x0
    E32 0xbc001073                          # csrw mccsr, x0
sweep_end:
    .option pop

# li t0, NSLOT must come after every SLOT: .set gives a symbol its value at that point in the
# file, so before the table it is 0 and the liveness check can never pass.
.Lload_nslot:
    li      t0, NSLOT
    j       .Lnslot_loaded
