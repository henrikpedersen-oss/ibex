// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Minimal CHERIoT SoC for running CHERIoT RTOS firmware built for Sonata (board sonata-1.1 /
// sonata-simulator) on this repository's ibex_top.
//
// It keeps what the firmware touches and nothing else (README.md has the evidence):
//
//   0x0010_0000  SRAM, 128 KiB, dual-ported (data + fetch); boot vector at +0x80
//   0x3000_0000  revocation bitmap window (2 KiB): the CHERIoT memory subsystem's meta SRAM
//   0x4000_0000  code RAM, 1 MiB, dual-ported: a plain SRAM model where Sonata has HyperRAM
//   0x8000_a000  rev_ctl (the RTOS hardware-revoker interface), driving the subsystem's TRBE
//   0x8004_0000  rv_timer (CLINT: mtime, mtimecmp)
//   0x8010_0000  UART0 -- the test oracle: the testbench captures it with uartdpi
//   0x8800_0000  rv_plic
//   anything else: cheriot_rtos_default_rsp (logged; reads 0, writes dropped)
//
// The core and memory-subsystem integration is Sonata's, taken from sonata_system.sv with
// UseNewIbexCore = 1 and UseCheriotMemSubsys = 1 (the gen_new_ibex_core / gen_cheriot_mem_subsys
// branches): same core parameters, same bus adapters, same memory-integrity encoding, same
// subsystem parameters. What is gone: the debug module (and so ndmreset and debug_req), the
// debug host, GPIO, pinmux, I2C, SPI, USB, PWM, XADC, the RGB LED controller, system_info,
// UARTs 1 and 2, the HyperRAM controller, Sonata's own tag stores and revocation RAM, the legacy
// ibexc core and the REVOCATION_CONNECT stub path.
//
// Core configuration: the parameters below come from ibex/ibex_configs.yaml through
// util/ibex_config.py (cheriot_rtos_xlm_build.sh: IBEX_CFG_* defines for the enum-typed ones,
// -defparam on u_soc for the rest; default configuration opentitan, the one the UVM testbench,
// compliance and TestRIG build, so the coverage databases are of the same model). The fallbacks
// are opentitan's values. opentitan differs from Sonata's gen_new_ibex_core in two places:
// ICacheScramble = 1 (Sonata: 0; the key handshake is answered below) and, outside the yaml,
// DbgHwBreakNum = 1 (Sonata: 2; no firmware here uses triggers, and the other benches keep 1).
`ifndef IBEX_CFG_BaseIsa
  `define IBEX_CFG_BaseIsa ibex_pkg::BaseIsaRV32IorCHERIoT
`endif
`ifndef IBEX_CFG_RV32M
  `define IBEX_CFG_RV32M ibex_pkg::RV32MSingleCycle
`endif
`ifndef IBEX_CFG_RV32B
  `define IBEX_CFG_RV32B ibex_pkg::RV32BFull
`endif
`ifndef IBEX_CFG_RV32ZC
  `define IBEX_CFG_RV32ZC ibex_pkg::RV32ZcaZcbZcmp
`endif
`ifndef IBEX_CFG_RegFile
  `define IBEX_CFG_RegFile ibex_pkg::RegFileFF
