// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Restricts a generated program to the 16 registers CHERIoT allows.
//
// ibex_decoder.sv's illegal_reg_16 makes ANY access to x16-x31 an illegal instruction
// once cheriot_enable_i is asserted. It checks rf_ren_a, rf_ren_b, rs3 and rd, so
// plain integer loads and stores trip it too -- this is not limited to capability
// opcodes. riscv-dv has no RV32E or 16-register mode of its own, so a stock random
// program roams all 32 registers and cannot run in CHERIoT mode at all.
//
// NUM_GPR in riscv_core_setting.sv is not the lever despite the name -- it is read in
// exactly one place, the init_gpr() loop in riscv_asm_program_gen.sv, and does not
// affect operand selection.
//
// There are four independent register-selection paths, and all four have to be
// pinned or the program still traps:
//
//   1. the main/sub instruction streams  -> instr_stream.avail_regs
//   2. the stack push prologue           -> instr_stack_enter.avail_regs
//   3. the stack pop epilogue            -> instr_stack_exit.avail_regs
//   4. the callstack jump instructions   -> riscv_jump_instr's own `gpr` field,
//                                           which ignores avail_regs entirely
//
// Paths 1-3 work because randomize_gpr() in riscv_instr_stream.sv constrains
// rs1/rs2/rd to avail_regs whenever that array is non-empty, and leaves all three
// unconstrained when it is empty -- the default, since nothing populates it. It is
// also the only lever that reaches rs2: cfg.reserved_regs constrains rd alone (plus
// rs1 for CB_FORMAT). Path 4 needs a subclass because riscv_jump_instr declares
// `rand riscv_reg_t gpr` and constrains it only against cfg.reserved_regs.
//
// Selected per test with +instr_seq=ibex_cheriot_instr_sequence in gen_opts, via the
// factory override riscv_instr_base_test already provides. It is opt-in because
// restricting registers would needlessly narrow non-CHERIoT random tests.

// In the riscv_reg_t enum A5 is x15 and A6 is x16, so indices 0..15 are exactly the
// registers illegal_reg_16 permits. Reserved registers are not filtered out here:
// randomize_gpr() already excludes cfg.reserved_regs and reserved_rd from rd on top of
// this, and dropping SP would additionally disable the C_ADDI4SPN/C_ADDI16SP/C_LWSP/
// C_LDSP compressed forms.
function automatic void ibex_cheriot_limit_regs(riscv_instr_stream s);
  if (s == null) return;
  s.avail_regs = new[16];
  foreach (s.avail_regs[i]) begin
    s.avail_regs[i] = riscv_reg_t'(i);
  end
endfunction

// Callstack jumps: riscv_jump_instr picks its address register from its own `gpr`
// field rather than avail_regs, so it needs its own bound. The base class already
// constrains gpr against cfg.reserved_regs and ZERO; this narrows it to x0-x15, and
// the two constraints conjoin.
class ibex_cheriot_jump_instr extends riscv_jump_instr;

  `uvm_object_utils(ibex_cheriot_jump_instr)

  constraint cheriot_gpr_c {
    gpr inside {[ZERO : A5]};
  }

  function new(string name = "");
    super.new(name);
  endfunction

  function void pre_randomize();
    super.pre_randomize();
    // Covers the filler instructions riscv_jump_instr mixes in around the jump.
    ibex_cheriot_limit_regs(this);
  endfunction

endclass

class ibex_cheriot_instr_sequence extends riscv_instr_sequence;

  `uvm_object_utils(ibex_cheriot_instr_sequence)

  function new(string name = "");
    uvm_coreservice_t coreservice;
    uvm_factory       factory;
    super.new(name);
    // gen_stack_enter_instr()/insert_jump_instr() are not virtual, so the jump stream
    // cannot be reached by overriding a method. It is created with
    // riscv_jump_instr::type_id::create() inside insert_jump_instr(), so a factory
    // override does reach it. Registered here because this runs well before
    // post_process_instr() inserts any jumps.
    coreservice = uvm_coreservice_t::get();
    factory     = coreservice.get_factory();
    factory.set_type_override_by_name("riscv_jump_instr", "ibex_cheriot_jump_instr");
  endfunction

  virtual function void gen_instr(bit is_main_program, bit no_branch = 1'b0);
    // instr_stack_enter/instr_stack_exit are separate stream objects with their own
    // empty avail_regs. gen_stack_enter_instr() is not virtual, but it runs inside
    // super.gen_instr() below and reads these members, so pinning them here is
    // enough -- without it the *_stack_p prologues kept emitting x16-x31.
    ibex_cheriot_limit_regs(instr_stream);
    ibex_cheriot_limit_regs(instr_stack_enter);
    ibex_cheriot_limit_regs(instr_stack_exit);
    super.gen_instr(is_main_program, no_branch);
  endfunction

endclass

// Pins the register *roles* to x0-x15.
//
// The three streams above only choose operands. riscv_instr_gen_config separately
// randomizes WHICH register plays each structural role -- sp, tp, ra, scratch_reg,
// gpr[4] and pmp_reg[2] are all `rand riscv_reg_t` with no upper bound. Left alone it
// duly picked sp=s6 (x22) and ra=t5 (x30), so every stack prologue emitted
// "addi s6, s6, -12" and every callstack jump "jal t5, ...", regardless of how
// tightly the instruction streams themselves were constrained.
//
// This also explains why excluding cfg.reserved_regs is never sufficient on its own:
// reserved_regs is {tp, sp, scratch_reg}, i.e. whichever registers were drawn for
// those roles, not the literal SP/TP.
//
// Registered with +uvm_set_type_override=riscv_instr_gen_config,ibex_cheriot_instr_gen_config
// rather than from code: riscv_instr_base_test creates cfg in its build_phase, which
// runs before any object here exists, so there is no earlier hook to register from.
class ibex_cheriot_instr_gen_config extends riscv_instr_gen_config;

  `uvm_object_utils(ibex_cheriot_instr_gen_config)

  // RA is x1 and A5 is x15, so this is x1-x15: the registers illegal_reg_16 permits,
  // minus x0. The lower bound must exclude ZERO -- a role register drawn as x0 is
  // meaningless (a stack pointer or link register that discards every write), and
  // riscv_jump_instr branches on `cfg.ra != RA`, so a zero ra sends it down a path
  // whose operand constraints then have no solution. Allowing ZERO here produced
  // "UVM_FATAL [jump_instr] Randomization failed" and no program at all.
  //
  // Conjoins with the base class's gpr_c, which additionally keeps gpr[] clear of
  // sp/tp/scratch_reg/pmp_reg/ZERO/RA/GP and unique.
  constraint cheriot_reg_roles_c {
    sp          inside {[RA : A5]};
    tp          inside {[RA : A5]};
    ra          inside {[RA : A5]};
    scratch_reg inside {[RA : A5]};
    foreach (gpr[i])     { gpr[i]     inside {[RA : A5]}; }
    foreach (pmp_reg[i]) { pmp_reg[i] inside {[RA : A5]}; }
  }

  function new(string name = "");
    super.new(name);
  endfunction

endclass
