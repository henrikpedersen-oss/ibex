// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// DII signals between the testbench and the core's DII_SIM hooks (ibex_fetch_fifo.sv,
// ibex_icache.sv), the retirement count the driver waits on, and the DII interrupt lines.
interface core_ibex_dii_intf (
  input clk, input rst_n, input rvfi_valid
);
  logic [31:0] dii_insn;
  logic        dii_ack;
  // Initialised in the declaration, not an initial block: these are driven through the clocking
  // block, and a second process writing them is a multiple-driver race (IEEE 1800-2023 14.3).
  logic        irq_software = 1'b0;
  logic        irq_timer    = 1'b0;
  logic        irq_external = 1'b0;

  initial begin
    dii_insn     = '0;
  end

  // dii_insn is driven directly (not via CB) to avoid #1step output-skew ambiguity:
  // RTL flip-flops sample at posedge, before the CB #1step drive, so using
  // cb.dii_insn <= would cause ibex to see the OLD instruction for one cycle after
  // set_dii_ready(1) is asserted.
  function void set_dii_insn(bit [31:0] insn);
    dii_insn = insn;
  endfunction

  clocking cb @(posedge clk);
    input  dii_ack;
    output irq_software;
    output irq_timer;
    output irq_external;
  endclocking

  // Retirements since the last reset (every rvfi_valid; a Zcmp instruction counts once per
  // micro-op).
  logic [31:0] instr_out;

  // When low, instr_gnt_i to ibex is suppressed, preventing ibex from fetching
  // (and looping on) the DII register while the driver is waiting for QCVEngine.
  bit dii_ready = 0;

  function void set_dii_ready(bit r);
    dii_ready = r;
  endfunction

  // Drives cheriot_enable_i. Set by the DII sequencer flavour during build, while the initial
  // reset is still asserted; it must not change mid-test.
  ibex_pkg::ibex_mubi_t cheriot_enable = ibex_pkg::IbexMuBiOn;

  function void set_cheriot_enable(bit en);
    cheriot_enable = en ? ibex_pkg::IbexMuBiOn : ibex_pkg::IbexMuBiOff;
  endfunction

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      instr_out <= '0;
    end else if (rvfi_valid) begin
      instr_out <= instr_out + 32'b1;
    end
  end
endinterface : core_ibex_dii_intf