`endif
module cheriot_rtos_soc #(
  parameter ibex_pkg::base_isa_e BaseIsa          = `IBEX_CFG_BaseIsa,
  parameter bit                  RV32E            = 1'b0,
  parameter ibex_pkg::rv32m_e    RV32M            = `IBEX_CFG_RV32M,
  parameter ibex_pkg::rv32b_e    RV32B            = `IBEX_CFG_RV32B,
  parameter ibex_pkg::rv32zc_e   RV32ZC           = `IBEX_CFG_RV32ZC,
  parameter ibex_pkg::regfile_e  RegFile          = `IBEX_CFG_RegFile,
  parameter bit                  BranchTargetALU  = 1'b1,
  parameter bit                  WritebackStage   = 1'b1,
  parameter bit                  ICache           = 1'b1,
  parameter bit                  ICacheECC        = 1'b1,
  parameter bit                  ICacheScramble   = 1'b1,
  parameter bit                  BranchPredictor  = 1'b0,
  parameter bit                  DbgTriggerEn     = 1'b1,
  parameter bit                  SecureIbex       = 1'b1,
  parameter bit                  PMPEnable        = 1'b1,
  parameter int unsigned         PMPGranularity   = 0,
  parameter int unsigned         PMPNumRegions    = 16,
  parameter int unsigned         MHPMCounterNum   = 10,
  parameter int unsigned         MHPMCounterWidth = 32
) (
  input  logic clk_i,
  input  logic rst_ni,

  // CHERIoT enable pin of the core (Sonata's cheri_en_i).
  input  logic cheri_en_i,

  // UART0 serial lines.
  input  logic uart_rx_i,
  output logic uart_tx_o
);
  import tl_main_pkg::*;

  localparam int unsigned MemSize       = 128 * 1024;  // SRAM
  localparam int unsigned CodeRamSize   = 1024 * 1024; // Sonata's HyperRAM
  localparam int unsigned BusDataWidth  = 32;
  localparam int unsigned TRegAddrWidth = 16;          // Timer uses more address bits.
  localparam int unsigned TAccessLatency = 0;

  // Size of the revocation bitmap: one bit for each 64 bits of SRAM (sonata_system.sv).
  localparam int unsigned RevTagDepth     = (MemSize / 8) / BusDataWidth;
  localparam int unsigned RevTagAddrWidth = $clog2(RevTagDepth);

  // Debug is not in this SoC, but the core keeps Sonata's debug addresses: dm::HaltAddress =
  // 0x800, dm::ExceptionAddress = 0x808 in the debug module's window at
  // tl_ifetch_pkg::ADDR_SPACE_DBG_DEV. Nothing raises debug_req. DbgHwBreakNum is ibex_top's
  // default (1), as in the UVM testbench, compliance and TestRIG; Sonata has 2.
  localparam logic [31:0] DmHaltAddr      = tl_ifetch_pkg::ADDR_SPACE_DBG_DEV + 32'h800;
  localparam logic [31:0] DmExceptionAddr = tl_ifetch_pkg::ADDR_SPACE_DBG_DEV + 32'h808;

  // The crossbar decodes with Sonata's masks; the memories must be the size those masks imply.
  initial begin
    if (MemSize - 1 != ADDR_MASK_SRAM || CodeRamSize - 1 != ADDR_MASK_HYPERRAM ||
        RevTagDepth * 4 - 1 != ADDR_MASK_REV_TAG) begin
      $fatal(1, "cheriot_rtos_soc: memory sizes disagree with tl_main_pkg's address masks");
    end
  end

  ////////////////
  // Interrupts //
  ////////////////

  localparam int unsigned UartIrqs = 9;

  logic                timer_irq;
  logic                external_irq;
  logic                hardware_revoker_irq;
  logic [UartIrqs-1:0] uart_interrupts;

  // Sonata's PLIC source numbering (sonata_system.sv intr_vector, and the board file's
  // "interrupts"): 1 = revoker, 8 = UART0. The other sources belong to devices this SoC does not
  // have and are held low.
  logic [31:0] intr_vector;
  always_comb begin
    intr_vector    = '0;
    intr_vector[1] = hardware_revoker_irq;
    intr_vector[8] = |uart_interrupts;
  end

  //////////////////////////
  // Buses and crossbars  //
  //////////////////////////

  tlul_pkg::tl_h2d_t tl_ibex_ins_h2d;
  tlul_pkg::tl_d2h_t tl_ibex_ins_d2h;
  // Core data port before the CHERIoT memory subsystem; tl_ibex_lsu_* is the xbar side.
  tlul_pkg::tl_h2d_t tl_core_lsu_h2d;
  tlul_pkg::tl_d2h_t tl_core_lsu_d2h;
  tlul_pkg::tl_h2d_t tl_ibex_lsu_h2d;
  tlul_pkg::tl_d2h_t tl_ibex_lsu_d2h;
  tlul_pkg::tl_h2d_t tl_cheriot_trbe_h2d;
  tlul_pkg::tl_d2h_t tl_cheriot_trbe_d2h;

  tlul_pkg::tl_h2d_t tl_sram_a_h2d,  tl_sram_b_h2d;
  tlul_pkg::tl_d2h_t tl_sram_a_d2h,  tl_sram_b_d2h;
  tlul_pkg::tl_h2d_t tl_code_a_h2d,  tl_code_b_h2d;
  tlul_pkg::tl_d2h_t tl_code_a_d2h,  tl_code_b_d2h;
  tlul_pkg::tl_h2d_t tl_rev_tag_h2d;
  tlul_pkg::tl_d2h_t tl_rev_tag_d2h;
  tlul_pkg::tl_h2d_t tl_hw_rev_h2d;
  tlul_pkg::tl_d2h_t tl_hw_rev_d2h;
  tlul_pkg::tl_h2d_t tl_timer_h2d;
  tlul_pkg::tl_d2h_t tl_timer_d2h;
  tlul_pkg::tl_h2d_t tl_uart0_h2d;
  tlul_pkg::tl_d2h_t tl_uart0_d2h;
  tlul_pkg::tl_h2d_t tl_rv_plic_h2d;
  tlul_pkg::tl_d2h_t tl_rv_plic_d2h;
  tlul_pkg::tl_h2d_t tl_default_h2d;
  tlul_pkg::tl_d2h_t tl_default_d2h;

  cheriot_rtos_xbar u_xbar (
    .clk_i,
    .rst_ni,
    .tl_lsu_i     (tl_ibex_lsu_h2d),
    .tl_lsu_o     (tl_ibex_lsu_d2h),
    .tl_trbe_i    (tl_cheriot_trbe_h2d),
    .tl_trbe_o    (tl_cheriot_trbe_d2h),
    .tl_ifetch_i  (tl_ibex_ins_h2d),
    .tl_ifetch_o  (tl_ibex_ins_d2h),
    .tl_sram_a_o  (tl_sram_a_h2d),
    .tl_sram_a_i  (tl_sram_a_d2h),
    .tl_code_a_o  (tl_code_a_h2d),
    .tl_code_a_i  (tl_code_a_d2h),
    .tl_rev_tag_o (tl_rev_tag_h2d),
    .tl_rev_tag_i (tl_rev_tag_d2h),
    .tl_hw_rev_o  (tl_hw_rev_h2d),
    .tl_hw_rev_i  (tl_hw_rev_d2h),
    .tl_timer_o   (tl_timer_h2d),
    .tl_timer_i   (tl_timer_d2h),
    .tl_uart0_o   (tl_uart0_h2d),
    .tl_uart0_i   (tl_uart0_d2h),
    .tl_rv_plic_o (tl_rv_plic_h2d),
    .tl_rv_plic_i (tl_rv_plic_d2h),
    .tl_default_o (tl_default_h2d),
    .tl_default_i (tl_default_d2h),
    .tl_sram_b_o  (tl_sram_b_h2d),
    .tl_sram_b_i  (tl_sram_b_d2h),
    .tl_code_b_o  (tl_code_b_h2d),
    .tl_code_b_i  (tl_code_b_d2h)
  );

  ///////////////////////////////
  // Core bus-host adapters    //
  ///////////////////////////////

  logic        core_instr_req, core_instr_gnt, core_instr_rvalid, core_instr_err;
  logic [31:0] core_instr_addr, core_instr_rdata;

  logic        core_data_req, core_data_gnt, core_data_rvalid, core_data_we, core_data_err;
  logic [3:0]  core_data_be;
  logic [31:0] core_data_addr, core_data_wdata, core_data_rdata;
  logic        core_data_wcap;  // tag of the store (data_tag_o)
  logic        core_data_rcap;  // tag of the load, from the memory subsystem (data_tag_i)
  logic        core_lsu_rcap;   // d_user tag from the adapter: not used, see below

  tlul_adapter_host ibex_ins_host_adapter (
    .clk_i,
    .rst_ni,

    .req_i        (core_instr_req),
    .gnt_o        (core_instr_gnt),
    .addr_i       (core_instr_addr),
    .we_i         ('0),
    .wdata_i      ('0),
    .wdata_cap_i  ('0),
    .wdata_intg_i ('0),
    .be_i         ('0),
    .instr_type_i (prim_mubi_pkg::MuBi4True),

    .valid_o      (core_instr_rvalid),
    .rdata_o      (core_instr_rdata),
    .rdata_cap_o  (), // Instructions should not have capability tag set.
    .rdata_intg_o (),
    .err_o        (core_instr_err),
    .intg_err_o   (),

    .tl_o         (tl_ibex_ins_h2d),
    .tl_i         (tl_ibex_ins_d2h)
  );

  tlul_adapter_host ibex_lsu_host_adapter (
    .clk_i,
    .rst_ni,

    .req_i        (core_data_req),
    .gnt_o        (core_data_gnt),
    .addr_i       (core_data_addr),
    .we_i         (core_data_we),
    .wdata_i      (core_data_wdata),
    .wdata_cap_i  (core_data_wcap),
    .wdata_intg_i ('0),
    .be_i         (core_data_be),
    .instr_type_i (prim_mubi_pkg::MuBi4False),

    .valid_o      (core_data_rvalid),
    .rdata_o      (core_data_rdata),
    .rdata_cap_o  (core_lsu_rcap),
    .rdata_intg_o (),
    .err_o        (core_data_err),
    .intg_err_o   (),

    .tl_o         (tl_core_lsu_h2d),
    .tl_i         (tl_core_lsu_d2h)
  );

  // The tag the core loads comes from the memory subsystem (core_tag_o), not from d_user: beyond
  // the subsystem's tag filter the capability bit is forced to 0 (cheriot_mem_subsys.sv).
  logic unused_core_lsu_rcap;
  assign unused_core_lsu_rcap = core_lsu_rcap;

  //////////
  // Core //
  //////////

  // Memory integrity bits for the core's ECC checks (sonata_system.sv, gen_new_ibex_core):
  // SecureIbex = 1 makes the core check *_rdata_intg_i, and Sonata's memories store no
  // integrity, so it is generated here with the same inverted SECDED encoder the UVM
  // testbench's memory agent uses. Tying these to 0 is wrong even for zero data.
  logic [38:0] core_instr_rdata_enc;
  logic [38:0] core_data_rdata_enc;
  assign core_instr_rdata_enc = prim_secded_pkg::prim_secded_inv_39_32_enc(core_instr_rdata);
  assign core_data_rdata_enc  = prim_secded_pkg::prim_secded_inv_39_32_enc(core_data_rdata);
  logic unused_rdata_enc;
  assign unused_rdata_enc = ^{core_instr_rdata_enc[31:0], core_data_rdata_enc[31:0]};

  // Load barrier (ibex_trvk) bitmap port, served by the memory subsystem.
  logic        trvk_revbm_req;
  logic [31:0] trvk_revbm_addr;
  logic        core_revbm_gnt, core_revbm_rvalid, core_revbm_err;
  logic [31:0] core_revbm_rdata;
  logic [6:0]  core_revbm_rdata_intg;

  // rev_ctl <-> memory subsystem (TRBE shim).
  logic [127:0] hardware_revoker_control_reg_rdata;
  logic [63:0]  hardware_revoker_control_reg_wdata;

  // ICacheScramble = 1: out of reset, and again on every fence.i, the ICache requests a scrambling
  // key and keeps its tag RAM blocked (no allocation, no hits) until scramble_key_valid_i
  // (ibex_icache.sv AWAIT_SCRAMBLE_KEY). There is no key manager here: answer each request one
  // cycle later with a fixed zero key and nonce, as the compliance testbench does. Left
  // unanswered, the firmware still runs (the fill path does not wait for the key), but the cache
  // would never be used, and its coverage would say so.
  logic scramble_req, scramble_key_valid;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) scramble_key_valid <= 1'b0;
    else         scramble_key_valid <= scramble_req;
  end

  // Parameterised from ibex_configs.yaml (module parameters above), so coverage from this SoC is of
  // the same generate structure as the UVM testbench's.
  ibex_top_tracing #(
    .BaseIsa         ( BaseIsa          ),
    .RV32E           ( RV32E            ),
    .RV32M           ( RV32M            ),
    .RV32B           ( RV32B            ),
    .RV32ZC          ( RV32ZC           ),
    .RegFile         ( RegFile          ),
    .BranchTargetALU ( BranchTargetALU  ),
    .WritebackStage  ( WritebackStage   ),
    .BranchPredictor ( BranchPredictor  ),
    .SecureIbex      ( SecureIbex       ),
    .ICacheECC       ( ICacheECC        ),
    .ICacheScramble  ( ICacheScramble   ),
    .PMPEnable       ( PMPEnable        ),
    .PMPGranularity  ( PMPGranularity   ),
    .PMPNumRegions   ( PMPNumRegions    ),
    .MHPMCounterWidth( MHPMCounterWidth ),
    .DbgTriggerEn    ( DbgTriggerEn     ),
    .MHPMCounterNum  ( MHPMCounterNum   ),
    .ICache          ( ICache           ),
    .DmHaltAddr      ( DmHaltAddr       ),
    .DmExceptionAddr ( DmExceptionAddr  ),
    // The barrier addresses the subsystem's bitmap port directly: the bitmap is the first bytes
    // of the meta SRAM, at the rev_tag window's address. ibex_trvk takes a byte-address width, so
    // +2 gives the same number of words as the bitmap.
    .CheriotRevBitmapAddrWidth ( RevTagAddrWidth + 2           ),
    .CheriotRevBitmapBaseAddr  ( ADDR_SPACE_REV_TAG            )
  ) u_top_tracing (
    .clk_i,
    .rst_ni,

    .test_en_i              (1'b0),
    .scan_rst_ni            (1'b1),
    .ram_cfg_icache_tag_i   ('0),
    .ram_cfg_icache_tag_o   (  ),
    .ram_cfg_icache_data_i  ('0),
    .ram_cfg_icache_data_o  (  ),

    // Revocation applies to all of SRAM (the board file's revokable_memory_start).
    .trvk_heap_base_addr_i  (ADDR_SPACE_SRAM),

    .cheriot_enable_i       (cheri_en_i ? ibex_pkg::IbexMuBiOn : ibex_pkg::IbexMuBiOff),

    .hart_id_i              (32'b0),
    // First instruction executed is at 0x0010_0000 + 0x80.
    .boot_addr_i            (ADDR_SPACE_SRAM),

    .instr_req_o            (core_instr_req),
    .instr_gnt_i            (core_instr_gnt),
    .instr_rvalid_i         (core_instr_rvalid),
    .instr_addr_o           (core_instr_addr),
    .instr_rdata_i          (core_instr_rdata),
    .instr_rdata_intg_i     (core_instr_rdata_enc[38:32]),
    .instr_err_i            (core_instr_err),

    .data_req_o             (core_data_req),
    .data_gnt_i             (core_data_gnt),
    .data_rvalid_i          (core_data_rvalid),
    .data_we_o              (core_data_we),
    .data_be_o              (core_data_be),
    .data_addr_o            (core_data_addr),
    .data_wdata_o           (core_data_wdata),
    .data_wdata_intg_o      (),
    .data_tag_o             (core_data_wcap),
    .data_rdata_i           (core_data_rdata),
    .data_rdata_intg_i      (core_data_rdata_enc[38:32]),
    .data_tag_i             (core_data_rcap),
    .data_err_i             (core_data_err),

    .trvk_revbm_req_o       (trvk_revbm_req),
    .trvk_revbm_gnt_i       (core_revbm_gnt),
    .trvk_revbm_rvalid_i    (core_revbm_rvalid),
    .trvk_revbm_addr_o      (trvk_revbm_addr),
    .trvk_revbm_rdata_i     (core_revbm_rdata),
    .trvk_revbm_rdata_intg_i(core_revbm_rdata_intg),
    .trvk_revbm_err_i       (core_revbm_err),

    .irq_software_i         (1'b0),
    .irq_timer_i            (timer_irq),
    .irq_external_i         (external_irq),
    .irq_fast_i             (15'b0),
    .irq_nm_i               (1'b0),

    .scramble_key_valid_i   (scramble_key_valid),
    .scramble_key_i         ('0),
    .scramble_nonce_i       ('0),
    .scramble_req_o         (scramble_req),

    .debug_req_i            (1'b0),
    .crash_dump_o           (  ),
    .double_fault_seen_o    (  ),

    .fetch_enable_i         (ibex_pkg::IbexMuBiOn),
    .mcounteren_writable_i  (ibex_pkg::IbexMuBiOn),
    // Not wired anywhere (no alert handler); the testbench watches them (core_alert_monitor).
    .alert_minor_o          (  ),
    .alert_major_internal_o (  ),
    .alert_major_bus_o      (  ),
    .core_sleep_o           (  ),

    // Lockstep shadow-core outputs (SecureIbex = 1): compared inside ibex_top, not used here.
    .lockstep_cmp_en_o       (  ),
    .data_req_shadow_o       (  ),
    .data_we_shadow_o        (  ),
    .data_be_shadow_o        (  ),
    .data_addr_shadow_o      (  ),
    .data_wdata_shadow_o     (  ),
    .data_wdata_intg_shadow_o(  ),
    .instr_req_shadow_o      (  ),
    .instr_addr_shadow_o     (  )
  );

  ////////////////////////////////////
  // CHERIoT memory subsystem       //
  ////////////////////////////////////

  // Not wired anywhere (no alert handler). The testbench's trbe_monitor watches the underlying
  // error state and fails the run on it.
  logic trbe_ctl_err;
  logic cheriot_fatal_alert;
  logic unused_mem_subsys_err;
  assign unused_mem_subsys_err = trbe_ctl_err ^ cheriot_fatal_alert;

  cheriot_mem_subsys #(
    .MainSramBaseAddr(ADDR_SPACE_SRAM),
    .MainSramTopAddr (ADDR_SPACE_SRAM + MemSize),
    .NvmBaseAddr     (ADDR_SPACE_HYPERRAM),
    .NvmTopAddr      (ADDR_SPACE_HYPERRAM + CodeRamSize),
    .MetaSramBaseAddr(ADDR_SPACE_REV_TAG),
    .MemSizeRevbm    (RevTagDepth * 4)
  ) u_cheriot_mem_subsys (
    .clk_i,
    .rst_ni,
    .cheri_en_i             (cheri_en_i),
    .core_tl_i              (tl_core_lsu_h2d),
    .core_tl_o              (tl_core_lsu_d2h),
    .core_tag_i             (core_data_wcap),
    .core_tag_o             (core_data_rcap),
    .lsu_tl_o               (tl_ibex_lsu_h2d),
    .lsu_tl_i               (tl_ibex_lsu_d2h),
    .trbe_tl_o              (tl_cheriot_trbe_h2d),
    .trbe_tl_i              (tl_cheriot_trbe_d2h),
    .revbm_tl_i             (tl_rev_tag_h2d),
    .revbm_tl_o             (tl_rev_tag_d2h),
    .trvk_revbm_req_i       (trvk_revbm_req),
    .trvk_revbm_gnt_o       (core_revbm_gnt),
    .trvk_revbm_addr_i      (trvk_revbm_addr),
    .trvk_revbm_rvalid_o    (core_revbm_rvalid),
    .trvk_revbm_rdata_o     (core_revbm_rdata),
    .trvk_revbm_rdata_intg_o(core_revbm_rdata_intg),
    .trvk_revbm_err_o       (core_revbm_err),
    .rev_ctl_to_core_i      (hardware_revoker_control_reg_rdata),
    .rev_core_to_ctl_o      (hardware_revoker_control_reg_wdata),
    .trbe_ctl_err_o         (trbe_ctl_err),
    .fatal_alert_o          (cheriot_fatal_alert)
  );

  rev_ctl u_rev_ctl (
    .clk_i,
    .rst_ni,

    .core_to_ctl_i (hardware_revoker_control_reg_wdata),
    .ctl_to_core_o (hardware_revoker_control_reg_rdata),
    .rev_ctl_irq_o (hardware_revoker_irq),

    .tl_i          (tl_hw_rev_h2d),
    .tl_o          (tl_hw_rev_d2h)
  );

  //////////////
  // Memories //
  //////////////

  // Both memories are Sonata's `sram` (the HyperRAM window uses it too, as Sonata does under
  // USE_HYPERRAM_SRAM_MODEL). Loaded by the testbench from vmem files; their own tag RAMs stay
  // empty because the subsystem forces the capability bit to 0 beyond its tag filter.
  sram #(
    .AddrWidth       ( $clog2(MemSize)     ),
    .DataWidth       ( BusDataWidth        ),
    .DataBitsPerMask ( 8                   ),
    .InitFile        ( ""                  )
  ) u_sram (
    .clk_i,
    .rst_ni,
    .tl_a_i (tl_sram_a_h2d),
    .tl_a_o (tl_sram_a_d2h),
    .tl_b_i (tl_sram_b_h2d),
    .tl_b_o (tl_sram_b_d2h)
  );

  sram #(
    .AddrWidth       ( $clog2(CodeRamSize) ),
    .DataWidth       ( BusDataWidth        ),
    .DataBitsPerMask ( 8                   ),
    .InitFile        ( ""                  )
  ) u_code_ram (
    .clk_i,
    .rst_ni,
    .tl_a_i (tl_code_a_h2d),
    .tl_a_o (tl_code_a_d2h),
    .tl_b_i (tl_code_b_h2d),
    .tl_b_o (tl_code_b_d2h)
  );

  /////////////////
  // Peripherals //
  /////////////////

  // RISC-V timer (CLINT), behind a register adapter as in sonata_system.sv.
  logic        timer_req, timer_re, timer_we, timer_rvalid, timer_err;
  logic [3:0]  timer_be;
  logic [31:0] timer_addr, timer_wdata, timer_rdata;

  assign timer_req = timer_re | timer_we;

  tlul_adapter_reg #(
    .RegAw         ( TRegAddrWidth  ),
    .AccessLatency ( TAccessLatency )
  ) timer_device_adapter (
    .clk_i,
    .rst_ni,

    .tl_i         (tl_timer_h2d),
    .tl_o         (tl_timer_d2h),

    .en_ifetch_i  (prim_mubi_pkg::MuBi4False),
    .intg_error_o (),

    .re_o         (timer_re),
    .we_o         (timer_we),
    .addr_o       (timer_addr[TRegAddrWidth-1:0]),
    .wdata_o      (timer_wdata),
    .be_o         (timer_be),
    .busy_i       ('0),
    .rdata_i      (timer_rdata),
    .error_i      (timer_err)
  );

  // Tie off upper bits of address.
  assign timer_addr[31:TRegAddrWidth] = '0;

  rv_timer #(
    .DataWidth    ( BusDataWidth   ),
    .AddressWidth ( 32             ),
    .AccessLatency( TAccessLatency )
  ) u_rv_timer (
    .clk_i,
    .rst_ni,

    .timer_req_i    (timer_req),
    .timer_we_i     (timer_we),
    .timer_be_i     (timer_be),
    .timer_addr_i   (timer_addr),
    .timer_wdata_i  (timer_wdata),
    .timer_rvalid_o (timer_rvalid),
    .timer_rdata_o  (timer_rdata),
    .timer_err_o    (timer_err),
    .timer_intr_o   (timer_irq)
  );

  // Sonata ignores the timer's rvalid too: with AccessLatency 0 the register adapter takes the
  // read data in the request cycle.
  logic unused_timer_rvalid;
  assign unused_timer_rvalid = timer_rvalid;

  rv_plic u_rv_plic (
    .clk_i,
    .rst_ni,

    .irq_o      (external_irq),
    .irq_id_o   (),
    .tl_i       (tl_rv_plic_h2d),
    .tl_o       (tl_rv_plic_d2h),

    .intr_src_i (intr_vector),

    .msip_o     ()
  );

  // UART0. On Sonata it reaches the FTDI pins through the pinmux, whose reset selection is this
  // UART; here it is wired straight to the testbench. Sonata drives an output pin high while its
  // enable is low (out_to_pins_o = data | ~en), so do the same.
  logic uart0_tx, uart0_tx_en;

  uart u_uart0 (
    .clk_i,
    .rst_ni,

    .cio_rx_i             (uart_rx_i),
    .cio_tx_o             (uart0_tx),
    .cio_tx_en_o          (uart0_tx_en),

    .tl_i                 (tl_uart0_h2d),
    .tl_o                 (tl_uart0_d2h),

    // Indexes match the bits in the intr_ registers (sonata_system.sv).
    .intr_tx_watermark_o  (uart_interrupts[0]),
    .intr_tx_empty_o      (uart_interrupts[8]),
    .intr_rx_watermark_o  (uart_interrupts[1]),
    .intr_tx_done_o       (uart_interrupts[2]),
    .intr_rx_overflow_o   (uart_interrupts[3]),
    .intr_rx_frame_err_o  (uart_interrupts[4]),
    .intr_rx_break_err_o  (uart_interrupts[5]),
    .intr_rx_timeout_o    (uart_interrupts[6]),
    .intr_rx_parity_err_o (uart_interrupts[7])
  );

  assign uart_tx_o = uart0_tx | ~uart0_tx_en;

  // Every other data address.
  cheriot_rtos_default_rsp u_default_rsp (
    .clk_i,
    .rst_ni,
    .tl_i (tl_default_h2d),
    .tl_o (tl_default_d2h)
  );
endmodule
