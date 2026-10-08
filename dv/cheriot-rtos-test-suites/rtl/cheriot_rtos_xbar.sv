// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// TL-UL crossbars of the CHERIoT RTOS test SoC (cheriot_rtos_soc.sv).
//
// A cut-down Sonata xbar_main / xbar_ifetch: same address decode (Sonata's tl_main_pkg and
// tl_ifetch_pkg constants, so the map cannot drift from the board file the firmware is built
// for) and the same per-device pipelining, but only the devices this SoC has. Everything else
// on the data side goes to one port, `default`, which the SoC connects to
// cheriot_rtos_default_rsp: the firmware sees a response, and the testbench log shows the access.
//
//   data host (ibex_lsu, after the CHERIoT memory subsystem)
//     -> sram      0x0010_0000  128 KiB   (shared with the TRBE host)
//     -> code_ram  0x4000_0000  1 MiB     (Sonata's HyperRAM window)
//     -> rev_tag   0x3000_0000  2 KiB     (the subsystem's revocation-bitmap window)
//     -> hw_rev    0x8000_a000  4 KiB     (rev_ctl)
//     -> timer     0x8004_0000  64 KiB    (rv_timer / CLINT)
//     -> uart0     0x8010_0000  4 KiB
//     -> rv_plic   0x8800_0000  128 MiB
//     -> default   everything else
//   cheriot_trbe host -> sram only, with no address decode (as in Sonata's xbar_main)
//   ifetch host
//     -> sram      0x0010_0000  (tl_ifetch_pkg mask: 256 KiB window, aliasing the 128 KiB)
//     -> code_ram  0x4000_0000
//     -> anything else: TL-UL error from the socket's own error responder, reported below
module cheriot_rtos_xbar (
  input  logic clk_i,
  input  logic rst_ni,

  // Hosts.
  input  tlul_pkg::tl_h2d_t tl_lsu_i,
  output tlul_pkg::tl_d2h_t tl_lsu_o,
  input  tlul_pkg::tl_h2d_t tl_trbe_i,
  output tlul_pkg::tl_d2h_t tl_trbe_o,
  input  tlul_pkg::tl_h2d_t tl_ifetch_i,
  output tlul_pkg::tl_d2h_t tl_ifetch_o,

  // Data-side devices.
  output tlul_pkg::tl_h2d_t tl_sram_a_o,
  input  tlul_pkg::tl_d2h_t tl_sram_a_i,
  output tlul_pkg::tl_h2d_t tl_code_a_o,
  input  tlul_pkg::tl_d2h_t tl_code_a_i,
  output tlul_pkg::tl_h2d_t tl_rev_tag_o,
  input  tlul_pkg::tl_d2h_t tl_rev_tag_i,
  output tlul_pkg::tl_h2d_t tl_hw_rev_o,
  input  tlul_pkg::tl_d2h_t tl_hw_rev_i,
  output tlul_pkg::tl_h2d_t tl_timer_o,
  input  tlul_pkg::tl_d2h_t tl_timer_i,
  output tlul_pkg::tl_h2d_t tl_uart0_o,
  input  tlul_pkg::tl_d2h_t tl_uart0_i,
  output tlul_pkg::tl_h2d_t tl_rv_plic_o,
  input  tlul_pkg::tl_d2h_t tl_rv_plic_i,
  output tlul_pkg::tl_h2d_t tl_default_o,
  input  tlul_pkg::tl_d2h_t tl_default_i,

  // Instruction-side devices (second ports of the two memories).
  output tlul_pkg::tl_h2d_t tl_sram_b_o,
  input  tlul_pkg::tl_d2h_t tl_sram_b_i,
  output tlul_pkg::tl_h2d_t tl_code_b_o,
  input  tlul_pkg::tl_d2h_t tl_code_b_i
);
  import tlul_pkg::*;

  // ── Data side ─────────────────────────────────────────────────────────────────────────────────
  typedef enum int {
    DevSram    = 0,
    DevCode    = 1,
    DevRevTag  = 2,
    DevHwRev   = 3,
    DevTimer   = 4,
    DevUart0   = 5,
    DevRvPlic  = 6,
    DevDefault = 7
  } lsu_dev_e;
  localparam int unsigned NLsuDev = 8;

  tl_h2d_t lsu_ds_h2d [NLsuDev];
  tl_d2h_t lsu_ds_d2h [NLsuDev];
  logic [3:0] lsu_dev_sel;

  function automatic logic hit(logic [31:0] addr, logic [31:0] base, logic [31:0] mask);
    return (addr & ~mask) == base;
  endfunction

  always_comb begin
    lsu_dev_sel = 4'(DevDefault);
    if      (hit(tl_lsu_i.a_address, tl_main_pkg::ADDR_SPACE_SRAM,     tl_main_pkg::ADDR_MASK_SRAM))
      lsu_dev_sel = 4'(DevSram);
    else if (hit(tl_lsu_i.a_address, tl_main_pkg::ADDR_SPACE_HYPERRAM, tl_main_pkg::ADDR_MASK_HYPERRAM))
      lsu_dev_sel = 4'(DevCode);
    else if (hit(tl_lsu_i.a_address, tl_main_pkg::ADDR_SPACE_REV_TAG,  tl_main_pkg::ADDR_MASK_REV_TAG))
      lsu_dev_sel = 4'(DevRevTag);
    else if (hit(tl_lsu_i.a_address, tl_main_pkg::ADDR_SPACE_HW_REV,   tl_main_pkg::ADDR_MASK_HW_REV))
      lsu_dev_sel = 4'(DevHwRev);
    else if (hit(tl_lsu_i.a_address, tl_main_pkg::ADDR_SPACE_TIMER,    tl_main_pkg::ADDR_MASK_TIMER))
      lsu_dev_sel = 4'(DevTimer);
    else if (hit(tl_lsu_i.a_address, tl_main_pkg::ADDR_SPACE_UART0,    tl_main_pkg::ADDR_MASK_UART0))
      lsu_dev_sel = 4'(DevUart0);
    else if (hit(tl_lsu_i.a_address, tl_main_pkg::ADDR_SPACE_RV_PLIC,  tl_main_pkg::ADDR_MASK_RV_PLIC))
      lsu_dev_sel = 4'(DevRvPlic);
  end

  // Pipelining as Sonata's xbar_main (u_s1n_27): pass-through except UART0 and the PLIC, which
  // have a one-entry request/response FIFO.
  tlul_socket_1n #(
    .HReqDepth (4'h0),
    .HRspDepth (4'h0),
    .DReqPass  (8'b1001_1111),
    .DRspPass  (8'b1001_1111),
    .DReqDepth (32'h0110_0000),
    .DRspDepth (32'h0110_0000),
    .N         (NLsuDev)
  ) u_s1n_lsu (
    .clk_i,
    .rst_ni,
    .tl_h_i       (tl_lsu_i),
    .tl_h_o       (tl_lsu_o),
    .tl_d_o       (lsu_ds_h2d),
    .tl_d_i       (lsu_ds_d2h),
    .dev_select_i (lsu_dev_sel)
  );

  // SRAM port A is shared by the core's data port and the TRBE's sweep reads.
  tl_h2d_t sram_us_h2d [2];
  tl_d2h_t sram_us_d2h [2];

  assign sram_us_h2d[0]     = lsu_ds_h2d[DevSram];
  assign lsu_ds_d2h[DevSram] = sram_us_d2h[0];
  assign sram_us_h2d[1]     = tl_trbe_i;
  assign tl_trbe_o          = sram_us_d2h[1];

  tlul_socket_m1 #(
    .HReqDepth (8'h0),
    .HRspDepth (8'h0),
    .DReqDepth (4'h0),
    .DRspDepth (4'h0),
    .M         (2)
  ) u_sm1_sram (
    .clk_i,
    .rst_ni,
    .tl_h_i (sram_us_h2d),
    .tl_h_o (sram_us_d2h),
    .tl_d_o (tl_sram_a_o),
    .tl_d_i (tl_sram_a_i)
  );

  assign tl_code_a_o             = lsu_ds_h2d[DevCode];
  assign lsu_ds_d2h[DevCode]     = tl_code_a_i;
  assign tl_rev_tag_o            = lsu_ds_h2d[DevRevTag];
  assign lsu_ds_d2h[DevRevTag]   = tl_rev_tag_i;
  assign tl_hw_rev_o             = lsu_ds_h2d[DevHwRev];
  assign lsu_ds_d2h[DevHwRev]    = tl_hw_rev_i;
  assign tl_timer_o              = lsu_ds_h2d[DevTimer];
  assign lsu_ds_d2h[DevTimer]    = tl_timer_i;
  assign tl_uart0_o              = lsu_ds_h2d[DevUart0];
  assign lsu_ds_d2h[DevUart0]    = tl_uart0_i;
  assign tl_rv_plic_o            = lsu_ds_h2d[DevRvPlic];
  assign lsu_ds_d2h[DevRvPlic]   = tl_rv_plic_i;
  assign tl_default_o            = lsu_ds_h2d[DevDefault];
  assign lsu_ds_d2h[DevDefault]  = tl_default_i;

  // ── Instruction side ──────────────────────────────────────────────────────────────────────────
  localparam int unsigned NIfDev = 2;

  tl_h2d_t if_ds_h2d [NIfDev];
  tl_d2h_t if_ds_d2h [NIfDev];
  logic [1:0] if_dev_sel;

  always_comb begin
    if_dev_sel = 2'(NIfDev); // the socket's own error responder
    if      (hit(tl_ifetch_i.a_address, tl_ifetch_pkg::ADDR_SPACE_SRAM, tl_ifetch_pkg::ADDR_MASK_SRAM))
      if_dev_sel = 2'd0;
    else if (hit(tl_ifetch_i.a_address, tl_ifetch_pkg::ADDR_SPACE_HYPERRAM,
                 tl_ifetch_pkg::ADDR_MASK_HYPERRAM))
      if_dev_sel = 2'd1;
  end

  // As Sonata's xbar_ifetch (u_s1n_4): both memories pass-through.
  tlul_socket_1n #(
    .HReqDepth (4'h0),
    .HRspDepth (4'h0),
    .DReqPass  (2'b11),
    .DRspPass  (2'b11),
    .DReqDepth (8'h00),
    .DRspDepth (8'h00),
    .N         (NIfDev)
  ) u_s1n_ifetch (
    .clk_i,
    .rst_ni,
    .tl_h_i       (tl_ifetch_i),
    .tl_h_o       (tl_ifetch_o),
    .tl_d_o       (if_ds_h2d),
    .tl_d_i       (if_ds_d2h),
    .dev_select_i (if_dev_sel)
  );

  assign tl_sram_b_o  = if_ds_h2d[0];
  assign if_ds_d2h[0] = tl_sram_b_i;
  assign tl_code_b_o  = if_ds_h2d[1];
  assign if_ds_d2h[1] = tl_code_b_i;

`ifndef SYNTHESIS
  // An instruction fetch outside both memories gets a bus error, which the core turns into an
  // instruction access fault. Say so: in the UART log it is only a crash report, if that.
  always_ff @(posedge clk_i) begin
    if (rst_ni && tl_ifetch_i.a_valid && tl_ifetch_o.a_ready && if_dev_sel == 2'(NIfDev)) begin
      $display("[cheriot_rtos_xbar] %0t: instruction fetch from unmapped address %h: TL-UL error",
               $time, tl_ifetch_i.a_address);
    end
  end
`endif
endmodule
