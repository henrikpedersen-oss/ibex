// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Tests of the core with the real RISC-V debug module (vendor/pulp_riscv_dbg dm_top, CHERIoT
// patches), driven over its DMI port. They need the DM build of the testbench:
//
//   make uvm-test-xlm TEST=dm_basic,dm_basic_cheriot DM=1
//
// (compile_tb.py: +define+IBEX_DM_REAL, ibex_dv_dm.f; core_ibex_tb_top.sv "Real debug module").

// Minimal DMI host: one request at a time on ibex_dm_dmi_if, no JTAG DTM in between.
class core_ibex_dmi_host extends uvm_object;

  `uvm_object_utils(core_ibex_dmi_host)

  virtual ibex_dm_dmi_if vif;
  int unsigned           timeout_cycles = 50000;

  // dm::dtm_op_e
  localparam bit [1:0] DtmRead  = 2'h1;
  localparam bit [1:0] DtmWrite = 2'h2;

  function new(string name = "core_ibex_dmi_host");
    super.new(name);
  endfunction

  // One DMI transaction. The request is accepted at the first clock edge with req_valid and
  // req_ready both high; the DM's response FIFO (dm_csrs, not pass-through) answers on a later
  // edge, and resp_ready is held high, so the response is taken in the first cycle it is valid.
  task access(bit [1:0] op, bit [31:0] addr, bit [31:0] wdata, output bit [31:0] rdata);
    int unsigned n = 0;
    @(vif.cb);
    vif.cb.resp_ready <= 1'b1;
    vif.cb.req_addr   <= addr;
    vif.cb.req_op     <= op;
    vif.cb.req_data   <= wdata;
    vif.cb.req_valid  <= 1'b1;
    do begin
      @(vif.cb);
      if (++n > timeout_cycles) begin
        `uvm_fatal(`gfn, $sformatf("DMI request to 0x%02x not accepted within %0d cycles",
                                   addr, timeout_cycles))
      end
    end while (vif.cb.req_ready !== 1'b1);
    vif.cb.req_valid <= 1'b0;
    n = 0;
    while (vif.cb.resp_valid !== 1'b1) begin
      @(vif.cb);
      if (++n > timeout_cycles) begin
        `uvm_fatal(`gfn, $sformatf("No DMI response for the access to 0x%02x within %0d cycles",
                                   addr, timeout_cycles))
      end
    end
    rdata = vif.cb.resp_data;
    // dm::dtm_op_status_e: 0 success, 2 error, 3 busy (an abstract command was still running)
    if (vif.cb.resp_resp !== 2'h0) begin
      `uvm_error(`gfn, $sformatf("DMI %s of 0x%02x answered with status %0d (2 = error, 3 = busy)",
                                 (op == DtmWrite) ? "write" : "read", addr, vif.cb.resp_resp))
    end
  endtask

  task write_reg(bit [31:0] addr, bit [31:0] data);
    bit [31:0] unused;
    access(DtmWrite, addr, data, unused);
  endtask

  task read_reg(bit [31:0] addr, output bit [31:0] data);
    access(DtmRead, addr, '0, data);
  endtask

endclass

// core_ibex_dm_test: halt, inspect, modify and resume a running program through the debug module.
//
// Program: directed_tests/dm_basic/dm_basic.S (RISC-V mode) and dm_basic_cheriot (the same source
// with DM_CHERIOT, run with +enable_cheriot_seq=1). It fills registers with known values, writes
// the expected capability images and its wait-loop bounds to dm_expect (ExpBase), reports
// CORE_STATUS INITIALIZED and spins until a2 holds DmMagic.
//
// This side (dm_sequence below), all over the DMI:
//   activate (dmcontrol.dmactive), check dmstatus / hartinfo / abstractcs reset values
//   halt (haltreq, dmstatus.allhalted), check the core really is in debug mode
//   abstract register reads, 32-bit: GPRs, dcsr (cause = haltreq), dpc (inside the wait loop)
//   CHERIoT mode only, 64-bit (aarsize 3, address in data0, metadata in data1): capability GPRs
//     against the program's own csc images, an integer GPR (null metadata), DEPCC through the SCR
//     path (regno = SCR number); the tag, which the DMI cannot carry, from the testbench's
//     observation of the core's store to data0
//   an abstract command that must fail with cmderr = exception (RISC-V: an unimplemented CSR;
//     CHERIoT: x16, which does not exist in CHERIoT mode) and, in RISC-V mode, the 64-bit access
//     that must be refused with cmderr = not supported; cmderr cleared afterwards
//   program buffer: addi a1, a1, 0x111; ebreak (postexec without transfer), a1 read back
//   abstract register writes: x20 (RISC-V) or a 64-bit capability write to a4 (CHERIoT, read
//     back, untagged by construction), then the mailbox a2 := DmMagic
//   resume (resumereq, dmstatus.allresumeack / allrunning), the core out of debug mode
// The program then checks every register the debugger wrote or must have left alone (s0 and a0
// are borrowed and restored by every abstract command, as capabilities in CHERIoT mode), and ends
// with the signature handshake. Every check is self-contained: the Spike and CHERIoT-Sail cosim
// cannot model the real debug module's ROM and abstract-command memory, so these tests run with
// +cosim_off=1: neither model is stepped. (+disable_cosim only relaxes Spike's step check; its
// mtval check and the Sail checkers would still fire once Spike's own debug model diverged.)
class core_ibex_dm_test extends core_ibex_base_test;

  `uvm_component_utils(core_ibex_dm_test)
  `uvm_component_new

  core_ibex_dmi_host       dmi;
  virtual ibex_dm_dmi_if   dmi_vif;
  bit                      cheriot_mode;
  bit                      dm_seq_done;
  int unsigned             n_checks;

  // Debug Module registers (Debug Spec 0.13, dm::dm_csr_e)
  localparam bit [31:0] DmiData0      = 32'h04;
  localparam bit [31:0] DmiData1      = 32'h05;
  localparam bit [31:0] DmiDmcontrol  = 32'h10;
  localparam bit [31:0] DmiDmstatus   = 32'h11;
  localparam bit [31:0] DmiHartinfo   = 32'h12;
  localparam bit [31:0] DmiAbstractcs = 32'h16;
  localparam bit [31:0] DmiCommand    = 32'h17;
  localparam bit [31:0] DmiProgbuf0   = 32'h20;

  localparam bit [31:0] DmcontrolDmactive  = 32'h0000_0001;
  localparam bit [31:0] DmcontrolHaltreq   = 32'h8000_0000;
  localparam bit [31:0] DmcontrolResumereq = 32'h4000_0000;

  // dmstatus bits
  localparam int StAllresumeack  = 17;
  localparam int StAllrunning    = 11;
  localparam int StAllhalted     = 9;
  localparam int StAuthenticated = 7;

  // abstractcs.cmderr (dm::cmderr_e)
  localparam bit [2:0] CmdErrNone         = 3'd0;
  localparam bit [2:0] CmdErrNotSupported = 3'd2;
  localparam bit [2:0] CmdErrException    = 3'd3;

  // hartinfo as core_ibex_tb_top ties it (DmHartInfo)
  localparam bit [31:0] ExpHartinfo = 32'h0021_2380;

  // Shared with directed_tests/dm_basic/dm_basic.S
  localparam bit [31:0] ExpBase    = 32'h8000_0040;  // dm_expect
  localparam bit [31:0] DmMagic    = 32'hD0D0_C0DE;  // a2: the program leaves its loop on this
  localparam bit [31:0] X20Write   = 32'h2020_D0D0;  // RISC-V mode: written to x20
  localparam bit [31:0] A4CapAddr  = 32'h8000_1234;  // CHERIoT mode: address of the cap written to a4
  localparam bit [31:0] A1Init     = 32'h5A5A_0B0B;
  localparam bit [31:0] ProgbufAdd = 32'h0000_0111;
  localparam bit [31:0] InsnAddiA1 = 32'h1115_8593;  // addi a1, a1, 0x111
  localparam bit [31:0] InsnEbreak = 32'h0010_0073;

  // Abstract command regno: GPR xN = 0x1000 + N; CSRs by number; in CHERIoT mode with aarsize 3,
  // regno 0x00-0x1f names an SCR (dm_mem.sv, patch 0010)
  localparam bit [15:0] RegGpr   = 16'h1000;
  localparam bit [15:0] RegDcsr  = 16'h07B0;
  localparam bit [15:0] RegDpc   = 16'h07B1;
  localparam bit [15:0] RegScrDepcc = 16'h0018;

  virtual function void build_phase(uvm_phase phase);
    bit dm_real;
    super.build_phase(phase);
    if (!uvm_config_db#(bit)::get(null, "", "DM_REAL", dm_real) || !dm_real) begin
      `uvm_fatal(`gfn, {"core_ibex_dm_test needs the testbench built with the real debug module: ",
                        "make uvm-test-xlm TEST=<test> DM=1"})
    end
    if (!uvm_config_db#(virtual ibex_dm_dmi_if)::get(null, "", "dm_dmi_if", dmi_vif)) begin
      `uvm_fatal(`gfn, "Cannot get dm_dmi_if")
    end
    if (!cfg.cosim_off) begin
      `uvm_fatal(`gfn, {"core_ibex_dm_test needs +cosim_off=1: ",
                        "the cosim models cannot follow the debug module's ROM"})
    end
    cheriot_mode = cfg.enable_cheriot_seq;
    dmi = core_ibex_dmi_host::type_id::create("dmi");
    dmi.vif = dmi_vif;
  endfunction

  virtual task send_stimulus();
    super.send_stimulus();  // memory response sequences etc.; returns once they are started
    dm_sequence();
    dm_seq_done = 1'b1;
  endtask

  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    // Liveness: the program can only pass if the debugger wrote the mailbox, but a test that ended
    // some other way must not look like a debug-module pass either.
    if (!dm_seq_done) begin
      `uvm_error(`gfn, "The debug module sequence did not complete")
    end else begin
      `uvm_info(`gfn, $sformatf("Debug module sequence complete: %0d checks (%s mode)", n_checks,
                                cheriot_mode ? "CHERIoT" : "RISC-V"), UVM_LOW)
    end
  endfunction

  /////////////////////
  // Checks          //
  /////////////////////

  function void chk(string what, bit [63:0] act, bit [63:0] expected);
    n_checks++;
    if (act !== expected) begin
      `uvm_error(`gfn, $sformatf("DM check FAILED: %s: got 0x%0h, expected 0x%0h", what, act, expected))
    end else begin
      `uvm_info(`gfn, $sformatf("DM check ok: %s = 0x%0h", what, act), UVM_LOW)
    end
  endfunction

  function bit [31:0] exp_word(bit [31:0] offset);
    return mem.read(ExpBase + offset);
  endfunction

  /////////////////////
  // DM operations   //
  /////////////////////

  function bit [31:0] ar_cmd(bit [2:0] aarsize, bit postexec, bit transfer, bit write,
                             bit [15:0] regno);
    // cmdtype 0 (access register), aarpostincrement 0
    return {8'h00, 1'b0, aarsize, 1'b0, postexec, transfer, write, regno};
  endfunction

  // Run an abstract command, wait until it is no longer busy, return abstractcs.cmderr.
  task run_cmd(bit [31:0] command, output bit [2:0] cmderr);
    bit [31:0]   abstractcs;
    int unsigned n = 0;
    dmi.write_reg(DmiCommand, command);
    do begin
      dmi.read_reg(DmiAbstractcs, abstractcs);
      if (++n > 1000) begin
        `uvm_fatal(`gfn, $sformatf("Abstract command 0x%08x still busy after %0d polls", command, n))
      end
    end while (abstractcs[12]);
    cmderr = abstractcs[10:8];
  endtask

  // As run_cmd, for a command that must succeed.
  task run_cmd_ok(string what, bit [31:0] command);
    bit [2:0] cmderr;
    run_cmd(command, cmderr);
    chk({what, ": abstractcs.cmderr"}, cmderr, CmdErrNone);
    if (cmderr != CmdErrNone) clear_cmderr();
  endtask

  task clear_cmderr();
    bit [31:0] abstractcs;
    dmi.write_reg(DmiAbstractcs, 32'h0000_0700);  // cmderr is W1C
    dmi.read_reg(DmiAbstractcs, abstractcs);
    chk("abstractcs.cmderr after clearing", abstractcs[10:8], CmdErrNone);
  endtask

  task reg_read32(string what, bit [15:0] regno, output bit [31:0] data);
    run_cmd_ok({"read ", what}, ar_cmd(3'd2, 1'b0, 1'b1, 1'b0, regno));
    dmi.read_reg(DmiData0, data);
  endtask

  // 64-bit abstract read (CHERIoT mode): {data1 = metadata, data0 = address}, and the tag the
  // core drove with its store to data0 (white-box, dm_dmi_if.data0_wtag).
  task reg_read64(string what, bit [15:0] regno, output bit [63:0] data,
                  output bit tag);
    bit [31:0]   lo, hi;
    int unsigned stores = dmi_vif.data0_wcount;
    run_cmd_ok({"read ", what, " (64-bit)"}, ar_cmd(3'd3, 1'b0, 1'b1, 1'b0, regno));
    dmi.read_reg(DmiData0, lo);
    dmi.read_reg(DmiData1, hi);
    data = {hi, lo};
    chk({what, " (64-bit): stores to data0"}, dmi_vif.data0_wcount - stores, 1);
    tag = dmi_vif.data0_wtag;
  endtask

  task reg_write32(string what, bit [15:0] regno, bit [31:0] data);
    dmi.write_reg(DmiData0, data);
    run_cmd_ok({"write ", what}, ar_cmd(3'd2, 1'b0, 1'b1, 1'b1, regno));
  endtask

  task reg_write64(string what, bit [15:0] regno, bit [63:0] data);
    dmi.write_reg(DmiData0, data[31:0]);
    dmi.write_reg(DmiData1, data[63:32]);
    run_cmd_ok({"write ", what, " (64-bit)"}, ar_cmd(3'd3, 1'b0, 1'b1, 1'b1, regno));
  endtask

  task poll_dmstatus(int bitpos, string what, output bit [31:0] dmstatus);
    int unsigned n = 0;
    do begin
      dmi.read_reg(DmiDmstatus, dmstatus);
      if (++n > 5000) begin
        `uvm_fatal(`gfn, $sformatf("dmstatus bit %0d (%s) not set after %0d polls (dmstatus 0x%08x)",
                                   bitpos, what, n, dmstatus))
      end
    end while (!dmstatus[bitpos]);
  endtask

  /////////////////////
  // The sequence    //
  /////////////////////

  virtual task dm_sequence();
    bit [31:0] rd, dmstatus, dpc, loop_lo, loop_hi, s1_meta;
    bit [63:0] rd64;
    bit [2:0]  cmderr;
    bit        tag;

    wait_for_core_status(INITIALIZED);
    `uvm_info(`gfn, $sformatf("Program initialised; debugging it through the DM (%s mode)",
                              cheriot_mode ? "CHERIoT" : "RISC-V"), UVM_LOW)
    clk_vif.wait_clks(200);

    // ── Activate ────────────────────────────────────────────────────────────────────────────
    dmi.write_reg(DmiDmcontrol, DmcontrolDmactive);
    dmi.read_reg(DmiDmcontrol, rd);
    chk("dmcontrol.dmactive", rd[0], 1'b1);
    dmi.read_reg(DmiDmstatus, dmstatus);
    chk("dmstatus.version (0.13)", dmstatus[3:0], 4'd2);
    chk("dmstatus.authenticated", dmstatus[StAuthenticated], 1'b1);
    chk("dmstatus.allrunning before halt", dmstatus[StAllrunning], 1'b1);
    chk("dmstatus.allhalted before halt", dmstatus[StAllhalted], 1'b0);
    dmi.read_reg(DmiHartinfo, rd);
    chk("hartinfo", rd, ExpHartinfo);
    dmi.read_reg(DmiAbstractcs, rd);
    chk("abstractcs.datacount", rd[3:0], 4'd2);
    chk("abstractcs.progbufsize", rd[28:24], 5'd8);
    chk("abstractcs.cmderr at start", rd[10:8], CmdErrNone);

    // ── Halt ────────────────────────────────────────────────────────────────────────────────
    dmi.write_reg(DmiDmcontrol, DmcontrolHaltreq | DmcontrolDmactive);
    poll_dmstatus(StAllhalted, "allhalted", dmstatus);
    dmi.write_reg(DmiDmcontrol, DmcontrolDmactive);  // drop haltreq, else resume would re-halt
    `uvm_info(`gfn, "Hart halted", UVM_LOW)
    chk("core in debug mode after allhalted (dut_if.debug_mode)", dut_vif.debug_mode, 1'b1);
    chk("dmstatus.allrunning while halted", dmstatus[StAllrunning], 1'b0);

    // ── Debug CSRs ──────────────────────────────────────────────────────────────────────────
    reg_read32("dcsr", RegDcsr, rd);
    chk("dcsr.xdebugver", rd[31:28], 4'd4);
    chk("dcsr.cause (haltreq)", rd[8:6], 3'd3);
    chk("dcsr.prv (M)", rd[1:0], 2'd3);
    reg_read32("dpc", RegDpc, dpc);
    loop_lo = exp_word(32'h10);
    loop_hi = exp_word(32'h14);
    n_checks++;
    if (!(dpc >= loop_lo && dpc < loop_hi)) begin
      `uvm_error(`gfn, $sformatf("DM check FAILED: dpc 0x%08x is not in the program's wait loop [0x%08x, 0x%08x)",
                                 dpc, loop_lo, loop_hi))
    end else begin
      `uvm_info(`gfn, $sformatf("DM check ok: dpc 0x%08x in the wait loop [0x%08x, 0x%08x)",
                                dpc, loop_lo, loop_hi), UVM_LOW)
    end

    // ── GPRs, 32-bit ────────────────────────────────────────────────────────────────────────
    // s0 (x8) and a0 (x10) are the two registers every abstract command borrows (dscratch0/1, or
    // DScratchC0/1 in CHERIoT mode); a0 has its own path in dm_mem.
    if (cheriot_mode) begin
      reg_read32("s0 (cap)", RegGpr + 8,  rd); chk("s0 address", rd, ExpBase);
      reg_read32("s1 (cap)", RegGpr + 9,  rd); chk("s1 address", rd, 32'h8FFF_FFFC);
      reg_read32("a0 (cap)", RegGpr + 10, rd); chk("a0 address", rd, ExpBase + 32'h8);
      reg_read32("a5 (cap)", RegGpr + 15, rd); chk("a5 address", rd, ExpBase);
    end else begin
      reg_read32("s0", RegGpr + 8,  rd); chk("s0", rd, 32'h5A5A_0808);
      reg_read32("s1", RegGpr + 9,  rd); chk("s1", rd, 32'h8FFF_FFFC);
      reg_read32("a0", RegGpr + 10, rd); chk("a0", rd, 32'h5A5A_0A0A);
      reg_read32("a5", RegGpr + 15, rd); chk("a5", rd, ExpBase);
      reg_read32("x16", RegGpr + 16, rd); chk("x16", rd, 32'h5A5A_1010);
      reg_read32("x31", RegGpr + 31, rd); chk("x31", rd, 32'h5A5A_1F1F);
    end
    reg_read32("a1", RegGpr + 11, rd); chk("a1", rd, A1Init);
    reg_read32("a4", RegGpr + 14, rd); chk("a4", rd, 32'h5A5A_0E0E);
    reg_read32("a2", RegGpr + 12, rd); chk("a2 (mailbox, not yet written)", rd, 32'h0);
    reg_read32("a3", RegGpr + 13, rd);
    n_checks++;
    if (rd == 0) `uvm_error(`gfn, "DM check FAILED: a3 (loop counter) is 0: the wait loop never ran")

    // ── Capabilities, 64-bit (CHERIoT mode) ─────────────────────────────────────────────────
    if (cheriot_mode) begin
      s1_meta = exp_word(32'h4);
      reg_read64("s1", RegGpr + 9, rd64, tag);
      chk("s1 capability (vs the program's csc image)", rd64, {exp_word(32'h4), exp_word(32'h0)});
      chk("s1 tag (core's store to data0)", tag, 1'b1);
      reg_read64("a5", RegGpr + 15, rd64, tag);
      chk("a5 capability (vs the program's csc image)", rd64, {exp_word(32'hC), exp_word(32'h8)});
      chk("a5 tag", tag, 1'b1);
      reg_read64("s0", RegGpr + 8, rd64, tag);
      chk("s0 capability (a copy of a5)", rd64, {exp_word(32'hC), exp_word(32'h8)});
      chk("s0 tag", tag, 1'b1);
      reg_read64("a0", RegGpr + 10, rd64, tag);
      chk("a0 capability (a5 + 8)", rd64, {exp_word(32'hC), ExpBase + 32'h8});
      chk("a0 tag", tag, 1'b1);
      reg_read64("a1", RegGpr + 11, rd64, tag);
      chk("a1 (integer: null metadata)", rd64, {32'h0, A1Init});
      chk("a1 tag", tag, 1'b0);
      reg_read64("DEPCC (SCR 24)", RegScrDepcc, rd64, tag);
      chk("DEPCC address = dpc", rd64[31:0], dpc);
      chk("DEPCC tag", tag, 1'b1);
      n_checks++;
      if (rd64[63:32] == 32'h0) `uvm_error(`gfn, "DM check FAILED: DEPCC metadata is null")
    end

    // ── Abstract commands that must fail ────────────────────────────────────────────────────
    if (cheriot_mode) begin
      // x16 does not exist in CHERIoT mode (ibex_decoder illegal_reg_16): the abstract command's
      // csw x16 must raise an exception in debug mode, which the ROM reports to the DM.
      run_cmd(ar_cmd(3'd2, 1'b0, 1'b1, 1'b0, RegGpr + 16), cmderr);
      chk("read x16 in CHERIoT mode: cmderr = exception", cmderr, CmdErrException);
      clear_cmderr();
    end else begin
      // 64-bit register access is only offered in CHERIoT mode (dm_mem max_aar).
      run_cmd(ar_cmd(3'd3, 1'b0, 1'b1, 1'b0, RegGpr + 9), cmderr);
      chk("64-bit read in RISC-V mode: cmderr = not supported", cmderr, CmdErrNotSupported);
      clear_cmderr();
      // CSR 0x000 is not implemented: the abstract command's csrr traps in debug mode.
      run_cmd(ar_cmd(3'd2, 1'b0, 1'b1, 1'b0, 16'h0000), cmderr);
      chk("read of unimplemented CSR 0x000: cmderr = exception", cmderr, CmdErrException);
      clear_cmderr();
    end
    dmi.read_reg(DmiDmstatus, dmstatus);
    chk("dmstatus.allhalted after the failing commands", dmstatus[StAllhalted], 1'b1);

    // ── Program buffer ──────────────────────────────────────────────────────────────────────
    dmi.write_reg(DmiProgbuf0,     InsnAddiA1);
    dmi.write_reg(DmiProgbuf0 + 1, InsnEbreak);
    run_cmd_ok("program buffer (addi a1, a1, 0x111; ebreak)", ar_cmd(3'd2, 1'b1, 1'b0, 1'b0, 16'h0));
    reg_read32("a1 after the program buffer", RegGpr + 11, rd);
    chk("a1 after the program buffer", rd, A1Init + ProgbufAdd);

    // ── Writes ──────────────────────────────────────────────────────────────────────────────
    if (cheriot_mode) begin
      // CLC from data0/data1: an untagged capability with s1's metadata at A4CapAddr. s1 is
      // MTDC with a different address, so any address is representable.
      reg_write64("a4", RegGpr + 14, {s1_meta, A4CapAddr});
      reg_read64("a4 after the write", RegGpr + 14, rd64, tag);
      chk("a4 capability after the write", rd64, {s1_meta, A4CapAddr});
      chk("a4 tag after the write (the DM cannot supply one)", tag, 1'b0);
    end else begin
      reg_write32("x20", RegGpr + 20, X20Write);
      reg_read32("x20 after the write", RegGpr + 20, rd);
      chk("x20 after the write", rd, X20Write);
    end
    reg_write32("a2 (mailbox)", RegGpr + 12, DmMagic);
    reg_read32("a2 after the write", RegGpr + 12, rd);
    chk("a2 after the write", rd, DmMagic);

    // ── Resume ──────────────────────────────────────────────────────────────────────────────
    dmi.write_reg(DmiDmcontrol, DmcontrolResumereq | DmcontrolDmactive);
    poll_dmstatus(StAllresumeack, "allresumeack", dmstatus);
    dmi.read_reg(DmiDmstatus, dmstatus);
    chk("dmstatus.allrunning after resume", dmstatus[StAllrunning], 1'b1);
    chk("dmstatus.allhalted after resume", dmstatus[StAllhalted], 1'b0);
    clk_vif.wait_clks(50);
    chk("core out of debug mode after resume (dut_if.debug_mode)", dut_vif.debug_mode, 1'b0);
    `uvm_info(`gfn, "Hart resumed; the program now checks what the debugger changed", UVM_LOW)
  endtask

endclass
