// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Revocation-bitmap responder for the UVM and TestRIG testbenches.
//
// Answers TRVK's revocation-bitmap lookups from the bitmap defined in ibex_revbm_pkg, and
// drives trvk_heap_base_addr_i. The same package feeds the CHERIoT-Sail cosim
// (ibex_cosim_scoreboard::cheriot_sail_load_revbm), so a revoked CLC is predicted by the model
// from the bitmap contents, not copied from the DUT. See ibex_revbm_pkg.sv for the plusargs and
// for how the TRVK and CHERIoT-Sail bitmap layouts are reconciled.
//
// History
// -------
// core_ibex_tb_top.sv once tied the whole port off (gnt/rvalid constant 0). With tagged
// capabilities modelled (ibex_tag_mem.sv), TRVK stalled on the first lookup and
// DsRspFifoNoOverflow_A fired. Until 2026-10 this module then answered "not revoked" for every
// lookup; that is still the default (+revbm_mode=off), so existing tests are unaffected, but the
// revoked arm of the load barrier (REQ_TMP_01) is now reachable with +revbm_mode=random|range.
//
// What TRVK does with the answer (ibex_trvk.sv)
// ---------------------------------------------
//   revbm_revoked = revbm_rdata_i[bit_select] || revbm_err_i || |intg_error
// so a device error or bad integrity revokes, fail-safe, and also raises alert_major_bus_o
// (ibex_top.sv: trvk_revbm_device_error / trvk_revbm_data_intg_error). Error injection relies on
// both: the model is told the whole word is revoked, and core_ibex_tb_top.sv allows the bus alert
// in exactly the cycles this module flags on inj_err_o -- and requires it there.
//
// Integrity bits must be generated, not guessed
// ---------------------------------------------
// The scheme is inverted SECDED (prim_secded_inv_39_32), so the codeword for all-zero data is
// not all-zero; the encoder is instantiated here. Integrity-error injection flips one ECC bit,
// which TRVK's decoder reports as a (correctable) single-bit error and still treats as revoked.
// It needs MemECC: without it TRVK ignores the ECC bits, so the injection would not revoke and
// the model would disagree -- that combination is rejected at time 0.
//
// Handshake
// ---------
// One lookup outstanding at a time, as TRVK issues them (RevbmRspOnlyWhenOutstanding_A). With the
// default delays of 0 this is exactly the old behaviour: gnt = req, rvalid on the next edge.
// +revbm_gnt_delay_max / +revbm_rsp_delay_max add random backpressure and latency
// (cp_trvk_revbm_handshake's backpressured bin is unreachable without the former).

