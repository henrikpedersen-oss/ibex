// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Xcelium testbench for RISC-V compliance tests on Ibex.
//
// Loads a memory image from +MEMFILE=<vmem_file> (32-bit VMem format as
// produced by "srec_cat <elf> -ELF -o <out> -VMem 32"), drives clock and
// reset, then waits for riscv_testutil to call $finish after dumping the
// test signature.
module tb_riscv_compliance;

  logic clk, rst_n;
  string memfile;

  // 100 MHz clock
  initial clk = 0;
  always #5 clk = ~clk;

  ibex_riscv_compliance u_dut (
    .IO_CLK   (clk),
    .IO_RST_N (rst_n)
  );

  initial begin : mem_init
    integer          mem_fd;
    string           mem_line;
    longint unsigned mem_cur_addr;
    logic [31:0]     mem_wval;
    integer          mem_rc;

    rst_n = 0;
    if (!$value$plusargs("MEMFILE=%s", memfile)) begin
      $fatal(1, "MEMFILE plusarg required. Usage: +MEMFILE=<path_to_vmem_file>");
    end
    // $readmemh with a hierarchical path through generate blocks silently fails
    // in Xcelium (no error, no load, RAM stays X).  Use an inline vmem parser
    // with direct indexed writes instead — confirmed working for Sonata HyperRAM.
    // run_xlm.sh normalises the vmem to one word per line before passing it here.
    foreach (u_dut.u_ram.u_ram.mem[i])
      u_dut.u_ram.u_ram.mem[i] = '0;
    mem_fd = $fopen(memfile, "r");
    if (mem_fd == 0) $fatal(1, "Cannot open MEMFILE: %s", memfile);
    mem_cur_addr = 0;
    while (!$feof(mem_fd)) begin
      void'($fgets(mem_line, mem_fd));
      if (mem_line.len() == 0) continue;
      if (mem_line[0] == "@") begin
        void'($sscanf(mem_line, "@%x", mem_cur_addr));
      end else begin
        mem_rc = $sscanf(mem_line, "%x", mem_wval);
        if (mem_rc == 1) begin
          u_dut.u_ram.u_ram.mem[mem_cur_addr] = mem_wval;
          mem_cur_addr++;
        end
      end
    end
    $fclose(mem_fd);
    $display("[tb] RAM init done; mem[0x20]=0x%08x (expect 0x0480006f)",
             u_dut.u_ram.u_ram.mem[32'h20]);
    repeat (10) @(posedge clk);
    rst_n = 1;
  end

  // Watchdog: 10M cycles (~100ms at 100MHz)
  initial begin
    repeat (10_000_000) @(posedge clk);
    $display("TIMEOUT: Simulation exceeded 10M cycles");
    $finish;
  end

  // Trap loop: a test that keeps trapping at one PC never ends on its own, and the core's "Illegal
  // instruction" $display on every pass made the 10M-cycle watchdog take hours of wall clock and
  // several GB of log and trace. In CHERIoT mode the trap target is MTCC, and the env cannot
  // redirect it (no mtvec): I-EBREAK-01's csrw stvec trapped to itself; I-MISALIGN_JMP-01 ran into
  // zeroed memory and looped 0x300 nop, nop, bge -> 0x312 c.unimp -> trap to 0x300 (2026-10-09).
  // Stop after TrapLoopMax traps at one PC with no trap at any other PC in between: other
  // retirements (a handler, the code leading back to the faulting instruction) do not reset the
  // count, a trap elsewhere does. A compliance test traps at many different PCs. No signature is
  // written, so the test fails.
  localparam int unsigned TrapLoopMax = 1000;
  int unsigned trap_loop_n;
  logic [31:0] trap_loop_pc;
  always @(posedge clk) begin
    if (!rst_n) begin
      trap_loop_n <= 0;
    end else if (u_dut.u_top.rvfi_valid && u_dut.u_top.rvfi_trap) begin
      if (trap_loop_n != 0 && u_dut.u_top.rvfi_pc_rdata == trap_loop_pc) begin
        trap_loop_n <= trap_loop_n + 1;
        if (trap_loop_n + 1 >= TrapLoopMax) begin
          $display("TIMEOUT: trap loop, %0d traps at PC 0x%08x and none elsewhere", TrapLoopMax,
                   trap_loop_pc);
          $finish;
        end
      end else begin
        trap_loop_n  <= 1;
        trap_loop_pc <= u_dut.u_top.rvfi_pc_rdata;
      end
    end
  end

endmodule
