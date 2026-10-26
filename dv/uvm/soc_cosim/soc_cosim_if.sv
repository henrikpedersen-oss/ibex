// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// The RVFI of an Ibex-based SoC's core, as the soc_cosim RVFI monitor samples it (soc_cosim_pkg).
// The SoC's testbench instantiates it and drives it from ibex_top hierarchically (Earl Grey 2:
// hw/top_earlgrey/dv/tb/tb.sv; the CHERIoT RTOS test SoC: dv/tb/cheriot_rtos_tb.sv).

interface soc_cosim_if #(
  parameter int unsigned CapW = 35  // $bits(ibex_cheriot_pkg::cap_t)
) (
  input logic clk,
  input logic rst_n
);
  logic            valid;
  logic [63:0]     order;
  logic [31:0]     insn;
  logic            trap;
  logic            halt;
  logic            intr;
  logic [1:0]      mode;
  logic [4:0]      rs1_addr;
  logic [4:0]      rs2_addr;
  logic [31:0]     rs1_rdata;
  logic [31:0]     rs2_rdata;
  logic [4:0]      rd_addr;
  logic [31:0]     rd_wdata;
  logic [31:0]     pc_rdata;
  logic [31:0]     pc_wdata;
  logic [31:0]     mem_addr;
  logic [3:0]      mem_rmask;
  logic [3:0]      mem_wmask;
  logic [31:0]     mem_rdata;
  logic [31:0]     mem_wdata;
  // CHERIoT
  logic [CapW-1:0] rs1_rcap;
  logic [CapW-1:0] rs2_rcap;
  logic [CapW-1:0] rd_wcap;
  logic            mem_is_cap;
  logic [CapW-1:0] mem_rcap;
  logic [CapW-1:0] mem_wcap;
  // Extensions: what a reference model needs to take interrupts where the core took them.
  logic [31:0]     ext_pre_mip;
  logic [31:0]     ext_post_mip;
  logic            ext_nmi;
  logic            ext_nmi_int;
  logic            ext_debug_req;
  logic            ext_debug_mode;
  logic            ext_rf_wr_suppress;
  logic            ext_irq_valid;
  logic [63:0]     ext_mcycle;
  logic [31:0]     ext_mhpmcounters [10];
  logic [31:0]     ext_mhpmcountersh [10];
  logic            ext_ic_scr_key_valid;
  // Zcmp: Ibex retires one item per micro-operation; the last one carries `_last`.
  logic            ext_expanded_insn_valid;
  logic            ext_expanded_insn_last;
  // The mtval Ibex writes when it takes an internal NMI (the address of the response with bad
  // integrity), which an ISS cannot derive: ibex_controller's irq_nm_int_mtval.
  logic [31:0]     nmi_int_mtval;
  // Core probes (ibex_top's ports, not the bus): a data response with an error, held until the
  // instruction it belongs to retires; the CHERIoT enable the core sees; its boot address.
  logic            data_err;
  logic            cheriot_ena;
  logic [31:0]     boot_addr;

  clocking monitor_cb @(posedge clk);
    input rst_n, valid, order, insn, trap, halt, intr, mode, rs1_addr, rs2_addr, rs1_rdata,
          rs2_rdata, rd_addr, rd_wdata, pc_rdata, pc_wdata, mem_addr, mem_rmask, mem_wmask,
          mem_rdata, mem_wdata, rs1_rcap, rs2_rcap, rd_wcap, mem_is_cap, mem_rcap, mem_wcap,
          ext_pre_mip, ext_post_mip, ext_nmi, ext_nmi_int, ext_debug_req, ext_debug_mode,
          ext_rf_wr_suppress, ext_irq_valid, ext_mcycle, ext_mhpmcounters, ext_mhpmcountersh,
          ext_ic_scr_key_valid, ext_expanded_insn_valid, ext_expanded_insn_last, nmi_int_mtval,
          data_err, cheriot_ena, boot_addr;
  endclocking

endinterface
