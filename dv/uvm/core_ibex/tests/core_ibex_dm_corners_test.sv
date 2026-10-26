// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// core_ibex_dm_corners_test: debug-mode corner cases through the real debug module
// (REQ_DBG_03, REQ_DBG_04, REQ_DBG_05, REQ_SCR_01's debug extension). Needs the DM build:
//
//   make uvm-test-xlm TEST=dm_corners_cheriot DM=1     (CHERIoT mode: all phases)
//   make uvm-test-xlm TEST=dm_corners DM=1             (RISC-V mode: the dcsr.prv phases)
//
// Program: directed_tests/dm_corners/dm_corners.S, which lists the phases, the shared layout and
// the program's own checks. This side, over the DMI, in each phase the program publishes at
// G + 0x00:
//   first halt: an ecall and an illegal instruction (SCR 27) in the program buffer each end with
//     abstractcs.cmderr = 3 and leave mcause and mepc as they were (Debug Spec 4.1: exceptions in
//     debug mode update no register). These are the positive controls: they show that a fault
//     in the program buffer is visible, so cmderr = 0 below means none happened.
//   A (CHERIoT): three program buffers, each `lw t1; sw t2; clc t0; csc a5; ebreak` through one
//     authority: a5 (every access beyond its top), a4 (untagged), a3 (GL only). Each must end
//     with cmderr = 0 (REQ_DBG_03: no bounds, tag or permission fault in debug mode); t1 must
//     hold the word, memory the stored t2, t0 the capability in memory with its tag and with
//     no LG/LM attenuation, and the CSC target a5's image. The program buffer runs in the debug
//     memory, outside the program's bounded PCC and MTCC, so every fetch is out of PCC bounds.
//     Then SCRs 24-26: DEPCC read (tagged, address = dpc), DScratchC1 and DScratchC0 written
//     with a5 and read back (tag kept), cmderr = 0.
//   C1-C3 (CHERIoT): DEPCC := untagged gp, sealed tp, ra without EX, read back over the SCR
//     path; resume. The fault on the first fetch is the program's check.
//   D0-D3: dcsr.prv := 0, 1, 2, 3. The value read back must be a level the mode implements
//     (RISC-V Debug Spec 0.13 dcsr.prv WARL; the core spec: CHERIoT mode M only, RISC-V mode M
//     and U, never S), and the written value itself when it is one. misa (read at D0) must
//     agree: S never, U only in RISC-V mode. The mailbox carries the value to the program,
//     which checks that dret returned to it (ecall cause).
//
// +dm_inject_fail=1 replaces one expectation with a deliberately wrong one, so the test must
// fail: in CHERIoT mode phase A's first program buffer is expected to fault (cmderr 3), in
// RISC-V mode dcsr.prv := 3 is expected to read back 0. Run it to see the test go red.
class core_ibex_dm_corners_test extends core_ibex_dm_test;

  `uvm_component_utils(core_ibex_dm_corners_test)
  `uvm_component_new

  bit          inject_fail;
  bit          first_halt_done;
  int unsigned phases_done;

  // Shared with directed_tests/dm_corners/dm_corners.S
  localparam bit [31:0] GBase    = 32'h8000_0100;
  localparam bit [31:0] GPhase   = 32'h00;
  localparam bit [31:0] GBuf     = 32'h40;
  localparam bit [31:0] GUt      = 32'h68;
  localparam bit [31:0] GNp      = 32'h80;
  localparam bit [31:0] WOob     = 32'h0B0B_0001;
  localparam bit [31:0] WUt      = 32'h0B0B_0002;
  localparam bit [31:0] WNp      = 32'h0B0B_0003;
  localparam bit [31:0] StA1     = 32'h5700_00A1;
  localparam bit [31:0] StA2     = 32'h5700_00A2;
  localparam bit [31:0] StA3     = 32'h5700_00A3;
  localparam bit [31:0] PhA      = 32'h01;
  localparam bit [31:0] PhC1     = 32'h11;
  localparam bit [31:0] PhD0     = 32'h20;
  localparam bit [31:0] MagicHi  = 32'hD0D0_C000;

  // Registers
  localparam bit [4:0] XRa = 5'd1,  XGp = 5'd3,  XTp = 5'd4,  XT0 = 5'd5, XT1 = 5'd6, XT2 = 5'd7;
  localparam bit [4:0] XA2 = 5'd12, XA3 = 5'd13, XA4 = 5'd14, XA5 = 5'd15;
  localparam bit [15:0] RegMisa   = 16'h0301;
  localparam bit [15:0] RegMepc   = 16'h0341;
  localparam bit [15:0] RegMcause = 16'h0342;

  // SCRs (CHERIoT ISA; the debug extension of REQ_SCR_01)
  localparam bit [4:0] ScrDepcc = 5'd24, ScrDscratchC0 = 5'd25, ScrDscratchC1 = 5'd26;
  localparam bit [4:0] ScrUndefined = 5'd27;

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    void'($value$plusargs("dm_inject_fail=%0d", inject_fail));
    if (inject_fail) begin
      `uvm_info(`gfn, "+dm_inject_fail=1: one expectation is deliberately wrong; this run must FAIL",
                UVM_NONE)
    end
  endfunction

  virtual function void check_phase(uvm_phase phase);
    int unsigned exp_phases = cheriot_mode ? 8 : 4;
    super.check_phase(phase);
    if (phases_done != exp_phases) begin
      `uvm_error(`gfn, $sformatf("Only %0d of the %0d debug phases ran", phases_done, exp_phases))
    end
  endfunction

  /////////////////////////////
  // Instruction encodings   //
  /////////////////////////////
  // RV32I and the CHERIoT encodings of cheriot_dv.h (CHERIoT-Sail cheri_insts.sail encdec).

  function bit [31:0] enc_lw(bit [4:0] rd, bit [4:0] rs1, bit [11:0] imm);
    return {imm, rs1, 3'b010, rd, 7'h03};
  endfunction

  function bit [31:0] enc_sw(bit [4:0] rs2, bit [4:0] rs1, bit [11:0] imm);
    return {imm[11:5], rs2, rs1, 3'b010, imm[4:0], 7'h23};
  endfunction

  function bit [31:0] enc_clc(bit [4:0] cd, bit [4:0] cs1, bit [11:0] imm);
    return {imm, cs1, 3'b011, cd, 7'h03};
  endfunction

  function bit [31:0] enc_csc(bit [4:0] cs2, bit [4:0] cs1, bit [11:0] imm);
    return {imm[11:5], cs2, cs1, 3'b011, imm[4:0], 7'h23};
  endfunction

  // CSpecialRW cd, scr, cs1 (cs1 = c0: read only; cd = c0: write only)
  function bit [31:0] enc_cspecialrw(bit [4:0] cd, bit [4:0] scr, bit [4:0] cs1);
    return {7'h01, scr, cs1, 3'b000, cd, 7'h5b};
  endfunction

  function bit [31:0] enc_ccleartag(bit [4:0] cd, bit [4:0] cs1);
    return {7'h7f, 5'd11, cs1, 3'b000, cd, 7'h5b};
  endfunction

  localparam bit [31:0] InsnEcall = 32'h0000_0073;

  /////////////////////////////
  // DM helpers              //
  /////////////////////////////

  // Load the program buffer (the last instruction must be ebreak) and run it (postexec, no
  // transfer). Returns abstractcs.cmderr.
  task run_progbuf(string what, bit [31:0] insns[$], output bit [2:0] cmderr);
    if (insns.size() > 8 || insns.size() == 0 || insns[$] != InsnEbreak) begin
      `uvm_fatal(`gfn, $sformatf("%s: a program buffer is 1-8 instructions ending in ebreak", what))
    end
    foreach (insns[i]) dmi.write_reg(DmiProgbuf0 + i, insns[i]);
    run_cmd(ar_cmd(3'd2, 1'b1, 1'b0, 1'b0, 16'h0), cmderr);
    `uvm_info(`gfn, $sformatf("Program buffer '%s': cmderr %0d", what, cmderr), UVM_LOW)
  endtask

  task expect_cmderr(string what, bit [2:0] cmderr, bit [2:0] expected);
    chk({what, ": abstractcs.cmderr"}, cmderr, expected);
    if (cmderr != CmdErrNone) clear_cmderr();
  endtask

  task halt_hart(string what);
    bit [31:0] dmstatus;
    dmi.write_reg(DmiDmcontrol, DmcontrolHaltreq | DmcontrolDmactive);
    poll_dmstatus(StAllhalted, "allhalted", dmstatus);
    dmi.write_reg(DmiDmcontrol, DmcontrolDmactive);
    chk({what, ": core in debug mode after allhalted"}, dut_vif.debug_mode, 1'b1);
    `uvm_info(`gfn, {"Hart halted: ", what}, UVM_LOW)
    if (!first_halt_done) begin
      first_halt_done = 1'b1;
      trap_probes();
    end
  endtask

  task resume_hart(string what);
    bit [31:0] dmstatus;
    dmi.write_reg(DmiDmcontrol, DmcontrolResumereq | DmcontrolDmactive);
    poll_dmstatus(StAllresumeack, "allresumeack", dmstatus);
    dmi.write_reg(DmiDmcontrol, DmcontrolDmactive);
    clk_vif.wait_clks(50);
    chk({what, ": core out of debug mode after resume"}, dut_vif.debug_mode, 1'b0);
    phases_done++;
  endtask

  // Wait until the program publishes phase ph (white-box read of the bench memory).
  task wait_phase(bit [31:0] ph);
    int unsigned n = 0;
    while (mem.read(GBase + GPhase) !== ph) begin
      clk_vif.wait_clks(20);
      if (++n > 200000) begin
        `uvm_fatal(`gfn, $sformatf("The program never reached phase 0x%02x (last 0x%02x)", ph,
                                   mem.read(GBase + GPhase)))
      end
    end
  endtask

  function bit [63:0] mem_cap(bit [31:0] addr);
    return {mem.read(addr + 4), mem.read(addr)};
  endfunction

  task write_mailbox(bit [7:0] data);
    reg_write32("a2 (mailbox)", RegGpr + XA2, MagicHi | data);
  endtask

  /////////////////////////////
  // Checks                  //
  /////////////////////////////

  // Exceptions in the program buffer: cmderr 3, no register updated.
  task trap_probes();
    bit [31:0] mcause0, mepc0, rd;
    bit [2:0]  cmderr;
    reg_read32("mcause", RegMcause, mcause0);
    reg_read32("mepc", RegMepc, mepc0);
    run_progbuf("ecall", '{InsnEcall, InsnEbreak}, cmderr);
    expect_cmderr("ecall in the program buffer", cmderr, CmdErrException);
    run_progbuf("CSpecialRW of SCR 27", '{enc_cspecialrw(XT0, ScrUndefined, 5'd0), InsnEbreak},
                cmderr);
    expect_cmderr("illegal instruction (SCR 27) in the program buffer", cmderr, CmdErrException);
    reg_read32("mcause", RegMcause, rd);
    chk("mcause unchanged by exceptions in debug mode", rd, mcause0);
    reg_read32("mepc", RegMepc, rd);
    chk("mepc unchanged by exceptions in debug mode", rd, mepc0);
  endtask

  // One authority: lw t1, sw t2, clc t0, csc a5 at the given offsets from its cursor.
  task bypass_probe(string what, bit [4:0] auth, bit [31:0] cursor, bit [11:0] o_lw,
                    bit [11:0] o_sw, bit [11:0] o_clc, bit [11:0] o_csc, bit [31:0] w_exp,
                    bit [31:0] st_val, bit inject_here);
    bit [31:0] rd;
    bit [63:0] rd64, a5_img;
    bit [2:0]  cmderr;
    bit        tag;
    reg_write32("t2", RegGpr + XT2, st_val);
    run_progbuf(what, '{enc_lw(XT1, auth, o_lw), enc_sw(XT2, auth, o_sw),
                        enc_clc(XT0, auth, o_clc), enc_csc(XA5, auth, o_csc), InsnEbreak}, cmderr);
    if (inject_here) begin
      `uvm_info(`gfn, "dm_inject_fail: expecting a capability fault (cmderr 3) on purpose", UVM_NONE)
    end
    expect_cmderr({what, ": no capability fault in debug mode"}, cmderr,
                  inject_here ? CmdErrException : CmdErrNone);
    reg_read32("t1", RegGpr + XT1, rd);
    chk({what, ": lw loaded the word"}, rd, w_exp);
    chk({what, ": sw stored t2"}, mem.read(cursor + o_sw), st_val);
    reg_read64("t0", RegGpr + XT0, rd64, tag);
    chk({what, ": clc loaded the capability in memory, unattenuated"}, rd64,
        mem_cap(cursor + o_clc));
    chk({what, ": clc capability's address (the slot)"}, rd64[31:0], cursor + o_clc);
    chk({what, ": clc kept the tag"}, tag, 1'b1);
    reg_read64("a5", RegGpr + XA5, a5_img, tag);
    chk({what, ": csc stored a5"}, mem_cap(cursor + o_csc), a5_img);
  endtask

  task scr_probe();
    bit [31:0] dpc;
    bit [63:0] a5_img, rd64;
    bit [2:0]  cmderr;
    bit        tag;
    reg_read32("dpc", RegDpc, dpc);
    reg_read64("a5", RegGpr + XA5, a5_img, tag);
    chk("a5 tag", tag, 1'b1);
    run_progbuf("SCRs 24-26", '{enc_cspecialrw(XT0, ScrDepcc, 5'd0),
                                enc_cspecialrw(5'd0, ScrDscratchC1, XA5),
                                enc_cspecialrw(XT1, ScrDscratchC1, 5'd0),
                                enc_cspecialrw(5'd0, ScrDscratchC0, XA5),
                                enc_cspecialrw(XT2, ScrDscratchC0, 5'd0),
                                InsnEbreak}, cmderr);
    expect_cmderr("SCRs 24-26 in debug mode: accessible", cmderr, CmdErrNone);
    reg_read64("t0 (DEPCC)", RegGpr + XT0, rd64, tag);
    chk("DEPCC read in the program buffer: address = dpc", rd64[31:0], dpc);
    chk("DEPCC read in the program buffer: tagged", tag, 1'b1);
    reg_read64("t1 (DScratchC1)", RegGpr + XT1, rd64, tag);
    chk("DScratchC1 written and read back", rd64, a5_img);
    chk("DScratchC1 kept the tag", tag, 1'b1);
    reg_read64("t2 (DScratchC0)", RegGpr + XT2, rd64, tag);
    chk("DScratchC0 written and read back", rd64, a5_img);
    chk("DScratchC0 kept the tag", tag, 1'b1);
  endtask

  // DEPCC := src (ccleartag first if untag), then resume; the program checks the fault.
  task depcc_phase(int k, string what, bit [4:0] src, bit untag);
    bit [63:0] src_img, rd64;
    bit [2:0]  cmderr;
    bit        src_tag, tag;
    bit [31:0] insns[$];
    wait_phase(PhC1 + k);
    halt_hart({"DEPCC ", what});
    reg_read64("DEPCC source", RegGpr + src, src_img, src_tag);
    chk({"DEPCC source (", what, ") is tagged"}, src_tag, 1'b1);
    if (untag) begin
      insns = '{enc_ccleartag(XT0, src), enc_cspecialrw(5'd0, ScrDepcc, XT0), InsnEbreak};
    end else begin
      insns = '{enc_cspecialrw(5'd0, ScrDepcc, src), InsnEbreak};
    end
    run_progbuf({"DEPCC := ", what}, insns, cmderr);
    expect_cmderr({"DEPCC := ", what}, cmderr, CmdErrNone);
    reg_read64({"DEPCC (", what, ")"}, RegScrDepcc, rd64, tag);
    chk({"DEPCC (", what, ") as written"}, rd64, src_img);
    chk({"DEPCC (", what, ") tag"}, tag, !untag);
    resume_hart({"DEPCC ", what});
  endtask

  task prv_phase(int v);
    bit [31:0] dcsr0, dcsr1, misa;
    bit [1:0]  r, expected;
    bit        legal;
    wait_phase(PhD0 + v);
    halt_hart($sformatf("dcsr.prv := %0d", v));
    if (v == 0) begin
      reg_read32("misa", RegMisa, misa);
      chk("misa.S (no S-mode in either mode)", misa[18], 1'b0);
      chk("misa.U (U-mode in RISC-V mode only)", misa[20], !cheriot_mode);
    end
    reg_read32("dcsr", RegDcsr, dcsr0);
    chk("dcsr.prv at the halt (the program runs at M)", dcsr0[1:0], 2'd3);
    dmi.write_reg(DmiData0, {dcsr0[31:2], v[1:0]});
    run_cmd_ok($sformatf("write dcsr.prv = %0d", v), ar_cmd(3'd2, 1'b0, 1'b1, 1'b1, RegDcsr));
    reg_read32("dcsr after the write", RegDcsr, dcsr1);
    r = dcsr1[1:0];
    // Implemented: M always; U in RISC-V mode only (core spec, privilege modes); S never.
    legal = (r == 2'd3) || (r == 2'd0 && !cheriot_mode);
    n_checks++;
    if (!legal) begin
      `uvm_error(`gfn, $sformatf("DM check FAILED: dcsr.prv := %0d read back %0d, a level the %s mode does not implement",
                                 v, r, cheriot_mode ? "CHERIoT" : "RISC-V"))
    end
    if (v == 3 || (v == 0 && !cheriot_mode)) begin
      expected = v[1:0];
      if (inject_fail && !cheriot_mode && v == 3) begin
        `uvm_info(`gfn, "dm_inject_fail: expecting dcsr.prv 0 after writing 3, on purpose", UVM_NONE)
        expected = 2'd0;
      end
      chk($sformatf("dcsr.prv := %0d (implemented) reads back as written", v), r, expected);
    end
    write_mailbox({6'h0, r});
    resume_hart($sformatf("dcsr.prv := %0d", v));
  endtask

  /////////////////////////////
  // The sequence            //
  /////////////////////////////

  virtual task dm_sequence();
    bit [31:0] rd;

    wait_for_core_status(INITIALIZED);
    `uvm_info(`gfn, $sformatf("Program initialised; debug corner cases (%s mode)",
                              cheriot_mode ? "CHERIoT" : "RISC-V"), UVM_LOW)
    dmi.write_reg(DmiDmcontrol, DmcontrolDmactive);
    dmi.read_reg(DmiDmcontrol, rd);
    chk("dmcontrol.dmactive", rd[0], 1'b1);

    if (cheriot_mode) begin
      // ── A: capability checks bypassed in debug mode ──────────────────────────────────────
      wait_phase(PhA);
      halt_hart("phase A");
      bypass_probe("beyond a5's top", XA5, GBase + GBuf, 12'h10, 12'h14, 12'h18, 12'h20,
                   WOob, StA1, inject_fail);
      bypass_probe("untagged a4", XA4, GBase + GUt, 12'h0, 12'h4, 12'h8, 12'h10,
                   WUt, StA2, 1'b0);
      bypass_probe("a3 without LD/SD/MC/LM/LG", XA3, GBase + GNp, 12'h0, 12'h4, 12'h8, 12'h10,
                   WNp, StA3, 1'b0);
      scr_probe();
      write_mailbox(8'h0A);
      resume_hart("phase A");

      // ── C1-C3: bad DEPCC, then dret ───────────────────────────────────────────────────────
      depcc_phase(0, "untagged", XGp, 1'b1);
      depcc_phase(1, "sealed", XTp, 1'b0);
      depcc_phase(2, "without EX", XRa, 1'b0);
    end

    // ── D0-D3: dcsr.prv ─────────────────────────────────────────────────────────────────────
    for (int v = 0; v < 4; v++) prv_phase(v);
    `uvm_info(`gfn, "All phases done; the program now makes its last checks", UVM_LOW)
  endtask

endclass
