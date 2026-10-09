// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Shared infrastructure for the CHERIoT-mode trap/debug/bus-error directed tests
// (cheriot_irq_cheri, cheriot_debug_mode, cheriot_mem_err).
//
// 1. CHERIoT instruction macros. The flow assembles with the stock rv32imc GCC, which knows no
//    CHERIoT mnemonic. Instead of hand-assembled .word constants, every instruction is built with
//    `.insn` from the CHERIoT-Sail encdec clauses (cheriot-sail-upstream/src/cheri_insts.sail),
//    so register operands can be macro arguments. Capability register cN is written as the
//    integer register of the same number (ct0 = t0, csp = sp, ...). An SCR number is passed in
//    the rs2 slot as x<scr>, which is how .insn encodes a 5-bit field there.
//    Encodings were checked against llvm-mc -triple riscv32cheriot -mcpu=cheriot (see the
//    report of 2026-10-01); re-check with that tool after changing a macro.
//
// 2. Register conventions shared by the tests: x0-x15 only (RV32E -- ibex_decoder.sv's
//    illegal_reg_16), s1 = signature capability (cursor 0x8ffffffc, never written after
//    SIG_INIT), MScratchC = trap stack capability while a test runs (the reset sealing root is
//    saved to memory first by the tests that need it).
//
// 3. riscv-dv signature protocol (core_ibex_base_test::wait_for_mem_txn): CORE_STATUS and
//    WRITE_CSR go to 0x8ffffffc, the test result to 0x8ffffff8. Plain sw is capability-relative
//    in CHERIoT mode, so they go through s1.

#ifndef CHERIOT_DV_H
#define CHERIOT_DV_H

#define SCR_DEPCC      24
#define SCR_DSCRATCHC0 25
#define SCR_DSCRATCHC1 26
#define SCR_MTCC       28
#define SCR_MTDC       29
#define SCR_MSCRATCHC  30
#define SCR_MEPCC      31

// riscv_signature_pkg.sv
#define SIG_CORE_STATUS 0x0
#define SIG_TEST_RESULT 0x1
#define SIG_WRITE_CSR   0x3
#define ST_INITIALIZED       0x0
#define ST_IN_DEBUG_MODE     0x1
#define ST_IN_MACHINE_MODE   0x2
#define ST_HANDLING_IRQ      0x6
#define ST_FINISHED_IRQ      0x7
#define ST_HANDLING_EXCEPTION 0x8

#define SIG_ADDR_VAL   0x8ffffffc

// Trigger address for +cheriot_enable_on_write (must match the testlist entry).
#define CHERIOT_ON_TRIGGER 0x80200000

// mcause values (CHERIoT-Sail / ibex_pkg.sv)
#define MCAUSE_CHERI      28
#define MCAUSE_IFETCH_ACC 1
#define MCAUSE_LOAD_MISALIGN  4
#define MCAUSE_LOAD_ACC   5
#define MCAUSE_STORE_MISALIGN 6
#define MCAUSE_STORE_ACC  7
#define MCAUSE_BREAKPOINT 3
#define MCAUSE_NMI_INTG   0xFFFFFFE0

// ---- CHERIoT instructions (cheri_insts.sail encdec) -------------------------------------------

// CSpecialRW: 0b0000001 @ scr @ cs1 @ 0b000 @ cd @ 0b1011011
.macro cspecialr cd, scr
  .insn r 0x5b, 0, 0x01, \cd, x0, x\scr
.endm
.macro cspecialw scr, cs1
  .insn r 0x5b, 0, 0x01, x0, \cs1, x\scr
.endm
.macro cspecialrw cd, scr, cs1
  .insn r 0x5b, 0, 0x01, \cd, \cs1, x\scr
.endm

// Two-source, funct3 = 000, funct7 = sub-opcode
.macro csetbounds cd, cs1, rs2
  .insn r 0x5b, 0, 0x08, \cd, \cs1, \rs2
.endm
.macro csetboundsexact cd, cs1, rs2
  .insn r 0x5b, 0, 0x09, \cd, \cs1, \rs2
.endm
.macro cseal cd, cs1, cs2
  .insn r 0x5b, 0, 0x0b, \cd, \cs1, \cs2
.endm
.macro cunseal cd, cs1, cs2
  .insn r 0x5b, 0, 0x0c, \cd, \cs1, \cs2
.endm
.macro candperm cd, cs1, rs2
  .insn r 0x5b, 0, 0x0d, \cd, \cs1, \rs2
