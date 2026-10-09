// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Testbench for the CHERIoT RTOS test SoC (rtl/cheriot_rtos_soc.sv).
//
// Drives clock and reset, loads the two memories from vmem files, and captures UART0 with
// uartdpi, which ends the run when the firmware sends the CHERIoT RTOS exit string. The UART log
// is the test oracle: the firmware reports each check on it, and run_all_tests.sh reads the
// verdict from it.
//
// Runtime plusargs:
//   +sram_vmem=<path>          SRAM image (0x0010_0000, 128 KiB): boot stub + SRAM-resident code
//   +code_vmem=<path>          code RAM image (0x4000_0000, 1 MiB)
//   +UARTDPI_LOG_uart0=<path>  UART0 log (uartdpi default: uart0.log)
//   +max_cycles=<n>            cycle timeout (default MAX_CYCLES below)
//   +sonata_mutate=<name>      break one hardware check (mutation testing, see below)
//   +default_rsp_error=1       unmapped data accesses get a TL-UL error instead of 0/dropped
//   +enable_ibex_fcov=1        sample the functional covergroups (fcov/)
//   +ibex_tracer_enable=0|1    ibex instruction tracer (ibex_top_tracing)
//   +uart_idle_cycles=<n>      end the run after n cycles of UART silence (0 disables; see below)

