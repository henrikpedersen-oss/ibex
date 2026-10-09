// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// DMI port of the real debug module (vendor/pulp_riscv_dbg dm_top), driven directly by the test
// (core_ibex_dm_test) instead of through a JTAG DTM.
//
// Only a DM build (make ... DM=1, +define+IBEX_DM_REAL) connects it to dm_top; core_ibex_tb_top
// instantiates it in every build so that the test package, which names the virtual interface type,
// elaborates the same way everywhere. The fields are plain vectors rather than dm::dmi_req_t /
// dm::dmi_resp_t because dm_pkg is only compiled into DM builds:
//   request  = {req_addr[31:0], req_op[1:0], req_data[31:0]}   (dm::dmi_req_t, 66 bits)
//   response = {resp_data[31:0], resp_resp[1:0]}               (dm::dmi_resp_t, 34 bits)
//   req_op:    0 nop, 1 read, 2 write                          (dm::dtm_op_e)
//   resp_resp: 0 success, 2 error, 3 busy                      (dm::dtm_op_status_e)
//
// data0_wcount / data0_wtag are white-box observations made in core_ibex_tb_top: how many stores
// the core has made to the DM's data0 word (DM base + 0x380) and the capability tag it drove with
// the latest one. The DMI cannot carry a tag (data0/data1 are plain words), so this is how the
// test sees that a 64-bit abstract register read in CHERIoT mode stored a tagged capability.

interface ibex_dm_dmi_if (
  input logic clk,
  input logic rst_n
);

  logic        req_valid;
  logic        req_ready;
  logic [31:0] req_addr;
  logic [1:0]  req_op;
  logic [31:0] req_data;

  logic        resp_valid;
  logic        resp_ready;
  logic [31:0] resp_data;
  logic [1:0]  resp_resp;

  int unsigned data0_wcount;
  logic        data0_wtag;

  clocking cb @(posedge clk);
    output req_valid;
    output req_addr;
    output req_op;
    output req_data;
    output resp_ready;
    input  req_ready;
    input  resp_valid;
    input  resp_data;
    input  resp_resp;
    input  data0_wcount;
    input  data0_wtag;
  endclocking

  initial begin
    req_valid  = 1'b0;
    req_addr   = '0;
    req_op     = '0;
    req_data   = '0;
    resp_ready = 1'b1;
  end

endinterface