.endm
.macro csetaddr cd, cs1, rs2
  .insn r 0x5b, 0, 0x10, \cd, \cs1, \rs2
.endm
.macro cincaddr cd, cs1, rs2
  .insn r 0x5b, 0, 0x11, \cd, \cs1, \rs2
.endm
.macro cseqx rd, cs1, cs2
  .insn r 0x5b, 0, 0x21, \rd, \cs1, \cs2
.endm
.macro csetboundsrndn cd, cs1, rs2
  .insn r 0x5b, 0, 0x0a, \cd, \cs1, \rs2
.endm
.macro csethigh cd, cs1, rs2
  .insn r 0x5b, 0, 0x16, \cd, \cs1, \rs2
.endm
.macro ctestsubset rd, cs1, cs2
  .insn r 0x5b, 0, 0x20, \rd, \cs1, \cs2
.endm

// AUICGP: imm20 @ cd @ 0b1111011 (its own major opcode; cs1 is implicitly c3). In CHERIoT mode
// the AUIPC encoding (0x17) is AUIPCC, so plain `auipc` is AUIPCC; both shift imm20 by 11.
.macro auicgp cd, imm20
  .insn u 0x7b, \cd, \imm20
.endm
.macro auipcc cd, imm20
  .insn u 0x17, \cd, \imm20
.endm

// Immediate forms
.macro cincaddrimm cd, cs1, imm
  .insn i 0x5b, 1, \cd, \cs1, \imm
.endm
.macro csetboundsimm cd, cs1, imm
  .insn i 0x5b, 2, \cd, \cs1, \imm
.endm

// Single-source, funct7 = 0x7f, sub-opcode in the rs2 slot
.macro cgetperm rd, cs1
  .insn r 0x5b, 0, 0x7f, \rd, \cs1, x0
.endm
.macro cgettype rd, cs1
  .insn r 0x5b, 0, 0x7f, \rd, \cs1, x1
.endm
.macro cgetbase rd, cs1
  .insn r 0x5b, 0, 0x7f, \rd, \cs1, x2
.endm
.macro cgetlen rd, cs1
  .insn r 0x5b, 0, 0x7f, \rd, \cs1, x3
.endm
.macro cgettag rd, cs1
  .insn r 0x5b, 0, 0x7f, \rd, \cs1, x4
.endm
.macro cmove cd, cs1
  .insn r 0x5b, 0, 0x7f, \cd, \cs1, x10
.endm
.macro ccleartag cd, cs1
  .insn r 0x5b, 0, 0x7f, \cd, \cs1, x11
.endm
.macro cgetaddr rd, cs1
  .insn r 0x5b, 0, 0x7f, \rd, \cs1, x15
.endm
.macro cgethigh rd, cs1
  .insn r 0x5b, 0, 0x7f, \rd, \cs1, x23
.endm
.macro cgettop rd, cs1
  .insn r 0x5b, 0, 0x7f, \rd, \cs1, x24
.endm

// CLC = LD encoding (opcode 0x03, funct3 011), CSC = SD encoding (opcode 0x23, funct3 011).
// Always 32-bit forms, so the encoding does not depend on the assembler's compression choice.
.macro clc cd, cs1, off
  .insn i 0x03, 3, \cd, \off(\cs1)
.endm
.macro csc cs2, cs1, off
  .insn s 0x23, 3, \cs2, \off(\cs1)
.endm

// ---- Helpers ----------------------------------------------------------------------------------

// The symbol addresses below come from LA_FAR (defined further down), never GNU `la`: in
// CHERIoT mode `la` is only right within about +-2 KiB of the pc (see LA_FAR).

// cd := MTDC with its cursor at \sym. \tmp is clobbered and must differ from \cd: cspecialr
// overwrites cd's integer part with MTDC's cursor.
.macro DCAP cd, sym, tmp
  LA_FAR    \tmp, \sym, \cd
  cspecialr \cd, SCR_MTDC
  csetaddr  \cd, \cd, \tmp
.endm

// MTCC := MTCC with its cursor at \sym (the only legal way to set the trap vector in CHERIoT mode;
// csrw mtvec is an illegal instruction, REQ_SCR_07). \ctmp and \tmp must differ.
.macro SET_MTCC sym, ctmp, tmp
  LA_FAR    \tmp, \sym, \ctmp
  cspecialr \ctmp, SCR_MTCC
  csetaddr  \ctmp, \ctmp, \tmp
  cspecialw SCR_MTCC, \ctmp
