// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

`include "uvm_macros.svh"
`include "dv_macros.svh"
`include "prim_assert.sv"

module core_ibex_tb_top;

  import uvm_pkg::*;
  import core_ibex_test_pkg::*;

  wire clk;

  wire rst_n;

  // test_en_i (scan/test enable) forces ibex_top's clock gates open (prim_clock_gating:
  // en_latch = en_i | test_en_i). Tied to 0 the "test_en" term of every gate was never covered
  // (core_clock_gate_i expression 7/8). Asserted in +test_en_pct=<n> percent of cycles (default 10;
  // 0 = the old constant 0), chosen afresh each cycle. It changes on the falling clock edge, while
  // the gate latch is transparent and clk_o is held low, so the gated clock cannot glitch; with the
  // gate forced open the core runs exactly as with it enabled, so no test behaviour changes.
  // Held at 0 through reset and for TestEnResetHold cycles after it: test_en_i also selects the
  // lockstep shadow core's reset from scan_rst_ni (ibex_lockstep.sv u_prim_rst_shadow_n_mux2),
  // which would release the shadow core early and raise a lockstep alert; once the internal
  // shadow-reset sequence is done both sources are deasserted and the mux makes no difference.
  localparam int unsigned TestEnResetHold = 100;
  logic        test_en = 1'b0;
  int unsigned test_en_pct;
  initial begin
    if (!$value$plusargs("test_en_pct=%d", test_en_pct)) test_en_pct = 10;
    if (test_en_pct > 100) test_en_pct = 100;
    if (test_en_pct != 0) begin
      forever begin
        test_en = 1'b0;
        wait (rst_n === 1'b1);
        repeat (TestEnResetHold) @(negedge clk);
        while (rst_n === 1'b1) begin
          @(negedge clk);
          test_en = (rst_n === 1'b1) && ($urandom_range(99) < test_en_pct);
        end
      end
    end
  end

  clk_rst_if     ibex_clk_if(.clk(clk), .rst_n(rst_n));
  irq_if         irq_vif(.clk(clk));
  ibex_mem_intf  data_mem_vif(.clk(clk));
  ibex_mem_intf  instr_mem_vif(.clk(clk));

  // DMI port of the real debug module. Connected (and published to the UVM config db) only in a DM
  // build -- make ... DM=1, which compiles with +define+IBEX_DM_REAL and ibex_dv_dm.f -- but
  // instantiated in every build so that the test package elaborates the same way in both.
  ibex_dm_dmi_if dm_dmi_if(.clk(clk), .rst_n(rst_n));


  // DUT probe interface
  core_ibex_dut_probe_if dut_if(.clk(clk));

  // Instruction monitor interface
  core_ibex_instr_monitor_if instr_monitor_if(.clk(clk));

  // RVFI interface
  core_ibex_rvfi_if rvfi_if(.clk(clk));

  // CSR access interface
  core_ibex_csr_if csr_if(.clk(clk));

  core_ibex_ifetch_if ifetch_if(.clk(clk));

  core_ibex_ifetch_pmp_if ifetch_pmp_if(.clk(clk));

  // VCS does not support overriding enum and string parameters via command line. Instead, a
  // `define is used that can be set from the command line. If no value has been specified, this
  // gives a default. Other simulators don't take the detour via `define and can override the
  // corresponding parameters directly.
  `ifndef IBEX_CFG_BaseIsa
    `define IBEX_CFG_BaseIsa ibex_pkg::BaseIsaRV32I
  `endif

  `ifndef IBEX_CFG_RV32M
    `define IBEX_CFG_RV32M ibex_pkg::RV32MFast
  `endif

  `ifndef IBEX_CFG_RV32B
    `define IBEX_CFG_RV32B ibex_pkg::RV32BNone
  `endif

  // Matches ibex_top.sv's own default (RV32ZC was never connected to dut
  // before, so every existing build already ran with Zcb+Zcmp enabled via
  // that default -- this fallback must match it, not silently disable them).
  `ifndef IBEX_CFG_RV32ZC
    `define IBEX_CFG_RV32ZC ibex_pkg::RV32ZcaZcbZcmp
  `endif

  `ifndef IBEX_CFG_RegFile
    `define IBEX_CFG_RegFile ibex_pkg::RegFileFF
  `endif

  // The bool/int configuration parameters take their defaults from IBEX_CFG_<param> defines as
  // well (util/ibex_config.py xlm_define_opts, scripts/ibex_cmd.py). Xcelium could set them with
  // -defparam core_ibex_tb_top.<param>, but a -defparam on the top-level module, even an unused
  // one, makes the Jasper UNR App's Xcelium-driven flow (xrun -unr, make formal-cov-unr) discard
  // every coverage item of the snapshot as "not synthesized during UNR elaboration" (bisected
  // 2026-10-07: a bare testbench with the same RTL, parameters, coverage configuration and
  // compile options maps every item). Simulators whose flow overrides the parameters directly
  // (VCS -pvalue+, Verilator -G) still can: these stay parameters.
  `ifndef IBEX_CFG_PMPEnable
    `define IBEX_CFG_PMPEnable 0
  `endif
  `ifndef IBEX_CFG_PMPGranularity
    `define IBEX_CFG_PMPGranularity 0
  `endif
  `ifndef IBEX_CFG_PMPNumRegions
    `define IBEX_CFG_PMPNumRegions 4
  `endif
  `ifndef IBEX_CFG_MHPMCounterNum
    `define IBEX_CFG_MHPMCounterNum 0
  `endif
  `ifndef IBEX_CFG_MHPMCounterWidth
    `define IBEX_CFG_MHPMCounterWidth 40
  `endif
  `ifndef IBEX_CFG_RV32E
    `define IBEX_CFG_RV32E 0
  `endif
  `ifndef IBEX_CFG_BranchTargetALU
    `define IBEX_CFG_BranchTargetALU 0
  `endif
  `ifndef IBEX_CFG_WritebackStage
    `define IBEX_CFG_WritebackStage 0
  `endif
  `ifndef IBEX_CFG_ICache
    `define IBEX_CFG_ICache 0
  `endif
  `ifndef IBEX_CFG_ICacheECC
    `define IBEX_CFG_ICacheECC 0
  `endif
  `ifndef IBEX_CFG_BranchPredictor
    `define IBEX_CFG_BranchPredictor 0
  `endif
  `ifndef IBEX_CFG_SecureIbex
    `define IBEX_CFG_SecureIbex 0
  `endif
  `ifndef IBEX_CFG_ICacheScramble
    `define IBEX_CFG_ICacheScramble 0
  `endif
  `ifndef IBEX_CFG_DbgTriggerEn
    `define IBEX_CFG_DbgTriggerEn 0
  `endif

  // Ibex Parameters
  parameter ibex_pkg::base_isa_e BaseIsa  = `IBEX_CFG_BaseIsa;
  parameter bit          PMPEnable        = `IBEX_CFG_PMPEnable;
  parameter int unsigned PMPGranularity   = `IBEX_CFG_PMPGranularity;
  parameter int unsigned PMPNumRegions    = `IBEX_CFG_PMPNumRegions;
  parameter int unsigned MHPMCounterNum   = `IBEX_CFG_MHPMCounterNum;
  parameter int unsigned MHPMCounterWidth = `IBEX_CFG_MHPMCounterWidth;
  parameter bit RV32E                     = `IBEX_CFG_RV32E;
  parameter ibex_pkg::rv32m_e RV32M       = `IBEX_CFG_RV32M;
  parameter ibex_pkg::rv32b_e RV32B       = `IBEX_CFG_RV32B;
  parameter ibex_pkg::rv32zc_e RV32ZC     = `IBEX_CFG_RV32ZC;
  parameter ibex_pkg::regfile_e RegFile   = `IBEX_CFG_RegFile;
  parameter bit BranchTargetALU           = `IBEX_CFG_BranchTargetALU;
  parameter bit WritebackStage            = `IBEX_CFG_WritebackStage;
  parameter bit ICache                    = `IBEX_CFG_ICache;
  parameter bit ICacheECC                 = `IBEX_CFG_ICacheECC;
  parameter bit ICacheTweakInfection      = 1'b0;
  parameter bit BranchPredictor           = `IBEX_CFG_BranchPredictor;
  parameter bit SecureIbex                = `IBEX_CFG_SecureIbex;
  parameter int unsigned LockstepOffset   = 1;
  parameter bit ICacheScramble            = `IBEX_CFG_ICacheScramble;
  parameter bit DbgTriggerEn              = `IBEX_CFG_DbgTriggerEn;
  parameter int unsigned DmBaseAddr       = 32'h`DM_ADDR;
  parameter int unsigned DmAddrMask       = 32'h`DM_ADDR_MASK;
  parameter int unsigned DmHaltAddr       = 32'h`DEBUG_MODE_HALT_ADDR;
  parameter int unsigned DmExceptionAddr  = 32'h`DEBUG_MODE_EXCEPTION_ADDR;
  // Ibex Inputs
  parameter int unsigned BootAddr         = 32'h`BOOT_ADDR; // ResetVec = BootAddr/256b + 0x80

  // Scrambling interface instantiation
  logic [ibex_pkg::SCRAMBLE_KEY_W-1:0]   scramble_key;
  logic [ibex_pkg::SCRAMBLE_NONCE_W-1:0] scramble_nonce;

  // CHERIoT capability tags on the data bus. The UVM memory agent models bytes
  // only, so the tag is held alongside it by ibex_tag_mem (see below). These
  // were previously 1'b0 / unconnected, which silently untagged every CLC.
  logic data_wtag;
  logic data_rtag;

  // TRVK revocation-bitmap port. Previously tied off, which only worked while
  // data_rtag was constant zero and TRVK therefore never had a lookup to do.
  logic        revbm_req;
  logic        revbm_gnt;
  logic        revbm_rvalid;
  logic [31:0] revbm_addr;
  logic [31:0] revbm_rdata;
  logic [6:0]  revbm_rdata_intg;
  // Driven by ibex_revbm_responder from ibex_revbm_pkg (+revbm_* plusargs). Both were tied to
  // 0: heap_base 0 meant only base-0 capabilities were ever looked up, and no bitmap error.
  logic        revbm_err;
  logic [31:0] trvk_heap_base;
  logic        revbm_inj_err;   // this cycle's bitmap response carries an injected error

  // Initiate push pull interface for connection between Ibex and a scrambling key provider.
  push_pull_if #(
    .DeviceDataWidth(ibex_pkg::SCRAMBLE_NONCE_W + ibex_pkg::SCRAMBLE_KEY_W)
  ) scrambling_key_if (
    .clk(clk),
    .rst_n(rst_n)
  );

  // key and nonce are driven by push_pull Device interface
  assign {scramble_key, scramble_nonce} = scrambling_key_if.d_data;

  // hart_id_i / boot_addr_i carry their configured values only while rst_n is high, and the
  // bitwise complement while it is low, so their toggle coverage measures the ports rather
  // than the tie-off. Nothing samples them during reset: the core reads boot_addr_i after
  // reset release (RESET/BOOT_SET fetch address, mtvec init) and at any time afterwards, and
  // hart_id_i continuously through mhartid. clk_rst_if releases reset just after a clock edge,
  // so the first sample is a full period later. Release toggles every bit one way; reset
  // assertion mid-run (riscv_reset_test) and +hart_id=FFFFFFFF (ibex_mhartid_ones) give the
  // other. boot_addr_i[7:0] stay 0 (IbexBootAddrUnaligned) and are waived.
  // +hart_id=<hex>: configured hart id, default 0.
  logic [31:0] hart_id = 32'b0;
  initial void'($value$plusargs("hart_id=%h", hart_id));

  // The first reset pulse, for tools that start from a simulated state (superlint unr-cfg-reset
  // loads the design state from waves.shm at a time inside it).
  initial begin
    @(negedge rst_n);
    $display("TB_RESET: rst_n low at %0d ps", $rtoi($realtime / 1ps));
    @(posedge rst_n);
    $display("TB_RESET: rst_n high at %0d ps", $rtoi($realtime / 1ps));
  end
  wire  [31:0] hart_id_drv   = (rst_n === 1'b1) ? hart_id  : ~hart_id;
  wire  [31:0] boot_addr_drv = (rst_n === 1'b1) ? BootAddr : {~BootAddr[31:8], 8'h00};

`ifdef IBEX_DM_REAL
  // Core side of ibex_dm_obi_mux (DM build only, see the debug module section below).
  logic        dm_core_instr_req,  dm_core_instr_gnt,  dm_core_instr_rvalid, dm_core_instr_err;
  logic [31:0] dm_core_instr_rdata;
  logic [6:0]  dm_core_instr_rintg;
  logic        dm_core_data_req,   dm_core_data_gnt,   dm_core_data_rvalid,  dm_core_data_err;
  logic [31:0] dm_core_data_rdata;
  logic [6:0]  dm_core_data_rintg;
  logic        dm_core_data_rtag;
  logic        dm_debug_req;
`endif

  ibex_top_tracing #(
    .BaseIsa              (BaseIsa             ),
    .PMPEnable            (PMPEnable           ),
    .PMPGranularity       (PMPGranularity      ),
    .PMPNumRegions        (PMPNumRegions       ),
    .MHPMCounterNum       (MHPMCounterNum      ),
    .MHPMCounterWidth     (MHPMCounterWidth    ),
    .RV32E                (RV32E               ),
    .RV32M                (RV32M               ),
    .RV32B                (RV32B               ),
    .RV32ZC               (RV32ZC              ),
    .RegFile              (RegFile             ),
    .BranchTargetALU      (BranchTargetALU     ),
    .WritebackStage       (WritebackStage      ),
    .ICache               (ICache              ),
    .ICacheECC            (ICacheECC           ),
    .ICacheTweakInfection (ICacheTweakInfection),
    .SecureIbex           (SecureIbex          ),
    .LockstepOffset       (LockstepOffset      ),
    .ICacheScramble       (ICacheScramble      ),
    .BranchPredictor      (BranchPredictor     ),
    .DbgTriggerEn         (DbgTriggerEn        ),
    .DmBaseAddr           (DmBaseAddr          ),
    .DmAddrMask           (DmAddrMask          ),
    .DmHaltAddr           (DmHaltAddr          ),
    .DmExceptionAddr      (DmExceptionAddr     ),
    // The ibex_top defaults, stated so the responder and the CHERIoT-Sail feed (both built from
    // ibex_revbm_pkg) cannot drift from the bitmap geometry TRVK is built with.
    .CheriotRevBitmapAddrWidth (ibex_revbm_pkg::RevBitmapAddrWidth),
    .CheriotRevBitmapBaseAddr  (ibex_revbm_pkg::RevBitmapBaseAddr )

  ) dut (
    .clk_i                     (clk                        ),
    .rst_ni                    (rst_n                      ),

    .test_en_i                 (test_en                    ),
    .scan_rst_ni               (1'b1                       ),
    .ram_cfg_icache_tag_i      ('{default: prim_ram_1p_pkg::RAM_1P_CFG_REQ_DEFAULT}),
    .ram_cfg_icache_tag_o      (                           ),
    .ram_cfg_icache_data_i     ('{default: prim_ram_1p_pkg::RAM_1P_CFG_REQ_DEFAULT}),
    .ram_cfg_icache_data_o     (                           ),

    .hart_id_i                 (hart_id_drv                ),
    .boot_addr_i               (boot_addr_drv              ),
    .trvk_heap_base_addr_i     (trvk_heap_base             ),

`ifdef IBEX_DM_REAL
    // DM build: the request/response lines go through ibex_dm_obi_mux (below), which sends
    // accesses to the debug module's window to dm_top and the rest to the memory agents.
    .instr_req_o               (dm_core_instr_req          ),
    .instr_gnt_i               (dm_core_instr_gnt          ),
    .instr_rvalid_i            (dm_core_instr_rvalid       ),
    .instr_addr_o              (instr_mem_vif.addr         ),
    .instr_rdata_i             (dm_core_instr_rdata        ),
    .instr_rdata_intg_i        (dm_core_instr_rintg        ),
    .instr_err_i               (dm_core_instr_err          ),

    .data_req_o                (dm_core_data_req           ),
    .data_gnt_i                (dm_core_data_gnt           ),
    .data_rvalid_i             (dm_core_data_rvalid        ),
    .data_addr_o               (data_mem_vif.addr          ),
    .data_we_o                 (data_mem_vif.we            ),
    .data_be_o                 (data_mem_vif.be            ),
    .data_rdata_i              (dm_core_data_rdata         ),
    .data_rdata_intg_i         (dm_core_data_rintg         ),
    .data_tag_i                (dm_core_data_rtag          ),
    .data_wdata_o              (data_mem_vif.wdata         ),
    .data_wdata_intg_o         (data_mem_vif.wintg         ),
    .data_tag_o                (data_wtag                  ),
    .data_err_i                (dm_core_data_err           ),
`else
    .instr_req_o               (instr_mem_vif.request      ),
    .instr_gnt_i               (instr_mem_vif.grant        ),
    .instr_rvalid_i            (instr_mem_vif.rvalid       ),
    .instr_addr_o              (instr_mem_vif.addr         ),
    .instr_rdata_i             (instr_mem_vif.rdata        ),
    .instr_rdata_intg_i        (instr_mem_vif.rintg        ),
    .instr_err_i               (instr_mem_vif.error        ),

    .data_req_o                (data_mem_vif.request       ),
    .data_gnt_i                (data_mem_vif.grant         ),
    .data_rvalid_i             (data_mem_vif.rvalid        ),
    .data_addr_o               (data_mem_vif.addr          ),
    .data_we_o                 (data_mem_vif.we            ),
    .data_be_o                 (data_mem_vif.be            ),
    .data_rdata_i              (data_mem_vif.rdata         ),
    .data_rdata_intg_i         (data_mem_vif.rintg         ),
    .data_tag_i                (data_rtag                  ),
    .data_wdata_o              (data_mem_vif.wdata         ),
    .data_wdata_intg_o         (data_mem_vif.wintg         ),
    .data_tag_o                (data_wtag                  ),
    .data_err_i                (data_mem_vif.error         ),
`endif

    .trvk_revbm_req_o          (revbm_req                  ),
    .trvk_revbm_gnt_i          (revbm_gnt                  ),
    .trvk_revbm_rvalid_i       (revbm_rvalid               ),
    .trvk_revbm_addr_o         (revbm_addr                 ),
    .trvk_revbm_rdata_i        (revbm_rdata                ),
    .trvk_revbm_rdata_intg_i   (revbm_rdata_intg           ),
    .trvk_revbm_err_i          (revbm_err                  ),

    .irq_software_i            (irq_vif.irq_software       ),
    .irq_timer_i               (irq_vif.irq_timer          ),
    .irq_external_i            (irq_vif.irq_external       ),
    .irq_fast_i                (irq_vif.irq_fast           ),
    .irq_nm_i                  (irq_vif.irq_nm             ),

    .scramble_key_valid_i      (scrambling_key_if.ack      ),
    .scramble_key_i            (scramble_key               ),
    .scramble_nonce_i          (scramble_nonce             ),
    .scramble_req_o            (scrambling_key_if.req      ),

`ifdef IBEX_DM_REAL
    .debug_req_i               (dm_debug_req               ),
`else
    .debug_req_i               (dut_if.debug_req           ),
`endif
    .crash_dump_o              (                           ),
    .double_fault_seen_o       (dut_if.double_fault_seen   ),

    .cheriot_enable_i          (dut_if.cheriot_enable      ),

    .fetch_enable_i            (dut_if.fetch_enable        ),
    .mcounteren_writable_i     (dut_if.mcounteren_writable ),
    .alert_minor_o             (dut_if.alert_minor         ),
    .alert_major_internal_o    (dut_if.alert_major_internal),
    .alert_major_bus_o         (dut_if.alert_major_bus     ),
    .core_sleep_o              (dut_if.core_sleep          ),

    .lockstep_cmp_en_o         (                           ),
    .data_req_shadow_o         (                           ),
    .data_we_shadow_o          (                           ),
    .data_be_shadow_o          (                           ),
    .data_addr_shadow_o        (                           ),
    .data_wdata_shadow_o       (                           ),
    .data_wdata_intg_shadow_o  (                           ),

    .instr_req_shadow_o        (                           ),
    .instr_addr_shadow_o       (                           )
  );

  // Capability tag storage for the data bus. The UVM memory agent owns the data
  // and the request/response protocol; this only holds the one bit per 8-byte
  // granule that the agent has no concept of, returned in step with rvalid.
  ibex_tag_mem u_data_tag_mem (
    .clk_i    (clk                  ),
    .rst_ni   (rst_n                ),
    .req_i    (data_mem_vif.request ),
    .gnt_i    (data_mem_vif.grant   ),
    .we_i     (data_mem_vif.we      ),
    .be_i     (data_mem_vif.be      ),
    .addr_i   (data_mem_vif.addr    ),
    .wtag_i   (data_wtag            ),
    .rvalid_i (data_mem_vif.rvalid  ),
    .spurious_response_i (data_mem_vif.spurious_response),
    .rtag_o   (data_rtag            )
  );

`ifdef IBEX_DM_REAL
  /////////////////////////////////////////////////////////////////////////////////////////////////
  // Real debug module (DM build: make uvm-test-xlm ... DM=1)
  /////////////////////////////////////////////////////////////////////////////////////////////////
  // vendor/pulp_riscv_dbg dm_top with the CHERIoT patches (cheriot_enable_i selects the CHERIoT
  // debug ROM, CSpecialRW scratch handling and 64-bit capability abstract register access). It
  // replaces the riscv-dv debug flow of the normal build, where the TB's debug agent drives
  // debug_req_i and the program carries its own debug section at DEBUG_MODE_HALT_ADDR = BOOT_ADDR.
  // The test (core_ibex_dm_test) drives the DMI port directly through dm_dmi_if; there is no JTAG
  // DTM.
  //
  // Address map. DM window [DmBaseAddr, DmBaseAddr + DmAddrMask] = [0x1A11_0000, 0x1A11_0FFF]
  // (`DM_ADDR / `DM_ADDR_MASK, the window the core's PMP exempts in debug mode). Offsets inside it
  // (dm_mem.sv): 0x100/0x108/0x110/0x118 halted/going/resuming/exception, 0x300 whereto, 0x338
  // abstract command, 0x360 program buffer, 0x380 data0/data1, 0x400 hart flags, 0x800 debug ROM
  // = DmHaltAddr, 0x808 resume, 0x810 = DmExceptionAddr. Everything else stays with the memory
  // agents: test programs at 0x8000_0000 (riscv-dv, directed_tests/link.ld), signature words at
  // 0x8fff_fff8/0x8fff_fffc; the revocation bitmap has its own port (ibex_revbm_responder).
  //
  // Bus: ibex_dm_obi_mux decodes both core ports (the core fetches the ROM, whereto, abstract
  // commands and program buffer, and loads/stores flags and data0/data1) and arbitrates the
  // single-ported slave; see that module for the ordering and integrity rules.
  //
  // cheriot_enable_i: the same pin the core gets (dut_if.cheriot_enable), translated from the
  // core's encoding (ibex_pkg::IbexMuBiOn = 4'b0101) to prim_mubi_pkg (MuBi4True = 4'h6). Only
  // exactly IbexMuBiOn, which is what the core itself treats as On, selects CHERIoT mode. Same
  // clock, so no synchroniser (OpenTitan's rv_dm has one because the pin crosses into its domain).
  //
  // Not connected: the system bus access (SBA) master is tied off (no grant, no response), so the
  // DM reports SBA accesses as never completing; nothing here uses SBA. ndmreset_o is not routed
  // to the core: the bench owns the reset (clk_rst_if, base test reload on reset), and a DM-driven
  // reset would bypass that. DmNdmresetNotRequested fails a test that sets dmcontrol.ndmreset
  // rather than letting it hang. dmi_rst_ni and rst_ni share the bench reset.

  // dm::hartinfo_t as OpenTitan's rv_dm builds it: nscratch = 2 (the generalized ROM, DM not at
  // address 0), dataaccess = 1 (data registers memory mapped), datasize = dm::DataCount = 2,
  // dataaddr = dm::DataAddr = 0x380. Spelled out because this file is compiled before dm_pkg.
  localparam logic [31:0] DmHartInfo = {8'h0,    // zero1
                                        4'd2,    // nscratch
                                        3'b0,    // zero0
                                        1'b1,    // dataaccess
                                        4'd2,    // datasize
                                        12'h380  // dataaddr
                                       };

  // The core's debug entry points must be the ROM's: dm::HaltAddress = 0x800 and
  // dm::ExceptionAddress = 0x810 inside the window (compile_tb.py sets the defines for DM=1).
  initial begin
    if (DmHaltAddr != DmBaseAddr + 32'h800 || DmExceptionAddr != DmBaseAddr + 32'h810) begin
      $fatal(1, "DM build: DmHaltAddr 0x%08x / DmExceptionAddr 0x%08x are not the debug ROM's entry points 0x%08x / 0x%08x",
             DmHaltAddr, DmExceptionAddr, DmBaseAddr + 32'h800, DmBaseAddr + 32'h810);
    end
  end

  logic                  dm_req, dm_we, dm_err;
  logic [31:0]           dm_addr, dm_wdata, dm_rdata;
  logic [3:0]            dm_be;
  logic                  dm_ndmreset, dm_dmactive;
  logic                  dm_data0_wr, dm_data0_wtag;
  logic [33:0]           dm_dmi_resp;
  prim_mubi_pkg::mubi4_t dm_cheriot_enable;

  assign dm_cheriot_enable = (dut_if.cheriot_enable == ibex_pkg::IbexMuBiOn) ?
                             prim_mubi_pkg::MuBi4True : prim_mubi_pkg::MuBi4False;

  dm_top #(
    .NrHarts       (1         ),
    .BusWidth      (32        ),
    .DmBaseAddress (DmBaseAddr)
  ) u_dm_top (
    .clk_i                (clk                  ),
    .rst_ni               (rst_n                ),
    .next_dm_addr_i       (32'h0                ),
    .cheriot_enable_i     (dm_cheriot_enable    ),
    .testmode_i           (1'b0                 ),
    .ndmreset_o           (dm_ndmreset          ),
    .ndmreset_ack_i       (1'b0                 ),
    .dmactive_o           (dm_dmactive          ),
    .debug_req_o          (dm_debug_req         ),
    .unavailable_i        (1'b0                 ),
    .hartinfo_i           (DmHartInfo           ),

    .slave_req_i          (dm_req               ),
    .slave_we_i           (dm_we                ),
    .slave_addr_i         (dm_addr              ),
    .slave_be_i           (dm_be                ),
    .slave_wdata_i        (dm_wdata             ),
    .slave_rdata_o        (dm_rdata             ),
    .slave_err_o          (dm_err               ),

    .master_req_o         (                     ),
    .master_add_o         (                     ),
    .master_we_o          (                     ),
    .master_wdata_o       (                     ),
    .master_be_o          (                     ),
    .master_gnt_i         (1'b0                 ),
    .master_r_valid_i     (1'b0                 ),
    .master_r_err_i       (1'b0                 ),
    .master_r_other_err_i (1'b0                 ),
    .master_r_rdata_i     (32'h0                ),

    .dmi_rst_ni           (rst_n                ),
    .dmi_req_valid_i      (dm_dmi_if.req_valid  ),
    .dmi_req_ready_o      (dm_dmi_if.req_ready  ),
    .dmi_req_i            ({dm_dmi_if.req_addr, dm_dmi_if.req_op, dm_dmi_if.req_data}),
    .dmi_resp_valid_o     (dm_dmi_if.resp_valid ),
    .dmi_resp_ready_i     (dm_dmi_if.resp_ready ),
    .dmi_resp_o           (dm_dmi_resp          )
  );

  assign {dm_dmi_if.resp_data, dm_dmi_if.resp_resp} = dm_dmi_resp;

  ibex_dm_obi_mux #(
    .DmBaseAddr (DmBaseAddr),
    .DmAddrMask (DmAddrMask)
  ) u_dm_obi_mux (
    .clk_i                (clk                            ),
    .rst_ni               (rst_n                          ),

    .core_instr_req_i     (dm_core_instr_req              ),
    .core_instr_addr_i    (instr_mem_vif.addr             ),
    .core_instr_gnt_o     (dm_core_instr_gnt              ),
    .core_instr_rvalid_o  (dm_core_instr_rvalid           ),
    .core_instr_rdata_o   (dm_core_instr_rdata            ),
    .core_instr_rintg_o   (dm_core_instr_rintg            ),
    .core_instr_err_o     (dm_core_instr_err              ),

    .mem_instr_req_o      (instr_mem_vif.request          ),
    .mem_instr_gnt_i      (instr_mem_vif.grant            ),
    .mem_instr_rvalid_i   (instr_mem_vif.rvalid           ),
    .mem_instr_rdata_i    (instr_mem_vif.rdata            ),
    .mem_instr_rintg_i    (instr_mem_vif.rintg            ),
    .mem_instr_err_i      (instr_mem_vif.error            ),
    .mem_instr_spurious_i (instr_mem_vif.spurious_response),

    .core_data_req_i      (dm_core_data_req               ),
    .core_data_addr_i     (data_mem_vif.addr              ),
    .core_data_we_i       (data_mem_vif.we                ),
    .core_data_be_i       (data_mem_vif.be                ),
    .core_data_wdata_i    (data_mem_vif.wdata             ),
    .core_data_wtag_i     (data_wtag                      ),
    .core_data_gnt_o      (dm_core_data_gnt               ),
    .core_data_rvalid_o   (dm_core_data_rvalid            ),
    .core_data_rdata_o    (dm_core_data_rdata             ),
    .core_data_rintg_o    (dm_core_data_rintg             ),
    .core_data_err_o      (dm_core_data_err               ),
    .core_data_rtag_o     (dm_core_data_rtag              ),

    .mem_data_req_o       (data_mem_vif.request           ),
    .mem_data_gnt_i       (data_mem_vif.grant             ),
    .mem_data_rvalid_i    (data_mem_vif.rvalid            ),
    .mem_data_rdata_i     (data_mem_vif.rdata             ),
    .mem_data_rintg_i     (data_mem_vif.rintg             ),
    .mem_data_err_i       (data_mem_vif.error             ),
    .mem_data_spurious_i  (data_mem_vif.spurious_response ),
    .mem_data_rtag_i      (data_rtag                      ),

    .dm_req_o             (dm_req                         ),
    .dm_we_o              (dm_we                          ),
    .dm_addr_o            (dm_addr                        ),
    .dm_be_o              (dm_be                          ),
    .dm_wdata_o           (dm_wdata                       ),
    .dm_rdata_i           (dm_rdata                       ),
    .dm_err_i             (dm_err                         ),

    .dm_data0_wr_o        (dm_data0_wr                    ),
    .dm_data0_wtag_o      (dm_data0_wtag                  )
  );

  // White-box view for the test: stores the core made to data0 and the tag of the latest one.
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dm_dmi_if.data0_wcount <= 0;
      dm_dmi_if.data0_wtag   <= 1'b0;
    end else if (dm_data0_wr) begin
      dm_dmi_if.data0_wcount <= dm_dmi_if.data0_wcount + 1;
      dm_dmi_if.data0_wtag   <= dm_data0_wtag;
    end
  end

  // ndmreset_o is not routed (see above): a test must not request it.
  `ASSERT(DmNdmresetNotRequested, !dm_ndmreset, clk, !rst_n)
  // In a DM build the TB debug agent (dut_if.debug_req) is disconnected from the core, so a test
  // that drives it (riscv-dv debug tests, +enable_debug_seq) would silently run without debug
  // requests. It belongs in the normal build.
  `ASSERT(DmBuildNoTbDebugReq, !dut_if.debug_req, clk, !rst_n)
`endif

  // Revocation-bitmap lookups and the TRVK heap base, from ibex_revbm_pkg. Default
  // (+revbm_mode=off) answers "not revoked" for every lookup; +revbm_mode=random|range revokes
  // granules and can inject bitmap errors. The CHERIoT-Sail cosim is given the same bitmap (see
  // ibex_revbm_pkg.sv), so revoked CLCs are checked, not waived.
  ibex_revbm_responder #(
    .BitmapAddrWidth (ibex_revbm_pkg::RevBitmapAddrWidth),
    .BitmapBaseAddr  (ibex_revbm_pkg::RevBitmapBaseAddr ),
    .MemECC          (SecureIbex                        )   // ibex_top: MemECC = SecureIbex
  ) u_revbm_responder (
    .clk_i              (clk             ),
    .rst_ni             (rst_n           ),
    .revbm_req_i        (revbm_req       ),
    .revbm_gnt_o        (revbm_gnt       ),
    .revbm_rvalid_o     (revbm_rvalid    ),
    .revbm_addr_i       (revbm_addr      ),
    .revbm_rdata_o      (revbm_rdata     ),
    .revbm_rdata_intg_o (revbm_rdata_intg),
    .revbm_err_o        (revbm_err       ),
    .heap_base_o        (trvk_heap_base  ),
    .inj_err_o          (revbm_inj_err   )
  );

  // An injected bitmap error must raise alert_major_bus_o in the same cycle (ibex_top.sv ORs
  // trvk_revbm_device_error / trvk_revbm_data_intg_error into it). NoAlertsTriggered below
  // tolerates the bus alert in exactly these cycles and no others.
  `ASSERT(RevbmInjectedErrRaisesBusAlert, revbm_inj_err |-> dut_if.alert_major_bus, clk, !rst_n)

  // CHERIoT-Sail keeps its revocation bits in its own RAM at ibex_revbm_pkg::SailShadowBase
  // (cheri_mem.sail mem_read_cap_revoked). A program store there changes the model's bitmap but
  // not the responder's, so a later CLC of a capability based in the matching granule would
  // mismatch on cd_wtag for a reason that is not an RTL bug. Report it where it happens. The
  // window covers every base the model can revoke in the 256 MiB RAM the scoreboard maps.
  always_ff @(posedge clk) begin
    if (rst_n && data_mem_vif.request && data_mem_vif.grant && data_mem_vif.we &&
        data_mem_vif.addr >= ibex_revbm_pkg::SailShadowBase &&
        data_mem_vif.addr <  ibex_revbm_pkg::SailShadowBase + (32'h1000_0000 >> 6)) begin
      $display("[REVBM] WARNING %0t: store to 0x%08x lands in CHERIoT-Sail's revocation shadow [0x%08x, +0x%0x): a cd_wtag mismatch on a later CLC may come from this store, not from the RTL",
               $time, data_mem_vif.addr, ibex_revbm_pkg::SailShadowBase, 32'h1000_0000 >> 6);
    end
  end

  // Debug instrumentation for the capability round-trip: TRVK issues a
  // revocation-bitmap lookup for one capability load and not another, so this
  // prints the six terms of revbm_req_required to identify the differing one,
  // plus the tag TRVK actually emits upstream.
  //
  // Off unless +trvk_probe=1. It fires on every upstream response, which on a
  // long random test is most cycles -- these prints were a large part of why the
  // 2026-09-23 regression's timeout runs produced 135 MB rtl_sim.log files.
  //
  // The format string must be ONE string literal. It was previously a
  // concatenation, {"...", "..."}, and $display only treats its first argument
  // as a format string when that argument is a literal -- given an expression it
  // printed the specifiers verbatim and appended the values, e.g.
  //   [TRVK] %0t up_tag=%b | seal=%b ... -> req_reqd=%b    2639356000011110
  if (BaseIsa == ibex_pkg::BaseIsaRV32IorCHERIoT) begin : g_trvk_probe
    bit trvk_probe_en;
    initial trvk_probe_en = $test$plusargs("trvk_probe");
    always_ff @(posedge clk) begin
      if (trvk_probe_en && rst_n && core_ibex_tb_top.dut.u_ibex_top.gen_cheriot_trvk.i_ibex_trvk.upstream_rvalid_o) begin
        $display("[TRVK] %0t up_tag=%b | seal=%b ptr_vld=%b rsp_tag=%b rsp_vld=%b mis=%b mis_vld=%b oor=%b -> req_reqd=%b",
          $time,
          core_ibex_tb_top.dut.u_ibex_top.gen_cheriot_trvk.i_ibex_trvk.upstream_tag_o,
          core_ibex_tb_top.dut.u_ibex_top.gen_cheriot_trvk.i_ibex_trvk.is_sealing_cap,
          core_ibex_tb_top.dut.u_ibex_top.gen_cheriot_trvk.i_ibex_trvk.ptr_storage_valid_q,
          core_ibex_tb_top.dut.u_ibex_top.gen_cheriot_trvk.i_ibex_trvk.downstream_rsp_out.tag,
          core_ibex_tb_top.dut.u_ibex_top.gen_cheriot_trvk.i_ibex_trvk.downstream_rsp_out_valid,
          core_ibex_tb_top.dut.u_ibex_top.gen_cheriot_trvk.i_ibex_trvk.misalign_flag_out,
          core_ibex_tb_top.dut.u_ibex_top.gen_cheriot_trvk.i_ibex_trvk.misalign_flag_out_valid,
          core_ibex_tb_top.dut.u_ibex_top.gen_cheriot_trvk.i_ibex_trvk.revbm_out_of_range,
          core_ibex_tb_top.dut.u_ibex_top.gen_cheriot_trvk.i_ibex_trvk.revbm_req_required);
      end
    end
  end

  `define IBEX_RF_PATH core_ibex_tb_top.dut.u_ibex_top.gen_regfile_ff.register_file_i

  // We should never see any alerts triggered in normal testing. The one exception is a bus alert
  // in a cycle where ibex_revbm_responder injected a bitmap error on purpose (revbm_inj_err is
  // constant 0 unless +revbm_err_pct / +revbm_err_list are given); any other bus alert, even
  // during such a run, still fails here.
  `ASSERT(NoAlertsTriggered,
    !dut_if.alert_minor && !dut_if.alert_major_internal &&
    (!dut_if.alert_major_bus || revbm_inj_err), clk, !rst_n)
  `DV_ASSERT_CTRL("tb_no_alerts_triggered", core_ibex_tb_top.NoAlertsTriggered)

  // OBI: a raised d-side request stays raised until it is granted (REQ_BCK_06). The core may not
  // drop data_req_o before data_gnt_i, whatever happens to cheriot_enable_i meanwhile.
  `ASSERT(DataReqHeldUntilGnt, data_mem_vif.request && !data_mem_vif.grant |=> data_mem_vif.request,
    clk, !rst_n)

  `DV_ASSERT_CTRL("tb_no_spurious_response",
    core_ibex_tb_top.dut.u_ibex_top.u_ibex_core.NoMemResponseWithoutPendingAccess)
  `DV_ASSERT_CTRL("tb_no_spurious_response",
    core_ibex_tb_top.dut.u_ibex_top.MaxOutstandingDSideAccessesCorrect)
  `DV_ASSERT_CTRL("tb_no_spurious_response",
    core_ibex_tb_top.dut.u_ibex_top.PendingAccessTrackingCorrect)

  if (SecureIbex) begin : g_lockstep_assert_ctrl
    `define IBEX_LOCKSTEP_PATH core_ibex_tb_top.dut.u_ibex_top.gen_lockstep.u_ibex_lockstep
    `DV_ASSERT_CTRL("tb_no_spurious_response",
      `IBEX_LOCKSTEP_PATH.u_shadow_core.NoMemResponseWithoutPendingAccess)
  end

  // CheriotEnableOneWaySwitch (ibex_core.sv) states the pin contract: once On, cheriot_enable_i stays
  // On until reset. cheriot_enable_on_off breaks that contract on purpose to check the core's reaction
  // (+cheriot_disable_on_write, core_ibex_base_test::watch_cheriot_disable_trigger), so it turns the
  // assertion off for its run; every other test keeps it.
  if (BaseIsa == ibex_pkg::BaseIsaRV32IorCHERIoT) begin : g_cheriot_enable_assert_ctrl
    `DV_ASSERT_CTRL("tb_cheriot_enable_one_way",
      core_ibex_tb_top.dut.u_ibex_top.u_ibex_core.gen_cheriot_enable_check.CheriotEnableOneWaySwitch)
    if (SecureIbex) begin : g_lockstep
      `DV_ASSERT_CTRL("tb_cheriot_enable_one_way",
        `IBEX_LOCKSTEP_PATH.u_shadow_core.gen_cheriot_enable_check.CheriotEnableOneWaySwitch)
    end
  end

  if (BaseIsa == ibex_pkg::BaseIsaRV32IorCHERIoT) begin : g_trvk_assert_ctrl
    // Disable TRVK's alignment FIFO assertion alongside the other spurious response checks.
    `DV_ASSERT_CTRL("tb_no_spurious_response",
      core_ibex_tb_top.dut.u_ibex_top.gen_cheriot_trvk.i_ibex_trvk.AlignValidOnRsp_A)
    // DsRspFifoNoOverflow_A is `downstream_rvalid_i |-> downstream_rsp_wready`
    // (ibex_trvk.sv:411) -- a response may only arrive when the store has a slot for
    // it. Spurious injection delivers downstream_rvalid_i with no matching request, so
    // no slot was ever reserved and wready is low: the assertion cannot hold and says
    // nothing about the RTL. It sits directly beside AlignValidOnRsp_A above and fails
    // for the same reason; it was simply missed when that one was added, and accounted
    // for 9 of the 57 failures in the 2026-09-23 regression. The give-away in the log is
    // "[TAGMEM] <t> RSP is_read=0 rtag=0 depth=0" -- depth 0 means nothing outstanding.
    `DV_ASSERT_CTRL("tb_no_spurious_response",
      core_ibex_tb_top.dut.u_ibex_top.gen_cheriot_trvk.i_ibex_trvk.DsRspFifoNoOverflow_A)
  end

`ifndef DV_FCOV_DISABLE
  assign dut.u_ibex_top.u_ibex_core.u_fcov_bind.rf_glitch_err =
    dut.u_ibex_top.alert_major_internal_o;
  assign dut.u_ibex_top.u_ibex_core.u_fcov_bind.lockstep_glitch_err =
    dut.u_ibex_top.lockstep_alert_major_internal;
  if (SecureIbex) begin : g_fcov_rf_ecc_shdw
    // Register-file ECC runs only in the lockstep shadow core (ibex_top: RegFileECC = 0 for the
    // main core), where fcov is off: hand its detection to the main core's fcov interface
    assign dut.u_ibex_top.u_ibex_core.u_fcov_bind.rf_ecc_err_a_shdw =
      dut.u_ibex_top.gen_lockstep.u_ibex_lockstep.u_shadow_core.gen_regfile_ecc.rf_ecc_err_a_id &
      dut.u_ibex_top.gen_lockstep.u_ibex_lockstep.u_shadow_core.instr_valid_id;
    assign dut.u_ibex_top.u_ibex_core.u_fcov_bind.rf_ecc_err_b_shdw =
      dut.u_ibex_top.gen_lockstep.u_ibex_lockstep.u_shadow_core.gen_regfile_ecc.rf_ecc_err_b_id &
      dut.u_ibex_top.gen_lockstep.u_ibex_lockstep.u_shadow_core.instr_valid_id;
  end else begin : g_no_fcov_rf_ecc_shdw
    assign dut.u_ibex_top.u_ibex_core.u_fcov_bind.rf_ecc_err_a_shdw = 1'b0;
    assign dut.u_ibex_top.u_ibex_core.u_fcov_bind.rf_ecc_err_b_shdw = 1'b0;
  end
`endif

  // Data load/store vif connection
  assign data_mem_vif.reset = ~rst_n;
  // Instruction fetch vif connection
  assign instr_mem_vif.reset = ~rst_n;
  assign instr_mem_vif.we    = 0;
  assign instr_mem_vif.be    = 0;
  assign instr_mem_vif.wdata = 0;
  // RVFI interface connections
  assign rvfi_if.reset                = ~rst_n;
  assign rvfi_if.valid                = dut.rvfi_valid;
  assign rvfi_if.order                = dut.rvfi_order;
  assign rvfi_if.insn                 = dut.rvfi_insn;
  assign rvfi_if.trap                 = dut.rvfi_trap;
  assign rvfi_if.intr                 = dut.rvfi_intr;
  assign rvfi_if.mode                 = dut.rvfi_mode;
  assign rvfi_if.ixl                  = dut.rvfi_ixl;
  assign rvfi_if.rs1_addr             = dut.rvfi_rs1_addr;
  assign rvfi_if.rs2_addr             = dut.rvfi_rs2_addr;
  assign rvfi_if.rs1_rdata            = dut.rvfi_rs1_rdata;
  assign rvfi_if.rs2_rdata            = dut.rvfi_rs2_rdata;
  assign rvfi_if.rd_addr              = dut.rvfi_rd_addr;
  assign rvfi_if.rd_wdata             = dut.rvfi_rd_wdata;
  // CHERIoT capability write: {tag, compressed 32-bit memory-format capability}.
  // ibex_cheriot_pkg::cheriot_cap_to_mem() packs the RTL's expanded register
  // capability (cap_t) the same way a CSC instruction would compress it to
  // store into memory -- used by the cheriot-sail cosim step below, which only
  // needs the tag bit (bit 32) and the compressed value, not the full struct.
  assign rvfi_if.rd_wcap              = ibex_cheriot_pkg::cheriot_cap_to_mem(dut.rvfi_rd_wcap);
  assign rvfi_if.rs1_rcap             = ibex_cheriot_pkg::cheriot_cap_to_mem(dut.rvfi_rs1_rcap);
  assign rvfi_if.rs2_rcap             = ibex_cheriot_pkg::cheriot_cap_to_mem(dut.rvfi_rs2_rcap);
  assign rvfi_if.mem_is_cap           = dut.rvfi_mem_is_cap;
  assign rvfi_if.mem_rcap             = ibex_cheriot_pkg::cheriot_cap_to_mem(dut.rvfi_mem_rcap);
  assign rvfi_if.mem_wcap             = ibex_cheriot_pkg::cheriot_cap_to_mem(dut.rvfi_mem_wcap);
  assign rvfi_if.pc_rdata             = dut.rvfi_pc_rdata;
  assign rvfi_if.pc_wdata             = dut.rvfi_pc_wdata;
  assign rvfi_if.mem_addr             = dut.rvfi_mem_addr;
  assign rvfi_if.mem_rmask            = dut.rvfi_mem_rmask;
  assign rvfi_if.mem_rdata            = dut.rvfi_mem_rdata;
  assign rvfi_if.mem_wdata            = dut.rvfi_mem_wdata;
  assign rvfi_if.ext_pre_mip          = dut.rvfi_ext_pre_mip;
  assign rvfi_if.ext_post_mip         = dut.rvfi_ext_post_mip;
  assign rvfi_if.ext_expanded_insn_valid = dut.rvfi_ext_expanded_insn_valid;
  assign rvfi_if.ext_expanded_insn       = dut.rvfi_ext_expanded_insn;
  assign rvfi_if.ext_expanded_insn_last  = dut.rvfi_ext_expanded_insn_last;
  assign rvfi_if.ext_nmi              = dut.rvfi_ext_nmi;
  assign rvfi_if.ext_nmi_int          = dut.rvfi_ext_nmi_int;
  assign rvfi_if.ext_debug_req        = dut.rvfi_ext_debug_req;
  assign rvfi_if.ext_rf_wr_suppress   = dut.rvfi_ext_rf_wr_suppress;
  assign rvfi_if.ext_mcycle           = dut.rvfi_ext_mcycle;
  assign rvfi_if.ext_mhpmcounters     = dut.rvfi_ext_mhpmcounters;
  assign rvfi_if.ext_mhpmcountersh    = dut.rvfi_ext_mhpmcountersh;
  assign rvfi_if.ext_ic_scr_key_valid = dut.rvfi_ext_ic_scr_key_valid;
  assign rvfi_if.ext_irq_valid        = dut.rvfi_ext_irq_valid;
  // Irq interface connections
  assign irq_vif.reset = ~rst_n;
  // Dut_if interface connections
  assign dut_if.ecall            = dut.u_ibex_top.u_ibex_core.id_stage_i.controller_i.ecall_insn;
  assign dut_if.wfi              = dut.u_ibex_top.u_ibex_core.id_stage_i.controller_i.wfi_insn;
  assign dut_if.ebreak           = dut.u_ibex_top.u_ibex_core.id_stage_i.controller_i.ebrk_insn;
  assign dut_if.illegal_instr
      = dut.u_ibex_top.u_ibex_core.id_stage_i.controller_i.illegal_insn_d;
  assign dut_if.dret             = dut.u_ibex_top.u_ibex_core.id_stage_i.controller_i.dret_insn;
  assign dut_if.mret             = dut.u_ibex_top.u_ibex_core.id_stage_i.controller_i.mret_insn;
  assign dut_if.reset            = ~rst_n;
  assign dut_if.ic_tag_req       = dut.u_ibex_top.ic_tag_req;
  assign dut_if.ic_tag_write     = dut.u_ibex_top.ic_tag_write;
  assign dut_if.ic_tag_addr      = dut.u_ibex_top.ic_tag_addr;
  assign dut_if.ic_data_req      = dut.u_ibex_top.ic_data_req;
  assign dut_if.ic_data_write    = dut.u_ibex_top.ic_data_write;
  assign dut_if.ic_data_addr     = dut.u_ibex_top.ic_data_addr;
  assign dut_if.priv_mode        = dut.u_ibex_top.u_ibex_core.priv_mode_id;
  assign dut_if.ctrl_fsm_cs      = dut.u_ibex_top.u_ibex_core.id_stage_i.controller_i.ctrl_fsm_cs;
  assign dut_if.debug_mode       = dut.u_ibex_top.u_ibex_core.id_stage_i.controller_i.debug_mode_q;
  assign dut_if.rf_ren_a         = dut.u_ibex_top.u_ibex_core.rf_ren_a;
  assign dut_if.rf_ren_b         = dut.u_ibex_top.u_ibex_core.rf_ren_b;
  assign dut_if.rf_rd_a_wb_match = dut.u_ibex_top.u_ibex_core.rf_rd_a_wb_match;
  assign dut_if.rf_rd_b_wb_match = dut.u_ibex_top.u_ibex_core.rf_rd_b_wb_match;
  assign dut_if.rf_write_wb      = dut.u_ibex_top.u_ibex_core.rf_write_wb;
  assign dut_if.sync_exc_seen    =
      dut.u_ibex_top.u_ibex_core.cs_registers_i.cpuctrlsts_part_q.sync_exc_seen;
  assign dut_if.csr_save_cause   = dut.u_ibex_top.u_ibex_core.csr_save_cause;
  assign dut_if.exc_cause        = dut.u_ibex_top.u_ibex_core.exc_cause;
  assign dut_if.wb_exception     = dut.u_ibex_top.u_ibex_core.id_stage_i.wb_exception;
  assign dut_if.lsu_ctx_wait_gnt1 =
    (dut.u_ibex_top.u_ibex_core.load_store_unit_i.ls_fsm_cs == ibex_pkg::CTX_WAIT_GNT1);
  assign dut_if.id_instr_held    = dut.u_ibex_top.u_ibex_core.id_stage_i.instr_valid_i &
                                   ~dut.u_ibex_top.u_ibex_core.id_stage_i.instr_valid_clear_o;
  assign dut_if.id_stall_mem     = dut.u_ibex_top.u_ibex_core.id_stage_i.stall_mem;
  // A PMP-blocked access sends no request, so it leaves WAIT_GNT* on pmp_err_q alone; in the next
  // (IDLE) cycle lsu_resp_valid_o reports the error (ibex_load_store_unit.sv)
  assign dut_if.lsu_pmp_err_next =
    dut.u_ibex_top.u_ibex_core.load_store_unit_i.pmp_err_q &
    (dut.u_ibex_top.u_ibex_core.load_store_unit_i.ls_fsm_cs != ibex_pkg::IDLE) &
    (dut.u_ibex_top.u_ibex_core.load_store_unit_i.ls_fsm_ns == ibex_pkg::IDLE);
  // Instruction monitor connections
  assign instr_monitor_if.reset        = ~rst_n;
  assign instr_monitor_if.valid_id     = dut.u_ibex_top.u_ibex_core.id_stage_i.instr_valid_i;
  assign instr_monitor_if.rvfi_id_done = dut.u_ibex_top.u_ibex_core.rvfi_id_done;

  assign instr_monitor_if.err_id =
    dut.u_ibex_top.u_ibex_core.id_stage_i.controller_i.instr_fetch_err;

  assign instr_monitor_if.is_compressed_id =
    dut.u_ibex_top.u_ibex_core.id_stage_i.instr_is_compressed_i;

  assign instr_monitor_if.instr_compressed_id =
    dut.u_ibex_top.u_ibex_core.id_stage_i.instr_rdata_c_i;

  assign instr_monitor_if.instr_id = dut.u_ibex_top.u_ibex_core.id_stage_i.instr_rdata_i;
  assign instr_monitor_if.pc_id    = dut.u_ibex_top.u_ibex_core.pc_id;

  assign instr_monitor_if.branch_taken_id =
    dut.u_ibex_top.u_ibex_core.id_stage_i.controller_i.branch_set_i;

  assign instr_monitor_if.branch_target_id = dut.u_ibex_top.u_ibex_core.branch_target_ex;
  assign instr_monitor_if.stall_id         = dut.u_ibex_top.u_ibex_core.id_stage_i.stall_id;
  assign instr_monitor_if.jump_set_id      = dut.u_ibex_top.u_ibex_core.id_stage_i.jump_set;
  assign instr_monitor_if.rvfi_order_id    = dut.u_ibex_top.u_ibex_core.rvfi_stage_order_d;
  // CSR interface connections
  assign csr_if.csr_access = dut.u_ibex_top.u_ibex_core.csr_access;
  assign csr_if.csr_addr   = dut.u_ibex_top.u_ibex_core.csr_addr;
  assign csr_if.csr_wdata  = dut.u_ibex_top.u_ibex_core.csr_wdata;
  assign csr_if.csr_rdata  = dut.u_ibex_top.u_ibex_core.csr_rdata;
  assign csr_if.csr_op     = dut.u_ibex_top.u_ibex_core.csr_op;

  assign ifetch_if.reset           = ~dut.u_ibex_top.u_ibex_core.if_stage_i.rst_ni;
  assign ifetch_if.fetch_ready     = dut.u_ibex_top.u_ibex_core.if_stage_i.fetch_ready;
  assign ifetch_if.fetch_valid     = dut.u_ibex_top.u_ibex_core.if_stage_i.fetch_valid;
  assign ifetch_if.fetch_rdata     = dut.u_ibex_top.u_ibex_core.if_stage_i.fetch_rdata;
  assign ifetch_if.fetch_addr      = dut.u_ibex_top.u_ibex_core.if_stage_i.fetch_addr;
  assign ifetch_if.fetch_err       = dut.u_ibex_top.u_ibex_core.if_stage_i.fetch_err;
  assign ifetch_if.fetch_err_plus2 = dut.u_ibex_top.u_ibex_core.if_stage_i.fetch_err_plus2;

  assign ifetch_pmp_if.reset         = ~dut.u_ibex_top.u_ibex_core.if_stage_i.rst_ni;
  assign ifetch_pmp_if.fetch_valid   = dut.u_ibex_top.u_ibex_core.instr_req_o;
  assign ifetch_pmp_if.fetch_addr    = dut.u_ibex_top.u_ibex_core.instr_addr_o;
  assign ifetch_pmp_if.fetch_pmp_err = dut.u_ibex_top.u_ibex_core.pmp_req_err[ibex_pkg::PMP_I];

  assign data_mem_vif.misaligned_first =
    dut.u_ibex_top.u_ibex_core.load_store_unit_i.handle_misaligned_d |
    ((dut.u_ibex_top.u_ibex_core.load_store_unit_i.lsu_type_i == 2'b01) &
     (dut.u_ibex_top.u_ibex_core.load_store_unit_i.data_offset == 2'b01));

  assign data_mem_vif.misaligned_second =
    dut.u_ibex_top.u_ibex_core.load_store_unit_i.addr_incr_req_o;

  assign data_mem_vif.misaligned_first_saw_error =
    dut.u_ibex_top.u_ibex_core.load_store_unit_i.addr_incr_req_o &
    dut.u_ibex_top.u_ibex_core.load_store_unit_i.lsu_err_d;

  assign data_mem_vif.m_mode_access =
    dut.u_ibex_top.u_ibex_core.priv_mode_lsu == ibex_pkg::PRIV_LVL_M;

  initial begin
    // Drive the clock and reset lines. Reset everything and start the clock at the beginning of
    // time
    #0; // needed for dsim
    ibex_clk_if.set_active();
    fork
      ibex_clk_if.apply_reset(.reset_width_clks (100));
    join_none

    uvm_config_db#(virtual clk_rst_if)::set(null, "*", "clk_if", ibex_clk_if);
    uvm_config_db#(virtual core_ibex_dut_probe_if)::set(null, "*", "dut_if", dut_if);
    uvm_config_db#(virtual core_ibex_instr_monitor_if)::set(null,
                                                            "*",
                                                            "instr_monitor_if",
                                                            instr_monitor_if);
    uvm_config_db#(virtual core_ibex_csr_if)::set(null, "*", "csr_if", csr_if);
    uvm_config_db#(virtual core_ibex_rvfi_if)::set(null, "*", "rvfi_if", rvfi_if);
    uvm_config_db#(virtual ibex_mem_intf)::set(null, "*data_if_response*", "vif", data_mem_vif);
    uvm_config_db#(virtual ibex_mem_intf)::set(null, "*instr_if_response*", "vif", instr_mem_vif);
    uvm_config_db#(virtual irq_if)::set(null, "*", "vif", irq_vif);
    uvm_config_db#(virtual core_ibex_ifetch_if)::set(null, "*", "ifetch_if", ifetch_if);
    uvm_config_db#(virtual core_ibex_ifetch_pmp_if)::set(null, "*", "ifetch_pmp_if",
                   ifetch_pmp_if);
    uvm_config_db#(scrambling_key_vif)::set(
      null, "*.env.scrambling_key_agent*", "vif", scrambling_key_if);

    // Expose ISA config parameters to UVM DB
    uvm_config_db#(bit)::set(null, "*", "RV32E", RV32E);
    uvm_config_db#(ibex_pkg::rv32m_e)::set(null, "*", "RV32M", RV32M);
    uvm_config_db#(ibex_pkg::rv32b_e)::set(null, "*", "RV32B", RV32B);
    uvm_config_db#(ibex_pkg::rv32zc_e)::set(null, "*", "RV32ZC", RV32ZC);

    if (PMPEnable) begin
      uvm_config_db#(bit [31:0])::set(null, "*", "PMPNumRegions", PMPNumRegions);
      uvm_config_db#(bit [31:0])::set(null, "*", "PMPGranularity", PMPGranularity);
    end else begin
      uvm_config_db#(bit [31:0])::set(null, "*", "PMPNumRegions", 0);
      uvm_config_db#(bit [31:0])::set(null, "*", "PMPGranularity", 0);
    end

    uvm_config_db#(bit [31:0])::set(null, "*", "MHPMCounterNum", MHPMCounterNum);
    uvm_config_db#(bit)::set(null, "*", "SecureIbex", SecureIbex);
    uvm_config_db#(bit)::set(null, "*", "CHERIoT",
                             BaseIsa == ibex_pkg::BaseIsaRV32IorCHERIoT);
    uvm_config_db#(bit)::set(null, "*", "ICache", ICache);
`ifdef IBEX_DM_REAL
    uvm_config_db#(bit)::set(null, "*", "DM_REAL", 1'b1);
    uvm_config_db#(virtual ibex_dm_dmi_if)::set(null, "*", "dm_dmi_if", dm_dmi_if);
`else
    uvm_config_db#(bit)::set(null, "*", "DM_REAL", 1'b0);
`endif

    run_test();
  end

  // Manually set unused_assert_connected = 1 to disable the AssertConnected_A assertion for
  // prim_count in case lockstep (set by SecureIbex) is enabled and the lockstep offset is
  // larger than 1. If not disabled, DV fails.
  if (SecureIbex && LockstepOffset > 1) begin : gen_disable_count_check
    assign dut.u_ibex_top.gen_lockstep.u_ibex_lockstep.gen_reset_counter.u_rst_shadow_cnt.
          unused_assert_connected = 1;
  end

  ibex_pkg::ctrl_fsm_e controller_state;
  logic                controller_handle_irq;
  ibex_pkg::irqs_t     ibex_irqs, last_ibex_irqs;

  assign controller_state      = dut.u_ibex_top.u_ibex_core.id_stage_i.controller_i.ctrl_fsm_cs;
  assign controller_handle_irq = dut.u_ibex_top.u_ibex_core.id_stage_i.controller_i.handle_irq;
  assign ibex_irqs             = dut.u_ibex_top.u_ibex_core.irqs;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      last_ibex_irqs <= '0;
    end else begin
      last_ibex_irqs <= ibex_irqs;
    end
  end

  always_ff @(posedge clk) begin
    if (controller_state == ibex_pkg::IRQ_TAKEN) begin
      if (!controller_handle_irq) begin
        $display("WARNING: Controller in IRQ_TAKEN but no IRQ to handle, returning to DECODE");
        $display("IRQs last cycle: %x, IRQs this cycle: %x", last_ibex_irqs, ibex_irqs);
      end else if (last_ibex_irqs != ibex_irqs) begin
        $display("WARNING: Controller in IRQ_TAKEN and IRQs have just changed");
        $display("IRQs last cycle: %x, IRQs this cycle: %x", last_ibex_irqs, ibex_irqs);
      end
    end
  end
endmodule
