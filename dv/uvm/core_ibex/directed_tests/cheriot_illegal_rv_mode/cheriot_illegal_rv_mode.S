# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_illegal_rv_mode -- CHERIoT-only encodings are illegal with
#                                  cheriot_enable_i Off
# =============================================================================
# The bench builds the CHERIoT-capable core (opentitan configuration) and this test
# never raises the pin, so the core is a plain RV32IMCB core: every encoding that only
# exists in CHERIoT mode must raise an illegal instruction exception, checked against
# Spike (cosim), which knows no CHERIoT encoding. In RISC-V mode mtval holds the
# instruction bits, zero-extended for a 16-bit instruction (ibex_controller.sv
# illegal_insn_prio; the RISC-V Privileged ISA allows it and Spike does it), and mepc
# is the instruction.
#   - opcode 0x5B (custom-2) and AUICGP 0x7B (custom-3): every CHERIoT instruction, one
#     slot each, decoded only when cheriot_enable_i is On (ibex_decoder.sv
#     OPCODE_CHERI, OPCODE_AUICGP);
#   - CLC/CSC: LOAD/STORE funct3 3 (ld/sd, RV64 only) (ibex_decoder.sv OPCODE_LOAD/STORE);
#   - mshwm 0xBC1, mshwmb 0xBC2 and cdbg_ctrl 0xBC4, read and write: these CSRs exist
#     only in CHERIoT mode (ibex_cs_registers.sv CSR_MSHWM/CSR_MSHWMB/CSR_CDBG_CTRL:
#     illegal_csr when the pin is not On; the CHERIoT half of the mshwm gating is in
#     cheriot_mshwm);
#   - the compressed capability loads/stores c.clc, c.csc, c.clcsp, c.cscsp, which are
#     c.flw, c.fsw, c.flwsp, c.fswsp here (no F).
# The table and failure codes work as in cheriot_illegal_sweep (illegal_sweep.h), with
# mtval = the slot's instruction bits instead of 0:
#   code = 100 + 4 * slot index + k (k 0 executed, 1 mcause != 2, 2 mtval, 3 mepc);
#   99 liveness (fewer slots processed than assembled).
# Reported as (code << 8) in the CORE_STATUS word, then TEST_FAIL, as in
# cheriot_bck_nocheck. An encoding executed by mistake writes at most t0, or stores
# through t1, which points at a scratch buffer.

#include "riscv_test.h"

.set NSLOT, 0
.macro E32 enc
  .set NSLOT, NSLOT + 1
  .word \enc
  j .Lnot_trapped
.endm
.macro E16 enc
  .set NSLOT, NSLOT + 1
  .half \enc
  .half 0x0001
  j .Lnot_trapped
.endm

# Record failure kind t2 for slot s0 (first failure in a4, count in a3). Clobbers t0, t1.
.macro RECORD
  addi      a3, a3, 1
  bnez      a4, 8f
  la        t0, sweep_start
  sub       t0, s0, t0
  srli      t0, t0, 1
  add       t0, t0, t2
  addi      a4, t0, 100
8:
.endm

# norelax before RVTEST_CODE_BEGIN, not after: otherwise the linker relaxes the header's
# .align and every later .balign 4 label lands at 2 mod 4.
    .option norelax
RVTEST_RV32M
RVTEST_CODE_BEGIN
    li      s1, 0
    li      a3, 0
    li      a4, 0
    la      t1, scratch                     # for anything wrongly executed
    li      t2, 0
    la      s0, sweep_start
    jr      s0

# Called from riscv_test.h's trap_vector (it has already used t5/t6).
    .balign 4
    .globl mtvec_handler
mtvec_handler:
    csrr    t0, mcause
    li      t1, 2
    beq     t0, t1, 1f
    li      t2, 1
    RECORD
1:  lhu     t1, 0(s0)                       # expected mtval: the instruction bits
    andi    t0, t1, 3
    li      t2, 3
    bne     t0, t2, 2f                      # 16-bit: lhu already zero-extended
    lw      t1, 0(s0)
2:  csrr    t0, mtval
    beq     t0, t1, 3f
    li      t2, 2
    RECORD
3:  csrr    t0, mepc
    beq     t0, s0, 4f
    li      t2, 3
    RECORD
4:  addi    s0, s0, 8
    addi    s1, s1, 1
    la      t0, sweep_end
    bne     s0, t0, 5f
    la      s0, .Ldone