.endm

// MEPCC := MTCC with its cursor at \sym, then mret: leaves a trap at \sym with a valid PCC.
// \ctmp and \tmp must differ.
.macro RESUME_AT sym, ctmp, tmp
  LA_FAR    \tmp, \sym, \ctmp
  cspecialr \ctmp, SCR_MTCC
  csetaddr  \ctmp, \ctmp, \tmp
  cspecialw SCR_MEPCC, \ctmp
  mret
.endm

// s1 := signature capability. Clobbers t0.
.macro SIG_INIT
  li        t0, SIG_ADDR_VAL
  cspecialr s1, SCR_MTDC
  csetaddr  s1, s1, t0
.endm

// CORE_STATUS handshake. Clobbers t0.
.macro SIG_STATUS st
  li        t0, ((\st) << 8) | SIG_CORE_STATUS
  sw        t0, 0(s1)
.endm

// WRITE_CSR handshake: {csr, type} then the CSR value. Clobbers t0.
.macro SIG_CSR csr
  li        t0, ((\csr) << 8) | SIG_WRITE_CSR
  sw        t0, 0(s1)
  csrr      t0, \csr
  sw        t0, 0(s1)
.endm

// End the test with exit code a0 (0 = pass). The CORE_STATUS-type word carries the code for the
// log, as crt_cheriot.S does; the TEST_RESULT word is what core_ibex_base_test waits on.
.macro TEST_END_A0
  slli      t0, a0, 8
  sltu      t1, x0, a0
  slli      t1, t1, 8
  ori       t1, t1, SIG_TEST_RESULT
  fence     iorw, iorw
  sw        t0, -4(s1)
  sw        t1, -4(s1)
1: j 1b
.endm

// if (\a != \b) fail with \code. Uses a0.
.macro CHECK_EQ a, b, code
  beq       \a, \b, 1f
  li        a0, \code
  j         test_end
1:
.endm
.macro CHECK_EQI a, imm, code, tmp
  li        \tmp, \imm
  CHECK_EQ  \a, \tmp, \code
.endm

// ---- Helpers for crt-based (cheriot-c-tests) self-checking tests ------------------------------
//
// Address of a far symbol. GNU `la` is AUIPC + ADDI with %pcrel_hi computed for AUIPC's
// imm << 12, but in CHERIoT mode the AUIPC encoding is AUIPCC, which shifts by 11
// (CHERIoT-Sail cheri_insts.sail AUIPCC: sign_extend(imm) << 11; ibex_cheriot_ex.sv
// CHERIOT_ADDER_A_IMM20). `la` is therefore only right while %pcrel_hi is 0, i.e. within
// about +-2 KiB of the pc, and .data is at least 64 KiB away (mseccfg_test.ld pads .text).
// LA_FAR takes the pc with AUIPCC 0 (same under either shift) and adds the link-time distance
// from absolute symbol values, so it is right at any distance. \rd and \tmp must differ.
.macro LA_FAR rd, sym, tmp
9:
  auipc     \rd, 0
  lui       \tmp, %hi(\sym)
  addi      \tmp, \tmp, %lo(\sym)
  add       \rd, \rd, \tmp
  lui       \tmp, %hi(9b)
  addi      \tmp, \tmp, %lo(9b)
  sub       \rd, \rd, \tmp
.endm

// cd := MTDC with its cursor at \sym (any distance). \tmp must differ from \cd.
.macro DCAP_FAR cd, sym, tmp
  LA_FAR    \tmp, \sym, \cd
  cspecialr \cd, SCR_MTDC
  csetaddr  \cd, \cd, \tmp
.endm

// MTCC := MTCC with its cursor at \sym (any distance).
.macro SET_VEC sym, ctmp, tmp
  LA_FAR    \tmp, \sym, \ctmp
  cspecialr \ctmp, SCR_MTCC
  csetaddr  \ctmp, \ctmp, \tmp
  cspecialw SCR_MTCC, \ctmp
.endm

// Leave a trap at \sym: MEPCC := MTCC with its cursor at \sym, then mret.
.macro RESUME sym, ctmp, tmp
  LA_FAR    \tmp, \sym, \ctmp
  cspecialr \ctmp, SCR_MTCC
  csetaddr  \ctmp, \ctmp, \tmp
  cspecialw SCR_MEPCC, \ctmp
  mret
.endm

