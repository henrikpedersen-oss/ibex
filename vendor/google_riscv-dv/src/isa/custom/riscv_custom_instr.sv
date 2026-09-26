/*
 * Copyright 2020 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// Custom instruction class -- carries the CHERIoT instructions for the lowRISC
// CHERIoT-Ibex verification effort. See rv32x_instr.sv for the instruction list
// and for which instructions are deliberately excluded.
//
// These are emitted as raw `.word 0x........` rather than as mnemonics. The UVM
// flow assembles generated programs with a stock RV32IMCB toolchain
// (RISCV_GCC in flake.nix, and -march=rv32imc in directed_testlist.yaml:101),
// which does not know any CHERIoT mnemonic. The hand-written directed tests in
// dv/uvm/core_ibex/directed_tests/cheriot_*/ solve it the same way, e.g.
//     .word   0x10B5055B              # csetbounds ca0, ca0, a1
// The mnemonic is reproduced in a trailing comment so the generated assembly
// stays readable and greppable.

class riscv_custom_instr extends riscv_instr;

  `uvm_object_utils(riscv_custom_instr)
  `uvm_object_new

  // CHERIoT truncates every register field to 4 bits (ibex_decoder.sv:211-222)
  // and raises illegal_reg_16 for x16-x31 (lines 237-245). A5 is x15, so this is
  // exactly the legal set. ibex_cheriot_instr_sequence pins avail_regs the same
  // way, but that only applies when that sequence is selected -- these
  // instructions are never legal outside CHERIoT mode, so constrain them here
  // too rather than depend on the caller.
  constraint cheriot_reg_c {
    rd  inside {[ZERO : A5]};
    rs1 inside {[ZERO : A5]};
    rs2 inside {[ZERO : A5]};
  }

  virtual function string get_instr_name();
    return instr_name.name();
  endfunction : get_instr_name

  // instr[24:20] sub-opcode for the funct3=000, funct7=0x7f family.
  // Returns 1 and sets sub_op if instr_name belongs to that family.
  virtual function bit get_fmt3_subop(output bit [4:0] sub_op);
    case (instr_name)
      CGETPERM:  sub_op = 5'h00;
      CGETTYPE:  sub_op = 5'h01;
      CGETBASE:  sub_op = 5'h02;
      CGETLEN:   sub_op = 5'h03;
      CGETTAG:   sub_op = 5'h04;
      CRRL:      sub_op = 5'h08;
      CRAM:      sub_op = 5'h09;
      CMOVE:     sub_op = 5'h0a;
      CCLEARTAG: sub_op = 5'h0b;
      CGETADDR:  sub_op = 5'h0f;
      CGETHIGH:  sub_op = 5'h17;
      CGETTOP:   sub_op = 5'h18;
      default:   return 1'b0;
    endcase
    return 1'b1;
  endfunction : get_fmt3_subop

  // funct7 sub-opcode for the two-source funct3=000 family.
  virtual function bit get_fmt2_funct7(output bit [6:0] funct7);
    case (instr_name)
      CSETBOUNDS:      funct7 = 7'h08;
      CSETBOUNDSEXACT: funct7 = 7'h09;
      CSETBOUNDSRNDN:  funct7 = 7'h0a;
      CSEAL:           funct7 = 7'h0b;
      CUNSEAL:         funct7 = 7'h0c;
      CANDPERM:        funct7 = 7'h0d;
      CSETADDR:        funct7 = 7'h10;
      CINCADDR:        funct7 = 7'h11;
      CSUB:            funct7 = 7'h14;
      CSETHIGH:        funct7 = 7'h16;
      CTESTSUBSET:     funct7 = 7'h20;
      CISEQUAL:        funct7 = 7'h21;
      default:         return 1'b0;
    endcase
    return 1'b1;
  endfunction : get_fmt2_funct7

  // Build the 32-bit encoding. All CHERIoT instructions handled here use major
  // opcode 0x5b (ibex_pkg.sv:73-85).
  virtual function bit [31:0] get_cheriot_encoding();
    // Explicit casts rather than bit-selects: rd/rs1/rs2 are riscv_reg_t enums,
    // and selecting bits out of an enum directly is not portable across
    // simulators.
    bit [4:0]  rd_f  = 5'(rd);
    bit [4:0]  rs1_f = 5'(rs1);
    bit [4:0]  rs2_f = 5'(rs2);
    bit [4:0]  sub_op;
    bit [6:0]  funct7;
    bit [11:0] imm_f = imm[11:0];

    if (get_fmt3_subop(sub_op)) begin
      // fmt3: rd = op(cs1); instr[24:20] is a fixed sub-opcode, not a register.
      return {7'h7f, sub_op, rs1_f, 3'b000, rd_f, 7'h5b};
    end else if (get_fmt2_funct7(funct7)) begin
      // fmt2: rd = op(cs1, cs2)
      return {funct7, rs2_f, rs1_f, 3'b000, rd_f, 7'h5b};
    end else begin
      case (instr_name)
        // fmt1 immediate forms -- the whole of instr[31:20] is the immediate.
        CINCADDRIMM:   return {imm_f, rs1_f, 3'b001, rd_f, 7'h5b};
        CSETBOUNDSIMM: return {imm_f, rs1_f, 3'b010, rd_f, 7'h5b};
        default: begin
          `uvm_fatal(`gfn, $sformatf("Unhandled CHERIoT instruction %0s",
                                     instr_name.name()))
          return 32'h0;
        end
      endcase
    end
  endfunction : get_cheriot_encoding

  // Human-readable operand list for the trailing comment. Capability registers
  // are conventionally written with a 'c' prefix in the directed tests.
  virtual function string get_cheriot_operands();
    bit [4:0] sub_op;
    bit [6:0] funct7;
    if (get_fmt3_subop(sub_op)) begin
      return $sformatf("%0s, c%0s", rd.name(), rs1.name());
    end else if (get_fmt2_funct7(funct7)) begin
      return $sformatf("%0s, c%0s, %0s", rd.name(), rs1.name(), rs2.name());
    end else begin
      return $sformatf("%0s, c%0s, %0d", rd.name(), rs1.name(), imm[11:0]);
    end
  endfunction : get_cheriot_operands

  // Convert the instruction to assembly code
  virtual function string convert2asm(string prefix = "");
    string asm_str;
    bit [31:0] enc = get_cheriot_encoding();
    asm_str = format_string(".word", MAX_INSTR_STR_LEN);
    asm_str = $sformatf("%0s 0x%08x", asm_str, enc);
    // Mnemonic always goes in the comment: the assembler cannot parse it, but it
    // is what makes a generated program reviewable and lets the trace be matched
    // back to an instruction.
    comment = $sformatf("%0s %0s %0s", get_instr_name().tolower(),
                        get_cheriot_operands(), comment);
    asm_str = {asm_str, " # ", comment};
    return asm_str;
  endfunction : convert2asm

endclass : riscv_custom_instr
