// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Top level for the TestRIG (RVFI-DII) flow. Instructions are injected into the fetch path
// (DII_SIM: the fetch FIFO with ICache = 0, the ICache output stage with ICache = 1), so there is
// no instruction memory; the data memory mirrors the Sail model's RAM.
//
// Runtime plusargs (besides the agent's and the scoreboard's):
//   +dii_intg_corrupt=<n>  flip one integrity bit of the n-th load response (1-based, counted over
//                          the whole run). Fault injection for the bus-integrity check: the core
//                          must raise alert_major_bus_o and the alert check below must fail the run.

`define BOOT_ADDR 32'h8000_0000

module core_ibex_testrig_tb_top;
  import ibex_pkg::*;
  import ibex_cheriot_pkg::*;

  // Core configuration. testrig_xlm_build.sh / testrig_vlt_build.sh set every one of these from
  // ibex/ibex_configs.yaml through util/ibex_config.py (default configuration: opentitan, the one
  // the UVM testbench, compliance and the RTOS SoC build, so their coverage databases are of the
  // same model): the enum-typed ones as IBEX_CFG_* defines, the rest as -defparam (Xcelium) or -G
  // (Verilator) overrides of the parameters below. The fallbacks are opentitan's values too, so a
  // build that bypasses the scripts still gets that core.
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
  parameter ibex_pkg::base_isa_e  BaseIsa          = `IBEX_CFG_BaseIsa;
  // RV32E = 0: with cheriot_enable_i low (riscv flavour) x16-x31 are real registers, matching the
  // 32-register RISC-V Sail model; in CHERIoT mode the decoder still limits the core to x0-x15.
  parameter bit                   RV32E            = 1'b0;
  parameter ibex_pkg::rv32m_e     RV32M            = `IBEX_CFG_RV32M;
  parameter ibex_pkg::rv32b_e     RV32B            = `IBEX_CFG_RV32B;
  parameter ibex_pkg::rv32zc_e    RV32ZC           = `IBEX_CFG_RV32ZC;
  parameter ibex_pkg::regfile_e   RegFile          = `IBEX_CFG_RegFile;
  parameter bit                   BranchTargetALU  = 1'b1;
  parameter bit                   WritebackStage   = 1'b1;
  parameter bit                   ICache           = 1'b1;
  parameter bit                   ICacheECC        = 1'b1;
  parameter bit                   ICacheScramble   = 1'b1;
  parameter bit                   BranchPredictor  = 1'b0;
  parameter bit                   DbgTriggerEn     = 1'b1;
  parameter bit                   SecureIbex       = 1'b1;
  parameter bit                   PMPEnable        = 1'b1;
  parameter int unsigned          PMPGranularity   = 0;
  parameter int unsigned          PMPNumRegions    = 16;
  parameter int unsigned          MHPMCounterNum   = 10;
  parameter int unsigned          MHPMCounterWidth = 32;

  // Not in ibex_configs.yaml; ibex_top_tracing's defaults, which the UVM testbench also keeps:
  // MemECC follows SecureIbex (bus integrity checked on instruction and data responses), one
  // debug trigger, and the lockstep shadow core one cycle behind (g_dii_shadow relies on that).
  localparam bit MemECC = SecureIbex;

  // The CHERIoT reset alignment below forces flops of the flip-flop register file.
  initial begin
    if (BaseIsa == ibex_pkg::BaseIsaRV32IorCHERIoT && RegFile != ibex_pkg::RegFileFF) begin
      $fatal(1, "core_ibex_testrig_tb_top: CHERIoT configurations need RegFile = RegFileFF");
    end
  end

  wire clk;
  wire rst_n;

  clk_rst_if clk_if(.clk(clk), .rst_n(rst_n));
  core_ibex_dii_intf dii_if(.clk(clk), .rst_n(rst_n), .rvfi_valid(dut.rvfi_valid));
  core_ibex_rvfi_if rvfi_if(.clk(clk));

  // Must match rv_ram_base/rv_ram_size in the Sail DPI bridges, or an access that Sail
  // accepts faults on the RTL (or vice versa).
  localparam logic [31:0] DataMemBase = 32'h8000_0000;
  localparam logic [31:0] DataMemSize = 32'h0080_0000;

  logic instr_req;
  logic instr_gnt;
  logic instr_rvalid;

  logic        data_req;
  logic        data_gnt;
  logic        data_rvalid;
  logic        data_we;
  logic [3:0]  data_be;
  logic [31:0] data_addr;
  logic [31:0] data_wdata;
  logic        data_tag_wr;
  logic [31:0] data_rdata;
  logic        data_tag_rd;
  logic        data_err;

  logic        revbm_req;
  logic        revbm_gnt;
  logic        revbm_rvalid;
  logic [31:0] revbm_addr;
  logic [31:0] revbm_rdata;
  logic [6:0]  revbm_rdata_intg;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      instr_rvalid <= 1'b0;
    end else begin
      instr_rvalid <= instr_gnt;
    end
  end

  // Without the dii_ready gate ibex keeps re-fetching the DII register while the driver waits
  // for the next packet, producing spurious retirements.
  assign instr_gnt = instr_req && dii_if.dii_ready;
  assign data_gnt  = data_req;

  logic data_addr_valid;
  assign data_addr_valid = (data_addr >= DataMemBase) && (data_addr < DataMemBase + DataMemSize);

  // Bus integrity (MemECC = SecureIbex): the core checks *_rdata_intg_i against *_rdata_i with
  // the inverted SECDED code and raises alert_major_bus_o, and faults the access, on a mismatch.
  // Neither memory here stores integrity, so it is generated from the response data, as
  // ibex_riscv_compliance.sv and the UVM memory agent do. Tying it to 0 is wrong even for zero
  // data: the inverted code of 0 is not 0. The instruction bus always returns 0 (DII supplies the
  // instruction words further in), so its code is a constant.
  logic [6:0] instr_rdata_intg;
  logic [6:0] data_rdata_intg;
  logic [6:0] data_rdata_intg_good;
  logic [6:0] data_rdata_intg_flip;
  if (MemECC) begin : g_mem_intg
    logic [31:0] unused_instr_enc, unused_data_enc;
    prim_secded_inv_39_32_enc u_instr_rdata_intg_gen (
      .data_i (32'h0),
      .data_o ({instr_rdata_intg, unused_instr_enc})
    );
    prim_secded_inv_39_32_enc u_data_rdata_intg_gen (
      .data_i (data_rdata),
      .data_o ({data_rdata_intg_good, unused_data_enc})
    );
  end else begin : g_no_mem_intg
    assign instr_rdata_intg     = '0;
    assign data_rdata_intg_good = '0;
  end
  assign data_rdata_intg = data_rdata_intg_good ^ data_rdata_intg_flip;

  // +dii_intg_corrupt=<n>: flip intg bit 0 of the n-th load response. Proves the alert check below
  // can fail: that run must end with NoAlertsTriggered firing (and, as the load faults on the RTL
  // only, a scoreboard trap mismatch).
  int unsigned intg_corrupt_n;
  int unsigned load_rsp_count;
  initial begin
    intg_corrupt_n = 0;
    void'($value$plusargs("dii_intg_corrupt=%d", intg_corrupt_n));
  end

  // ICacheScramble: out of reset (and on every fence.i) the ICache asks for a scrambling key and
  // keeps its tag RAM blocked until scramble_key_valid_i (ibex_icache.sv AWAIT_SCRAMBLE_KEY).
  // Answer each request one cycle later with a fixed zero key and nonce, as compliance does. With
  // cpuctrl.icache_enable at its reset value (0) the cache would fetch regardless, but a stimulus
  // that sets the bit must not hang.
  logic scramble_req, scramble_key_valid;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) scramble_key_valid <= 1'b0;
    else        scramble_key_valid <= scramble_req;
  end

  logic alert_minor, alert_major_internal, alert_major_bus;
  logic revbm_inj_err;

  ibex_top_tracing #(
    .PMPEnable        ( PMPEnable              ),
    .PMPGranularity   ( PMPGranularity         ),
    .PMPNumRegions    ( PMPNumRegions          ),
    .MHPMCounterNum   ( MHPMCounterNum         ),
    .MHPMCounterWidth ( MHPMCounterWidth       ),
    .RV32E            ( RV32E                  ),
    .RV32M            ( RV32M                  ),
    .RV32B            ( RV32B                  ),
    .RV32ZC           ( RV32ZC                 ),
    .RegFile          ( RegFile                ),
    .BranchTargetALU  ( BranchTargetALU        ),
    .ICache           ( ICache                 ),
    .ICacheECC        ( ICacheECC              ),
    .BranchPredictor  ( BranchPredictor        ),
    .DbgTriggerEn     ( DbgTriggerEn           ),
    .WritebackStage   ( WritebackStage         ),
    .SecureIbex       ( SecureIbex             ),
    .ICacheScramble   ( ICacheScramble         ),
    // DbgHwBreakNum, LockstepOffset, MemECC, MemDataWidth, RndCnst*: ibex_top_tracing's defaults,
    // as in the UVM testbench (MemECC = SecureIbex, MemDataWidth = 39 with it).
    // Debug module addresses from cheriot-ibex ibex_top_sram.sv; chosen to stand out in a trace.
    // The rest as the UVM bench passes them (core_ibex_tb_top.sv, scripts/compile_tb.py), so both
    // builds have the same ibex_top and their coverage databases merge into one model. TestRIG
    // never requests debug, so the debug-ROM addresses (Spike's, at the boot address) do not
    // matter to its stimulus.
    .DmBaseAddr           ( 32'h1A110000                        ),
    .DmAddrMask           ( 32'h00000FFF                        ),
    .DmHaltAddr           ( 32'h80000000                        ),
    .DmExceptionAddr      ( 32'h80000008                        ),
    .ICacheTweakInfection ( 1'b0                                ),
    .LockstepOffset       ( 1                                   ),
    .CheriotRevBitmapAddrWidth ( ibex_revbm_pkg::RevBitmapAddrWidth ),
    .CheriotRevBitmapBaseAddr  ( ibex_revbm_pkg::RevBitmapBaseAddr  ),
    .BaseIsa          ( BaseIsa                )
  ) dut (
    .clk_i                     (clk),
    .rst_ni                    (rst_n),

    .test_en_i                 (1'b0),
    .scan_rst_ni               (1'b1),
    .ram_cfg_icache_tag_i      ('{default: prim_ram_1p_pkg::RAM_1P_CFG_REQ_DEFAULT}),
    .ram_cfg_icache_tag_o      (),
    .ram_cfg_icache_data_i     ('{default: prim_ram_1p_pkg::RAM_1P_CFG_REQ_DEFAULT}),
    .ram_cfg_icache_data_o     (),

    .hart_id_i                 ('0),
    .boot_addr_i               (`BOOT_ADDR),
    .trvk_heap_base_addr_i     (32'b0),

    .instr_req_o               (instr_req),
    .instr_gnt_i               (instr_gnt),
    .instr_rvalid_i            (instr_rvalid),
    .instr_addr_o              (),
    .instr_rdata_i             ('0),
    .instr_rdata_intg_i        (instr_rdata_intg),
    .instr_err_i               (1'b0),

    .data_req_o                (data_req),
    .data_gnt_i                (data_gnt),
    .data_rvalid_i             (data_rvalid),
    .data_we_o                 (data_we),
    .data_be_o                 (data_be),
    .data_addr_o               (data_addr),
    .data_wdata_o              (data_wdata),
    .data_tag_o                (data_tag_wr),
    .data_wdata_intg_o         (),
    .data_rdata_i              (data_rdata),
    .data_tag_i                (data_tag_rd),
    .data_rdata_intg_i         (data_rdata_intg),
    .data_err_i                (data_err),

    .trvk_revbm_req_o          (revbm_req),
    .trvk_revbm_gnt_i          (revbm_gnt),
    .trvk_revbm_rvalid_i       (revbm_rvalid),
    .trvk_revbm_addr_o         (revbm_addr),
    .trvk_revbm_rdata_i        (revbm_rdata),
    .trvk_revbm_rdata_intg_i   (revbm_rdata_intg),
    .trvk_revbm_err_i          (1'b0),

    .irq_software_i            (dii_if.irq_software),
    .irq_timer_i               (dii_if.irq_timer),
    .irq_external_i            (dii_if.irq_external),
    .irq_fast_i                (15'h0),
    .irq_nm_i                  (1'b0),

    .scramble_key_valid_i      (scramble_key_valid),
    .scramble_key_i            (128'h0),
    .scramble_nonce_i          (64'h0),
    .scramble_req_o            (scramble_req),

    .debug_req_i               (1'b0),
    .crash_dump_o              (),
    .double_fault_seen_o       (),

    .cheriot_enable_i          (dii_if.cheriot_enable),

    .fetch_enable_i            (ibex_pkg::IbexMuBiOn),
    .mcounteren_writable_i     (ibex_pkg::IbexMuBiOn),
    .alert_minor_o             (alert_minor),
    .alert_major_internal_o    (alert_major_internal),
    .alert_major_bus_o         (alert_major_bus),
    .core_sleep_o              (),

    .lockstep_cmp_en_o         (),

    .data_req_shadow_o         (),
    .data_we_shadow_o          (),
    .data_be_shadow_o          (),
    .data_addr_shadow_o        (),
    .data_wdata_shadow_o       (),
    .data_wdata_intg_shadow_o  (),

    .instr_req_shadow_o        (),
    .instr_addr_shadow_o       ()
  );

  // Revocation-bitmap lookups: always "not revoked" (see ibex_revbm_responder.sv).
  ibex_revbm_responder u_revbm_responder (
    .clk_i              (clk             ),
    .rst_ni             (rst_n           ),
    .revbm_req_i        (revbm_req       ),
    .revbm_gnt_o        (revbm_gnt       ),
    .revbm_rvalid_o     (revbm_rvalid    ),
    .revbm_addr_i       (revbm_addr      ),
    .revbm_rdata_o      (revbm_rdata     ),
    .revbm_rdata_intg_o (revbm_rdata_intg),
    .revbm_err_o        (                ),
    .heap_base_o        (                ),
    .inj_err_o          (revbm_inj_err   )
  );

  // Sparse data + tag memory, emptied on every reset. Each DII test starts from a reset and
  // the Sail model starts from zeroed RAM, so unwritten locations must read 0 (not X, and not
  // data left by an earlier test). One tag per 8-byte granule, as a CHERIoT capability is two
  // bus beats sharing a tag; only a full-width capability write keeps it (as ibex_tag_mem.sv).
  bit [31:0] data_mem [bit [29:0]];
  bit        tag_mem  [bit [28:0]];

  logic data_err_q;
  assign data_err = data_err_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      data_mem.delete();
      tag_mem.delete();
      data_rvalid <= 1'b0;
      data_rdata  <= '0;
      data_tag_rd <= 1'b0;
      data_err_q  <= 1'b0;
    end else begin
      data_rvalid <= data_req;
      data_err_q  <= data_req && !data_addr_valid;
      data_rdata  <= '0;
      data_tag_rd <= 1'b0;
      if (data_req && data_addr_valid) begin
        if (data_we) begin
          bit [31:0] word;
          word = data_mem.exists(data_addr[31:2]) ? data_mem[data_addr[31:2]] : '0;
          for (int b = 0; b < 4; b++) begin
            if (data_be[b]) word[8*b+:8] = data_wdata[8*b+:8];
          end
          // Blocking on purpose: nonblocking assignment to an associative array is illegal
          // (IEEE 1800-2023 6.21). Only this block touches the arrays, so there is no race.
          data_mem[data_addr[31:2]] = word;
          tag_mem[data_addr[31:3]]  = data_tag_wr && (data_be == 4'b1111);
        end else begin
          data_rdata  <= data_mem.exists(data_addr[31:2]) ? data_mem[data_addr[31:2]] : '0;
          data_tag_rd <= tag_mem.exists(data_addr[31:3])  ? tag_mem[data_addr[31:3]]  : 1'b0;
        end
      end
    end
  end

  logic        data_we_q;
  logic [31:0] data_addr_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      data_we_q   <= 1'b0;
      data_addr_q <= '0;
    end else if (data_req) begin
      data_we_q   <= data_we;
      data_addr_q <= data_addr;
    end
  end

  // Load responses seen so far (not reset between tests), for +dii_intg_corrupt.
  logic load_rsp;
  assign load_rsp = rst_n && data_rvalid && !data_we_q && !data_err;
  always @(posedge clk) begin
    if (load_rsp) load_rsp_count <= load_rsp_count + 1;
  end
  assign data_rdata_intg_flip = (MemECC && intg_corrupt_n != 0 && load_rsp &&
                                 load_rsp_count + 1 == intg_corrupt_n) ? 7'b000_0001 : 7'b0;
  always @(posedge clk) begin
    if (data_rdata_intg_flip != '0) begin
      $display("[tb] +dii_intg_corrupt=%0d: flipped data_rdata_intg bit 0 of load response %0d (addr 0x%08h)",
               intg_corrupt_n, load_rsp_count + 1, data_addr_q);
    end
  end
  final begin
    if (intg_corrupt_n != 0 && load_rsp_count < intg_corrupt_n) begin
      $error("[tb] +dii_intg_corrupt=%0d never applied: only %0d load responses", intg_corrupt_n,
             load_rsp_count);
    end
  end

  // RVFI interface connections
  assign rvfi_if.reset                   = ~rst_n;
  assign rvfi_if.valid                   = dut.rvfi_valid;
  assign rvfi_if.order                   = dut.rvfi_order;
  assign rvfi_if.insn                    = dut.rvfi_insn;
  assign rvfi_if.trap                    = dut.rvfi_trap;
  assign rvfi_if.halt                    = dut.rvfi_halt;
  assign rvfi_if.intr                    = dut.rvfi_intr;
  assign rvfi_if.mode                    = dut.rvfi_mode;
  assign rvfi_if.ixl                     = dut.rvfi_ixl;
  assign rvfi_if.rs1_addr                = dut.rvfi_rs1_addr;
  assign rvfi_if.rs2_addr                = dut.rvfi_rs2_addr;
  assign rvfi_if.rs1_rdata               = dut.rvfi_rs1_rdata;
  assign rvfi_if.rs2_rdata               = dut.rvfi_rs2_rdata;
  assign rvfi_if.rd_addr                 = dut.rvfi_rd_addr;
  assign rvfi_if.rd_wdata                = dut.rvfi_rd_wdata;
  assign rvfi_if.pc_rdata                = dut.rvfi_pc_rdata;
  assign rvfi_if.pc_wdata                = dut.rvfi_pc_wdata;
  assign rvfi_if.mem_addr                = dut.rvfi_mem_addr;
  assign rvfi_if.mem_rmask               = dut.rvfi_mem_rmask;
  assign rvfi_if.mem_rdata               = dut.rvfi_mem_rdata;
  assign rvfi_if.mem_wdata               = dut.rvfi_mem_wdata;
  assign rvfi_if.mem_wmask               = dut.rvfi_mem_wmask;
  assign rvfi_if.ext_pre_mip             = dut.rvfi_ext_pre_mip;
  assign rvfi_if.ext_post_mip            = dut.rvfi_ext_post_mip;
  assign rvfi_if.ext_nmi                 = dut.rvfi_ext_nmi;
  assign rvfi_if.ext_nmi_int             = dut.rvfi_ext_nmi_int;
  assign rvfi_if.ext_debug_req           = dut.rvfi_ext_debug_req;
  assign rvfi_if.ext_rf_wr_suppress      = dut.rvfi_ext_rf_wr_suppress;
  assign rvfi_if.ext_expanded_insn_valid = dut.rvfi_ext_expanded_insn_valid;
  assign rvfi_if.ext_expanded_insn       = dut.rvfi_ext_expanded_insn;
  assign rvfi_if.ext_expanded_insn_last  = dut.rvfi_ext_expanded_insn_last;
  assign rvfi_if.ext_mcycle              = dut.rvfi_ext_mcycle;
  assign rvfi_if.ext_mhpmcounters        = dut.rvfi_ext_mhpmcounters;
  assign rvfi_if.ext_mhpmcountersh       = dut.rvfi_ext_mhpmcountersh;
  assign rvfi_if.ext_ic_scr_key_valid    = dut.rvfi_ext_ic_scr_key_valid;
  assign rvfi_if.ext_irq_valid           = dut.rvfi_ext_irq_valid;
  assign rvfi_if.rs1_rcap                = cheriot_cap_to_mem(dut.rvfi_rs1_rcap);
  assign rvfi_if.rs2_rcap                = cheriot_cap_to_mem(dut.rvfi_rs2_rcap);
  assign rvfi_if.rd_wcap                 = cheriot_cap_to_mem(dut.rvfi_rd_wcap);
  assign rvfi_if.mem_is_cap              = dut.rvfi_mem_is_cap;
  assign rvfi_if.mem_rcap                = cheriot_cap_to_mem(dut.rvfi_mem_rcap);
  assign rvfi_if.mem_wcap                = cheriot_cap_to_mem(dut.rvfi_mem_wcap);

  // DII injection point. ICache = 0: the prefetch buffer's fetch FIFO (ibex_fetch_fifo.sv).
  // ICache = 1: there is no prefetch buffer, so the ICache's output stage (ibex_icache.sv) takes
  // the same three signals. The cache stays in the fetch path either way: it fetches (zeros, with
  // valid integrity) from the bus, and with cpuctrl.icache_enable set it allocates and hits; only
  // the words it hands to the core are the injected ones.
  `define IBEX_MAIN_CORE   dut.u_ibex_top.u_ibex_core
  `define IBEX_SHADOW_CORE dut.u_ibex_top.gen_lockstep.u_ibex_lockstep.u_shadow_core
  `define IBEX_RF_FF_PATH dut.u_ibex_top.gen_regfile_ff.register_file_i
  `define IBEX_SHADOW_RF_PATH \
      dut.u_ibex_top.gen_lockstep.u_ibex_lockstep.gen_shadow_regfile_ff.register_file_shadow_i

  if (ICache) begin : g_dii_icache
    assign `IBEX_MAIN_CORE.if_stage_i.gen_icache.icache_i.dii_insn  = dii_if.dii_insn;
    assign `IBEX_MAIN_CORE.if_stage_i.gen_icache.icache_i.dii_valid = dii_if.dii_ready;
    assign dii_if.dii_ack = `IBEX_MAIN_CORE.if_stage_i.gen_icache.icache_i.dii_ack;
  end else begin : g_dii_fetch_fifo
    assign `IBEX_MAIN_CORE.if_stage_i.gen_prefetch_buffer.prefetch_buffer_i.fifo_i.dii_insn  =
      dii_if.dii_insn;
    assign `IBEX_MAIN_CORE.if_stage_i.gen_prefetch_buffer.prefetch_buffer_i.fifo_i.dii_valid =
      dii_if.dii_ready;
    assign dii_if.dii_ack =
      `IBEX_MAIN_CORE.if_stage_i.gen_prefetch_buffer.prefetch_buffer_i.fifo_i.dii_ack;
  end

  // SecureIbex = 1: the lockstep shadow core (ibex_lockstep.sv) has its own fetch path and gets
  // every core input LockstepOffset (here 1, ibex_top_tracing's default) cycles late. Give its
  // DII hook the same packet stream one cycle late, so it executes what the main core executes;
  // left undriven, its fetch would never be valid, every compared output would diverge and
  // alert_major_internal_o would fire on the first instruction. Its dii_ack is not used: the
  // driver paces the stream on the main core's.
  if (SecureIbex) begin : g_dii_shadow
    logic [31:0] dii_insn_q;
    logic        dii_valid_q;
    always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
        dii_insn_q  <= '0;
        dii_valid_q <= 1'b0;
      end else begin
        dii_insn_q  <= dii_if.dii_insn;
        dii_valid_q <= dii_if.dii_ready;
      end
    end
    if (ICache) begin : g_icache
      assign `IBEX_SHADOW_CORE.if_stage_i.gen_icache.icache_i.dii_insn  = dii_insn_q;
      assign `IBEX_SHADOW_CORE.if_stage_i.gen_icache.icache_i.dii_valid = dii_valid_q;
    end else begin : g_fetch_fifo
      assign `IBEX_SHADOW_CORE.if_stage_i.gen_prefetch_buffer.prefetch_buffer_i.fifo_i.dii_insn  =
        dii_insn_q;
      assign `IBEX_SHADOW_CORE.if_stage_i.gen_prefetch_buffer.prefetch_buffer_i.fifo_i.dii_valid =
        dii_valid_q;
    end
  end

  // The CHERIoT reset alignment below runs once per real reset release, with one decision for all
  // of it. rst_n starts high (see the clock/reset initial block), so X->1 at time 0 is a posedge
  // too: a force waiting on 'posedge rst_n' alone fired then, while cheriot_enable still held its
  // On default (the riscv flavour switches it Off during build), and forced the main core but not
  // the shadow core -- a lockstep mismatch at the first reset of every riscv run. So: a release
  // only counts after a falling edge, and the mode is sampled there, once, for both cores.
  bit   cheriot_reset_align;
  event reset_released;
  initial begin
    forever begin
      @(negedge rst_n);
      @(posedge rst_n);
      cheriot_reset_align = (dii_if.cheriot_enable == ibex_pkg::IbexMuBiOn);
      -> reset_released;
    end
  end

  // In CHERIoT mode the Sail model resets every GPR capability to the memory root (TM), whereas
  // the RTL resets them to null. TestRIG's CHERIoT generators rely on starting from root
  // capabilities, so bring the RTL into line after each reset. x1-x15 capability metadata lives
  // in the shared flops when CHERIoT is enabled (ibex_register_file_ff.sv).
  // Only a BaseIsaRV32IorCHERIoT core has that register file (g_cheriot_rf); a plain RV32I
  // configuration (-C small, maxperf, ...) can only run the riscv flavour, which needs no force.
  if (BaseIsa == ibex_pkg::BaseIsaRV32IorCHERIoT) begin : g_cheriot_rf_force
    for (genvar i = 1; i < 16; i++) begin : g_tb_rf_force_reset
      initial begin
        forever begin
          @(reset_released);
          if (cheriot_reset_align) begin
            force `IBEX_RF_FF_PATH.g_cheriot_rf.g_rf_shared_flops[i].rf_reg_q = cheriot_regcap_to_vec(ROOT_CAP_TM);
            @(posedge clk);
            release `IBEX_RF_FF_PATH.g_cheriot_rf.g_rf_shared_flops[i].rf_reg_q;
          end
        end
      end
    end
  end

  // The Sail model resets MEPCC's address to the boot address, the RTL to 0; both are legal.
  // Without this an mret or a MEPCC read in the first test diverges (MEPCC metadata already
  // matches). Only the address is forced.
  initial begin
    forever begin
      @(reset_released);
      if (cheriot_reset_align) begin
        force dut.u_ibex_top.u_ibex_core.cs_registers_i.u_mepc_csr.rdata_q = `BOOT_ADDR;
        @(posedge clk);
        release dut.u_ibex_top.u_ibex_core.cs_registers_i.u_mepc_csr.rdata_q;
      end
    end
  end

  // The shadow core has its own CSRs (the register file's data is shared, so the capability force
  // above reaches both cores' data; its ECC is not shared, see g_shadow_rf_ecc_force). It leaves
  // reset one cycle after the main core (rst_shadow_n); apply the same MEPC force then, or the
  // first mret / MEPCC read differs between the cores and raises the lockstep alert.
  if (SecureIbex) begin : g_shadow_mepc_force
    initial begin
      forever begin
        @(reset_released);
        wait (dut.u_ibex_top.gen_lockstep.u_ibex_lockstep.rst_shadow_n === 1'b1);
        if (cheriot_reset_align) begin
          force `IBEX_SHADOW_CORE.cs_registers_i.u_mepc_csr.rdata_q = `BOOT_ADDR;
          @(posedge clk);
          release `IBEX_SHADOW_CORE.cs_registers_i.u_mepc_csr.rdata_q;
        end
      end
    end
  end

  // The shadow core checks every x1-x15 capability it reads with SECDED over {its own 7 check bits,
  // the shared capability data}. The check bits live in the lockstep's shadow register file and
  // reset to the null capability's ECC, so forcing root capabilities into the shared flops alone
  // makes the first read of each register an ECC error in the shadow core: alert_major_internal at
  // the start of every TestRIG test. Give the shadow flops the root capability's check bits, after
  // the shadow reset (a force released while it is still in reset would be reset again).
  if (SecureIbex && BaseIsa == ibex_pkg::BaseIsaRV32IorCHERIoT) begin : g_shadow_rf_ecc_force
    logic [63:0] root_cap_ecc;
    assign root_cap_ecc =
        prim_secded_pkg::prim_secded_inv_64_57_enc({22'b0, cheriot_regcap_to_vec(ROOT_CAP_TM)});
    for (genvar i = 1; i < 16; i++) begin : g_tb_shadow_rf_force
      initial begin
        forever begin
          @(reset_released);
          wait (dut.u_ibex_top.gen_lockstep.u_ibex_lockstep.rst_shadow_n === 1'b1);
          if (cheriot_reset_align) begin
            force `IBEX_SHADOW_RF_PATH.g_cheriot_rf.g_rf_shared_flops[i].rf_reg_q =
                root_cap_ecc[63:57];
            @(posedge clk);
            release `IBEX_SHADOW_RF_PATH.g_cheriot_rf.g_rf_shared_flops[i].rf_reg_q;
          end
        end
      end
    end
  end

  // No alert may fire in a TestRIG run. Bus-integrity, register-file, PC, CSR-shadow, ICache-ECC
  // and lockstep mismatches all end up here, so this also checks the bench's own integrity
  // generation, scramble-key handshake and shadow-core feed. The one tolerated exception is a bus
  // alert in a cycle where ibex_revbm_responder injected a bitmap error on purpose (only with its
  // +revbm_err_* plusargs), as in core_ibex_tb_top.sv. +dii_intg_corrupt must make this fire.
  // A procedural check reporting a UVM_ERROR, not an SVA: testrig_vlt_build.sh does not pass
  // --assert, so Verilator would drop an assertion, and run_all_tests.sh fails a run on a non-zero
  // UVM_ERROR count from either simulator. Reported once per alert rise, not every cycle.
  // Which source raised alert_major_internal (the check below only sees the OR): reported as an
  // info when the set of active sources changes, so the cause is in the log without waves. On a
  // lockstep output mismatch the two compared output structs are printed for the first few.
  if (SecureIbex) begin : g_alert_source_diag
    string       src_q;
    int unsigned n_mismatch_dumps;
    always @(posedge clk) begin
      string src;
      src = "";
      if (dut.u_ibex_top.u_ibex_core.rf_ecc_err_comb)         src = {src, " core.rf_ecc_err"};
      if (dut.u_ibex_top.u_ibex_core.pc_mismatch_alert)       src = {src, " core.pc_mismatch"};
      if (dut.u_ibex_top.u_ibex_core.csr_shadow_err)          src = {src, " core.csr_shadow_err"};
      if (dut.u_ibex_top.u_ibex_core.cheriot_fatal_err)       src = {src, " core.cheriot_fatal"};
      if (dut.u_ibex_top.u_ibex_core.cheriot_enable_mubi_err) src = {src, " core.cheriot_enable_mubi"};
      if (dut.u_ibex_top.u_ibex_core.cheriot_disable_err)     src = {src, " core.cheriot_disable"};
      if (`IBEX_SHADOW_CORE.rf_ecc_err_comb)                  src = {src, " shadow.rf_ecc_err"};
      if (`IBEX_SHADOW_CORE.pc_mismatch_alert)                src = {src, " shadow.pc_mismatch"};
      if (`IBEX_SHADOW_CORE.csr_shadow_err)                   src = {src, " shadow.csr_shadow_err"};
      if (`IBEX_SHADOW_CORE.cheriot_fatal_err)                src = {src, " shadow.cheriot_fatal"};
      if (`IBEX_SHADOW_CORE.cheriot_enable_mubi_err)          src = {src, " shadow.cheriot_enable_mubi"};
      if (`IBEX_SHADOW_CORE.cheriot_disable_err)              src = {src, " shadow.cheriot_disable"};
      if (dut.u_ibex_top.gen_lockstep.u_ibex_lockstep.outputs_mismatch)
        src = {src, " lockstep.outputs_mismatch"};
      if (dut.u_ibex_top.gen_lockstep.u_ibex_lockstep.rst_shadow_cnt_err)
        src = {src, " lockstep.rst_shadow_cnt_err"};
      if (dut.u_ibex_top.icache_alert_major_internal)         src = {src, " icache"};
      if (src != "" && src != src_q)
        uvm_pkg::uvm_report_info("AlertSource", {"alert_major_internal source:", src},
                                 uvm_pkg::UVM_NONE);
      if (dut.u_ibex_top.gen_lockstep.u_ibex_lockstep.outputs_mismatch && src != src_q &&
          n_mismatch_dumps < 5) begin
        n_mismatch_dumps++;
        uvm_pkg::uvm_report_info("AlertSource", $sformatf("lockstep core   outputs: %p",
            dut.u_ibex_top.gen_lockstep.u_ibex_lockstep.core_outputs_q[0]), uvm_pkg::UVM_NONE);
        uvm_pkg::uvm_report_info("AlertSource", $sformatf("lockstep shadow outputs: %p",
            dut.u_ibex_top.gen_lockstep.u_ibex_lockstep.shadow_outputs_q), uvm_pkg::UVM_NONE);
      end
      src_q <= src;
    end
  end

  // The one expected internal alert: a trap taken while MTCC is untagged sets the sticky
  // cheriot_fatal_err (ibex_cs_registers.sv, "exception with invalid mepcc ... need external
  // reset"). TestRIG's random CSpecialRW writes MTCC with capabilities CHERIoT legalises to
  // untagged (e.g. without EX), so this is the RTL working as designed; TestRIG resets between
  // tests. Exempt only while cheriot_fatal_err is the sole source: any other source still fails,
  // including cheriot_disable_err (REQ_BCK_06: cheriot_enable_i left On while running), which is
  // never expected here: the flavour sets the pin during build, while the initial reset is still
  // asserted, and it must not change mid-test (core_ibex_dii_intf.sv).
  logic cheriot_fatal_only;
  logic core_other_internal;
  assign core_other_internal = dut.u_ibex_top.u_ibex_core.rf_ecc_err_comb |
                               dut.u_ibex_top.u_ibex_core.pc_mismatch_alert |
                               dut.u_ibex_top.u_ibex_core.csr_shadow_err |
                               dut.u_ibex_top.u_ibex_core.cheriot_enable_mubi_err |
                               dut.u_ibex_top.u_ibex_core.cheriot_disable_err |
                               dut.u_ibex_top.icache_alert_major_internal;
  if (SecureIbex) begin : g_fatal_only_lockstep
    assign cheriot_fatal_only =
        (dut.u_ibex_top.u_ibex_core.cheriot_fatal_err | `IBEX_SHADOW_CORE.cheriot_fatal_err) &
        ~core_other_internal &
        ~(`IBEX_SHADOW_CORE.rf_ecc_err_comb | `IBEX_SHADOW_CORE.pc_mismatch_alert |
          `IBEX_SHADOW_CORE.csr_shadow_err | `IBEX_SHADOW_CORE.cheriot_enable_mubi_err |
          `IBEX_SHADOW_CORE.cheriot_disable_err) &
        ~(dut.u_ibex_top.gen_lockstep.u_ibex_lockstep.outputs_mismatch |
          dut.u_ibex_top.gen_lockstep.u_ibex_lockstep.rst_shadow_cnt_err);
  end else begin : g_fatal_only_single
    assign cheriot_fatal_only = dut.u_ibex_top.u_ibex_core.cheriot_fatal_err & ~core_other_internal;
  end
  int unsigned n_fatal_untagged_mtcc;
  logic        fatal_only_q;
  always @(posedge clk) begin
    if (cheriot_fatal_only && !fatal_only_q) n_fatal_untagged_mtcc++;
    fatal_only_q <= cheriot_fatal_only;
  end
  final if (n_fatal_untagged_mtcc != 0)
    $display("NoAlertsTriggered: %0d expected cheriot_fatal_err alert(s) (trap with untagged MTCC)",
             n_fatal_untagged_mtcc);

  logic alert_seen_q;
  always @(posedge clk or negedge rst_n) begin : NoAlertsTriggered_A
    logic alert_now;
    if (!rst_n) begin
      alert_seen_q <= 1'b0;
    end else begin
      alert_now = alert_minor || (alert_major_internal && !cheriot_fatal_only) ||
                  (alert_major_bus && !revbm_inj_err);
      if (alert_now && !alert_seen_q) begin
        uvm_pkg::uvm_report_error("NoAlertsTriggered",
          $sformatf("core alert raised: minor=%b major_internal=%b major_bus=%b", alert_minor,
                    alert_major_internal, alert_major_bus));
      end
      alert_seen_q <= alert_now;
    end
  end

  initial begin
    // clk_rst_if starts its clock on `@set_active_called`, which set_active() triggers. Initial
    // blocks at time 0 run in an unspecified order: if this one runs first the event is missed and
    // the clock never starts (Xcelium happens to order it the other way; Verilator does not). #0
    // lets every other time-0 initial block reach its wait before the event fires.
    #0;
    clk_if.set_active();
    // Start rst_n high so the power-on reset is a real 1->0 edge. clk_rst_if leaves o_rst_n
    // uninitialised: X on Xcelium, where X->0 counts as a negedge, but 0 on two-state Verilator,
    // where apply_reset's 0 is no edge at all. The core's async-reset flops then never reset, PCC
    // stays zero and every fetch of the first test faults (only between-test resets worked).
    clk_if.drive_rst_pin(1'b1);

    fork
      clk_if.apply_reset(.reset_width_clks(10));
    join_none

    uvm_config_db#(virtual clk_rst_if)::set(null, "*", "clk_if", clk_if);
    uvm_config_db#(virtual core_ibex_dii_intf)::set(null, "*", "dii_if", dii_if);
    uvm_config_db#(virtual core_ibex_rvfi_if)::set(null, "*", "rvfi_if", rvfi_if);
    // For the RISC-V Sail scoreboard, which configures the model's PMP to match the core.
    uvm_config_db#(int)::set(null, "*", "pmp_num_regions", PMPEnable ? int'(PMPNumRegions) : 0);
    uvm_config_db#(int)::set(null, "*", "pmp_granularity", int'(PMPGranularity));

    run_test();
  end

  // -------------------------------------------------------------------------
  // X-propagation checks: one per signal so the message names the origin.
  // -------------------------------------------------------------------------

  DataWeX_A   : assert property (@(posedge clk) disable iff (!rst_n)
    data_req |-> !$isunknown(data_we))
    else $error("[X-check] data_we is X/Z while data_req");
  DataBeX_A   : assert property (@(posedge clk) disable iff (!rst_n)
    data_req |-> !$isunknown(data_be))
    else $error("[X-check] data_be is X/Z while data_req");
  DataAddrX_A : assert property (@(posedge clk) disable iff (!rst_n)
    data_req |-> !$isunknown(data_addr))
    else $error("[X-check] data_addr is X/Z while data_req");
  // Ibex legitimately leaves data_wdata_o X on loads, so only stores are checked.
  DataWdataX_A : assert property (@(posedge clk) disable iff (!rst_n)
    (data_req && data_we) |-> !$isunknown(data_wdata))
    else $error("[X-check] data_wdata is X/Z on a store request (addr=0x%08h)", data_addr);

  // Store responses are ignored by ibex, so only load responses are checked.
  DataRdataX_A : assert property (@(posedge clk) disable iff (!rst_n)
    (data_rvalid && !data_err && !data_we_q) |-> !$isunknown(data_rdata))
    else $error("[X-check] data_rdata is X/Z on a valid load response, addr was 0x%08h",
      data_addr_q);

  RvfiPcRdataX_A : assert property (@(posedge clk) disable iff (!rst_n)
    dut.rvfi_valid |-> !$isunknown(dut.rvfi_pc_rdata))
    else $error("[X-check] rvfi_pc_rdata is X/Z on retirement");
  RvfiPcWdataX_A : assert property (@(posedge clk) disable iff (!rst_n)
    dut.rvfi_valid |-> !$isunknown(dut.rvfi_pc_wdata))
    else $error("[X-check] rvfi_pc_wdata is X/Z on retirement");
  RvfiRs1X_A : assert property (@(posedge clk) disable iff (!rst_n)
    dut.rvfi_valid |-> !$isunknown(dut.rvfi_rs1_rdata))
    else $error("[X-check] rvfi_rs1_rdata is X/Z on retirement");
  RvfiRs2X_A : assert property (@(posedge clk) disable iff (!rst_n)
    dut.rvfi_valid |-> !$isunknown(dut.rvfi_rs2_rdata))
    else $error("[X-check] rvfi_rs2_rdata is X/Z on retirement");
  RvfiRdWdataX_A : assert property (@(posedge clk) disable iff (!rst_n)
    (dut.rvfi_valid && dut.rvfi_rd_addr != '0) |-> !$isunknown(dut.rvfi_rd_wdata))
    else $error("[X-check] rvfi_rd_wdata is X/Z on retirement (rd != x0)");

  DiiAckX_A   : assert property (@(posedge clk) disable iff (!rst_n)
    !$isunknown(dii_if.dii_ack))
    else $error("[X-check] dii_ack is X/Z");
  InstrGntX_A : assert property (@(posedge clk) disable iff (!rst_n)
    instr_req |-> !$isunknown(instr_gnt))
    else $error("[X-check] instr_gnt is X/Z while instr_req");

endmodule
