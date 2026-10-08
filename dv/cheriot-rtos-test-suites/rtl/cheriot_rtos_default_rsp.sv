// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Default responder of the CHERIoT RTOS test SoC: answers every data access the crossbar does not
// map to a device (cheriot_rtos_xbar.sv), and reports each one.
//
// The SoC keeps only what the firmware needs (see README.md). A firmware that touches a Sonata
// peripheral that is not here -- GPIO, pinmux, SPI, I2C, the LCD, USB, the RGB LED controller,
// system_info -- lands here. By default the access completes: reads return 0, writes are dropped,
// no bus error. That keeps the RTOS and its test suites running, and it is not silent: every
// access is printed to the simulator log as
//
//   [cheriot_rtos_default_rsp] <time>: READ|WRITE <address> (unmapped, <outcome>)
//
// and the number of accesses is printed at the end of the run. +default_rsp_error=1 makes the
// responder return a TL-UL error instead, which the core raises as a load/store access fault:
// use it to find which code made the access.
//
// Structure as tlul_err_resp: one outstanding request, response one cycle after acceptance.
module cheriot_rtos_default_rsp (
  input  logic              clk_i,
  input  logic              rst_ni,
  input  tlul_pkg::tl_h2d_t tl_i,
  output tlul_pkg::tl_d2h_t tl_o
);
  import tlul_pkg::*;

  logic                            err_mode;
  logic                            rsp_pending;
  tl_a_op_e                        rsp_opcode;
  logic [$bits(tl_i.a_source)-1:0] rsp_source;
  logic [$bits(tl_i.a_size)-1:0]   rsp_size;
  tl_d2h_t                         tl_o_int;

`ifndef SYNTHESIS
  int unsigned n_reads, n_writes;
  initial begin
    int e;
    err_mode = 1'b0;
    if ($value$plusargs("default_rsp_error=%d", e)) err_mode = (e != 0);
  end
`else
  assign err_mode = 1'b0;
`endif

  tlul_rsp_intg_gen #(
    .EnableRspIntgGen (0),
    .EnableDataIntgGen(0)
  ) u_intg_gen (
    .tl_i(tl_o_int),
    .tl_o(tl_o)
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rsp_pending <= 1'b0;
      rsp_source  <= '0;
      rsp_opcode  <= Get;
      rsp_size    <= '0;
    end else if (rsp_pending && tl_i.d_ready) begin
      rsp_pending <= 1'b0;
    end else if (tl_i.a_valid && tl_o_int.a_ready) begin
      rsp_pending <= 1'b1;
      rsp_source  <= tl_i.a_source;
      rsp_opcode  <= tl_i.a_opcode;
      rsp_size    <= tl_i.a_size;
    end
  end

  assign tl_o_int.a_ready  = ~rsp_pending;
  assign tl_o_int.d_valid  = rsp_pending;
  assign tl_o_int.d_data   = '0;
  assign tl_o_int.d_source = rsp_source;
  assign tl_o_int.d_sink   = '0;
  assign tl_o_int.d_param  = '0;
  assign tl_o_int.d_size   = rsp_size;
  assign tl_o_int.d_opcode = (rsp_opcode == Get) ? AccessAckData : AccessAck;
  assign tl_o_int.d_user   = '0;
  assign tl_o_int.d_error  = err_mode;

`ifndef SYNTHESIS
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      n_reads  <= 0;
      n_writes <= 0;
    end else if (tl_i.a_valid && tl_o_int.a_ready) begin
      if (tl_i.a_opcode == Get) n_reads  <= n_reads + 1;
      else                      n_writes <= n_writes + 1;
      $display("[cheriot_rtos_default_rsp] %0t: %s %h (unmapped, %s)", $time,
               tl_i.a_opcode == Get ? "READ " : "WRITE", tl_i.a_address,
               err_mode ? "TL-UL error" : (tl_i.a_opcode == Get ? "read as 0" : "dropped"));
    end
  end

  final begin
    $display("[cheriot_rtos_default_rsp] %0d read(s), %0d write(s) to unmapped addresses",
             n_reads, n_writes);
  end
`endif

  logic unused_tl_i;
  assign unused_tl_i = ^{tl_i.a_param, tl_i.a_mask, tl_i.a_data, tl_i.a_user};
endmodule
