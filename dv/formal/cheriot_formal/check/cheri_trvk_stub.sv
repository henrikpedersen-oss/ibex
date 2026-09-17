// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Stub for the CHERIoT TBRE/TRVK stage.
// ibex-private does not implement TBRE; all signals are hardwired to 0.
// This lets the formal proof properties that reference TRVK signals elaborate
// (they will be vacuously true since cpu_op_valid_q is always 0).

module cheri_trvk_stub ();
  logic         cpu_op_active;
  logic [2:0]   cpu_op_valid_q;
  logic [4:0]   trsv_addr_q [3];
  logic [4:0]   trsv_addr;

  assign cpu_op_active     = 1'b0;
  assign cpu_op_valid_q[0] = 1'b0;
  assign cpu_op_valid_q[1] = 1'b0;
  assign cpu_op_valid_q[2] = 1'b0;
  assign trsv_addr_q[0]    = 5'b0;
  assign trsv_addr_q[1]    = 5'b0;
  assign trsv_addr_q[2]    = 5'b0;
  assign trsv_addr         = 5'b0;
endmodule
