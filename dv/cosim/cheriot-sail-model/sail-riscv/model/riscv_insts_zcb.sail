/*=======================================================================================*/
/*  This Sail RISC-V architecture model, comprising all files and                        */
/*  directories except where otherwise noted is subject the BSD                          */
/*  two-clause license in the LICENSE file.                                              */
/*                                                                                       */
/*  SPDX-License-Identifier: BSD-2-Clause                                                */
/*=======================================================================================*/

/* ****************************************************************** */
/* This file specifies the compressed instructions in the 'Zcb' extension
 * (ratified Zc 1.0), for RV32.
 *
 * CHERIoT-Ibex verification local change (VENDORED_FROM 2026-10-10). Upstream sail-riscv has
 * Zcb (model/extensions/C/zcb_insts.sail) since after this fork was taken; CHERIoT-Ibex
 * implements it in CHERIoT mode. The Zc specification defines each Zcb instruction as an
 * existing instruction with fixed operands, so unlike upstream these clauses decode straight
 * to that instruction's ast and add no ast clauses of their own: a Zcb load or store executes,
 * traps and reaches RVFI exactly as lbu/lhu/lh/sb/sh, and is authorised in CHERIoT by the
 * capability in rs1' (ext_data_get_addr), as c.lw is. The clauses are backwards only (bits to
 * ast): the forwards direction of LOAD and the others is the 32-bit encdec. As for every
 * compressed instruction, misa.C is checked by the step and nextPC = PC + 2 comes from the
 * fetch. The generated C carries the same decode as a hand edit (zcb_decode_compressed);
 * the reserved encodings (Q0 funct3 100 with bit 12 set, c.sh with bit 6 set, c.zext.w on
 * RV32, unary forms 110 and 111) match no clause here and stay C_ILLEGAL.
 */

/* c.lbu rd', uimm(rs1'): uimm[1:0] = {bit 5, bit 6} */
mapping clause encdec_compressed = backwards
  0b100 @ 0b000 @ rs1 : cregidx @ ui0 : bits(1) @ ui1 : bits(1) @ rd : cregidx @ 0b00 if haveZcb()
  => LOAD(zero_extend(ui1 @ ui0), creg2reg_idx(rs1), creg2reg_idx(rd), true, BYTE, false, false)

/* c.lhu rd', uimm(rs1'): uimm[1] = bit 5 */
mapping clause encdec_compressed = backwards
  0b100 @ 0b001 @ rs1 : cregidx @ 0b0 @ ui1 : bits(1) @ rd : cregidx @ 0b00 if haveZcb()
  => LOAD(zero_extend(ui1 @ 0b0), creg2reg_idx(rs1), creg2reg_idx(rd), true, HALF, false, false)

/* c.lh rd', uimm(rs1') */
mapping clause encdec_compressed = backwards
  0b100 @ 0b001 @ rs1 : cregidx @ 0b1 @ ui1 : bits(1) @ rd : cregidx @ 0b00 if haveZcb()
  => LOAD(zero_extend(ui1 @ 0b0), creg2reg_idx(rs1), creg2reg_idx(rd), false, HALF, false, false)

/* c.sb rs2', uimm(rs1') */
mapping clause encdec_compressed = backwards
  0b100 @ 0b010 @ rs1 : cregidx @ ui0 : bits(1) @ ui1 : bits(1) @ rs2 : cregidx @ 0b00 if haveZcb()
  => STORE(zero_extend(ui1 @ ui0), creg2reg_idx(rs2), creg2reg_idx(rs1), BYTE, false, false)

/* c.sh rs2', uimm(rs1') */
mapping clause encdec_compressed = backwards
  0b100 @ 0b011 @ rs1 : cregidx @ 0b0 @ ui1 : bits(1) @ rs2 : cregidx @ 0b00 if haveZcb()
  => STORE(zero_extend(ui1 @ 0b0), creg2reg_idx(rs2), creg2reg_idx(rs1), HALF, false, false)

/* c.zext.b rsd' -> andi rsd', rsd', 0xff */
mapping clause encdec_compressed = backwards
  0b100 @ 0b111 @ rsd : cregidx @ 0b11 @ 0b000 @ 0b01 if haveZcb()
  => ITYPE(0x0ff, creg2reg_idx(rsd), creg2reg_idx(rsd), RISCV_ANDI)

/* c.sext.b rsd' -> sext.b rsd', rsd' */
mapping clause encdec_compressed = backwards
  0b100 @ 0b111 @ rsd : cregidx @ 0b11 @ 0b001 @ 0b01 if haveZcb() & haveZbb()
  => ZBB_EXTOP(creg2reg_idx(rsd), creg2reg_idx(rsd), RISCV_SEXTB)

/* c.zext.h rsd' -> zext.h rsd', rsd' */
mapping clause encdec_compressed = backwards
  0b100 @ 0b111 @ rsd : cregidx @ 0b11 @ 0b010 @ 0b01 if haveZcb() & haveZbb()
  => ZBB_EXTOP(creg2reg_idx(rsd), creg2reg_idx(rsd), RISCV_ZEXTH)

/* c.sext.h rsd' -> sext.h rsd', rsd' */
mapping clause encdec_compressed = backwards
  0b100 @ 0b111 @ rsd : cregidx @ 0b11 @ 0b011 @ 0b01 if haveZcb() & haveZbb()
  => ZBB_EXTOP(creg2reg_idx(rsd), creg2reg_idx(rsd), RISCV_SEXTH)

/* c.not rsd' -> xori rsd', rsd', -1 */
mapping clause encdec_compressed = backwards
  0b100 @ 0b111 @ rsd : cregidx @ 0b11 @ 0b101 @ 0b01 if haveZcb()
  => ITYPE(0xfff, creg2reg_idx(rsd), creg2reg_idx(rsd), RISCV_XORI)

/* c.mul rsd', rs2' -> mul rsd', rsd', rs2' */
mapping clause encdec_compressed = backwards
  0b100 @ 0b111 @ rsd : cregidx @ 0b10 @ rs2 : cregidx @ 0b01 if haveZcb() & (haveMulDiv() | haveZmmul())
  => MUL(creg2reg_idx(rs2), creg2reg_idx(rsd), creg2reg_idx(rsd), false, true, true)
