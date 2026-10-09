// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Table-driven illegal-instruction sweep in CHERIoT mode, shared by cheriot_illegal_sweep
// and cheriot_illegal_sweep_sail_only (crt_cheriot.S, CHERIoT-Sail cosim). Include after
// cheriot_dv.h.
//
// The table is a run of 8-byte slots in .text, each holding one encoding:
//   E32:  .word ENC  ; j .Lsw_not_trapped
//   E16:  .half ENC  ; .half 0x0001 (c.nop) ; j .Lsw_not_trapped
// s0 points at the slot being executed and MTCC at .Lsw_trap for the whole sweep. For
// every slot one of two things happens:
//   the encoding traps   -> .Lsw_trap checks mcause = 2, mtval = 0, MEPCC.address = s0
//   it executes          -> the next instruction jumps to .Lsw_not_trapped
// and the sweep continues at the next slot (s0 += 8). A slot that misbehaves is recorded
// and the sweep carries on, so a single run reports on every slot:
//   a4 = code of the first failure, \base + 4 * slot index + k, where k is
//        0 the encoding executed instead of trapping
//        1 mcause != 2 (illegal instruction)
//        2 mtval != 0
//        3 MEPCC.address != the slot (the trap was not raised by this encoding)
//   a3 = number of failed checks; the test leaves it in mscratch for the log
//   s1 = number of slots processed; the test must compare it with NSLOT, so that a
//        sweep which stops early cannot pass.
// Expected trap values in CHERIoT mode:
//   mcause 2: sail-riscv handle_illegal (riscv_platform.sail:511-519), reached when no
//     decode clause matches (riscv_insts_end.sail) or a clause rejects the encoding.
//   mtval 0: handle_illegal passes the instruction bits only if
//     plat_mtval_has_illegal_inst_bits(), which the C platform leaves false
//     (sail-riscv/c_emulator/riscv_platform_impl.c:18; the cosim DPI does not set it).
//     ibex agrees: ibex_controller.sv illegal_insn_prio gives mtval 0 in CHERIoT mode.
//   MEPCC: PCC with the faulting pc (cheri_sys_exceptions.sail:71-81).
// The encodings are chosen so that one which is wrongly executed can only write t0 or
// a5 (or fault through an untagged a5), never s0, s1, a3 or a4.
//
// Registers: s0 slot pointer, s1 slot count, a3/a4 as above, t0-t2 and ca0 scratch.

#ifndef ILLEGAL_SWEEP_H
#define ILLEGAL_SWEEP_H

.set NSLOT, 0

.macro E32 enc
  .set NSLOT, NSLOT + 1
  .word \enc
  j .Lsw_not_trapped
.endm

.macro E16 enc
  .set NSLOT, NSLOT + 1
  .half \enc
  .half 0x0001
  j .Lsw_not_trapped
.endm

// Record failure kind t2 for the current slot. Clobbers t0, t1.
.macro SW_RECORD start, base
  addi      a3, a3, 1
  bnez      a4, 8f
  LA_FAR    t0, \start, t1
  sub       t0, s0, t0                  // 8 * index
  srli      t0, t0, 1                   // 4 * index
  add       t0, t0, t2
  li        t1, \base
  add       a4, t0, t1
8:
.endm

// MEPCC := MTCC with cursor \reg, then mret. Clobbers ca0.
.macro SW_MRET_TO reg
  cspecialr a0, SCR_MTCC
  csetaddr  a0, a0, \reg
  cspecialw SCR_MEPCC, a0
  mret
.endm

// Run the table [\start, \end) with failure codes from \base.
.macro SWEEP start, end, base
  li        s1, 0
  li        a3, 0
  li        a4, 0
  SET_VEC   .Lsw_trap, t0, t1
  LA_FAR    s0, \start, t0
  cspecialr a0, SCR_MTCC
  csetaddr  a0, a0, s0
  jalr      zero, 0(a0)                 // first slot

  .balign 4
.Lsw_trap:
  csrr      t0, mcause
  li        t1, 2
  beq       t0, t1, 1f
  li        t2, 1
  SW_RECORD \start, \base
1:
  csrr      t0, mtval
  beqz      t0, 2f
  li        t2, 2
  SW_RECORD \start, \base
2:
  cspecialr a0, SCR_MEPCC
  cgetaddr  t0, a0
  beq       t0, s0, 3f
  li        t2, 3
  SW_RECORD \start, \base
3:
  addi      s0, s0, 8
  addi      s1, s1, 1
  LA_FAR    t0, \end, t1
  beq       s0, t0, 4f
  SW_MRET_TO s0                         // next slot
4:
  LA_FAR    t0, .Lsw_done, t1
  SW_MRET_TO t0                         // table finished

.Lsw_not_trapped:
  li        t2, 0
  SW_RECORD \start, \base
  addi      s0, s0, 8
  addi      s1, s1, 1
  LA_FAR    t0, \end, t1
  beq       t0, s0, .Lsw_done
  cspecialr a0, SCR_MTCC
  csetaddr  a0, a0, s0
  jalr      zero, 0(a0)                 // next slot

.Lsw_done:
.endm

#endif  // ILLEGAL_SWEEP_H