5:  csrw    mepc, s0
    la      t1, scratch
    li      t2, 0
    mret

.Lnot_trapped:
    li      t2, 0
    RECORD
    addi    s0, s0, 8
    addi    s1, s1, 1
    la      t1, scratch
    li      t2, 0
    la      t0, sweep_end
    beq     s0, t0, .Ldone
    jr      s0

.Ldone:
    csrw    mscratch, a3                    # failure count, for the log
    bnez    a4, fail
    j      .Lload_nslot             # NSLOT is final only after the table (gas .set)
.Lnslot_loaded:
    li      a4, 99
    bne     s1, t0, fail
    RVTEST_PASS

# Failure report: (code << 8) | CORE_STATUS, then TEST_FAIL. a4 holds the code.
fail:
    fence
    li      t0, SIGNATURE_ADDR
    slli    t1, a4, 8
    sw      t1, 0(t0)
    li      t1, (TEST_FAIL << 8) | TEST_RESULT
    sw      t1, 0(t0)
1:  j       1b

    .option push
    .option norvc
    .balign 8
sweep_start:
    E32 0xfe0302db                          # cgetperm t0, ct1
    E32 0xfe1302db                          # cgettype t0, ct1
    E32 0xfe2302db                          # cgetbase t0, ct1
    E32 0xfe3302db                          # cgetlen t0, ct1
    E32 0xfe4302db                          # cgettag t0, ct1
    E32 0xfe8302db                          # crrl t0, ct1
    E32 0xfe9302db                          # cram t0, ct1
    E32 0xfea302db                          # cmove t0, ct1
    E32 0xfeb302db                          # ccleartag t0, ct1
    E32 0xfef302db                          # cgetaddr t0, ct1
    E32 0xff7302db                          # cgethigh t0, ct1
    E32 0xff8302db                          # cgettop t0, ct1
    E32 0x03c002db                          # cspecialr ct0, mtcc
    E32 0x03d002db                          # cspecialr ct0, mtdc
    E32 0x03e002db                          # cspecialr ct0, mscratchc
    E32 0x03f002db                          # cspecialr ct0, mepcc
    E32 0x03c3005b                          # cspecialw mtcc, ct1
    E32 0x107302db                          # csetbounds t0, ct1, t2
    E32 0x127302db                          # csetboundsexact t0, ct1, t2
    E32 0x147302db                          # csetboundsrounddown t0, ct1, t2
    E32 0x167302db                          # cseal t0, ct1, t2
    E32 0x187302db                          # cunseal t0, ct1, t2
    E32 0x1a7302db                          # candperm t0, ct1, t2
    E32 0x207302db                          # csetaddr t0, ct1, t2
    E32 0x227302db                          # cincaddr t0, ct1, t2
    E32 0x287302db                          # csub t0, ct1, t2
    E32 0x2c7302db                          # csethigh t0, ct1, t2
    E32 0x407302db                          # ctestsubset t0, ct1, t2
    E32 0x427302db                          # cseqx t0, ct1, t2
    E32 0x001312db                          # cincaddrimm ct0, ct1, 1
    E32 0x001322db                          # csetboundsimm ct0, ct1, 1
    E32 0x000012fb                          # auicgp ct0, 1
    E32 0x00033283                          # clc ct0, 0(ct1) (ld in RV64)
    E32 0x00733023                          # csc ct2, 0(ct1) (sd in RV64)
    E32 0xbc1022f3                          # csrr t0, mshwm
    E32 0xbc2022f3                          # csrr t0, mshwmb
    E32 0xbc4022f3                          # csrr t0, cdbg_ctrl
    E32 0xbc131073                          # csrw mshwm, t1
    E32 0xbc231073                          # csrw mshwmb, t1
    E16 0x6190                              # c.clc ca2, 0(ca1) (c.flw)
    E16 0xe990                              # c.csc ca2, 16(ca1) (c.fsw)
    E16 0x6602                              # c.clcsp ca2, 0(csp) (c.flwsp)
    E16 0xe032                              # c.cscsp ca2, 0(csp) (c.fswsp)
sweep_end:
    .option pop

# li t0, NSLOT must come after every SLOT: .set gives a symbol its value at that point in the
# file, so before the table it is 0 and the liveness check can never pass.
.Lload_nslot:
    li      t0, NSLOT
    j       .Lnslot_loaded

RVTEST_CODE_END

    .data
RVTEST_DATA_BEGIN
    .balign 16
scratch: .space 32
RVTEST_DATA_END
