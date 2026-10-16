// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// The bare single-port RAM (prim_generic prim_ram_1p's interface) as a black box: in silicon the
// iCache's tag and data arrays are SRAM macros, so synthesis counts the logic around them
// (prim_ram_1p_adv's ECC, prim_ram_1p_scr's PRINCE scrambling, the iCache itself) but not the
// arrays. sv2v_convert.sh converts it into lib/, which yosys_run_synth.tcl reads with -lib.
module prim_ram_1p import prim_ram_1p_pkg::*; #(
  parameter  int Width           = 32,
  parameter  int Depth           = 128,
  parameter  int DataBitsPerMask = 1,
  parameter      MemInitFile     = "",

  localparam int Aw              = $clog2(Depth)
) (
  input  logic             clk_i,
  input  logic             rst_ni,

  input  logic             req_i,
  input  logic             write_i,
  input  logic [Aw-1:0]    addr_i,
  input  logic [Width-1:0] wdata_i,
  input  logic [Width-1:0] wmask_i,
  output logic [Width-1:0] rdata_o,
  input  ram_1p_cfg_req_t  cfg_i,
  output ram_1p_cfg_rsp_t  cfg_o
);
endmodule
