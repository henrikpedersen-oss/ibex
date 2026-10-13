// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Debug-access gate on the debug module's system bus access (SBA) host port of the CHERIoT RTOS
// test SoC (cheriot_rtos_soc.sv).
//
// The SoC's model of OpenTitan's rv_dm SBA gate: rv_dm puts a tlul_lc_gate
// (u_tlul_lc_gate_sba, SEC_CM SBA_TL_LC_GATE) between its SBA tlul_adapter_host and the crossbar,
// enabled by lc_hw_debug_en. Same behaviour, without the life-cycle and sparse-FSM machinery (no
// lc_ctrl_pkg, prim_lc_sync or prim_blanker in this SoC):
//   - en_i uses lc_ctrl_pkg::lc_tx_t's encoding (On = 4'b0101 = ibex_pkg::IbexMuBiOn, Off =
//     4'b1010). The gate is open only for a strict On; any other value, including an invalid
//     encoding, closes it (fail closed, as lc_tx_test_true_strict / lc_tx_test_false_loose).
//   - While open, requests and responses pass unchanged.
//   - When en_i leaves On, new requests are held off until every outstanding response has
//     returned (StDrain); then every request is answered here with a TL-UL error by tlul_err_resp
//     and nothing reaches the crossbar (StError). The DM reports such an access as sberror = 2
//     (bus error).
//   - When en_i returns to On, error responses still in flight are let out first (StErrorDrain).
//   - Out of reset the gate is closed (StError), as tlul_lc_gate's state register resets to it.
// Not modelled: tlul_lc_gate's flush handshake (unused by rv_dm) and its sparse-state alert.
module cheriot_rtos_dbg_gate (
  input  logic                 clk_i,
  input  logic                 rst_ni,

  // Debug access enable (lc_hw_debug_en), lc_tx_t encoding.
  input  ibex_pkg::ibex_mubi_t en_i,

  // From the debug module's SBA host adapter.
  input  tlul_pkg::tl_h2d_t    tl_h_i,
  output tlul_pkg::tl_d2h_t    tl_h_o,

  // To the crossbar's dbg_host port.
  output tlul_pkg::tl_h2d_t    tl_d_o,
  input  tlul_pkg::tl_d2h_t    tl_d_i
);
  import tlul_pkg::*;

  typedef enum logic [1:0] {
    StActive,
    StDrain,
    StError,
    StErrorDrain
  } state_e;

  state_e     state_d, state_q;
  logic       en;
  logic       a_ack, d_ack;
  logic       block_cmd, err_en;
  logic [1:0] outstanding_q;

  assign en    = (en_i == ibex_pkg::IbexMuBiOn);
  assign a_ack = tl_h_i.a_valid & tl_h_o.a_ready;
  assign d_ack = tl_h_o.d_valid & tl_h_i.d_ready;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      outstanding_q <= '0;
    end else if (a_ack && !d_ack) begin
      outstanding_q <= outstanding_q + 2'd1;
    end else if (d_ack && !a_ack) begin
      outstanding_q <= outstanding_q - 2'd1;
    end
  end

  always_comb begin
    state_d   = state_q;
    block_cmd = 1'b0;
    err_en    = 1'b0;
    unique case (state_q)
      StActive: begin
        if (!en) state_d = StDrain;
      end
      StDrain: begin
        block_cmd = 1'b1;
        if (outstanding_q == '0) state_d = en ? StActive : StError;
      end
      StError: begin
        err_en = 1'b1;
        if (en) state_d = StErrorDrain;
      end
      StErrorDrain: begin
        err_en    = 1'b1;
        block_cmd = 1'b1;
        if (outstanding_q == '0) state_d = StActive;
      end
      default: begin
        err_en  = 1'b1;
        state_d = StError;
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) state_q <= StError;
    else         state_q <= state_d;
  end

  // Host-side interposition, as tlul_lc_gate: while closed the crossbar sees nothing (all-zero
  // request, no d_ready) and the host is answered by the local error responder.
  tl_h2d_t err_h2d;
  tl_d2h_t err_d2h;

  always_comb begin
    tl_d_o  = tl_h_i;
    tl_h_o  = tl_d_i;
    err_h2d = '0;
    if (err_en) begin
      tl_d_o  = '0;
      err_h2d = tl_h_i;
      tl_h_o  = err_d2h;
    end
    if (block_cmd) begin
      tl_h_o.a_ready  = 1'b0;
      tl_d_o.a_valid  = 1'b0;
      err_h2d.a_valid = 1'b0;
    end
  end

  tlul_err_resp u_err_resp (
    .clk_i,
    .rst_ni,
    .tl_h_i (err_h2d),
    .tl_h_o (err_d2h)
  );
endmodule