module ibex_revbm_responder #(
    parameter int unsigned BitmapAddrWidth = ibex_revbm_pkg::RevBitmapAddrWidth,
    parameter int unsigned BitmapBaseAddr  = ibex_revbm_pkg::RevBitmapBaseAddr,
    parameter bit          MemECC          = 1'b1
) (
    input  logic        clk_i,
    input  logic        rst_ni,

    input  logic        revbm_req_i,
    output logic        revbm_gnt_o,
    output logic        revbm_rvalid_o,
    input  logic [31:0] revbm_addr_i,
    output logic [31:0] revbm_rdata_o,
    output logic [6:0]  revbm_rdata_intg_o,
    output logic        revbm_err_o,

    // Value for the DUT's trvk_heap_base_addr_i (ibex_revbm_pkg::get_heap_base()).
    output logic [31:0] heap_base_o,
    // The response presented this cycle carries an injected device or integrity error.
    output logic        inj_err_o
);

  localparam int unsigned NumWords = 32'd1 << (BitmapAddrWidth - 2);

  //////////////////
  // Configuration //
  //////////////////

  bit          trace_en;
  bit [31:0]   heap_base_q;
  int unsigned gnt_delay_max;
  int unsigned rsp_delay_max;

  initial begin
    ibex_revbm_pkg::init();
    if (BitmapAddrWidth != ibex_revbm_pkg::RevBitmapAddrWidth ||
        BitmapBaseAddr  != ibex_revbm_pkg::RevBitmapBaseAddr) begin
      $fatal(1, "[REVBM] responder geometry (width %0d, base 0x%08x) differs from ibex_revbm_pkg (width %0d, base 0x%08x): the model would be fed a different bitmap",
             BitmapAddrWidth, BitmapBaseAddr,
             ibex_revbm_pkg::RevBitmapAddrWidth, ibex_revbm_pkg::RevBitmapBaseAddr);
    end
    if (!MemECC && ibex_revbm_pkg::uses_intg_errors()) begin
      $fatal(1, "[REVBM] +revbm_err_kind=intg|mixed needs MemECC (SecureIbex=1): without it TRVK ignores the ECC bits and the injected error would not revoke");
    end
    heap_base_q   = ibex_revbm_pkg::get_heap_base();
    gnt_delay_max = ibex_revbm_pkg::gnt_delay_max;
    rsp_delay_max = ibex_revbm_pkg::rsp_delay_max;
    // Per-lookup [REVBM] REQ/RSP lines: on by default (unchanged), off with +revbm_trace=0.
    trace_en = 1'b1;
    void'($value$plusargs("revbm_trace=%0b", trace_en));
  end

  assign heap_base_o = heap_base_q;

  ///////////////
  // Handshake //
  ///////////////

  logic        busy_q;        // a lookup has been granted and not yet answered
  int unsigned gnt_wait_q;    // cycles the next request still waits for its grant
  int unsigned rsp_wait_q;    // cycles the granted lookup still waits for its response
  logic [31:0] rsp_data_q;
  logic        rsp_dev_err_q;
  logic        rsp_intg_err_q;

  assign revbm_gnt_o    = revbm_req_i && !busy_q && (gnt_wait_q == 0);
  assign revbm_rvalid_o = busy_q && (rsp_wait_q == 0);

  function automatic int unsigned draw_delay(int unsigned max);
    return (max == 0) ? 0 : $urandom_range(max, 0);
  endfunction

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      busy_q         <= 1'b0;
      gnt_wait_q     <= 0;
      rsp_wait_q     <= 0;
      rsp_data_q     <= '0;
      rsp_dev_err_q  <= 1'b0;
      rsp_intg_err_q <= 1'b0;
    end else begin
      if (revbm_rvalid_o) begin
        busy_q <= 1'b0;
      end else if (busy_q && rsp_wait_q != 0) begin
        rsp_wait_q <= rsp_wait_q - 1;
      end

      if (revbm_req_i && !revbm_gnt_o && !busy_q && gnt_wait_q != 0) begin
        gnt_wait_q <= gnt_wait_q - 1;
      end

      if (revbm_gnt_o) begin
        automatic int unsigned word;
        word = (revbm_addr_i - BitmapBaseAddr) >> 2;
        if (revbm_addr_i[1:0] != 2'b00 || revbm_addr_i < BitmapBaseAddr || word >= NumWords) begin
          $error("[REVBM] lookup address 0x%08x outside the bitmap [0x%08x, +0x%0x)",
                 revbm_addr_i, BitmapBaseAddr, NumWords * 4);
          word = 0;
        end
        busy_q         <= 1'b1;
        rsp_wait_q     <= draw_delay(rsp_delay_max);
        gnt_wait_q     <= draw_delay(gnt_delay_max);
        rsp_data_q     <= ibex_revbm_pkg::bitmap_word(word);
        rsp_dev_err_q  <= ibex_revbm_pkg::word_err(word) && !ibex_revbm_pkg::word_err_is_intg(word);
        rsp_intg_err_q <= ibex_revbm_pkg::word_err_is_intg(word);
      end
    end
  end

  //////////////
  // Response //
  //////////////

  assign revbm_rdata_o = rsp_data_q;
  assign revbm_err_o   = revbm_rvalid_o && rsp_dev_err_q;
  assign inj_err_o     = revbm_rvalid_o && (rsp_dev_err_q || rsp_intg_err_q);

  logic [38:0] enc_word;
  prim_secded_inv_39_32_enc u_revbm_intg_enc (
    .data_i (rsp_data_q),
    .data_o (enc_word  )
  );
  // One flipped ECC bit: a single-bit error, which TRVK still counts as revoked.
  assign revbm_rdata_intg_o = enc_word[38:32] ^ {6'b0, rsp_intg_err_q};
  logic [31:0] unused_enc_data;
  assign unused_enc_data = enc_word[31:0];

  always_ff @(posedge clk_i) begin
    if (trace_en && rst_ni && revbm_req_i) begin
      $display("[REVBM] %0t REQ addr=%08h gnt=%b", $time, revbm_addr_i, revbm_gnt_o);
    end
    if (trace_en && rst_ni && revbm_rvalid_o) begin
      $display("[REVBM] %0t RSP rdata=%08h intg=%02h err=%b intg_err=%b",
               $time, revbm_rdata_o, revbm_rdata_intg_o, revbm_err_o, rsp_intg_err_q);
    end
  end

endmodule