`timescale 1ns/10ps

module cheriot_rtos_tb;

  // Clock: 40 MHz (25 ns period), the board file's timer_hz. One clock for everything.
  localparam int unsigned SysClkFreq = 40_000_000;
  localparam int unsigned BaudRate   = 921_600;
  localparam realtime     CLK_PERIOD = 1s / real'(SysClkFreq);
  // Timeout: 120 s of simulated time = 4.8 billion clock cycles at 40 MHz.
  localparam longint unsigned MAX_CYCLES = 64'd4_800_000_000;

  // Memory images: word counts of the SoC's two memories.
  localparam int unsigned SramWords = 128 * 1024 / 4;
  localparam int unsigned CodeWords = 1024 * 1024 / 4;
  // The boot stub's first instruction: boot_addr 0x0010_0000 + 0x80.
  localparam int unsigned BootWord  = 32'h80 / 4;

  // EXIT_STRING must match the one hard-coded in the CHERIoT RTOS build
  // (platform-simulation_exit.hh).
  //
  // The eight trailing bytes are built from their values, not written as "\xd8\xaf..." escapes:
  // on 2026-09-29 the firmware demonstrably sent the string and the run did not stop, so the
  // escaped literal did not produce these bytes. Casting an integral to string gives one character
  // per byte (IEEE 1800-2017 6.16), independent of escape handling.
  localparam string EXIT_STRING = {"Safe to exit simulator.",
    string'(8'hd8), string'(8'haf), string'(8'hfb), string'(8'ha0),
    string'(8'hc7), string'(8'he1), string'(8'ha9), string'(8'hd7)};

  // Show the exit string as the simulator holds it: 31 bytes ending d8 af fb a0 c7 e1 a9 d7. If
  // it differs, uartdpi can never match it and the run only ends at the timeout.
  initial begin : show_exit_string
    string tail_hex;
    tail_hex = "";
    for (int i = (EXIT_STRING.len() > 8 ? EXIT_STRING.len() - 8 : 0); i < EXIT_STRING.len(); i++)
      tail_hex = {tail_hex, $sformatf(" %h", EXIT_STRING[i])};
    $display("[cheriot_rtos_tb] EXIT_STRING: %0d bytes, last 8:%s", EXIT_STRING.len(), tail_hex);
  end

  // ── Clock and reset ─────────────────────────────────────────────────────────────────────────
  logic clk;
  logic rst_n;

  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD / 2) clk = ~clk;
  end

  initial begin
    rst_n = 1'b0;
    repeat (20) @(posedge clk);
    rst_n = 1'b1;
  end

  // ── DUT ──────────────────────────────────────────────────────────────────────────────────────
  logic uart_soc_tx, uart_soc_rx;

  cheriot_rtos_soc u_soc (
    .clk_i      (clk),
    .rst_ni     (rst_n),
    .cheri_en_i (1'b1),
    .uart_rx_i  (uart_soc_rx),
    .uart_tx_o  (uart_soc_tx)
  );

  // Elaborates the bind statements for the memory-subsystem and TRVK covergroups
  // (fcov/cheriot_mem_subsys_fcov_bind.sv); a bind in a module only takes effect if it is
  // elaborated.
  cheriot_mem_subsys_fcov_bind u_cheriot_mem_subsys_fcov_bind ();

  // ── uartdpi: UART capture + EXIT_STRING termination ─────────────────────────────────────────
  uartdpi #(
    .BAUD        (BaudRate),
    .FREQ        (SysClkFreq),
    .NAME        ("uart0"),
    .EXIT_STRING (EXIT_STRING)
  ) u_uartdpi (
    .clk_i  (clk),
    .rst_ni (rst_n),
    .active (1'b1),
    .tx_o   (uart_soc_rx),
    .rx_i   (uart_soc_tx)
  );

  // ── UART line watcher: end the run on a firmware failure ───────────────────────────────────
  // uartdpi only ends the run on EXIT_STRING, and the firmware sends that only on success. After
  // a failure the CHERIoT RTOS test runner prints "Test failure in test runner" and then idles, so
  // the run used to continue to MAX_CYCLES (days): on 2026-10-01 a test suite that failed at 17 M
  // cycles was still running at 125 M twelve hours later. This decodes the SoC's TX line (8N1, the
  // same bit time as uartdpi), keeps the current line, and finishes on:
  //   - a failure line (FailLines below)                 -> "[cheriot_rtos_tb] FIRMWARE FAILURE: ..."
  //   - no UART output for +uart_idle_cycles=<n> after the first byte (default UartIdleCycles;
  //     0 disables)                                      -> "[cheriot_rtos_tb] UART IDLE ..."
  // Both lines are failures for run_all_tests.sh, like TIMEOUT.
  localparam int unsigned     ClksPerBit     = SysClkFreq / BaudRate;
  localparam longint unsigned UartIdleCycles = 64'd200_000_000;  // 5 s of simulated time
  localparam string           FailLines [2]  = '{"Test failure in test runner",
                                                 "One or more tests failed"};
  // A build without SIMULATION (e.g. board sonata-prerelease, which the nix-built suite uses) never
  // sends EXIT_STRING: after "All tests finished" the runner only reports a failure, if any, then
  // idles. End such a run DoneWaitCycles after that line (enough for the verdict lines to arrive,
  // ~430 cycles per character) unless a FailLine came first.
  localparam string           DoneLine       = "All tests finished";
  localparam int unsigned     DoneWaitCycles = 1_000_000;
  longint unsigned cycle_count;
  longint unsigned uart_last_byte_cyc;
  bit              uart_seen_byte;

  always @(posedge clk) cycle_count <= rst_n ? cycle_count + 1 : 0;

  initial begin : uart_watch
    string  line;
    byte    ch;
    line = "";
    uart_seen_byte = 1'b0;
    @(posedge rst_n);
    forever begin
      @(negedge uart_soc_tx);                      // start bit
      repeat (ClksPerBit / 2) @(posedge clk);
      if (uart_soc_tx) continue;                   // glitch, not a start bit
      for (int b = 0; b < 8; b++) begin
        repeat (ClksPerBit) @(posedge clk);
        ch[b] = uart_soc_tx;                       // LSB first
      end
      repeat (ClksPerBit) @(posedge clk);          // stop bit
      uart_seen_byte = 1'b1;
      uart_last_byte_cyc = cycle_count;
      if (ch == 8'h0a || ch == 8'h0d) begin
        foreach (FailLines[i]) begin
          for (int p = 0; p + FailLines[i].len() <= line.len(); p++) begin
            if (line.substr(p, p + FailLines[i].len() - 1) == FailLines[i]) begin
              $display("[cheriot_rtos_tb] FIRMWARE FAILURE at cycle %0d: \"%s\"", cycle_count, line);
              repeat (ClksPerBit * 200) @(posedge clk);   // let uartdpi flush the rest of the line
              $finish(2);
            end
          end
        end
        for (int p = 0; p + DoneLine.len() <= line.len(); p++) begin
          if (line.substr(p, p + DoneLine.len() - 1) == DoneLine) begin
            fork
              begin
                repeat (DoneWaitCycles) @(posedge clk);
                $display("[cheriot_rtos_tb] FIRMWARE DONE at cycle %0d: \"%s\" and no failure line followed (no exit string: a non-SIMULATION build)",
                         cycle_count, DoneLine);
                $finish(0);
              end
            join_none
            break;
          end
        end
        line = "";
      end else if (ch >= 8'h20 && ch < 8'h7f) begin
        line = {line, string'(ch)};
      end
    end
  end

  initial begin : uart_idle_watch
    longint unsigned idle;
    if (!$value$plusargs("uart_idle_cycles=%d", idle)) idle = UartIdleCycles;
    if (idle != 0) begin
      forever begin
        repeat (1_000_000) @(posedge clk);
        if (uart_seen_byte && cycle_count - uart_last_byte_cyc > idle) begin
          $display("[cheriot_rtos_tb] UART IDLE: no output for %0d cycles (last byte at cycle %0d)",
                   cycle_count - uart_last_byte_cyc, uart_last_byte_cyc);
          $finish(2);
        end
      end
    end
  end

  // ── Memory initialisation ───────────────────────────────────────────────────────────────────
`define SRAM_MEM  u_soc.u_sram.u_ram.mem
`define SRAM_TAGS u_soc.u_sram.u_cap_ram.mem
`define CODE_MEM  u_soc.u_code_ram.u_ram.mem
`define CODE_TAGS u_soc.u_code_ram.u_cap_ram.mem

  // The images are read into arrays here and copied element by element into the RAMs. That keeps
  // the file name a runtime plusarg, and avoids a hierarchical $readmemh, which Xcelium silently
  // failed to apply through generate blocks in the Sonata flow this replaces (it passed the file
  // as the RAM's MemInitFile parameter instead, fixed at elaboration).
  //
  // The memories' own tag RAMs are zeroed: the memory subsystem forces the capability bit to 0
  // beyond its tag filter, so they are never written, but their X read data would still reach the
  // bus. Tags are the subsystem's meta SRAM, which zeroes itself (cheriot_mem_subsys.sv).
  logic [31:0] sram_img [SramWords];
  logic [31:0] code_img [CodeWords];

  initial begin : mem_init
    string sram_file, code_file;
    int unsigned sram_nz, code_nz;

    foreach (sram_img[i]) sram_img[i] = '0;
    foreach (code_img[i]) code_img[i] = '0;

    if (!$value$plusargs("sram_vmem=%s", sram_file))
      $fatal(1, "[cheriot_rtos_tb] no +sram_vmem=<file>: nothing to boot");
    $readmemh(sram_file, sram_img);
    if ($value$plusargs("code_vmem=%s", code_file)) $readmemh(code_file, code_img);
    else code_file = "(none)";

    sram_nz = 0;
    code_nz = 0;
    foreach (sram_img[i]) begin
      if (sram_img[i] !== '0) sram_nz++;
      `SRAM_MEM[i] = sram_img[i];
    end
    foreach (code_img[i]) begin
      if (code_img[i] !== '0) code_nz++;
      `CODE_MEM[i] = code_img[i];
    end
    foreach (`SRAM_TAGS[i]) `SRAM_TAGS[i] = '0;
    foreach (`CODE_TAGS[i]) `CODE_TAGS[i] = '0;

    $display("[cheriot_rtos_tb] SRAM:     %0d non-zero words from %s", sram_nz, sram_file);
    $display("[cheriot_rtos_tb] code RAM: %0d non-zero words from %s", code_nz, code_file);
    // An image that did not load leaves the core fetching zeros (c.unimp) at the reset vector and
    // the UART silent until the timeout. Fail at time 0 instead.
    if (^`SRAM_MEM[BootWord] === 1'bx || `SRAM_MEM[BootWord] == '0)
      $fatal(1, "[cheriot_rtos_tb] no code at the boot vector (0x%h): SRAM image not loaded",
             32'h0010_0000 + BootWord * 4);
  end

`undef CODE_TAGS
`undef CODE_MEM
`undef SRAM_TAGS
`undef SRAM_MEM

  // ── Cycle timeout ───────────────────────────────────────────────────────────────────────────
  // +max_cycles=<n> overrides MAX_CYCLES, so a run can be bounded by what its firmware needs (the
  // root Makefile's SONATA_MAX_CYCLES) instead of days. The TIMEOUT line is what run_all_tests.sh
  // looks for: $finish leaves xrun's exit status 0, so without it a hung run reads as a clean one.
  initial begin : cycle_timeout
    longint unsigned cyc, max_cycles;
    if (!$value$plusargs("max_cycles=%d", max_cycles)) max_cycles = MAX_CYCLES;
    for (cyc = 0; cyc < max_cycles; cyc++) begin
      @(posedge clk);
    end
    $display("[cheriot_rtos_tb] TIMEOUT after %0d cycles", max_cycles);
    $finish(2);
  end

  // ── Progress heartbeat ──────────────────────────────────────────────────────────────────────
  // A full RTOS test-suite run is tens of millions of cycles and the UART log stays empty until
  // the loader's first print, so a blank log a minute in means nothing. One line per million
  // cycles in run.log shows whether the design is still advancing.
  initial begin : progress_heartbeat
    longint unsigned hb;
    hb = 0;
    forever begin
      repeat (1_000_000) @(posedge clk);
      hb += 1_000_000;
      $display("[cheriot_rtos_tb] progress: %0d cycles, %0t sim time", hb, $time);
    end
  end

  // ── Mutation testing ────────────────────────────────────────────────────────────────────────
  // +sonata_mutate=<name> breaks one hardware check, so a test suite can be shown to notice: a
  // suite that stays green with the check broken is not testing it. Driven by
  // `make sonata-mutation-check-xlm` (ibex/dv/testplans/mutation_check.py lists each mutation, the runs
  // that must go red, and the tests that must report FAIL). Runtime-selected, so one build serves
  // every mutation. The plusarg keeps its Sonata-flow name, as do the root Makefile targets.
  //
  // Core-side mutations are applied to the main core *and* the lockstep shadow core
  // (SecureIbex = 1): a mismatch between the two would raise the lockstep alert -- and possibly
  // assertions -- and fail the run for a reason unrelated to the test under measurement. The load
  // barrier and the TBRE sit outside both cores, so they are forced once.
  //
  // Not mutated: representability. It is computed inside a package function
  // (ibex_cheriot_pkg set_address), which force cannot reach, and forcing the result's tag would
  // need a part-select of a struct variable, which SystemVerilog does not allow.
`define RTOS_CORE  u_soc.u_top_tracing.u_ibex_top
`define RTOS_EX_M  `RTOS_CORE.u_ibex_core.g_cheriot_ex.u_ibex_cheriot_ex
`define RTOS_EX_S  `RTOS_CORE.gen_lockstep.u_ibex_lockstep.u_shadow_core.g_cheriot_ex.u_ibex_cheriot_ex
`define RTOS_LSU_M `RTOS_CORE.u_ibex_core.load_store_unit_i
`define RTOS_LSU_S `RTOS_CORE.gen_lockstep.u_ibex_lockstep.u_shadow_core.load_store_unit_i
`define RTOS_TRVK  `RTOS_CORE.gen_cheriot_trvk.i_ibex_trvk
`define RTOS_MOVER u_soc.u_cheriot_mem_subsys.u_cheriot.u_cheriot_tbre.u_cheriot_tbre_mover
  initial begin : mutate
    string m;
    if ($value$plusargs("sonata_mutate=%s", m)) begin
      $display("[cheriot_rtos_tb] MUTATION %s active", m);
      case (m)
        // Bounds checks on loads and stores: the RV32 path (plain loads/stores through a
        // capability) and the capability path (CLC/CSC).
        "bounds_off": begin
          force `RTOS_EX_M.addr_bound_vio_rv32 = 1'b0;
          force `RTOS_EX_M.addr_bound_vio      = 1'b0;
          force `RTOS_EX_S.addr_bound_vio_rv32 = 1'b0;
          force `RTOS_EX_S.addr_bound_vio      = 1'b0;
        end
        // Load and store permission checks (PVIO_LD = bit 3, PVIO_SD = bit 4); tag and seal
        // checks (bits 0, 1) and the capability path's other checks stay.
        "ldst_perm_off": begin
          force `RTOS_EX_M.perm_vio_rv32 = `RTOS_EX_M.perm_vio_vec_rv32[0] |
                                           `RTOS_EX_M.perm_vio_vec_rv32[1];
          force `RTOS_EX_M.perm_vio      = |(`RTOS_EX_M.perm_vio_vec & ~8'h18);
          force `RTOS_EX_S.perm_vio_rv32 = `RTOS_EX_S.perm_vio_vec_rv32[0] |
                                           `RTOS_EX_S.perm_vio_vec_rv32[1];
          force `RTOS_EX_S.perm_vio      = |(`RTOS_EX_S.perm_vio_vec & ~8'h18);
        end
        // Execute-permission check on capability jumps (PVIO_EX = bit 2).
        "exec_off": begin
          force `RTOS_EX_M.perm_vio = |(`RTOS_EX_M.perm_vio_vec & ~8'h04);
          force `RTOS_EX_S.perm_vio = |(`RTOS_EX_S.perm_vio_vec & ~8'h04);
        end
        // A data (non-capability) store no longer clears the tag of the word it writes: it sets
        // it. Capability stores keep their real tag.
        "datastore_tag": begin
          force `RTOS_LSU_M.data_tag_o = `RTOS_LSU_M.lsu_is_cap_i ?
                                         `RTOS_LSU_M.data_wdata_tag : 1'b1;
          force `RTOS_LSU_S.data_tag_o = `RTOS_LSU_S.lsu_is_cap_i ?
                                         `RTOS_LSU_S.data_wdata_tag : 1'b1;
        end
        // The core's load barrier never revokes / always revokes a capability it looks up.
        "barrier_none": force `RTOS_TRVK.revbm_revoked = 1'b0;
        "barrier_all":  force `RTOS_TRVK.revbm_revoked = 1'b1;
        // The TBRE sweeps but never issues an invalidation: every revoked capability is treated
        // as needing no write (cheriot_tbre_mover word_dropped), so the sweep completes cleanly.
        "tbre_no_inval": force `RTOS_MOVER.write_a_valid = 1'b0;
        default: $fatal(1, "[cheriot_rtos_tb] unknown mutation '%s'", m);
      endcase
    end
  end
`undef RTOS_MOVER
`undef RTOS_TRVK
`undef RTOS_LSU_S
`undef RTOS_LSU_M
`undef RTOS_EX_S
`undef RTOS_EX_M
`undef RTOS_CORE

  // ── Core alert monitor ──────────────────────────────────────────────────────────────────────
  // The core's alert outputs are not wired in the SoC (no alert handler), so without this a bus
  // integrity error, a lockstep mismatch (SecureIbex = 1), an ICache ECC error, a register-file
  // or CSR-shadow error would leave the run green. Any rise is an $error, which run_all_tests.sh
  // counts as a failure (*E in run.log). This also checks the SoC's own integrity encoding and
  // scramble-key handshake. Mutations that break a check in only one core would trip the lockstep
  // alert; the core-side mutations above are applied to both cores for that reason.
  initial begin : core_alert_monitor
    logic [2:0] alerts, alerts_prev;
    alerts_prev = '0;
    @(posedge rst_n);
    forever begin
      @(posedge clk);
      alerts = {u_soc.u_top_tracing.alert_minor_o, u_soc.u_top_tracing.alert_major_internal_o,
                u_soc.u_top_tracing.alert_major_bus_o};
      if (rst_n && (alerts & ~alerts_prev) != '0) begin
        $error("[core_alert_monitor] %0d: core alert raised: minor=%b major_internal=%b major_bus=%b",
               cycle_count, alerts[2], alerts[1], alerts[0]);
      end
      alerts_prev = alerts;
    end
  end

  // ── Revocation sweep monitor ────────────────────────────────────────────────────────────────
  // Logs each stage of a sweep -- rev_ctl go, the shim's CSR sequence, the TBRE accepting it, its
  // end -- plus fatal errors, and while a sweep runs a progress line every 100k cycles: the word
  // counter, words in flight and the bus handshakes on the mover's read/write ports and the TBRE's
  // SRAM port. Whichever count stops moving is where it is stuck. (Written for revocation_test's
  // sweep check on 2026-09-29, which saw rev_ctl's epoch stop while the TBRE was stalled.)
  initial begin : tbre_monitor
    longint unsigned cyc, rd_req, rd_rsp, wr_req, wr_rsp, sram_req, sram_rsp;
    logic running_prev, tbre_busy_prev, accept_prev, err_prev;
    logic [8:0] fatal_prev;
    logic [3:0] shim_state_prev;
    int unsigned tbre_sweeps;
    cyc = 0; rd_req = 0; rd_rsp = 0; wr_req = 0; wr_rsp = 0; sram_req = 0; sram_rsp = 0;
    running_prev = 0; tbre_busy_prev = 0; accept_prev = 0; fatal_prev = '0; shim_state_prev = '0;
    err_prev = 0; tbre_sweeps = 0;
    forever begin
      @(posedge clk);
      cyc++;
      begin : sample
        `define MS u_soc.u_cheriot_mem_subsys
        `define MV `MS.u_cheriot.u_cheriot_tbre.u_cheriot_tbre_mover
        if (`MV.tl_r_o.a_valid && `MV.tl_r_i.a_ready) rd_req++;
        if (`MV.tl_r_i.d_valid && `MV.tl_r_o.d_ready) rd_rsp++;
        if (`MV.tl_w_o.a_valid && `MV.tl_w_i.a_ready) wr_req++;
        if (`MV.tl_w_i.d_valid && `MV.tl_w_o.d_ready) wr_rsp++;
        if (`MS.tbre_tl_o.a_valid && `MS.tbre_tl_i.a_ready) sram_req++;
        if (`MS.tbre_tl_i.d_valid && `MS.tbre_tl_o.d_ready) sram_rsp++;

        if (`MS.u_rev_ctl_tbre.go)
          $display("[tbre_monitor] %0d: rev_ctl go start=%h end=%h (shim %s)", cyc,
                   `MS.u_rev_ctl_tbre.start_addr, `MS.u_rev_ctl_tbre.end_addr,
                   `MS.u_rev_ctl_tbre.state_q == 0 ? "idle, accepted" : "busy, ignored");
        if (`MS.u_rev_ctl_tbre.state_q != shim_state_prev)
          $display("[tbre_monitor] %0d: shim state %0d -> %0d (base=%h num_caps=%0d)", cyc,
                   shim_state_prev, `MS.u_rev_ctl_tbre.state_q,
                   `MS.u_rev_ctl_tbre.base_q, `MS.u_rev_ctl_tbre.num_caps_q);
        if (`MS.u_cheriot.tbre_valid_q && `MS.u_cheriot.tbre_ready && !accept_prev)
          $display("[tbre_monitor] %0d: TBRE accepted sweep start=%h num_words=%0d", cyc,
                   `MS.u_cheriot.tbre_start_addr, `MS.u_cheriot.tbre_num_words);
        if (`MS.u_cheriot.tbre_busy != tbre_busy_prev)
          $display("[tbre_monitor] %0d: TBRE busy %0d -> %0d (words issued %0d, in flight %0d)",
                   cyc, tbre_busy_prev, `MS.u_cheriot.tbre_busy, `MV.current_q, `MV.inflight_q);
        if (`MS.u_rev_ctl_tbre.running_q != running_prev)
          $display("[tbre_monitor] %0d: shim running %0d -> %0d (err=%0d, TBRE_STATUS=%h, TBRE_EPOCH count %0d)",
                   cyc, running_prev, `MS.u_rev_ctl_tbre.running_q, `MS.u_rev_ctl_tbre.err_q,
                   `MS.u_rev_ctl_tbre.status_q, `MS.u_cheriot.tbre_epoch_q);
        // The shim ends a sweep, and rev_ctl advances the firmware's epoch, only for a sweep the
        // TBRE counted in TBRE_EPOCH as one without an error. An empty range ends without the TBRE.
        if (running_prev && !`MS.u_rev_ctl_tbre.running_q && `MS.u_rev_ctl_tbre.num_caps_q != 0) begin
          tbre_sweeps++;
          if (`MS.u_cheriot.tbre_epoch_q != 31'(tbre_sweeps))
            $error("[tbre_monitor] %0d: shim completed %0d sweeps, TBRE_EPOCH counts %0d", cyc,
                   tbre_sweeps, `MS.u_cheriot.tbre_epoch_q);
        end
        // Bit order: {csr_intg, meta_sram_intg, meta_sram_data_intg, rmw_error,
        //             tbre_mover_error, tbre_revbm_intg, tbre_revbm_data_intg, tbre_revbm_error,
        //             wtrc_error}
        // A raised fatal error is a failed run, not a log line: the subsystem's fatal alert and the
        // shim's sticky error flag are not wired to anything in the SoC, so without an $error
        // here an integrity or bus error inside the subsystem would leave the run green.
        // run_all_tests.sh fails the run on *E lines in run.log.
        if (`MS.u_cheriot.cheriot_fatal_error != fatal_prev) begin
          if (|`MS.u_cheriot.cheriot_fatal_error)
            $error("[tbre_monitor] %0d: fatal errors %b -> %b", cyc, fatal_prev,
                   `MS.u_cheriot.cheriot_fatal_error);
          else
            $display("[tbre_monitor] %0d: fatal errors %b -> %b", cyc, fatal_prev,
                     `MS.u_cheriot.cheriot_fatal_error);
        end
        if (`MS.u_rev_ctl_tbre.err_q && !err_prev)
          $error("[tbre_monitor] %0d: rev_ctl shim: sweep failed after state %0d (last TBRE_STATUS=%h); the firmware's epoch stays odd",
                 cyc, shim_state_prev, `MS.u_rev_ctl_tbre.status_q);
        if (`MS.u_rev_ctl_tbre.running_q && (cyc % 100_000 == 0))
          $display("[tbre_monitor] %0d: running: mover state=%0d word=%0d in_flight=%0d rd %0d/%0d wr %0d/%0d sram %0d/%0d (req/rsp) shim state=%0d pending=%0d",
                   cyc, `MV.state_q, `MV.current_q, `MV.inflight_q,
                   rd_req, rd_rsp, wr_req, wr_rsp, sram_req, sram_rsp,
                   `MS.u_rev_ctl_tbre.state_q, `MS.u_rev_ctl_tbre.pending_q);

        running_prev    = `MS.u_rev_ctl_tbre.running_q;
        tbre_busy_prev  = `MS.u_cheriot.tbre_busy;
        accept_prev     = `MS.u_cheriot.tbre_valid_q && `MS.u_cheriot.tbre_ready;
        fatal_prev      = `MS.u_cheriot.cheriot_fatal_error;
        shim_state_prev = `MS.u_rev_ctl_tbre.state_q;
        err_prev        = `MS.u_rev_ctl_tbre.err_q;
        `undef MV
        `undef MS
      end
    end
  end

endmodule