// Self-checks with a liveness count: s1 counts the checks executed and NCHK the checks
// assembled; CHECK_LIVENESS at the end fails unless they agree, so a test that skips part of
// its body cannot pass. A failing check puts its code in a0 and jumps to .Lexit, which the test
// defines (restore what it changed, then `ret` to crt_cheriot.S, which reports a0).
.set NCHK, 0
.macro EXPECT_EQ a, b, code
  .set      NCHK, NCHK + 1
  addi      s1, s1, 1
  beq       \a, \b, 9f
  li        a0, \code
  j         .Lexit
9:
.endm
// Uses t2: \a must not be t2.
.macro EXPECT_EQI a, imm, code
  li        t2, \imm
  EXPECT_EQ \a, t2, \code
.endm
.macro CHECK_LIVENESS code
  li        t0, NCHK
  beq       s1, t0, 9f
  li        a0, \code
  j         .Lexit
9:
.endm

// Trap frame: 16 capability slots of 8 bytes; slot 2 holds the interrupted csp.
#define TRAP_FRAME 128

// Entry: swap csp with MScratchC (the trap stack capability) and save c1, c3-c15 and the
// interrupted csp with csc, so tags and metadata survive -- an integer sw of a capability
// register keeps only its address. Requires PCC.SR (the handler runs on MTCC, which has it).
.macro SAVE_CTX
  cspecialrw sp, SCR_MSCRATCHC, sp
  cincaddrimm sp, sp, -TRAP_FRAME
  csc  x1,  sp, 8
  csc  x3,  sp, 24
  csc  x4,  sp, 32
  csc  x5,  sp, 40
  csc  x6,  sp, 48
  csc  x7,  sp, 56
  csc  x8,  sp, 64
  csc  x9,  sp, 72
  csc  x10, sp, 80
  csc  x11, sp, 88
  csc  x12, sp, 96
  csc  x13, sp, 104
  csc  x14, sp, 112
  csc  x15, sp, 120
  cspecialr t0, SCR_MSCRATCHC
  csc  t0,  sp, 16
.endm

// Exit: MScratchC := trap stack top again, reload every register, csp last.
.macro RESTORE_CTX
  cincaddrimm t0, sp, TRAP_FRAME
  cspecialw SCR_MSCRATCHC, t0
  clc  x1,  sp, 8
  clc  x3,  sp, 24
  clc  x4,  sp, 32
  clc  x5,  sp, 40
  clc  x6,  sp, 48
  clc  x7,  sp, 56
  clc  x8,  sp, 64
  clc  x9,  sp, 72
  clc  x10, sp, 80
  clc  x11, sp, 88
  clc  x12, sp, 96
  clc  x13, sp, 104
  clc  x14, sp, 112
  clc  x15, sp, 120
  clc  sp,  sp, 16
.endm

// MScratchC := bounded capability over [\sym, \sym + 512), cursor at the top. \sym must be
// 512-byte aligned so the bounds are exact (9-bit mantissa).
.macro INIT_TRAP_STACK sym, ctmp, tmp
  DCAP          \ctmp, \sym, \tmp
  li            \tmp, 512
  csetboundsexact \ctmp, \ctmp, \tmp
  cincaddrimm   \ctmp, \ctmp, 512
  cspecialw     SCR_MSCRATCHC, \ctmp
.endm

// Vector words at BOOT_ADDR + 0 (debug halt, DEBUG_MODE_HALT_ADDR) and + 8 (debug exception,
// DEBUG_MODE_EXCEPTION_ADDR), _start at BOOT_ADDR + 0x80 (the reset PC), as riscv-dv lays out
// its programs (ibex_asm_program_gen::gen_program_header).
.macro DV_VECTORS halt_label, exc_label
  .section .text.init, "ax"
  .option push
  .option norvc
  .globl _start
  j \halt_label
  .org 8
  j \exc_label
  .org 0x80
  .option pop
.endm

// Boot in RISC-V mode and have the testbench raise cheriot_enable_i
// (+cheriot_enable_on_write=80200000), then confirm CHERIoT mode: AUIPC now decodes as AUIPCC
// and returns a tagged capability. If the pin never comes on, cgettag is illegal and the test
// ends by timeout -- a failure, never a pass.
.macro ENABLE_CHERIOT_VIA_TRIGGER
  li        t0, CHERIOT_ON_TRIGGER
  sw        zero, 0(t0)
  .rept 30
  nop
  .endr
  auipc     t1, 0
  cgettag   t2, t1
1: beqz     t2, 1b
.endm

#endif  // CHERIOT_DV_H
