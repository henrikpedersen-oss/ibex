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

// CSpecialRW (cheri_insts.sail: 0b0000001 @ scr @ cs1 @ 0b000 @ cd @ 0b1011011). Deliberately
// not in the random RV32X set (it traps without PCC.SR and for SCRs other than 28-31); only the
// capability seed stream below emits it, for MTDC/MScratchC reads with cs1 = c0. instr_name is a
// placeholder (CMOVE) so the rest of riscv-dv sees an ordinary non-branch ARITHMETIC RV32X
// instruction; the encoding and mnemonic come from the overrides.
class ibex_cheriot_cspecialrw_instr extends riscv_custom_instr;

  `uvm_object_utils(ibex_cheriot_cspecialrw_instr)

  bit [4:0] scr;

  function new(string name = "");
    super.new(name);
    instr_name = CMOVE;
    format     = R_FORMAT;
    category   = ARITHMETIC;
    group      = RV32X;
  endfunction

  virtual function string get_instr_name();
    return (rs1 == ZERO) ? "cspecialr" : "cspecialrw";
  endfunction

  virtual function bit [31:0] get_cheriot_encoding();
    return {7'h01, scr, 5'(rs1), 3'b000, 5'(rd), 7'h5b};
  endfunction

  virtual function string get_cheriot_operands();
    return $sformatf("c%0s, scr%0d, c%0s", rd.name(), scr, rs1.name());
  endfunction

endclass

// Seeds a few registers with meaningful capabilities, so that the random RV32X instructions
// (CSetBounds, CSeal, CUnseal, CTestSubset, CSetAddr, ...) operate on tagged, bounded and sealed
// operands rather than almost exclusively on untagged integers -- in a stock random program
// every register is written by integer instructions, and an integer write clears the tag.
//
// Every value is derived from an architectural root, as software would derive it (CHERIoT-Sail
// semantics throughout; nothing here can trap with PCC = the reset execution root):
//   data     cspecialr cR, MTDC; csetaddr cR, cR, <address>; csetbounds cR, cR, <len>,
//            optionally candperm
//   code     auipcc cR, 0; csetboundsimm cR, cR, <len>
//   sealing  cspecialr cR, MScratchC (the reset sealing root, address 0); cincaddrimm cR, cR,
//            <otype> -- left in its register as a valid authority for random CSeal/CUnseal
//   sealed   a data capability sealed with that authority (otype 9-15)
// Registers come from x1-x15 minus every register riscv-dv reserves for a role (sp, tp, ra,
// scratch_reg, gpr[], pmp_reg[]), so no role register is clobbered. If fewer than two are left
// the stream emits nothing.
//
// Used at the start of every main program by ibex_cheriot_instr_sequence, and available as a
// periodic re-seed: +directed_instr_N=ibex_cheriot_cap_seed_stream,<count>.
class ibex_cheriot_cap_seed_stream extends riscv_directed_instr_stream;

  `uvm_object_utils(ibex_cheriot_cap_seed_stream)

  function new(string name = "");
    super.new(name);
  endfunction

  local function riscv_instr cheri_rr(riscv_instr_name_t name, riscv_reg_t rd, riscv_reg_t rs1,
                                      riscv_reg_t rs2);
    riscv_instr i = riscv_instr::get_instr(name);
    i.rd = rd; i.rs1 = rs1; i.rs2 = rs2;
    i.atomic = 1'b1;
    return i;
  endfunction

  local function riscv_instr cheri_ri(riscv_instr_name_t name, riscv_reg_t rd, riscv_reg_t rs1,
                                      bit [11:0] imm12);
    riscv_instr i = riscv_instr::get_instr(name);
    i.rd = rd; i.rs1 = rs1; i.imm = 32'(imm12);
    i.atomic = 1'b1;
    return i;
  endfunction

  local function riscv_instr scr_read(riscv_reg_t rd, bit [4:0] scr);
    ibex_cheriot_cspecialrw_instr i;
    i = ibex_cheriot_cspecialrw_instr::type_id::create("cspecialr");
    i.rd = rd; i.rs1 = ZERO; i.scr = scr;
    i.atomic = 1'b1;
    return i;
  endfunction

  local function riscv_instr li(riscv_reg_t rd, bit [31:0] val);
    riscv_pseudo_instr i = riscv_pseudo_instr::type_id::create("li");
    i.pseudo_instr_name = LI;
    i.rd = rd;
    i.imm_str = $sformatf("0x%0x", val);
    i.atomic = 1'b1;
    return i;
  endfunction

  local function riscv_instr la(riscv_reg_t rd, string sym);
    riscv_pseudo_instr i = riscv_pseudo_instr::type_id::create("la");
    i.pseudo_instr_name = LA;
    i.rd = rd;
    i.imm_str = sym;
    i.atomic = 1'b1;
    return i;
  endfunction

  // A directed stream must not be empty (riscv-dv indexes instr_list[0]); emit one nop instead.
  local function void emit_nop();
    instr_list = {riscv_instr::get_instr(NOP)};
    super.post_randomize();
  endfunction

  function void post_randomize();
    riscv_reg_t  pool[$];
    riscv_reg_t  tmp;
    riscv_reg_t  seal_reg;
    riscv_instr  seq[$];
    int unsigned n_seed;

    // The RV32X instructions are only registered when +march carries RV32X.
    if (!riscv_instr::instr_template.exists(CSETADDR)) begin
      emit_nop();
      return;
    end

    for (int r = int'(RA); r <= int'(A5); r++) begin
      riscv_reg_t reg_r = riscv_reg_t'(r);
      if (reg_r inside {cfg.reserved_regs, cfg.ra, cfg.sp, cfg.tp, cfg.scratch_reg,
                        cfg.gpr, cfg.pmp_reg}) continue;
      pool.push_back(reg_r);
    end
    if (pool.size() < 2) begin
      `uvm_info(`gfn, $sformatf("Only %0d free registers, no capability seeding", pool.size()),
                UVM_LOW)
      emit_nop();
      return;
    end
    pool.shuffle();
    tmp = pool.pop_front();        // integer operand register; ends up holding the sealer
    seal_reg = tmp;
    n_seed = (pool.size() > 4) ? 4 : pool.size();

    foreach (pool[i]) begin
      riscv_reg_t cr = pool[i];
      int unsigned kind;
      bit [11:0]   len;
      if (i >= n_seed) break;
      kind = $urandom_range(3, 0);
      len  = 12'($urandom_range(511, 8) & ~7);
      case (kind)
        0, 3: begin   // bounded data capability (3: also sealed, below)
          seq.push_back(scr_read(cr, 5'd29));                                   // MTDC
          if (cfg.mem_region.size() > 0 && cfg.mem_region[0].size_in_bytes > 512) begin
            seq.push_back(la(tmp, $sformatf("%0s+%0d", cfg.mem_region[0].name,
                                            $urandom_range(cfg.mem_region[0].size_in_bytes - 512,
                                                           0) & ~7)));
          end else begin
            seq.push_back(li(tmp, 32'h8010_0000 + ($urandom_range(32'hFFF0, 0) & ~7)));
          end
          seq.push_back(cheri_rr(CSETADDR, cr, cr, tmp));
          seq.push_back(li(tmp, 32'(len)));
          seq.push_back(cheri_rr(CSETBOUNDS, cr, cr, tmp));
          if ($urandom_range(1, 0)) begin
            seq.push_back(li(tmp, $urandom_range(12'hFFF, 0)));
            seq.push_back(cheri_rr(CANDPERM, cr, cr, tmp));
          end
          if (kind == 3) begin
            seq.push_back(scr_read(tmp, 5'd30));                                // MScratchC
            seq.push_back(cheri_ri(CINCADDRIMM, tmp, tmp, 12'($urandom_range(15, 9))));
            seq.push_back(cheri_rr(CSEAL, cr, cr, tmp));
          end
        end
        1: begin      // bounded code capability
          riscv_instr auipcc = riscv_instr::get_instr(AUIPC);
          auipcc.rd = cr;
          auipcc.imm_str = "0";
          auipcc.atomic = 1'b1;
          seq.push_back(auipcc);
          seq.push_back(cheri_ri(CSETBOUNDSIMM, cr, cr, len));
        end
        2: begin      // copy of the sealing root, cursor on a random otype
          seq.push_back(scr_read(cr, 5'd30));
          seq.push_back(cheri_ri(CINCADDRIMM, cr, cr, 12'($urandom_range(15, 1))));
        end
      endcase
    end
    // Leave a valid sealing authority in tmp for the random CSeal/CUnseal that follow.
    seq.push_back(scr_read(seal_reg, 5'd30));
    seq.push_back(cheri_ri(CINCADDRIMM, seal_reg, seal_reg, 12'($urandom_range(15, 9))));

    instr_list = seq;
    super.post_randomize();
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
    // Seed meaningful capabilities before the first random CHERI instruction of the main
    // program (+cheriot_cap_seed=0 turns it off). Inserted at the front of the stream, before
    // post_process_instr() labels and links it.
    if (is_main_program) begin
      bit seed_en = 1'b1;
      void'($value$plusargs("cheriot_cap_seed=%0d", seed_en));
      if (seed_en) begin
        ibex_cheriot_cap_seed_stream seed;
        seed = ibex_cheriot_cap_seed_stream::type_id::create("cheriot_cap_seed");
        seed.cfg = cfg;
        `DV_CHECK_RANDOMIZE_FATAL(seed)
        if (seed.instr_list.size() > 0) instr_stream.insert_instr_stream(seed.instr_list, 0);
      end
    end
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
  // sp/tp/scratch_reg are kept out of x8-x15, not merely inside x1-x15.
  //
  // Those three are what riscv-dv puts in cfg.reserved_regs, and
  // randomize_gpr() (riscv_instr_stream.sv:299-306) excludes reserved_regs from
  // rs1 whenever the instruction is CB_FORMAT. CB_FORMAT is compressed branch
  // (c.beqz/c.bnez), whose rs1 is a 3-bit field and so is *already* restricted
  // to x8-x15. Allowing a reserved register into that window eats one of only
  // eight legal values, and with three of them in there the solver can run out
  // entirely:
  //
  //   UVM_FATAL riscv_instr_stream.sv(308) [jump_instr] Randomization failed!
  //     format               = CB_FORMAT
  //     cfg.reserved_regs[2] = S0 (0x8)      <-- scratch_reg had drawn x8
  //     rs1                  = <unassigned>
  //
  // That is seed-dependent (23043 failed, 12042-12044 passed), and because the
  // generator still exits zero on UVM_FATAL it took the whole nyx regression
  // down with it on 2026-09-24 rather than failing just this test.
  //
  // RA:T2 is x1-x7, which is inside CHERIoT's legal x0-x15 and clear of the
  // compressed window. Four distinct registers (ra, sp, tp, scratch_reg) into
  // seven slots always solves.
  //
  // gpr[]/pmp_reg[] stay on the wider range: they are not in reserved_regs, so
  // they do not constrain rs1, and confining ten distinct role registers to
  // x1-x7 would itself be unsatisfiable.
  constraint cheriot_reg_roles_c {
    sp          inside {[RA : T2]};
    tp          inside {[RA : T2]};
    ra          inside {[RA : T2]};
    scratch_reg inside {[RA : T2]};
    foreach (gpr[i])     { gpr[i]     inside {[RA : A5]}; }
    foreach (pmp_reg[i]) { pmp_reg[i] inside {[RA : A5]}; }
  }

  function new(string name = "");
    super.new(name);
  endfunction

endclass
