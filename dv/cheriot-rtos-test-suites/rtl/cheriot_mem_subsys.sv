// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Derived from sonata-system/rtl/system/cheriot_mem_subsys.sv, where it is an uncommitted local
// addition, so that this flow does not depend on a local change in another submodule. This copy
// follows lowRISC/opentitan PR #31515 (the trbe_done interrupt into the shim); the sonata-system
// copy still targets PR #31470.

// Sonata integration of the OpenTitan CHERIoT memory subsystem (opentitan-cheriot/hw/ip/cheriot,
// lowRISC/opentitan PR #31515): capability tags and the revocation bitmap in one meta SRAM, the
// revocation engine (TRBE) sweeping the SRAM, and the rev_ctl shim so the CHERIoT RTOS drives the
// TRBE through its existing hardware-revoker interface.
//
// What changes relative to Sonata without it:
// - Tags live in the meta SRAM, not in the SRAM/HyperRAM models. The core's tag goes to the
//   subsystem's tag filter; the capability bit on the bus beyond it is forced to 0, so the old tag
//   stores stay empty and there is one source of truth. The tag the core loads comes from the
//   subsystem (core_tag_o), not from d_user.
// - The load barrier's bitmap reads (ibex_top trvk_revbm_*) go to the subsystem's bitmap port.
// - Software's bitmap window (the xbar's rev_tag device, 0x3000_0000) is the subsystem's revbm
//   window: the first MemSizeRevbm bytes of the meta SRAM. Full 32-bit word accesses only.
// - The debug host's SRAM writes bypass the tag filter and do not clear tags, as SBA does in
//   OpenTitan.
// - The HyperRAM window is the subsystem's NVM region. The core's tag filter treats it as
//   read-only (cheriot_wtrc): a capability store there is a read and compare, not a write, and
//   is answered with a bus error unless the memory already holds the capability's 64 bits.
// - The subsystem's trbe_done interrupt goes to the rev_ctl shim, which waits on it; the
//   firmware's revoker interrupt is rev_ctl's.
module cheriot_mem_subsys #(
  parameter logic [31:0] MainSramBaseAddr = 32'h0010_0000,
  parameter logic [31:0] MainSramTopAddr  = 32'h0012_0000,
  parameter logic [31:0] NvmBaseAddr      = 32'h4000_0000, // HyperRAM
  parameter logic [31:0] NvmTopAddr       = 32'h4010_0000,
  parameter logic [31:0] MetaSramBaseAddr = 32'h3000_0000,
  parameter int unsigned MemSizeRevbm     = 2048
) (
  input  logic clk_i,
  input  logic rst_ni,

  input  logic cheri_en_i,

  // Core data port, from the core's tlul_adapter_host, and its tag sideband.
  input  tlul_pkg::tl_h2d_t core_tl_i,
  output tlul_pkg::tl_d2h_t core_tl_o,
  input  logic              core_tag_i,
  output logic              core_tag_o,

  // Core data port onwards, to the xbar's ibex_lsu host port.
  output tlul_pkg::tl_h2d_t lsu_tl_o,
  input  tlul_pkg::tl_d2h_t lsu_tl_i,

  // Revocation engine read port, to the xbar's cheriot_trbe host port.
  output tlul_pkg::tl_h2d_t trbe_tl_o,
  input  tlul_pkg::tl_d2h_t trbe_tl_i,

  // Software's revocation bitmap window, from the xbar's rev_tag device port.
  input  tlul_pkg::tl_h2d_t revbm_tl_i,
  output tlul_pkg::tl_d2h_t revbm_tl_o,

  // Load barrier bitmap port (ibex_top trvk_revbm_*).
  input  logic        trvk_revbm_req_i,
  output logic        trvk_revbm_gnt_o,
  input  logic [31:0] trvk_revbm_addr_i,
  output logic        trvk_revbm_rvalid_o,
  output logic [31:0] trvk_revbm_rdata_o,
  output logic [6:0]  trvk_revbm_rdata_intg_o,
  output logic        trvk_revbm_err_o,

  // rev_ctl core-side interface.
  input  logic [127:0] rev_ctl_to_core_i,
  output logic [ 63:0] rev_core_to_ctl_o,

  // Sticky: a sweep the shim started did not complete without an error (cheriot_rev_ctl_trbe.sv).
  output logic trbe_ctl_err_o,
  // The subsystem's fatal alert, as a level (alert handshake terminated here).
  output logic fatal_alert_o
);
  // Meta SRAM: revocation bitmap, then HyperRAM tags, then SRAM tags, one bit per 8 bytes
  // (cheriot.sv address map).
  localparam int unsigned MetaSizeByte = MemSizeRevbm +
                                         (NvmTopAddr - NvmBaseAddr) / 256 * 4 +
                                         (MainSramTopAddr - MainSramBaseAddr) / 256 * 4;
  localparam int unsigned MetaWords    = MetaSizeByte / 4;
  localparam int unsigned MetaAw       = $clog2(MetaWords);

  prim_mubi_pkg::mubi4_t cheriot_ena;
  assign cheriot_ena = cheri_en_i ? prim_mubi_pkg::MuBi4True : prim_mubi_pkg::MuBi4False;

  tlul_pkg::tl_h2d_t cored_h_h2d;
  tlul_pkg::tl_h2d_t corerevbm_h2d;
  tlul_pkg::tl_d2h_t corerevbm_d2h;
  tlul_pkg::tl_h2d_t regs_h2d;
  tlul_pkg::tl_d2h_t regs_d2h;
  tlul_pkg::tl_h2d_t meta_h2d;
  tlul_pkg::tl_d2h_t meta_d2h;
  tlul_pkg::tl_d2h_t trbe_d2h_intg;
  logic              intr_trbe_done;

  prim_alert_pkg::alert_tx_t [cheriot_reg_pkg::NumAlerts-1:0] alert_tx;

  cheriot #(
    .addr_t          (logic [31:0]),
    .MainSramBaseAddr(MainSramBaseAddr),
    .MainSramTopAddr (MainSramTopAddr),
    .NvmBaseAddr     (NvmBaseAddr),
    .NvmTopAddr      (NvmTopAddr),
    .MetaSramBaseAddr(MetaSramBaseAddr),
    .MemSizeRevbm    (MemSizeRevbm),
    .AlertAsyncOn    ('0),
    // The "NVM" region here is the writable code RAM (Sonata's HyperRAM), and the RTOS loader stores
    // capabilities into its import tables: they must be written, not verified against the RAM.
    // Parameter added by opentitan-cheriot/patches/0002-nvmcapstores-parameter.patch.
    .NvmCapStores    (1'b0)
  ) u_cheriot (
    .clk_i,
    .rst_ni,
    .cheriot_ena_i   (cheriot_ena),
    .intr_trbe_done_o(intr_trbe_done),
    .alert_rx_i      ({cheriot_reg_pkg::NumAlerts{prim_alert_pkg::ALERT_RX_DEFAULT}}),
    .alert_tx_o      (alert_tx),
    .regs_tl_d_i     (regs_h2d),
    .regs_tl_d_o     (regs_d2h),
    .cored_tl_d_i    (core_tl_i),
    .cored_tag_h2d_i (core_tag_i),
    .cored_tl_d_o    (core_tl_o),
    .cored_tag_d2h_o (core_tag_o),
    .corerevbm_tl_i  (corerevbm_h2d),
    .corerevbm_tl_o  (corerevbm_d2h),
    .revbm_tl_d_i    (revbm_tl_i),
    .revbm_tl_d_o    (revbm_tl_o),
    .cored_tl_h_o    (cored_h_h2d),
    .cored_tl_h_i    (lsu_tl_i),
    .trbe_tl_h_o     (trbe_tl_o),
    .trbe_tl_h_i     (trbe_d2h_intg),
    .meta_sram_tl_o  (meta_h2d),
    .meta_sram_tl_i  (meta_d2h)
  );

  // Tags beyond the tag filter are the subsystem's business; never store them in the SRAM or
  // HyperRAM models as well.
  always_comb begin
    lsu_tl_o                   = cored_h_h2d;
    lsu_tl_o.a_user.capability = 1'b0;
  end

  // The TRBE checks response and data integrity on every word it sweeps and never revokes a
  // capability whose read failed the check (cheriot_trbe_mover.sv rerr). Sonata's SRAM adapter
  // does not generate integrity (EnableRspIntgGen = 0), so without this every sweep would revoke
  // nothing while reporting success. OpenTitan's SRAM generates it at its adapter; this generates
  // it at the same point of the path, as Sonata's SRAM stores no ECC to protect either way.
  tlul_rsp_intg_gen #(
    .EnableRspIntgGen (1'b1),
    .EnableDataIntgGen(1'b1)
  ) u_trbe_rsp_intg_gen (
    .tl_i(trbe_tl_i),
    .tl_o(trbe_d2h_intg)
  );

  // Load barrier bitmap reads.
  tlul_adapter_host #(
    .MAX_REQS(1)
  ) u_trvk_revbm_host (
    .clk_i,
    .rst_ni,
    .req_i        (trvk_revbm_req_i),
    .gnt_o        (trvk_revbm_gnt_o),
    .addr_i       (trvk_revbm_addr_i),
    .we_i         (1'b0),
    .wdata_i      ('0),
    .wdata_cap_i  (1'b0),
    .wdata_intg_i ('0),
    .be_i         ('1),
    .instr_type_i (prim_mubi_pkg::MuBi4False),
    .valid_o      (trvk_revbm_rvalid_o),
    .rdata_o      (trvk_revbm_rdata_o),
    .rdata_cap_o  (),
    .rdata_intg_o (trvk_revbm_rdata_intg_o),
    .err_o        (trvk_revbm_err_o),
    .intg_err_o   (),
    .tl_o         (corerevbm_h2d),
    .tl_i         (corerevbm_d2h)
  );

  cheriot_rev_ctl_trbe u_rev_ctl_trbe (
    .clk_i,
    .rst_ni,
    .ctl_to_core_i(rev_ctl_to_core_i),
    .core_to_ctl_o(rev_core_to_ctl_o),
    .tl_o         (regs_h2d),
    .tl_i         (regs_d2h),
    .trbe_done_i  (intr_trbe_done),
    .err_o        (trbe_ctl_err_o)
  );

  // Meta SRAM. Requests from Sonata's hosts carry no command integrity, so it is not checked;
  // responses carry response and data integrity, which the RMW filter, the TRBE's TRVK filter and
  // the core (MemECC) all check.
  logic              meta_req, meta_we, meta_rvalid;
  logic [MetaAw-1:0] meta_addr;
  logic [31:0]       meta_wdata, meta_wmask, meta_rdata;

  tlul_adapter_sram #(
    .SramAw           (MetaAw),
    .SramDw           (32),
    .Outstanding      (1),
    .ByteAccess       (0),
    .CmdIntgCheck     (1'b0),
    .EnableRspIntgGen (1'b1),
    .EnableDataIntgGen(1'b1)
  ) u_meta_sram_adapter (
    .clk_i,
    .rst_ni,
    .tl_i                      (meta_h2d),
    .tl_o                      (meta_d2h),
    .en_ifetch_i               (prim_mubi_pkg::MuBi4False),
    .req_o                     (meta_req),
    .req_type_o                (),
    .gnt_i                     (meta_req),
    .we_o                      (meta_we),
    .addr_o                    (meta_addr),
    .wdata_o                   (meta_wdata),
    .wdata_cap_o               (),
    .wmask_o                   (meta_wmask),
    .intg_error_o              (),
    .rdata_i                   (meta_rdata),
    .rdata_cap_i               (1'b0),
    .rvalid_i                  (meta_rvalid),
    .rerror_i                  (2'b00),
    .compound_txn_in_progress_o(),
    .readback_en_i             (prim_mubi_pkg::MuBi4False),
    .readback_error_o          (),
    .wr_collision_i            (1'b0),
    .write_pending_i           (1'b0)
  );

  // Starts all-zero: no tags set, nothing revoked (OpenTitan's sram_ctrl initialises its RAM).
  logic [31:0] meta_mem [MetaWords];
  initial begin
    for (int i = 0; i < MetaWords; i++) meta_mem[i] = '0;
  end

  always_ff @(posedge clk_i) begin
    if (meta_req && meta_we && meta_addr < MetaAw'(MetaWords)) begin
      meta_mem[meta_addr] <= (meta_mem[meta_addr] & ~meta_wmask) | (meta_wdata & meta_wmask);
    end
    meta_rdata <= (meta_addr < MetaAw'(MetaWords)) ? meta_mem[meta_addr] : '0;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) meta_rvalid <= 1'b0;
    else         meta_rvalid <= meta_req && !meta_we;
  end

  // With AsyncOn = 0 the fatal alert is a differential pair; alert_p high is the alert.
  assign fatal_alert_o = alert_tx[0].alert_p;
endmodule
