// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

`include "prim_assert.sv"
`include "core_ibex_csr_categories.svh"

interface core_ibex_fcov_if import ibex_pkg::*, ibex_cheriot_pkg::*; #(
    // The fetch FIFO coverpoints probe ibex_prefetch_buffer, which ibex_if_stage only
    // instantiates when ICache == 0. The bind passes ibex_core's ICache through.
    parameter bit ICache = 1'b0,
    // With the branch target ALU jumps never stall in ID; the bind passes ibex_core's value
    parameter bit BranchTargetALU = 1'b0,
    // Which configuration this core is: with BaseIsaRV32IorCHERIoT ibex_top puts TRVK between
    // ibex_core and the data bus and ibex_core has the cheriot_disable_err alert latch; with
    // BaseIsaRV32I neither exists. The bind should pass ibex_core's BaseIsa through; the default
    // is the configuration this bench builds (opentitan, TestRIG).
    parameter base_isa_e BaseIsa = BaseIsaRV32IorCHERIoT
) (
  input clk_i,
  input rst_ni,

  input priv_lvl_e priv_mode_id,
  input priv_lvl_e priv_mode_lsu,

  input debug_mode,

  input fcov_csr_read_only,
  input fcov_csr_write,

  input fcov_rf_ecc_err_a_id,
  input fcov_rf_ecc_err_b_id,

  input ibex_mubi_t fetch_enable_i,

  input instr_req_o,
  input instr_gnt_i,
  input instr_rvalid_i,

  input data_req_o,
  input data_gnt_i,
  input data_rvalid_i,

  // CHERIoT-specific ports (connected via bind .* from ibex_core internals)
  input ibex_mubi_t          cheriot_enable_i,
  input logic [31:0]         branch_target_ex,
  input cheriot_op_t            cheriot_operator,
  // REQ_BCK_06 alert latch (ibex_core.sv gen_cheriot_enable_check); tied to 0 in RV32I configs
  input logic                cheriot_disable_err
);
  `include "dv_fcov_macros.svh"
  import uvm_pkg::*;

  localparam bit CheriotIsa = (BaseIsa == BaseIsaRV32IorCHERIoT);
  // cp_obi_handshake value {0, req, gnt} that this configuration cannot produce: gnt without req
  // with TRVK in front of the core, else the 3-bit value no bin lists (see the coverpoint)
  localparam logic [2:0] GntNoReqUnreach = CheriotIsa ? 3'b001 : 3'b100;

  typedef enum {
    InstrCategoryALU,
    InstrCategoryMul,
    InstrCategoryDiv,
    InstrCategoryBranch,
    InstrCategoryJump,
    InstrCategoryLoad,
    InstrCategoryStore,
    InstrCategoryCSRAccess,
    InstrCategoryEBreakDbg,
    InstrCategoryEBreakExc,
    InstrCategoryECall,
    InstrCategoryMRet,
    InstrCategoryDRet,
    InstrCategoryWFI,
    InstrCategoryFence,
    InstrCategoryFenceI,
    InstrCategoryCheri,
    InstrCategoryNone,
    InstrCategoryFetchError,
    InstrCategoryCompressedIllegal,
    InstrCategoryUncompressedIllegal,
    InstrCategoryCSRIllegal,
    InstrCategoryPrivIllegal,
    InstrCategoryOtherIllegal,
    // Category not in coverage plan, it should never be seen. An instruction given the Other
    // category should either be classified under an existing category or a new category should be
    // created as appropriate.
    InstrCategoryOther
  } instr_category_e;

  typedef enum {
    IdStallTypeNone,
    IdStallTypeInstr,
    IdStallTypeLdHz,
    IdStallTypeMem
  } id_stall_type_e;

  instr_category_e id_instr_category, wb_instr_category, id_instr_category_q;
  // Set `id_instr_category` to the appropriate category for the uncompressed instruction in the
  // ID/EX stage.  Compressed instructions are not handled (`id_stage_i.instr_rdata_i` is always
  // uncompressed).  When the `id_stage.instr_valid_i` isn't set `InstrCategoryNone` is the given
  // instruction category.
  always_comb begin
    id_instr_category = InstrCategoryOther;

    case (id_stage_i.instr_rdata_i[6:0])
      ibex_pkg::OPCODE_LUI:    id_instr_category = InstrCategoryALU;
      ibex_pkg::OPCODE_AUIPC:  id_instr_category = InstrCategoryALU;
      ibex_pkg::OPCODE_JAL:    id_instr_category = InstrCategoryJump;
      ibex_pkg::OPCODE_JALR:   id_instr_category = InstrCategoryJump;
      ibex_pkg::OPCODE_BRANCH: id_instr_category = InstrCategoryBranch;
      ibex_pkg::OPCODE_LOAD:   id_instr_category = InstrCategoryLoad;
      ibex_pkg::OPCODE_STORE:  id_instr_category = InstrCategoryStore;
      ibex_pkg::OPCODE_OP_IMM: id_instr_category = InstrCategoryALU;
      ibex_pkg::OPCODE_OP: begin
        if ({id_stage_i.instr_rdata_i[26], id_stage_i.instr_rdata_i[13:12]} == {1'b1, 2'b01}) begin
          id_instr_category = InstrCategoryALU; // reg-reg/reg-imm ops
        end else if (id_stage_i.instr_rdata_i[31:25] inside {7'b000_0000, 7'b010_0000, 7'b011_0000,
              7'b011_0100, 7'b001_0100, 7'b001_0000, 7'b000_0101, 7'b000_0100, 7'b010_0100}) begin
          id_instr_category = InstrCategoryALU; // RV32I and RV32B reg-reg/reg-imm ops
        end else if (id_stage_i.instr_rdata_i[31:25] == 7'b000_0001) begin
          if (id_stage_i.instr_rdata_i[14]) begin
            id_instr_category = InstrCategoryDiv; // DIV*
          end else begin
            id_instr_category = InstrCategoryMul; // MUL*
          end
        end
      end
      ibex_pkg::OPCODE_SYSTEM: begin
        if (id_stage_i.instr_rdata_i[14:12] == 3'b000) begin
          case (id_stage_i.instr_rdata_i[31:20])
            12'h000: id_instr_category = InstrCategoryECall;
            12'h001: begin
              if (id_stage_i.debug_ebreakm_i && priv_mode_id == PRIV_LVL_M) begin
                id_instr_category = InstrCategoryEBreakDbg;
              end else if (id_stage_i.debug_ebreaku_i && priv_mode_id == PRIV_LVL_U) begin
                id_instr_category = InstrCategoryEBreakDbg;
              end else begin
                id_instr_category = InstrCategoryEBreakExc;
              end
            end
            12'h302: id_instr_category = InstrCategoryMRet;
            12'h7b2: id_instr_category = InstrCategoryDRet;
            12'h105: id_instr_category = InstrCategoryWFI;
          endcase
        end else begin
          id_instr_category = InstrCategoryCSRAccess;
        end
      end
      ibex_pkg::OPCODE_MISC_MEM: begin
        case (id_stage_i.instr_rdata_i[14:12])
          3'b000: id_instr_category = InstrCategoryFence;
          3'b001: id_instr_category = InstrCategoryFenceI;
        endcase
      end
      // CHERIoT custom encodings. Without this branch every CHERI instruction
      // fell through to InstrCategoryOther, which is an illegal_bin, so Xcelium
      // raised *E,EILLEN on each one (32-60 per directed test).
      ibex_pkg::OPCODE_CHERI:  id_instr_category = InstrCategoryCheri;
      ibex_pkg::OPCODE_AUICGP: id_instr_category = InstrCategoryCheri;
      default: id_instr_category = InstrCategoryOther;
    endcase

    if (id_stage_i.instr_valid_i) begin
      if (id_stage_i.instr_fetch_err_i) begin
        id_instr_category = InstrCategoryFetchError;
      end else if (id_stage_i.illegal_c_insn_i) begin
        id_instr_category = InstrCategoryCompressedIllegal;
      end else if (id_stage_i.illegal_insn_dec) begin
        id_instr_category = InstrCategoryUncompressedIllegal;
      end else if (id_stage_i.illegal_csr_insn_i) begin
        if (cs_registers_i.illegal_csr_priv || cs_registers_i.illegal_csr_dbg) begin
          id_instr_category = InstrCategoryPrivIllegal;
        end else begin
          id_instr_category = InstrCategoryCSRIllegal;
        end
      end else if (id_stage_i.illegal_insn_o) begin
        if (id_stage_i.illegal_dret_insn || id_stage_i.illegal_umode_insn) begin
          id_instr_category = InstrCategoryPrivIllegal;
        end else begin
          id_instr_category = InstrCategoryOtherIllegal;
        end
      end
    end else begin
      id_instr_category = InstrCategoryNone;
    end
  end

  // Registered pipeline snapshots used by instr_error_sequence crosses.
  // fcov_id_exc_int[1] = handle_irq, [0] = special_req_pc_change (exception/mret/dret/trap).
  logic [1:0] fcov_id_exc_int, fcov_id_exc_int_q;
  assign fcov_id_exc_int = {id_stage_i.controller_i.handle_irq,
                             id_stage_i.controller_i.special_req_pc_change};

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wb_instr_category   <= InstrCategoryNone;
      id_instr_category_q <= InstrCategoryNone;
      fcov_id_exc_int_q   <= 2'b0;
    end else begin
      wb_instr_category <= id_instr_category;
      if (id_stage_i.instr_done | id_stage_i.gen_stall_mem.instr_kill) begin
        id_instr_category_q <= id_instr_category;
        fcov_id_exc_int_q   <= fcov_id_exc_int;
      end
    end
  end

  // Check instruction categories calculated from instruction bits match what decoder has produced.

  // The ALU category is tricky as there's no specific ALU enable and instructions that actively use
  // the result of the ALU but aren't themselves ALU operations (such as load/store and JALR). This
  // categorizes anything that selects the ALU as the source of register write data and enables
  // register writes minus some exclusions as an ALU operation.
  `ASSERT(InstrCategoryALUCorrect, id_instr_category == InstrCategoryALU |->
      (id_stage_i.rf_wdata_sel == RF_WD_EX) && id_stage_i.rf_we_dec && ~id_stage_i.mult_sel_ex_o &&
      ~id_stage_i.div_sel_ex_o && ~id_stage_i.lsu_req_dec && ~id_stage_i.jump_in_dec)

  `ASSERT(InstrCategoryMulCorrect,
      id_instr_category == InstrCategoryMul |-> id_stage_i.mult_sel_ex_o)

  `ASSERT(InstrCategoryDivCorrect,
      id_instr_category == InstrCategoryDiv |-> id_stage_i.div_sel_ex_o)

  `ASSERT(InstrCategoryBranchCorrect,
      id_instr_category == InstrCategoryBranch |-> id_stage_i.branch_in_dec)

  `ASSERT(InstrCategoryJumpCorrect,
      id_instr_category == InstrCategoryJump |->
          id_stage_i.jump_in_dec || id_stage_i.instr_is_cheriot_id_o)

  `ASSERT(InstrCategoryLoadCorrect,
      id_instr_category == InstrCategoryLoad |->
          (id_stage_i.lsu_req_dec || id_stage_i.cheriot_lsu_req_dec) && !id_stage_i.lsu_we)

  `ASSERT(InstrCategoryStoreCorrect,
      id_instr_category == InstrCategoryStore |->
          (id_stage_i.lsu_req_dec || id_stage_i.cheriot_lsu_req_dec) && id_stage_i.lsu_we)

  `ASSERT(InstrCategoryCSRAccessCorrect,
      id_instr_category == InstrCategoryCSRAccess |-> id_stage_i.csr_access_o)
  `ASSERT(InstrCategoryEBreakDbgCorrect, id_instr_category == InstrCategoryEBreakDbg |->
      id_stage_i.ebrk_insn && id_stage_i.controller_i.ebreak_into_debug)

  `ASSERT(InstrCategoryEBreakExcCorrect, id_instr_category == InstrCategoryEBreakExc |->
      id_stage_i.ebrk_insn && !id_stage_i.controller_i.ebreak_into_debug)

  `ASSERT(InstrCategoryECallCorrect,
      id_instr_category == InstrCategoryECall |-> id_stage_i.ecall_insn_dec)

  `ASSERT(InstrCategoryMRetCorrect,
      id_instr_category == InstrCategoryMRet |-> id_stage_i.mret_insn_dec)

  `ASSERT(InstrCategoryDRetCorrect,
      id_instr_category == InstrCategoryDRet |-> id_stage_i.dret_insn_dec)

  `ASSERT(InstrCategoryWFICorrect,
      id_instr_category == InstrCategoryWFI |-> id_stage_i.wfi_insn_dec)

  `ASSERT(InstrCategoryFenceICorrect,
      id_instr_category == InstrCategoryFenceI && id_stage_i.instr_first_cycle |->
      id_stage_i.icache_inval_o)



  id_stall_type_e id_stall_type;

  // Set `id_stall_type` to the appropriate type based on signals in the ID/EX stage
  always_comb begin
    id_stall_type = IdStallTypeNone;

    if (id_stage_i.instr_valid_i) begin
      if (id_stage_i.stall_mem) begin
        id_stall_type = IdStallTypeMem;
      end

      if (id_stage_i.stall_ld_hz) begin
        id_stall_type = IdStallTypeLdHz;
      end

      if (id_stage_i.stall_multdiv || id_stage_i.stall_branch ||
          id_stage_i.stall_jump) begin
        id_stall_type = IdStallTypeInstr;
      end
    end
  end

  // IF specific state enum
  typedef enum {
    IFStageFullAndFetching,
    IFStageFullAndIdle,
    IFStageEmptyAndFetching,
    IFStageEmptyAndIdle
  } if_stage_state_e;

  // ID/EX and WB have the same state enum
  typedef enum {
    PipeStageFullAndStalled,
    PipeStageFullAndUnstalled,
    PipeStageEmpty
  } pipe_stage_state_e;

  if_stage_state_e   if_stage_state;
  pipe_stage_state_e id_stage_state;
  pipe_stage_state_e wb_stage_state;

  always_comb begin
    if_stage_state = IFStageEmptyAndIdle;

    if (if_stage_i.if_instr_valid) begin
      if (if_stage_i.req_i) begin
        if_stage_state = IFStageFullAndFetching;
      end else begin
        if_stage_state = IFStageFullAndIdle;
      end
    end else if(if_stage_i.req_i) begin
      if_stage_state = IFStageEmptyAndFetching;
    end
  end

  always_comb begin
    id_stage_state = PipeStageEmpty;

    if (id_stage_i.instr_valid_i) begin
      if (id_stage_i.id_in_ready_o) begin
        id_stage_state = PipeStageFullAndUnstalled;
      end else begin
        id_stage_state = PipeStageFullAndStalled;
      end
    end
  end

  always_comb begin
    wb_stage_state = PipeStageEmpty;

    if (wb_stage_i.fcov_wb_valid) begin
      if (wb_stage_i.ready_wb_o) begin
        wb_stage_state = PipeStageFullAndUnstalled;
      end else begin
        wb_stage_state = PipeStageFullAndStalled;
      end
    end
  end

  // This latch is needed because if we cannot register this condition being true
  // with a clock. Being in the sleep mode implies that we don't have an active clock.
  // So, we need to catch the condition, latch it and keep it until we wake up and decode
  // an instruction (which guarantees we have a clock in the core)
  logic kept_wfi_with_irq;

  always_latch begin
    if (id_stage_i.controller_i.ctrl_fsm_cs == DECODE) begin
      kept_wfi_with_irq = 1'b0;
    end else if (id_stage_i.controller_i.ctrl_fsm_cs == SLEEP &&
                 id_stage_i.controller_i.ctrl_fsm_ns == SLEEP &&
                 (|cs_registers_i.mip)) begin
      kept_wfi_with_irq = 1'b1;
    end
  end

  logic instr_id_matches_trigger_d, instr_id_matches_trigger_q;

  assign instr_id_matches_trigger_d = id_stage_i.controller_i.trigger_match_i &&
                                      id_stage_i.controller_i.fcov_debug_entry_if;

  // Delay instruction matching trigger point since it is cached in IF stage.
  // We would want to cross it with decoded instruction categories and it does not matter
  // when exactly we are hitting the condition.
  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      instr_id_matches_trigger_q <= 1'b0;
    end else begin
      instr_id_matches_trigger_q <= instr_id_matches_trigger_d;
    end
  end

  // Keep track of previous data addr of Store to catch RAW hazard caused by STORE->LOAD
  logic [31:0]     prev_store_addr;
  logic [31:0]     data_addr_incr;
  logic [31:0]     curr_data_addr;
  logic            raw_hz;

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      prev_store_addr <= 1'b0;
    end else if (load_store_unit_i.data_we_o) begin
      // It does not matter if the store we executed before load is misaligned or not. Because
      // even if it is misaligned, we would catch the "corrected" version (2nd access) before
      // doing the RAW hazard check.
      prev_store_addr <= load_store_unit_i.data_addr_o;
    end
  end

  // Calculate the corrected version of the new data addr at the same time while LOAD instruction
  // gets decoded.
  always_comb begin
    if (load_store_unit_i.split_misaligned_access) begin
      data_addr_incr = load_store_unit_i.data_addr + 4;
      curr_data_addr = {data_addr_incr[2+:30],2'b00};
    end else begin
      curr_data_addr = load_store_unit_i.data_addr;
    end
  end

  // If we have LOAD at ID/EX stage and STORE at WB stage, compare the calculated address for LOAD
  // and the saved STORE address. If they are matching we would have RAW hazard.
  assign raw_hz = wb_stage_i.outstanding_store_wb_o &&
                  id_instr_category == InstrCategoryLoad &&
                  prev_store_addr == curr_data_addr;

  // Collect all the interrupts for collecting them in different bins.
  logic [5:0] fcov_irqs;

  assign fcov_irqs = {id_stage_i.controller_i.irq_nm_ext_i,
                      id_stage_i.controller_i.irq_nm_int,
                      (|id_stage_i.controller_i.irqs_i.irq_fast),
                      id_stage_i.controller_i.irqs_i.irq_external,
                      id_stage_i.controller_i.irqs_i.irq_software,
                      id_stage_i.controller_i.irqs_i.irq_timer};

  logic            instr_unstalled;
  logic            instr_unstalled_last;
  logic            id_stall_type_last_valid;
  id_stall_type_e  id_stall_type_last;
  instr_category_e id_instr_category_last;

  // Keep track of previous values for some signals. These are used for some of the crosses relating
  // to exception and debug entry. We want to cross different instruction categories and stalling
  // behaviour with exception and debug entry but signals indicating entry occur a cycle after the
  // relevant information is flushed from the pipeline.
  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      // First cycle out of reset there is no last stall, use valid bit to deal with this case
      id_stall_type_last_valid <= 1'b0;
      id_stall_type_last       <= IdStallTypeNone;
      instr_unstalled_last     <= 1'b0;
      id_instr_category_last   <= InstrCategoryNone;
    end else begin
      id_stall_type_last_valid <= 1'b1;
      id_stall_type_last       <= id_stall_type;
      instr_unstalled_last     <= instr_unstalled;
      id_instr_category_last   <= id_instr_category;
    end
  end

  assign instr_unstalled =
    (id_stall_type == IdStallTypeNone) && (id_stall_type_last != IdStallTypeNone) &&
    id_stall_type_last_valid;

  // V2S Related Probes for Top-Level
  logic rf_glitch_err;
  logic lockstep_glitch_err;
  // Register-file ECC errors as the lockstep shadow core detects them (gen_regfile_ecc
  // rf_ecc_err_*_id & instr_valid_id), driven by core_ibex_tb_top.sv when SecureIbex = 1
  logic rf_ecc_err_a_shdw;
  logic rf_ecc_err_b_shdw;

  logic imem_single_cycle_response, dmem_single_cycle_response;

  mem_monitor_if iside_mem_monitor(
    .clk_i,
    .rst_ni,
    .req_i(instr_req_o),
    .gnt_i(instr_gnt_i),
    .rvalid_i(instr_rvalid_i),
    .outstanding_requests_o(),
    .single_cycle_response_o(imem_single_cycle_response)
  );

  mem_monitor_if dside_mem_monitor(
    .clk_i,
    .rst_ni,
    .req_i(data_req_o),
    .gnt_i(data_gnt_i),
    .rvalid_i(data_rvalid_i),
    .outstanding_requests_o(),
    .single_cycle_response_o(dmem_single_cycle_response)
  );

  // Fetch FIFO probes (ibex_fetch_fifo inside ibex_prefetch_buffer). The prefetch buffer only
  // exists when ICache == 0; with the icache these probes read 0 and the cp_fetch_* coverpoints
  // below stay unhit. valid_q is [NUM_REQS:0] with the prefetch buffer's NUM_REQS = 2.
  logic [2:0] fcov_fifo_valid_q;           // entry occupancy, thermometer from entry 0
  logic       fcov_fifo_in_valid;          // fetch response pushed/bypassed this cycle
  logic       fcov_fifo_clear;             // FIFO flushed (IF redirect)
  logic       fcov_fifo_pop;               // entry 0 shifted out
  logic       fcov_fifo_out_taken;         // instruction handed to IF and not flushed
  logic       fcov_fifo_out_unaligned;     // handed-out instruction starts at PC[1] == 1
  logic       fcov_fifo_unaligned_is_c;    // FIFO treats the unaligned half-word as 16-bit

  if (!ICache) begin : g_fcov_fetch_fifo
    assign fcov_fifo_valid_q        =
      if_stage_i.gen_prefetch_buffer.prefetch_buffer_i.fifo_i.valid_q;
    assign fcov_fifo_in_valid       =
      if_stage_i.gen_prefetch_buffer.prefetch_buffer_i.fifo_i.in_valid_i;
    assign fcov_fifo_clear          =
      if_stage_i.gen_prefetch_buffer.prefetch_buffer_i.fifo_i.clear_i;
    assign fcov_fifo_pop            =
      if_stage_i.gen_prefetch_buffer.prefetch_buffer_i.fifo_i.pop_fifo;
    assign fcov_fifo_out_taken      =
      if_stage_i.gen_prefetch_buffer.prefetch_buffer_i.fifo_i.out_valid_o &
      if_stage_i.gen_prefetch_buffer.prefetch_buffer_i.fifo_i.out_ready_i &
      ~if_stage_i.gen_prefetch_buffer.prefetch_buffer_i.fifo_i.clear_i;
    assign fcov_fifo_out_unaligned  =
      if_stage_i.gen_prefetch_buffer.prefetch_buffer_i.fifo_i.out_addr_o[1];
    assign fcov_fifo_unaligned_is_c =
      if_stage_i.gen_prefetch_buffer.prefetch_buffer_i.fifo_i.unaligned_is_compressed;
  end else begin : g_no_fcov_fetch_fifo
    assign fcov_fifo_valid_q        = '0;
    assign fcov_fifo_in_valid       = 1'b0;
    assign fcov_fifo_clear          = 1'b0;
    assign fcov_fifo_pop            = 1'b0;
    assign fcov_fifo_out_taken      = 1'b0;
    assign fcov_fifo_out_unaligned  = 1'b0;
    assign fcov_fifo_unaligned_is_c = 1'b0;
  end

  // Categories that can never see an Instr stall with BranchTargetALU; without it they select
  // InstrCategoryOther, which is already an illegal bin of cp_id_instr_category
  localparam instr_category_e JumpBtalu   = BranchTargetALU ? InstrCategoryJump   : InstrCategoryOther;
  localparam instr_category_e FenceIBtalu = BranchTargetALU ? InstrCategoryFenceI : InstrCategoryOther;

  covergroup uarch_cg @(posedge clk_i);
    option.per_instance = 1;
    option.name = "uarch_cg";

    cp_id_instr_category: coverpoint id_instr_category {
      // Not certain if InstrCategoryOtherIllegal can occur. Put it in illegal_bins for now and
      // revisit if any issues are seen
      illegal_bins illegal = {InstrCategoryOther, InstrCategoryOtherIllegal};
    }

    cp_id_instr_category_last: coverpoint id_instr_category_last {
      // Not certain if InstrCategoryOtherIllegal can occur. Put it in illegal_bins for now and
      // revisit if any issues are seen
      illegal_bins illegal = {InstrCategoryOther, InstrCategoryOtherIllegal};
    }

    cp_stall_type_id: coverpoint id_stall_type;

    cp_wb_reg_no_load_hz: coverpoint id_stage_i.fcov_rf_rd_wb_hz &&
                                     !wb_stage_i.outstanding_load_wb_o;

    cp_mem_raw_hz: coverpoint raw_hz;

    cp_mprv: coverpoint cs_registers_i.mstatus_q.mprv;

    // Qualified the way the core qualifies the LSU error (ibex_core.sv g_check_mem_response,
    // lsu_resp_err): with SecureIbex the bench's spurious d-side responses carry a random error
    // bit the core drops, and counting them filled bins a real error cannot reach
    cp_ls_error_exception: coverpoint load_store_unit_i.fcov_ls_error_exception &
                                      wb_stage_i.lsu_resp_err_i;
    cp_ls_pmp_exception: coverpoint load_store_unit_i.fcov_ls_pmp_exception;

    cp_branch_taken: coverpoint id_stage_i.fcov_branch_taken;
    cp_branch_not_taken: coverpoint id_stage_i.fcov_branch_not_taken;

    cp_priv_mode_id: coverpoint priv_mode_id {
      illegal_bins illegal = {PRIV_LVL_H, PRIV_LVL_S};
    }
    cp_priv_mode_lsu: coverpoint priv_mode_lsu {
      illegal_bins illegal = {PRIV_LVL_H, PRIV_LVL_S};
    }

    cp_if_stage_state : coverpoint if_stage_state;
    cp_id_stage_state : coverpoint id_stage_state;
    cp_wb_stage_state : coverpoint wb_stage_state;

    // V2S Coverpoints
    cp_data_ind_timing: coverpoint cs_registers_i.data_ind_timing_o;
    cp_data_ind_timing_instr: coverpoint id_instr_category iff (cs_registers_i.data_ind_timing_o) {
      // Not certain if InstrCategoryOtherIllegal can occur. Put it in illegal_bins for now and
      // revisit if any issues are seen
      illegal_bins illegal = {InstrCategoryOther, InstrCategoryOtherIllegal};
    }

    cp_dummy_instr_en: coverpoint cs_registers_i.dummy_instr_en_o;
    cp_dummy_instr_mask: coverpoint cs_registers_i.dummy_instr_mask_o;
    cp_dummy_instr_type: coverpoint if_stage_i.fcov_dummy_instr_type;
    cp_dummy_instr: coverpoint id_instr_category iff (cs_registers_i.dummy_instr_en_o) {
      // Not certain if InstrCategoryOtherIllegal can occur. Put it in illegal_bins for now and
      // revisit if any issues are seen
      illegal_bins illegal = {InstrCategoryOther, InstrCategoryOtherIllegal};
    }

    // Each stage sees a dummy instruction.
    cp_dummy_instr_if_stage: coverpoint if_stage_i.fcov_insert_dummy_instr;
    cp_dummy_instr_id_stage: coverpoint if_stage_i.dummy_instr_id_o;
    cp_dummy_instr_wb_stage: coverpoint wb_stage_i.dummy_instr_wb_o;

    // The main core is built with RegFileECC = 0 (ibex_top.sv), so its fcov_rf_ecc_err_*_id are
    // tied to 0; the register-file ECC check runs in the lockstep shadow core only, where fcov is
    // off. core_ibex_tb_top.sv drives these probes from the shadow core (see rf_ecc_err_a_shdw).
    `DV_FCOV_EXPR_SEEN(rf_a_ecc_err, rf_ecc_err_a_shdw)
    `DV_FCOV_EXPR_SEEN(rf_b_ecc_err, rf_ecc_err_b_shdw)

    `DV_FCOV_EXPR_SEEN(icache_ecc_err, if_stage_i.icache_ecc_error_o)

    `DV_FCOV_EXPR_SEEN(mem_load_ecc_err, load_store_unit_i.load_resp_intg_err_o)
    `DV_FCOV_EXPR_SEEN(mem_store_ecc_err, load_store_unit_i.store_resp_intg_err_o)

    `DV_FCOV_EXPR_SEEN(lockstep_err, lockstep_glitch_err)
    `DV_FCOV_EXPR_SEEN(rf_glitch_err, rf_glitch_err)
    `DV_FCOV_EXPR_SEEN(pc_mismatch_err, if_stage_i.pc_mismatch_alert_o)

    cp_fetch_enable: coverpoint fetch_enable_i {
      bins fetch_on    = {IbexMuBiOn};
      bins fetch_off   = {IbexMuBiOff};
      bins fetch_inval = default;
    }

    // TODO: MRET/WFI in debug mode?
    // Specific cover points for these as `id_instr_category` will be InstrCategoryPrivIllegal when
    // executing these instructions in U-mode.
    `DV_FCOV_EXPR_SEEN(mret_in_umode, id_stage_i.mret_insn_dec && priv_mode_id == PRIV_LVL_U)
    `DV_FCOV_EXPR_SEEN(wfi_in_umode, id_stage_i.wfi_insn_dec && priv_mode_id == PRIV_LVL_U)

    // Unsupported writes to WARL type CSRs
    `DV_FCOV_EXPR_SEEN(warl_check_mstatus,
                       fcov_csr_write &&
                       (cs_registers_i.u_mstatus_csr.wr_data_i !=
                       cs_registers_i.csr_wdata_int))

    `DV_FCOV_EXPR_SEEN(warl_check_mie,
                       fcov_csr_write &&
                       (cs_registers_i.u_mie_csr.wr_data_i !=
                       cs_registers_i.csr_wdata_int))

    `DV_FCOV_EXPR_SEEN(warl_check_mtvec,
                       fcov_csr_write &&
                       (cs_registers_i.u_mtvec_csr.wr_data_i !=
                       cs_registers_i.csr_wdata_int))

    `DV_FCOV_EXPR_SEEN(warl_check_mepc,
                       fcov_csr_write &&
                       (cs_registers_i.u_mepc_csr.wr_data_i !=
                       cs_registers_i.csr_wdata_int))

    `DV_FCOV_EXPR_SEEN(warl_check_mtval,
                       fcov_csr_write &&
                       (cs_registers_i.u_mtval_csr.wr_data_i !=
                       cs_registers_i.csr_wdata_int))

    `DV_FCOV_EXPR_SEEN(warl_check_dcsr,
                       fcov_csr_write &&
                       (cs_registers_i.u_dcsr_csr.wr_data_i !=
                       cs_registers_i.csr_wdata_int))

    `DV_FCOV_EXPR_SEEN(warl_check_cpuctrl,
                       fcov_csr_write &&
                       (cs_registers_i.u_cpuctrlsts_part_csr.wr_data_i !=
                       cs_registers_i.csr_wdata_int))

    `DV_FCOV_EXPR_SEEN(double_fault, cs_registers_i.cpuctrlsts_part_d.double_fault_seen)
    `DV_FCOV_EXPR_SEEN(icache_enable, cs_registers_i.cpuctrlsts_part_d.icache_enable)

    cp_irq_pending: coverpoint id_stage_i.irq_pending_i | id_stage_i.irq_nm_i;
    cp_debug_req: coverpoint id_stage_i.controller_i.fcov_debug_req;

    cp_csr_read_only: coverpoint cs_registers_i.csr_addr_i iff (fcov_csr_read_only) {
      ignore_bins ignore = {`IGNORED_CSRS};
    }

    cp_csr_write: coverpoint cs_registers_i.csr_addr_i iff (fcov_csr_write) {
      ignore_bins ignore = {`IGNORED_CSRS};
    }

    `DV_FCOV_EXPR_SEEN(csr_invalid_read_only, fcov_csr_read_only && cs_registers_i.illegal_csr)
    `DV_FCOV_EXPR_SEEN(csr_invalid_write, fcov_csr_write && cs_registers_i.illegal_csr)

    cp_debug_mode: coverpoint debug_mode;

    `DV_FCOV_EXPR_SEEN(debug_wakeup, id_stage_i.controller_i.fcov_debug_wakeup)
    `DV_FCOV_EXPR_SEEN(all_debug_req, id_stage_i.controller_i.fcov_all_debug_req)
    `DV_FCOV_EXPR_SEEN(debug_entry_if, id_stage_i.controller_i.fcov_debug_entry_if)
    `DV_FCOV_EXPR_SEEN(debug_entry_id, id_stage_i.controller_i.fcov_debug_entry_id)
    `DV_FCOV_EXPR_SEEN(pipe_flush, id_stage_i.controller_i.fcov_pipe_flush)
    `DV_FCOV_EXPR_SEEN(single_step_taken, id_stage_i.controller_i.fcov_debug_single_step_taken)
    `DV_FCOV_EXPR_SEEN(single_step_exception, id_stage_i.controller_i.do_single_step_d &&
                                              id_stage_i.controller_i.fcov_pipe_flush)
    `DV_FCOV_EXPR_SEEN(insn_trigger_enter_debug, instr_id_matches_trigger_q)

    cp_nmi_taken: coverpoint ((fcov_irqs[5] || fcov_irqs[4])) iff
                             (id_stage_i.controller_i.fcov_interrupt_taken);

    cp_interrupt_taken: coverpoint fcov_irqs iff (id_stage_i.controller_i.fcov_interrupt_taken){
      wildcard bins nmi_external  = {6'b1?????};
      wildcard bins nmi_internal  = {6'b01????};
      wildcard bins irq_fast      = {6'b001???};
      wildcard bins irq_external  = {6'b0001??};
      wildcard bins irq_software  = {6'b00001?};
      wildcard bins irq_timer     = {6'b000001};
    }

    cp_controller_fsm: coverpoint id_stage_i.controller_i.ctrl_fsm_cs {
      bins out_of_reset = (RESET => BOOT_SET);
      bins out_of_boot_set = (BOOT_SET => FIRST_FETCH);
      bins out_of_first_fetch0 = (FIRST_FETCH => DECODE);
      bins out_of_first_fetch1 = (FIRST_FETCH => IRQ_TAKEN);
      bins out_of_first_fetch2 = (FIRST_FETCH => DBG_TAKEN_IF);
      bins out_of_decode0 = (DECODE => FLUSH);
      bins out_of_decode1 = (DECODE => DBG_TAKEN_IF);
      bins out_of_decode2 = (DECODE => IRQ_TAKEN);
      bins out_of_irq_taken = (IRQ_TAKEN => DECODE);
      bins out_of_debug_taken_if = (DBG_TAKEN_IF => DECODE);
      bins out_of_debug_taken_id = (DBG_TAKEN_ID => DECODE);
      bins out_of_flush0 = (FLUSH => DECODE);
      bins out_of_flush1 = (FLUSH => DBG_TAKEN_ID);
      bins out_of_flush2 = (FLUSH => WAIT_SLEEP);
      bins out_of_flush3 = (FLUSH => DBG_TAKEN_IF);
      bins out_of_wait_sleep = (WAIT_SLEEP => SLEEP);
      bins out_of_sleep = (SLEEP => FIRST_FETCH);
      // TODO: VCS does not implement default sequence so illegal_bins will be empty
      illegal_bins illegal_transitions = default sequence;
    }

    cp_controller_fsm_sleep: coverpoint id_stage_i.controller_i.ctrl_fsm_cs {
      bins out_of_sleep = (SLEEP => FIRST_FETCH);
      bins enter_sleep = (WAIT_SLEEP => SLEEP);
      // TODO: VCS does not implement default sequence so illegal_bins will be empty
      illegal_bins illegal_transitions = default sequence;
    }

    // This will only be seen when specific interrupt is disabled by MIE CSR
    `DV_FCOV_EXPR_SEEN(irq_continue_sleep, kept_wfi_with_irq)

    cp_single_step_instr: coverpoint id_instr_category iff
                                     (id_stage_i.controller_i.fcov_debug_single_step_taken) {
      // Not certain if InstrCategoryOtherIllegal can occur. Put it in illegal_bins for now and
      // revisit if any issues are seen
      // DRet: a step is taken only outside debug mode (ibex_controller.sv do_single_step_d), where
      // dret is illegal_dret_insn and categorised PrivIllegal (ibex_id_stage.sv). That is what
      // [Debug Spec v1.0.0-STABLE, p.95] "dret is an instruction which only has meaning while
      // Debug Mode" means for Ibex: stepping over a dret is covered by the PrivIllegal bin, and
      // the DRet category itself cannot be sampled here.
      illegal_bins illegal =
        {InstrCategoryOther, InstrCategoryNone, InstrCategoryOtherIllegal, InstrCategoryDRet
         // [Debug Spec v1.0.0-STABLE, p.50]
         // > If the instruction being stepped over is wfi and would normally stall the hart,
         // > then instead the instruction is treated as nop.
         // Again this will be useful coverage to verify we are testing this behaviour.
        };
    }

    // Only sample the bus error from the first access of misaligned load/store when we are in
    // the data phase of the second access. Without this, we cannot sample the case when both
    // first and second access fails.
    cp_misaligned_first_data_bus_err: coverpoint load_store_unit_i.fcov_mis_bus_err_1_q iff
      (load_store_unit_i.fcov_mis_rvalid_2);

    cp_misaligned_second_data_bus_err: coverpoint load_store_unit_i.data_bus_err_i iff
      (load_store_unit_i.fcov_mis_rvalid_2);

    cp_imem_response_latency: coverpoint imem_single_cycle_response iff (instr_rvalid_i) {
      bins single_cycle = {1'b1};
      bins multi_cycle = {1'b0};
    }

    `DV_FCOV_EXPR_SEEN(imem_req_gnt_rvalid, instr_rvalid_i & instr_req_o & instr_gnt_i)

    // Fetch FIFO structural states (see the fcov_fifo_* probes above uarch_cg).

    // REQ_BRA_03, REQ_IFE_05: FIFO empty and the instruction handed to IF comes straight off the
    // bus (rdata = in_rdata_i while valid_q[0] == 0), not from a FIFO entry.
    cp_fetch_fifo_bypass: coverpoint fcov_fifo_in_valid
      iff (fcov_fifo_out_taken & ~fcov_fifo_valid_q[0]) {
      bins bypass_active = {1'b1};
    }

    // REQ_BRA_07, REQ_IFE_04, REQ_IFE_06: IF redirect (clear_i) while all three FIFO entries are
    // occupied; every entry is invalidated in one cycle.
    cp_fetch_fifo_clear_while_full: coverpoint (&fcov_fifo_valid_q) iff (fcov_fifo_clear) {
      bins clear_full = {1'b1};
    }

    // REQ_IFE_05: a fetch response is pushed in the same cycle entry 0 is popped, so the fill
    // level stays constant. Binned by that fill level. The empty case is the bypass above (the
    // push never lands in an entry); the full case cannot push (IbexFetchFifoPushPopFull).
    cp_fetch_push_during_pop: coverpoint fcov_fifo_valid_q
      iff (fcov_fifo_in_valid & fcov_fifo_pop & ~fcov_fifo_clear) {
      bins simultaneous_one_entry   = {3'b001};
      bins simultaneous_two_entries = {3'b011};
    }

    // REQ_BRA_03, REQ_IFE_02: 16-bit instruction at PC[1] == 1, taken from the upper half-word
    // of entry 0 (which is then popped) or, with the FIFO empty, from the upper half of the
    // incoming bus word. unaligned_is_compressed includes CHERIoT force-UC (PCC headroom < 4).
    cp_fetch_unaligned_compressed: coverpoint fcov_fifo_valid_q[0]
      iff (fcov_fifo_out_taken & fcov_fifo_out_unaligned & fcov_fifo_unaligned_is_c) {
      bins uc_align_from_fifo = {1'b1};
      bins uc_align_bypass    = {1'b0};
    }

    // REQ_IFE_03: 32-bit instruction at PC[1] == 1, straddling a word boundary. The upper half
    // comes from entry 1 when valid_q[1] is set, otherwise from the incoming bus word
    // (valid_unaligned = valid_q[0] & in_valid_i).
    cp_fetch_unaligned_uncompressed: coverpoint fcov_fifo_valid_q[1]
      iff (fcov_fifo_out_taken & fcov_fifo_out_unaligned & ~fcov_fifo_unaligned_is_c) {
      bins u32_align_two_entries = {1'b1};
      bins u32_align_bypass      = {1'b0};
    }

    // REQ_BRA_01, REQ_BRA_07, REQ_IFE_04: a branch/jump redirect (pc_set_i with PC_JUMP) while a
    // valid instruction is waiting in IF, which must be discarded. With ID stalled the FIFO clear
    // discards it; with ID ready the ~pc_set_i term of instr_valid_id_d does.
    cp_if_stall_with_branch: coverpoint if_stage_i.id_in_ready_i
      iff (if_stage_i.pc_set_i & (if_stage_i.pc_mux_i == PC_JUMP) & if_stage_i.if_instr_valid) {
      bins stall_and_branch = {1'b0};
      bins ready_and_branch = {1'b1};
    }

    cp_dmem_response_latency: coverpoint dmem_single_cycle_response iff (data_rvalid_i) {
      bins single_cycle = {1'b1};
      bins multi_cycle = {1'b0};
    }

    `DV_FCOV_EXPR_SEEN(dmem_req_gnt_rvalid, data_rvalid_i & data_req_o & data_gnt_i)

    // Both halves failing is reachable (e.g. a misaligned access wholly outside memory): the
    // first half's error is held in fcov_mis_bus_err_1_q until the second half's response, which
    // is what lets this cross see it. It was an illegal_bins, which fired on that legal case.
    misaligned_data_bus_err_cross: cross cp_misaligned_first_data_bus_err,
                                         cp_misaligned_second_data_bus_err;

    misaligned_insn_bus_err_cross: cross id_stage_i.instr_fetch_err_i,
                                         id_stage_i.instr_fetch_err_plus2_i;

    // Include both mstatus.mie enabled/disabled because it should not affect wakeup condition
    irq_wfi_cross: cross cp_controller_fsm_sleep, cs_registers_i.mstatus_q.mie iff
                         (id_stage_i.irq_pending_i | id_stage_i.irq_nm_i);

    debug_wfi_cross: cross cp_controller_fsm_sleep, cp_all_debug_req iff
                           (id_stage_i.controller_i.fcov_all_debug_req);

    // InstrCategoryCSRAccess in U mode is legal: cycle/instret/hpmcounterN(h) reads are permitted
    // when the matching mcounteren bit is set (ibex_cs_registers.sv), so it is a bin to cover.
    priv_mode_instr_cross: cross cp_priv_mode_id, cp_id_instr_category {
      // MRET in U-mode is illegal_umode_insn, categorised PrivIllegal (ibex_id_stage.sv); it is
      // covered by cp_mret_in_umode
      illegal_bins umode_mret = binsof(cp_priv_mode_id) intersect {PRIV_LVL_U} &&
                                binsof(cp_id_instr_category) intersect {InstrCategoryMRet};
      // CHERI encodings decode only in CHERIoT mode, which is M-only (MPP reads M,
      // ibex_cs_registers.sv); U-mode needs the pin raised in U-mode, which the bench never does
      ignore_bins umode_cheri = binsof(cp_priv_mode_id) intersect {PRIV_LVL_U} &&
                                binsof(cp_id_instr_category) intersect {InstrCategoryCheri};
    }

    priv_mode_irq_cross: cross cp_priv_mode_id, cp_interrupt_taken, cs_registers_i.mstatus_q.mie {
      // No interrupt would be taken in M-mode when its mstatus.MIE = 0 unless it's an NMI
      illegal_bins mmode_mstatus_mie =
        binsof(cs_registers_i.mstatus_q.mie) intersect {1'b0} &&
        binsof(cp_priv_mode_id) intersect {PRIV_LVL_M} with (cp_interrupt_taken >> 4 == 6'd0);
    }

    priv_mode_exception_cross: cross cp_priv_mode_id, cp_ls_pmp_exception, cp_ls_error_exception {
      illegal_bins pmp_and_error_exeption_both =
        (binsof(cp_ls_pmp_exception) intersect {1'b1} &&
         binsof(cp_ls_error_exception) intersect {1'b1});
    }

    stall_cross: cross cp_id_instr_category, cp_stall_type_id {
      illegal_bins illegal =
        // Only Div, Mul, Branch and Jump instructions can see an instruction stall
        (!binsof(cp_id_instr_category) intersect {InstrCategoryDiv, InstrCategoryMul,
                                                 InstrCategoryBranch, InstrCategoryJump,
                                                 InstrCategoryFenceI} &&
         binsof(cp_stall_type_id) intersect {IdStallTypeInstr})
    ||
        // Only ALU, Mul, Div, Branch, Jump, Load, Store, CSR Access and CHERI instructions can see
        // a load hazard stall (CHERI ops read rs1/rs2, e.g. lw a0; cincoffset ca1, ca1, a0)
        (!binsof(cp_id_instr_category) intersect {InstrCategoryALU, InstrCategoryMul,
                                                 InstrCategoryDiv, InstrCategoryBranch,
                                                 InstrCategoryJump, InstrCategoryLoad,
                                                 InstrCategoryStore, InstrCategoryCSRAccess,
                                                 InstrCategoryCheri} &&
         binsof(cp_stall_type_id) intersect {IdStallTypeLdHz});

      // An outstanding access keeps mult_en/div_en off (ibex_id_stage.sv instr_executing), so a
      // waiting MUL/DIV raises stall_multdiv, and Instr takes priority over Mem in id_stall_type
      illegal_bins muldiv_mem =
        binsof(cp_id_instr_category) intersect {InstrCategoryMul, InstrCategoryDiv} &&
        binsof(cp_stall_type_id) intersect {IdStallTypeMem};

      // With BranchTargetALU jumps (FENCE.I decodes as a jump) stay in FIRST_CYCLE and never
      // stall; without it JumpBtalu/FenceIBtalu select InstrCategoryOther, an illegal bin anyway
      illegal_bins btalu_jump_instr =
        binsof(cp_id_instr_category) intersect {JumpBtalu, FenceIBtalu} &&
        binsof(cp_stall_type_id) intersect {IdStallTypeInstr};

      // No instruction in ID means no stall type (id_stall_type is gated by instr_valid_i)
      illegal_bins none_stall =
        binsof(cp_id_instr_category) intersect {InstrCategoryNone} &&
        !binsof(cp_stall_type_id) intersect {IdStallTypeNone};
    }

    wb_reg_no_load_hz_instr_cross: cross cp_id_instr_category, cp_wb_reg_no_load_hz {
      // Only ALU, Mul, Div, Branch, Jump, Load, Store, CSRAccess and CHERI instructions can see a
      // WB register hazard; CHERI ops read rs1/rs2 like any ALU op
      illegal_bins illegal =
        !binsof(cp_id_instr_category) intersect {InstrCategoryALU, InstrCategoryMul,
          InstrCategoryDiv, InstrCategoryBranch, InstrCategoryJump, InstrCategoryLoad,
          InstrCategoryStore, InstrCategoryCSRAccess, InstrCategoryCheri}              &&
        binsof(cp_wb_reg_no_load_hz) intersect {1'b1};
    }

    pipe_cross: cross cp_id_instr_category, cp_if_stage_state, cp_id_stage_state, cp_wb_stage_state {
      // When ID stage is empty the only legal instruction category is InstrCategoryNone. Conversly
      // when the instruction category is InstrCategoryNone the only legal ID stage state is
      // PipeStageEmpty.
      illegal_bins illegal = (!binsof(cp_id_instr_category) intersect {InstrCategoryNone} &&
        binsof(cp_id_stage_state) intersect {PipeStageEmpty}) ||
      (binsof(cp_id_instr_category) intersect {InstrCategoryNone} &&
        !binsof(cp_id_stage_state) intersect {PipeStageEmpty});

      // WB stalled means a load/store awaits its response, so outstanding_memory_access forces
      // stall_mem in ID (ibex_wb_stage.sv ready_wb_o, ibex_id_stage.sv stall_mem)
      illegal_bins id_unstalled_wb_stalled =
        binsof(cp_id_stage_state) intersect {PipeStageFullAndUnstalled} &&
        binsof(cp_wb_stage_state) intersect {PipeStageFullAndStalled};

      // IF req_i is low only in (WAIT_)SLEEP/RESET or with fetch_enable_i off; all of these set
      // halt_if (or have ID empty), so ID cannot be unstalled
      illegal_bins id_unstalled_if_idle =
        binsof(cp_id_stage_state) intersect {PipeStageFullAndUnstalled} &&
        binsof(cp_if_stage_state) intersect {IFStageFullAndIdle, IFStageEmptyAndIdle};

      // These categories raise special_req: retain_id holds them in DECODE and FLUSH sets halt_if
      illegal_bins id_unstalled_special =
        binsof(cp_id_stage_state) intersect {PipeStageFullAndUnstalled} &&
        binsof(cp_id_instr_category) intersect {InstrCategoryEBreakDbg, InstrCategoryEBreakExc,
          InstrCategoryECall, InstrCategoryMRet, InstrCategoryDRet, InstrCategoryWFI,
          InstrCategoryFetchError, InstrCategoryCompressedIllegal,
          InstrCategoryUncompressedIllegal, InstrCategoryCSRIllegal, InstrCategoryPrivIllegal};

      // A divide takes at least two executing cycles and only starts with nothing outstanding, so
      // WB cannot still be full when it completes (ibex_multdiv_fast.sv, ibex_id_stage.sv)
      ignore_bins div_done_wb_full =
        binsof(cp_id_instr_category) intersect {InstrCategoryDiv} &&
        binsof(cp_id_stage_state) intersect {PipeStageFullAndUnstalled} &&
        binsof(cp_wb_stage_state) intersect {PipeStageFullAndUnstalled};
    }

    interrupt_taken_instr_cross: cross cp_nmi_taken, instr_unstalled_last,
      cp_id_instr_category_last iff (id_stage_i.controller_i.fcov_interrupt_taken) {
      // An IRQ is only taken with ID empty (ibex_controller.sv !id_wb_pending, PipeEmptyOnIrq).
      // These categories leave ID only through a trap FLUSH (M-mode, MIE := 0), DBG_TAKEN_ID or
      // WFI -> WAIT_SLEEP, so the next interrupt taken can only be an NMI
      ignore_bins trap_masks_irq =
        binsof(cp_nmi_taken) intersect {1'b0} &&
        binsof(cp_id_instr_category_last) intersect {InstrCategoryEBreakDbg,
          InstrCategoryEBreakExc, InstrCategoryECall, InstrCategoryWFI, InstrCategoryFetchError,
          InstrCategoryCompressedIllegal, InstrCategoryUncompressedIllegal,
          InstrCategoryCSRIllegal, InstrCategoryPrivIllegal};
      // ID empties after a stall only through flush_id, and the only FLUSH that can follow a stall
      // is a trap FLUSH (MIE := 0)
      ignore_bins none_unstalled_after_trap =
        binsof(cp_nmi_taken) intersect {1'b0} && binsof(instr_unstalled_last) intersect {1'b1} &&
        binsof(cp_id_instr_category_last) intersect {InstrCategoryNone};
      // These read no registers, make no LSU request, and an outstanding access holds DECODE, so
      // the FLUSH cycle before the interrupt never follows a stall
      ignore_bins special_flush_no_unstall =
        binsof(instr_unstalled_last) intersect {1'b1} &&
        binsof(cp_id_instr_category_last) intersect {InstrCategoryEBreakDbg,
          InstrCategoryEBreakExc, InstrCategoryECall, InstrCategoryMRet, InstrCategoryDRet,
          InstrCategoryWFI, InstrCategoryFetchError, InstrCategoryCompressedIllegal,
          InstrCategoryCSRIllegal, InstrCategoryPrivIllegal};
      // A divide is in ID with stall None only when it completes or is flushed, both unstalling
      ignore_bins div_always_unstalled =
        binsof(instr_unstalled_last) intersect {1'b0} &&
        binsof(cp_id_instr_category_last) intersect {InstrCategoryDiv};
      // An illegal instruction leaves ID through FLUSH, and unstalling there needs an Instr stall
      // in DECODE: only the illegal_reg_16 branch with data-independent timing has one, the open
      // RTL finding in tech-notes/rtl_todo.md (ibex_decoder.sv clears branch_in_dec for
      // illegal_insn only). A hit is that defect
      illegal_bins illegal_unstall_nmi =
        binsof(cp_nmi_taken) intersect {1'b1} && binsof(instr_unstalled_last) intersect {1'b1} &&
        binsof(cp_id_instr_category_last) intersect {InstrCategoryUncompressedIllegal};
    }

    debug_instruction_cross: cross cp_debug_mode, cp_id_instr_category {
      // Outside debug mode dret is illegal_dret_insn, categorised PrivIllegal (ibex_id_stage.sv)
      illegal_bins dret_outside_debug =
        binsof(cp_debug_mode) intersect {1'b0} &&
        binsof(cp_id_instr_category) intersect {InstrCategoryDRet};
    }

    debug_entry_if_instr_cross: cross cp_debug_entry_if, instr_unstalled_last,
      cp_id_instr_category_last {
      // Entry from FLUSH needs enter_debug_mode_prio_q, masked by ~debug_mode_q while DRET is in
      // ID (ibex_controller.sv); otherwise DRET's last cycle is a FLUSH, which never unstalls
      // (no register reads, and a Mem stall clears in the cycle that allows FLUSH)
      ignore_bins dret_unstalled =
        binsof(instr_unstalled_last) intersect {1'b1} &&
        binsof(cp_id_instr_category_last) intersect {InstrCategoryDRet};
    }
    pipe_flush_instr_cross: cross cp_pipe_flush, instr_unstalled, cp_id_instr_category {
      // These raise no ID exception (CHERIoT load/store faults are WB errors), so FLUSH with one in
      // ID is a WB exception, which kills it (instr_kill) and keeps it stalled (Mem or Instr);
      // None unstalled follows a flush state, where WB is empty and cannot start a FLUSH
      ignore_bins killed_by_wb_exc =
        binsof(cp_pipe_flush) intersect {1'b1} && binsof(instr_unstalled) intersect {1'b1} &&
        binsof(cp_id_instr_category) intersect {InstrCategoryMul, InstrCategoryDiv,
          InstrCategoryLoad, InstrCategoryStore, InstrCategoryNone};
    }

    exception_stall_instr_cross: cross cp_ls_pmp_exception, cp_ls_error_exception,
      cp_id_instr_category, cp_stall_type_id, instr_unstalled, cp_irq_pending, cp_debug_req {
      illegal_bins illegal =
        // Only Div, Mul, Branch and Jump instructions can see an instruction stall
        (!binsof(cp_id_instr_category) intersect {InstrCategoryDiv, InstrCategoryMul,
                                                 InstrCategoryBranch, InstrCategoryJump,
                                                 InstrCategoryFenceI} &&
         binsof(cp_stall_type_id) intersect {IdStallTypeInstr})
    ||
        // Only ALU, Mul, Div, Branch, Jump, Load, Store, CSR Access and CHERI instructions can see
        // a load hazard stall (CHERI ops read rs1/rs2, e.g. lw a0; cincoffset ca1, ca1, a0)
        (!binsof(cp_id_instr_category) intersect {InstrCategoryALU, InstrCategoryMul,
                                                 InstrCategoryDiv, InstrCategoryBranch,
                                                 InstrCategoryJump, InstrCategoryLoad,
                                                 InstrCategoryStore, InstrCategoryCSRAccess,
                                                 InstrCategoryCheri} &&
         binsof(cp_stall_type_id) intersect {IdStallTypeLdHz});

      // Cannot have a memory stall when we see an LS exception unless it is a load or store
      // instruction or a fetch error (the raw instruction decode can still indicate a load or store
      // which produces a stall, though won't cause any load or store to occur due to the fetch
      // error).
      illegal_bins mem_stall_illegal =
        (!binsof(cp_id_instr_category) intersect {InstrCategoryLoad, InstrCategoryStore,
                                                  InstrCategoryFetchError} &&
         binsof(cp_stall_type_id) intersect {IdStallTypeMem}) with
        (cp_ls_pmp_exception == 1'b1 || cp_ls_error_exception == 1'b1);

      // When pipeline has unstalled stall type will always be none
      illegal_bins unstalled_illegal =
        !binsof(cp_stall_type_id) intersect {IdStallTypeNone} with (instr_unstalled == 1'b1);

      // An LSU error is either a PMP or a bus/CHERIoT error, never both: the two fcov signals are
      // qualified by pmp_err_q and ~pmp_err_q (ibex_load_store_unit.sv)
      illegal_bins pmp_and_bus_err_illegal =
        binsof(cp_ls_pmp_exception) intersect {1'b1} &&
        binsof(cp_ls_error_exception) intersect {1'b1};

      // A PMP error reports in the first IDLE cycle after lsu_req_done; in the cycle before, the
      // access left ID with no stall, so instr_unstalled cannot be set
      illegal_bins pmp_unstalled_illegal =
        binsof(cp_ls_pmp_exception) intersect {1'b1} &&
        binsof(instr_unstalled) intersect {1'b1};

      // wb_exception kills lsu_req and mult_en (instr_kill), so a Load/Store in ID stalls Mem and
      // a Mul stalls Instr
      illegal_bins pmp_no_stall_illegal =
        binsof(cp_ls_pmp_exception) intersect {1'b1} &&
        binsof(cp_id_instr_category) intersect {InstrCategoryLoad, InstrCategoryStore,
                                                 InstrCategoryMul} &&
        binsof(cp_stall_type_id) intersect {IdStallTypeNone};

      // Data PMP errors are gated off in CHERIoT mode (ibex_core.sv g_pmp_cheriot_gate) and CHERI
      // instructions only decode in it. Depends on cheriot_enable_i being static, hence ignore.
      ignore_bins pmp_cheri_ignore =
        binsof(cp_ls_pmp_exception) intersect {1'b1} &&
        binsof(cp_id_instr_category) intersect {InstrCategoryCheri};

      // With BranchTargetALU jumps (FENCE.I decodes as a jump) stay in FIRST_CYCLE and never
      // stall; without it JumpBtalu/FenceIBtalu select InstrCategoryOther, an illegal bin anyway
      illegal_bins btalu_jump_instr_stall_illegal =
        binsof(cp_id_instr_category) intersect {JumpBtalu, FenceIBtalu} &&
        binsof(cp_stall_type_id) intersect {IdStallTypeInstr};

      // A divide never completes in its first ID cycle (ibex_multdiv_fast.sv MD_FINISH), so stall
      // None only occurs on the cycle it unstalls
      illegal_bins div_no_stall_illegal =
        binsof(cp_id_instr_category) intersect {InstrCategoryDiv} &&
        binsof(cp_stall_type_id) intersect {IdStallTypeNone} &&
        binsof(instr_unstalled) intersect {1'b0};

      // An outstanding memory access clears instr_executing, so a waiting MUL/DIV always raises
      // stall_multdiv, and Instr takes priority over Mem in id_stall_type
      illegal_bins muldiv_mem_stall_illegal =
        binsof(cp_id_instr_category) intersect {InstrCategoryMul, InstrCategoryDiv} &&
        binsof(cp_stall_type_id) intersect {IdStallTypeMem};

      // DRet is only categorised in debug mode, where fcov_debug_req is masked
      illegal_bins dret_debug_req_illegal =
        binsof(cp_id_instr_category) intersect {InstrCategoryDRet} &&
        binsof(cp_debug_req) intersect {1'b1};

      // No instruction in ID means no stall type (id_stall_type is gated by instr_valid_i)
      illegal_bins none_stall_illegal =
        binsof(cp_id_instr_category) intersect {InstrCategoryNone} &&
        !binsof(cp_stall_type_id) intersect {IdStallTypeNone};

      // A real LSU error reports while the instruction behind the access is in FIRST_CYCLE and
      // killed by wb_exception (ibex_id_stage.sv instr_kill): a load/store keeps stall_mem (its
      // lsu_req is gated off, so no lsu_req_done), a MUL/DIV keeps stall_multdiv (not enabled)
      illegal_bins err_no_stall_illegal =
        binsof(cp_ls_error_exception) intersect {1'b1} &&
        binsof(cp_id_instr_category) intersect {InstrCategoryLoad, InstrCategoryStore,
                                                 InstrCategoryMul, InstrCategoryDiv} &&
        binsof(cp_stall_type_id) intersect {IdStallTypeNone};

      // ID empties after a stall only through flush_id, and no flushing state is entered while
      // WB waits on a response (ibex_controller.sv DECODE -> FLUSH needs ready_wb_i)
      illegal_bins err_none_unstalled_illegal =
        binsof(cp_ls_error_exception) intersect {1'b1} &&
        binsof(cp_id_instr_category) intersect {InstrCategoryNone} &&
        binsof(instr_unstalled) intersect {1'b1};
    }

    csr_read_only_priv_cross: cross cp_csr_read_only, cp_priv_mode_id;
    csr_write_priv_cross: cross cp_csr_write, cp_priv_mode_id;

    csr_read_only_debug_cross: cross cp_csr_read_only, cp_debug_mode {
      // Only care about specific debug CSRs
      ignore_bins ignore = !binsof(cp_csr_read_only) intersect {`DEBUG_CSRS};
    }

    csr_write_debug_cross: cross cp_csr_write, cp_debug_mode {
      // Only care about specific debug CSRs
      ignore_bins ignore = !binsof(cp_csr_write) intersect {`DEBUG_CSRS};
    }

    // V2S Crosses

    dummy_instr_config_cross: cross cp_dummy_instr_type, cp_dummy_instr_mask
                                iff (cs_registers_i.dummy_instr_en_o);

    // Shadow-core probes (see cp_rf_a_ecc_err); they already include the shadow core's
    // instr_valid_id, which runs LockstepOffset cycles behind this core's instr_valid_i
    rf_ecc_err_cross: cross rf_ecc_err_a_shdw, rf_ecc_err_b_shdw;

    // Each stage sees a debug request while executing a dummy instruction.
    debug_req_dummy_instr_if_stage_cross: cross cp_debug_req, cp_dummy_instr_if_stage;
    debug_req_dummy_instr_id_stage_cross: cross cp_debug_req, cp_dummy_instr_id_stage;
    debug_req_dummy_instr_wb_stage_cross: cross cp_debug_req, cp_dummy_instr_wb_stage;

    // Each stage sees an interrupt request while executing a dummy instruction.
    irq_pending_dummy_instr_if_stage_cross: cross cp_irq_pending, cp_dummy_instr_if_stage;
    irq_pending_dummy_instr_id_stage_cross: cross cp_irq_pending, cp_dummy_instr_id_stage;
    irq_pending_dummy_instr_wb_stage_cross: cross cp_irq_pending, cp_dummy_instr_wb_stage;

  endgroup

  // The lockstep shadow core (ibex_lockstep u_shadow_core) is a second ibex_core, so the bind lands
  // in it too. It runs the main core's instruction stream a few cycles late: its covergroups record
  // the same hits and doubled every denominator (ibex_top 170536 items vs 85235 per core on
  // 2026-09-28). Functional coverage is sampled in the main core only; code coverage of the two
  // instances is unioned per module at report time instead.
  function automatic bit fcov_in_shadow_core();
    string path = $sformatf("%m");
    for (int i = 0; i + 13 <= path.len(); i++) begin
      if (path.substr(i, i + 12) == "u_shadow_core") return 1'b1;
    end
    return 1'b0;
  endfunction

  bit en_uarch_cov;

  initial begin
   void'($value$plusargs("enable_ibex_fcov=%d", en_uarch_cov));
   if (fcov_in_shadow_core()) en_uarch_cov = 1'b0;
  end

  `DV_FCOV_INSTANTIATE_CG(uarch_cg, en_uarch_cov)

  // ==========================================================================
  // CHERIoT Functional Coverage
  // Ported from cheriot-ibex/dv/cheriot/fcov/core_ibex_fcov_if.sv
  //
  // Architecture notes vs cheriot-ibex:
  //  - ibex-private OPDW=26 (26-bit one-hot cheriot_operator); cheriot-ibex was 36-bit.
  //  - All CGET_* ops folded into CGET_FIELD (op 0) + cheriot_cap_field_sel in ibex-private.
  //  - No TBRE / STKZ hardware in ibex-private → those coverpoints are TODO.
  //  - No g_trvk_stage hierarchy (TRVK stall always 0) → trvk_addr/cond/tsmap are TODO.
  //  - No DV-extension bind modules → signals that need them are computed locally.
  //  - cheriot_pmode: ibex-private uses cheriot_enable_i (IbexMuBiOn) rather than a 1-bit port.
  // ==========================================================================

  // ---- Helper functions (inlined from cheriot_dv_pkg / cheri_pkg) ----

  function automatic logic [5:0] fcov_thermo_dec32(logic [31:0] a32);
    logic [5:0] count;
    logic [31:0] b32;
    if (a32[31]) count = 32;
    else begin
      count[5] = 1'b0;
      count[4] = a32[15];
      b32[15:0] = count[4] ? a32[31:16] : a32[15:0];
      count[3] = b32[7];
      b32[ 7:0] = count[3] ? b32[15:8] : b32[7:0];
      count[2] = b32[3];
      b32[ 3:0] = count[2] ?  b32[7:4] : b32[3:0];
      count[1] = b32[1];
      b32[ 1:0] = count[1] ?  b32[3:2] : b32[1:0];
      count[0] = b32[0];
    end
    return count;
  endfunction

  function automatic logic [5:0] get_size(logic [31:0] din);
    logic [5:0]  count;
    logic [31:0] a32;
    int i;
    a32 = {din[31], 31'h0};
    for (i = 30; i >= 0; i--) a32[i] = a32[i+1] | din[i];
    count = fcov_thermo_dec32(a32);
    return count;
  endfunction

  function automatic logic [2:0] fcov_repr_cases(decoded_cap_t in_cap, logic [31:0] address);
    logic [2:0]  result;
    logic [32:0] rep_top;
    rep_top = 33'h1 << (9 + cheriot_expand_exp(in_cap.cexp));
    if (cheriot_expand_exp(in_cap.cexp) == 24)
      result = 3'd0;
    else if (address < in_cap.base32)
      result = 3'd1;
    else if ((address - in_cap.base32) >= rep_top)
      result = 3'd2;
    else
      result = 3'd0;
    return result;
  endfunction

  function automatic logic [5:0] fcov_count32_zeros(logic [31:0] address);
    logic [5:0] result;
    int i;
    result = 6'd0;
    for (i = 0; i <= 31; i++) if (address[i] == 1'b0) result = result + 6'd1;
    return result;
  endfunction

  function automatic logic [8:0] fcov_bound_check_cases(decoded_cap_t in_cap, logic [31:0] address);
    logic [8:0]  result;
    logic [33:0] room;
    result[0] = (address <  in_cap.base32);
    result[1] = (address == in_cap.base32);
    result[2] = ({1'b0, address} >  in_cap.top33);
    result[3] = ({1'b0, address} == in_cap.top33);
    room = in_cap.top33 - {1'b0, address};
    if ((room > 0) && (room < 8)) result[6:4] = room[2:0];
    else result[6:4] = 3'd0;
    result[7] = (in_cap.top33  == 33'h1_0000_0000);
    result[8] = (in_cap.base32 == 32'h0);
    return result;
  endfunction

  function automatic logic [4:0] fcov_setbounds_cases_fn(
      decoded_cap_t cs1_cap, logic [31:0] cs1_address, logic [31:0] req_len);
    logic [4:0]  result;
    logic [32:0] cs1_len;
    result[0] = (cs1_address <  cs1_cap.base32);
    result[1] = (cs1_address == cs1_cap.base32);
    result[2] = ({1'b0, cs1_address} >  cs1_cap.top33);
    result[3] = ({1'b0, cs1_address} == cs1_cap.top33);
    cs1_len   = cs1_cap.top33 - {1'b0, cs1_cap.base32};
    result[4] = ({1'b0, req_len} <= cs1_len);
    return result;
  endfunction

  // Cursor position relative to capability bounds.
  // Returns: 0=below_base 1=at_base 2=in_range 3=at_top_minus_1 4=at_top_or_above
  function automatic logic [2:0] fcov_cursor_rel(
    input logic [32:0] top33,
    input logic [31:0] base32,
    input logic [31:0] addr
  );
    logic [32:0] addr33;
    logic [32:0] top_minus1;
    addr33     = {1'b0, addr};
    top_minus1 = top33 - 33'd1;
    if      (addr < base32)         return 3'd0;
    else if (addr == base32)        return 3'd1;
    else if (addr33 >= top33)       return 3'd4;
    else if (addr33 == top_minus1)  return 3'd3;
    else                            return 3'd2;
  endfunction

  // ---- CHERIoT mode signal ----
  logic cheriot_pmode;
  assign cheriot_pmode = (cheriot_enable_i == IbexMuBiOn);

  // ---- cheriot_operator shorthand (26-bit one-hot, ibex_core internal) ----
  // Accessed hierarchically; all CGET_* fold into CGET_FIELD (bit 0).

  // ---- fcov signal assignments ----

  logic        fcov_cheri_tag_clear_cs1cd;
  logic [2:0]  fcov_cheri_cd_cs1_repr_cases;
  logic [2:0]  fcov_cheri_cd_pcc_repr_cases;
  logic [5:0]  fcov_cheri_cs1_addr_0cnt;
  logic [5:0]  fcov_cheri_cs2_addr_0cnt;
  logic [5:0]  fcov_cheri_cd_addr_0cnt;
  logic [8:0]  fcov_cheri_cjal_bound;
  logic [8:0]  fcov_cheri_cjalr_bound;
  logic [8:0]  fcov_cheri_branch_bound;
  logic [8:0]  fcov_cheri_clsc_bound;
  logic [8:0]  fcov_cheri_seal_bound_tmp9;
  logic [3:0]  fcov_cheri_seal_bound;
  logic [4:0]  fcov_cheri_setbounds;
  logic [4:0]  fcov_cheri_setboundsimm;
  logic [5:0]  fcov_cheri_rs1_bitsize;
  logic        fcov_cheri_scr_read_only;
  logic        fcov_cheri_scr_write;
  logic        fcov_cheri_cpu_lsu_req;
  logic        fcov_cheri_cpu_lsu_err;
  decoded_cap_t   fcov_cheri_scr_wfcap;

  assign fcov_cheri_tag_clear_cs1cd =
    g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.valid &
    ~g_cheriot_ex.u_ibex_cheriot_ex.result_cap_o.valid;

  assign fcov_cheri_cd_cs1_repr_cases = fcov_repr_cases(
    g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a,
    g_cheriot_ex.u_ibex_cheriot_ex.result_data_o);

  assign fcov_cheri_cd_pcc_repr_cases = fcov_repr_cases(
    cs_registers_i.pcc_cap_o,
    g_cheriot_ex.u_ibex_cheriot_ex.result_data_o);

  assign fcov_cheri_cs1_addr_0cnt = fcov_count32_zeros(g_cheriot_ex.u_ibex_cheriot_ex.rf_rdata_a);
  assign fcov_cheri_cs2_addr_0cnt = fcov_count32_zeros(g_cheriot_ex.u_ibex_cheriot_ex.rf_rdata_b);
  assign fcov_cheri_cd_addr_0cnt  = fcov_count32_zeros(g_cheriot_ex.u_ibex_cheriot_ex.result_data_o);

  assign fcov_cheri_cjal_bound = fcov_bound_check_cases(
    cs_registers_i.pcc_cap_o,
    g_cheriot_ex.u_ibex_cheriot_ex.branch_target_o);

  assign fcov_cheri_cjalr_bound = fcov_bound_check_cases(
    g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a,
    g_cheriot_ex.u_ibex_cheriot_ex.branch_target_o);

  // branch_target_ex is ibex_core internal combining rv32 and cheri branch targets
  assign fcov_cheri_branch_bound = fcov_bound_check_cases(
    cs_registers_i.pcc_cap_o,
    branch_target_ex);

  assign fcov_cheri_clsc_bound = fcov_bound_check_cases(
    g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a,
    g_cheriot_ex.u_ibex_cheriot_ex.cheriot_ls_chkaddr);

  assign fcov_cheri_seal_bound_tmp9 = fcov_bound_check_cases(
    g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_b,
    g_cheriot_ex.u_ibex_cheriot_ex.rf_rdata_b);
  assign fcov_cheri_seal_bound = fcov_cheri_seal_bound_tmp9[3:0];

  assign fcov_cheri_setbounds = fcov_setbounds_cases_fn(
    g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a,
    g_cheriot_ex.u_ibex_cheriot_ex.rf_rdata_a,
    g_cheriot_ex.u_ibex_cheriot_ex.rf_rdata_b);

  assign fcov_cheri_setboundsimm = fcov_setbounds_cases_fn(
    g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a,
    g_cheriot_ex.u_ibex_cheriot_ex.rf_rdata_a,
    {20'h0, g_cheriot_ex.u_ibex_cheriot_ex.cheriot_imm12_i});

  assign fcov_cheri_rs1_bitsize = get_size(g_cheriot_ex.u_ibex_cheriot_ex.rf_rdata_a);

  // SCR read/write (replicate cheriot_ex_dv_ext logic)
  assign fcov_cheri_scr_read_only =
    (g_cheriot_ex.u_ibex_cheriot_ex.csr_op_o == CHERIOT_CSR_RW) &&
    g_cheriot_ex.u_ibex_cheriot_ex.csr_access_o &&
    ~g_cheriot_ex.u_ibex_cheriot_ex.csr_op_en_o &&
    cheriot_operator.CCSR_RW &&
    g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i;

  assign fcov_cheri_scr_write =
    (g_cheriot_ex.u_ibex_cheriot_ex.csr_op_o == CHERIOT_CSR_RW) &&
    g_cheriot_ex.u_ibex_cheriot_ex.csr_op_en_o &&
    cheriot_operator.CCSR_RW &&
    g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i;

  // CPU LSU request/error
  assign fcov_cheri_cpu_lsu_req =
    g_cheriot_ex.u_ibex_cheriot_ex.cheriot_lsu_req | g_cheriot_ex.u_ibex_cheriot_ex.rv32_lsu_req_i;
  assign fcov_cheri_cpu_lsu_err =
    (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_lsu_err | g_cheriot_ex.u_ibex_cheriot_ex.rv32_lsu_err) &&
    fcov_cheri_cpu_lsu_req;

  // SCR write cap (for mtcc/mepcc legalization coverage)
  assign fcov_cheri_scr_wfcap =
    cheriot_decode_cap(cs_registers_i.cheriot_csr_wcap_i, cs_registers_i.cheriot_csr_wdata_i);

  // Cursor-relative-to-bounds helpers for CS1 and CS2.
  logic [2:0] fcov_cs1_cursor_rel;
  logic [2:0] fcov_cs2_cursor_rel;

  assign fcov_cs1_cursor_rel = fcov_cursor_rel(
    g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.top33,
    g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.base32,
    g_cheriot_ex.u_ibex_cheriot_ex.rf_rdata_a);

  assign fcov_cs2_cursor_rel = fcov_cursor_rel(
    g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_b.top33,
    g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_b.base32,
    g_cheriot_ex.u_ibex_cheriot_ex.rf_rdata_b);

  // ID-stage and WB-stage error flags for instr_error_sequence crosses.
  // fcov_id_error: any exception taken at the ID stage (fetch error, illegal, ecall, ebreak, CHERI).
  // fcov_wb_error: any exception taken at the WB stage (load/store fault, CHERI WB error).
  logic fcov_id_error, fcov_wb_error;
  assign fcov_id_error = id_stage_i.controller_i.instr_fetch_err_prio |
                         id_stage_i.controller_i.illegal_insn_prio     |
                         id_stage_i.controller_i.ecall_insn_prio       |
                         id_stage_i.controller_i.ebrk_insn_prio        |
                         id_stage_i.controller_i.cheriot_ex_err_prio     |
                         id_stage_i.controller_i.cheriot_asr_err_prio;
  assign fcov_wb_error = id_stage_i.controller_i.load_err_prio  |
                         id_stage_i.controller_i.store_err_prio |
                         id_stage_i.controller_i.cheriot_wb_err_prio;

  // ---- CHERIoT covergroup ----

  // cheriot_uarch_cg note -- large crosses, off by default (+define+CHERIOT_FCOV_LARGE_CROSSES).
  // Fifteen crosses in this covergroup each take the exhaustive product of several operand
  // properties (e.g. cheriot_cseqx_cross1: cs1 perms 24 x cs1 correction 4 x cs2 perms 24 x cs2
  // correction 4 = 9216 bins). Together they held 67,593 of the main core's 85,235 functional
  // coverage items on 2026-09-29, and most of their bins are either unreachable by ISA rule (a
  // tagged CSetBounds result from an untagged or sealed source) or add nothing a relational cross
  // (equal/different, in/out of bounds) would not. They stay in the source, compiled out by default,
  // so the coverage figure is not dominated by them, until each is replaced by a smaller cross with
  // its purpose and ignore_bins justified (TODO.md). Define CHERIOT_FCOV_LARGE_CROSSES to bring them
  // back. The upstream exception_stall_instr_cross (uarch_cg, 1072 bins) is not affected.
  // The 78 values fcov_bound_check_cases() can return when base <= top <= 2^32, one bin each.
  // Without explicit bins the 512-value space is folded into 64 auto bins (auto_bin_max).
  // Jump and branch targets are always even (CJALR/CJAL take {sum[31:1], 1'b0}, branch targets are
  // 2-byte aligned). With top = 2^32 (b7) top is even too, so the distance top - target (b6:4) can
  // never be odd: these 15 values cannot occur for a jump or branch target, whatever the operands.
  // (An odd distance needs an odd top, i.e. exponent 0.) CLC/CSC addresses can be odd, so
  // cp_cheri_clsc_bound keeps them. Verified on regression 7931: 0 hits in all 300
  // cheriot_cjalr_cross1 bins they formed.
  `define FCOV_EVEN_TARGET_IGNORE \
    ignore_bins top32_odd_room = { \
      9'h090, 9'h092, 9'h0b0, 9'h0b1, 9'h0b2, 9'h0d0, 9'h0d1, 9'h0d2, \
      9'h0f0, 9'h0f1, 9'h0f2, 9'h190, 9'h1b0, 9'h1d0, 9'h1f0 \
    };

  `define FCOV_BOUND_CASE_BINS \
    bins cases[] = { \
      9'h000, 9'h001, 9'h002, 9'h004, 9'h008, 9'h00a, 9'h010, 9'h011, \
      9'h012, 9'h020, 9'h021, 9'h022, 9'h030, 9'h031, 9'h032, 9'h040, \
      9'h041, 9'h042, 9'h050, 9'h051, 9'h052, 9'h060, 9'h061, 9'h062, \
      9'h070, 9'h071, 9'h072, 9'h080, 9'h081, 9'h082, 9'h090, 9'h092, \
      9'h0a0, 9'h0a1, 9'h0a2, 9'h0b0, 9'h0b1, 9'h0b2, 9'h0c0, 9'h0c1, \
      9'h0c2, 9'h0d0, 9'h0d1, 9'h0d2, 9'h0e0, 9'h0e1, 9'h0e2, 9'h0f0, \
      9'h0f1, 9'h0f2, 9'h100, 9'h102, 9'h104, 9'h108, 9'h10a, 9'h110, \
      9'h112, 9'h120, 9'h122, 9'h130, 9'h132, 9'h140, 9'h142, 9'h150, \
      9'h152, 9'h160, 9'h162, 9'h170, 9'h172, 9'h180, 9'h182, 9'h190, \
      9'h1a0, 9'h1b0, 9'h1c0, 9'h1d0, 9'h1e0, 9'h1f0 \
    };

  covergroup cheriot_uarch_cg @(posedge clk_i);
    option.per_instance = 1;
    option.name = "cheriot_uarch_cg";

    // ------------------------------------------------------------------
    // Register address coverage (CHERIoT-relevant registers)
    // ------------------------------------------------------------------

    cp_cheri_rs1_regaddr: coverpoint id_stage_i.rf_raddr_a_o[4:0]
      iff (cheriot_pmode & id_stage_i.rf_ren_a) {
      bins bin0      = {0};
      bins bin1to14  = {[1:14]};
      bins bin15     = {15};
      // In CHERIoT mode x16-x31 do not exist (CheriLimit16Regs, ibex_decoder.sv); only an
      // instruction the decoder rejects as illegal presents these addresses.
      ignore_bins bin16to31 = {[16:31]};
    }

    cp_cheri_rs2_regaddr: coverpoint id_stage_i.rf_raddr_b_o[4:0]
      iff (cheriot_pmode & id_stage_i.rf_ren_b) {
      bins bin0      = {0};
      bins bin1to14  = {[1:14]};
      bins bin15     = {15};
      // In CHERIoT mode x16-x31 do not exist (CheriLimit16Regs, ibex_decoder.sv); only an
      // instruction the decoder rejects as illegal presents these addresses.
      ignore_bins bin16to31 = {[16:31]};
    }

    cp_cheri_rd_regaddr: coverpoint id_stage_i.rf_waddr_id_o[4:0]
      iff (cheriot_pmode & (id_stage_i.rf_we_id_o | g_cheriot_ex.u_ibex_cheriot_ex.cheriot_rf_we_o)) {
      bins bin0      = {0};
      bins bin1to14  = {[1:14]};
      bins bin15     = {15};
      // In CHERIoT mode x16-x31 do not exist (CheriLimit16Regs, ibex_decoder.sv); only an
      // instruction the decoder rejects as illegal presents these addresses.
      ignore_bins bin16to31 = {[16:31]};
    }

    // rs2 as increment (for CINC_ADDR)
    cp_cheri_rs2_as_inc: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.rf_rdata_b {
      bins bin1 = {32'h0};
      bins bin2 = {[32'h1:32'h7fff_ffff]};
      bins bin3 = {32'h8000_0000};
      bins bin4 = {[32'h8000_0001:32'hffff_fffe]};
      bins bin5 = {32'hffff_ffff};
    }

    // CHERIoT instruction executed (index of the set bit in the one-hot operator).
    // Note: CGET_* ops all map to CGET_FIELD (bit 0) + cap_field_sel; the field
    // itself is covered by cp_cheri_cget_field below.
    //
    // ibex-private cast this to `cheri_op_e`, an enum giving one named bin per
    // operator. This tree has no such enum -- ibex_cheriot_pkg defines the
    // operators as `cheriot_op_t`, a packed struct of named one-hot bits. The
    // index is covered as an integer instead: the same operators are covered,
    // but the bins are numbered rather than named. Restoring the names would
    // mean adding an enum to the package, which is an RTL change.
    // One bin per operator bit. Without explicit bins the 32-bit $clog2 result was split into
    // 64 auto bins of ~2^26 values each, so every operator landed in the first (1/64 covered),
    // and cheriot_pcc2cd_tag_cross's 'intersect {21, 20, 19}' could not single out any operator.
    cp_cheri_instr_set: coverpoint $clog2({1'b0, cheriot_operator})
      iff ((|cheriot_operator) && g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i) {
      bins op[] = {[0:$bits(cheriot_operator)-1]};
    }

    // CGET_* field selector when CGET_FIELD is executing
    cp_cheri_cget_field: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.cheriot_cap_field_sel_i
      iff (cheriot_operator.CGET_FIELD && g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i) {
      // CGetOffset is not present in CHERIoT (ISA chap-cheri-riscv.tex, no Sail instruction): the
      // decoder no longer selects CFIELD_OFFSET, rs2 = 6 is illegal (ibex_decoder.sv)
      illegal_bins offset = {CFIELD_OFFSET};
    }

    // ------------------------------------------------------------------
    // PCC coverage
    // ------------------------------------------------------------------

    cp_cheri_pcc_tag: coverpoint cs_registers_i.pcc_cap_o.valid;

    cp_cheri_pcc_exp: coverpoint cheriot_expand_exp(cs_registers_i.pcc_cap_o.cexp)
      iff (cs_registers_i.pcc_cap_o.valid) {
      bins bin0 = {0};
      bins bin1 = {[1:14]};
      bins bin2 = {24};
      illegal_bins illegal = default;
    }

    cp_cheri_pcc_perm_asr: coverpoint cs_registers_i.pcc_cap_o.perms.SR;
    cp_cheri_pcc_perm_ex:  coverpoint cs_registers_i.pcc_cap_o.perms.EX;

    // ------------------------------------------------------------------
    // Instruction immediates
    // ------------------------------------------------------------------

    cp_cheri_imm20: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.cheriot_imm20_i {
      bins bin1 = {20'h0};
      bins bin2 = {[20'h1:20'h7_ffff]};
      bins bin3 = {20'h8_0000};
      bins bin4 = {[20'h8_0001:20'hf_fffe]};
      bins bin5 = {20'hf_ffff};
    }

    cp_cheri_imm12: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.cheriot_imm12_i {
      bins bin1 = {12'h0};
      bins bin2 = {[12'h1:12'h7ff]};
      bins bin3 = {12'h800};
      bins bin4 = {[12'h801:12'hffe]};
      bins bin5 = {12'hfff};
    }

    // ------------------------------------------------------------------
    // CS1 capability operand coverage
    // ------------------------------------------------------------------

    cp_cheri_cs1_tag: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.valid;

    cp_cheri_cs1_exp: coverpoint cheriot_expand_exp(g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.cexp) {
      bins bin0 = {0};
      bins bin1 = {[1:14]};
      bins bin2 = {24};
    }

    cp_cheri_cs1_otype: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.otype {
      bins bin[] = {[0:7]};
    }

    cp_cheri_cs1_sealed: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.otype != 0;

    cp_cheri_cs1_sealed_tagged_cross: cross cp_cheri_cs1_tag, cp_cheri_cs1_sealed;

    // Bound corrections, from cap_cor directly ({top_hi ^ addr_hi, addr_hi}, ibex_cheriot_pkg.sv
    // cheriot_get_top/base_correction). The 4-bit {base, top} correction was compared with 3-bit
    // constants, and two of the four bins asked for a base correction of +1, which does not exist.
    cp_cheri_cs1_cor: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.cap_cor {
      bins bin0 = {2'b00};  // top 0,  base 0
      bins bin1 = {2'b10};  // top +1, base 0
      bins bin3 = {2'b01};  // top 0,  base -1
      bins bin5 = {2'b11};  // top -1, base -1
    }

    cp_cheri_cs1_top: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.top {
      bins bin_all1 = {9'h1ff};
      bins bin_all0 = {9'h0};
      bins bin1     = {[9'h1:9'h1fe]};
    }

    cp_cheri_cs1_base: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.base {
      bins bin_all1 = {9'h1ff};
      bins bin_all0 = {9'h0};
      bins bin1     = {[9'h1:9'h1fe]};
    }

    cp_cheri_cs1_perms: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.perms {
      wildcard bins gl0  = {12'b????_????_???0};
      wildcard bins gl1  = {12'b????_????_???1};
      wildcard bins lg0  = {12'b????_????_??0?};
      wildcard bins lg1  = {12'b????_????_??1?};
      wildcard bins sd0  = {12'b????_????_?0??};
      wildcard bins sd1  = {12'b????_????_?1??};
      wildcard bins lm0  = {12'b????_????_0???};
      wildcard bins lm1  = {12'b????_????_1???};
      wildcard bins sl0  = {12'b????_???0_????};
      wildcard bins sl1  = {12'b????_???1_????};
      wildcard bins ld0  = {12'b????_??0?_????};
      wildcard bins ld1  = {12'b????_??1?_????};
      wildcard bins mc0  = {12'b????_?0??_????};
      wildcard bins mc1  = {12'b????_?1??_????};
      wildcard bins sr0  = {12'b????_0???_????};
      wildcard bins sr1  = {12'b????_1???_????};
      wildcard bins ex0  = {12'b???0_????_????};
      wildcard bins ex1  = {12'b???1_????_????};
      wildcard bins us0  = {12'b??0?_????_????};
      wildcard bins us1  = {12'b??1?_????_????};
      wildcard bins se0  = {12'b?0??_????_????};
      wildcard bins se1  = {12'b?1??_????_????};
      wildcard bins u00  = {12'b0???_????_????};
      wildcard bins u01  = {12'b1???_????_????};
    }

    cp_cheri_cs1_perms_load: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.perms {
      wildcard bins lg0  = {12'b????_????_??0?};
      wildcard bins lg1  = {12'b????_????_??1?};
      wildcard bins lm0  = {12'b????_????_0???};
      wildcard bins lm1  = {12'b????_????_1???};
      wildcard bins ld0  = {12'b????_??0?_????};
      wildcard bins ld1  = {12'b????_??1?_????};
      wildcard bins mc0  = {12'b????_?0??_????};
      wildcard bins mc1  = {12'b????_?1??_????};
    }

    cp_cheri_cs1_perms_store: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.perms {
      wildcard bins sd0  = {12'b????_????_?0??};
      wildcard bins sd1  = {12'b????_????_?1??};
      wildcard bins sl0  = {12'b????_???0_????};
      wildcard bins sl1  = {12'b????_???1_????};
      wildcard bins mc0  = {12'b????_?0??_????};
      wildcard bins mc1  = {12'b????_?1??_????};
    }

    cp_cheri_cs1_perm_ex: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.perms.EX;
    cp_cheri_cs1_perm_gl: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.perms.GL;

    cp_cheri_cs1_address: coverpoint fcov_cheri_cs1_addr_0cnt {
      bins valid[] = {[0:32]};
      ignore_bins ignore = {[33:$]};
    }

    cp_cheri_cs1_base32: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.base32 {
      bins bin0 = {32'h0};
      bins bin1 = {[32'h1:32'hffff_fffe]};
      bins bin3 = {32'hffff_ffff};
    }

    cp_cheri_cs1_top33: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.top33 {
      bins bin0 = {33'h0};
      bins bin1 = {[33'h1:33'hffff_fffe]};
      bins bin2 = {33'hffff_ffff};
      bins bin3 = {33'h1_0000_0000};
    }

    // ------------------------------------------------------------------
    // CS2 capability operand coverage
    // ------------------------------------------------------------------

    cp_cheri_cs2_tag: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_b.valid;

    cp_cheri_cs2_exp: coverpoint cheriot_expand_exp(g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_b.cexp) {
      bins bin0 = {0};
      bins bin1 = {[1:14]};
      bins bin2 = {24};
    }

    cp_cheri_cs2_otype: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_b.otype {
      bins bin[] = {[0:7]};
    }

    cp_cheri_cs2_sealed: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_b.otype != 0;

    // As cp_cheri_cs1_cor
    cp_cheri_cs2_cor: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_b.cap_cor {
      bins bin0 = {2'b00};  // top 0,  base 0
      bins bin1 = {2'b10};  // top +1, base 0
      bins bin3 = {2'b01};  // top 0,  base -1
      bins bin5 = {2'b11};  // top -1, base -1
    }

    cp_cheri_cs2_top: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_b.top {
      bins bin_all1 = {9'h1ff};
      bins bin_all0 = {9'h0};
      bins bin1     = {[9'h1:9'h1fe]};
    }

    cp_cheri_cs2_base: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_b.base {
      bins bin_all1 = {9'h1ff};
      bins bin_all0 = {9'h0};
      bins bin1     = {[9'h1:9'h1fe]};
    }

    cp_cheri_cs2_perms: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_b.perms {
      wildcard bins gl0  = {12'b????_????_???0};
      wildcard bins gl1  = {12'b????_????_???1};
      wildcard bins lg0  = {12'b????_????_??0?};
      wildcard bins lg1  = {12'b????_????_??1?};
      wildcard bins sd0  = {12'b????_????_?0??};
      wildcard bins sd1  = {12'b????_????_?1??};
      wildcard bins lm0  = {12'b????_????_0???};
      wildcard bins lm1  = {12'b????_????_1???};
      wildcard bins sl0  = {12'b????_???0_????};
      wildcard bins sl1  = {12'b????_???1_????};
      wildcard bins ld0  = {12'b????_??0?_????};
      wildcard bins ld1  = {12'b????_??1?_????};
      wildcard bins mc0  = {12'b????_?0??_????};
      wildcard bins mc1  = {12'b????_?1??_????};
      wildcard bins sr0  = {12'b????_0???_????};
      wildcard bins sr1  = {12'b????_1???_????};
      wildcard bins ex0  = {12'b???0_????_????};
      wildcard bins ex1  = {12'b???1_????_????};
      wildcard bins us0  = {12'b??0?_????_????};
      wildcard bins us1  = {12'b??1?_????_????};
      wildcard bins se0  = {12'b?0??_????_????};
      wildcard bins se1  = {12'b?1??_????_????};
      wildcard bins u00  = {12'b0???_????_????};
      wildcard bins u01  = {12'b1???_????_????};
    }

    cp_cheri_cs2_perm_gl: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_b.perms.GL;
    cp_cheri_cs2_perm_se: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_b.perms.SE;
    cp_cheri_cs2_perm_us: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_b.perms.US;

    cp_cheri_cs2_address: coverpoint fcov_cheri_cs2_addr_0cnt {
      bins valid[] = {[0:32]};
      ignore_bins ignore = {[33:$]};
    }

    cp_cheri_cs2_seal_type: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.rf_rdata_b {
      bins bin_hi    = {[32'd16:$]};
      bins bin_mi[]  = {[32'd8:32'd15]};
      bins bin_lo[]  = {[32'd0:32'd7]};
    }

    // CAndPerm mask (rs2 lower 12 bits)
    cp_cheri_rs2_perm_mask: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.rf_rdata_b[11:0] {
      wildcard bins gl0  = {12'b????_????_???0};
      wildcard bins gl1  = {12'b????_????_???1};
      wildcard bins lg0  = {12'b????_????_??0?};
      wildcard bins lg1  = {12'b????_????_??1?};
      wildcard bins sd0  = {12'b????_????_?0??};
      wildcard bins sd1  = {12'b????_????_?1??};
      wildcard bins lm0  = {12'b????_????_0???};
      wildcard bins lm1  = {12'b????_????_1???};
      wildcard bins sl0  = {12'b????_???0_????};
      wildcard bins sl1  = {12'b????_???1_????};
      wildcard bins ld0  = {12'b????_??0?_????};
      wildcard bins ld1  = {12'b????_??1?_????};
      wildcard bins mc0  = {12'b????_?0??_????};
      wildcard bins mc1  = {12'b????_?1??_????};
      wildcard bins sr0  = {12'b????_0???_????};
      wildcard bins sr1  = {12'b????_1???_????};
      wildcard bins ex0  = {12'b???0_????_????};
      wildcard bins ex1  = {12'b???1_????_????};
      wildcard bins us0  = {12'b??0?_????_????};
      wildcard bins us1  = {12'b??1?_????_????};
      wildcard bins se0  = {12'b?0??_????_????};
      wildcard bins se1  = {12'b?1??_????_????};
      wildcard bins u00  = {12'b0???_????_????};
      wildcard bins u01  = {12'b1???_????_????};
    }

    // ------------------------------------------------------------------
    // CD (result capability) coverage
    // ------------------------------------------------------------------

    cp_cheri_cd_tag: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.result_cap_o.valid;

    cp_cheri_cd_exp: coverpoint cheriot_expand_exp(g_cheriot_ex.u_ibex_cheriot_ex.result_cap_o.cexp) {
      bins bin0 = {0};
      bins bin1 = {[1:14]};
      bins bin2 = {24};
    }

    cp_cheri_cd_otype: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.result_cap_o.otype {
      bins bin[] = {[0:7]};
    }

    // As cp_cheri_cs1_cor
    cp_cheri_cd_cor: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.result_cap_o.cap_cor {
      bins bin0 = {2'b00};  // top 0,  base 0
      bins bin1 = {2'b10};  // top +1, base 0
      bins bin3 = {2'b01};  // top 0,  base -1
      bins bin5 = {2'b11};  // top -1, base -1
    }

    cp_cheri_cd_top: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.result_cap_o.top {
      bins bin_all1 = {9'h1ff};
      bins bin_all0 = {9'h0};
      bins bin1     = {[9'h1:9'h1fe]};
    }

    cp_cheri_cd_base: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.result_cap_o.base {
      bins bin_all1 = {9'h1ff};
      bins bin_all0 = {9'h0};
      bins bin1     = {[9'h1:9'h1fe]};
    }

    cp_cheri_cd_cperms: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.result_cap_o.cperms;

    cp_cheri_cd_address: coverpoint fcov_cheri_cd_addr_0cnt {
      bins valid[] = {[0:32]};
      ignore_bins ignore = {[33:$]};
    }

    // ------------------------------------------------------------------
    // Violation / exception coverage
    // ------------------------------------------------------------------

    // Permission and address violations (any of perm_vio_vec bits or addr_bound_vio)
    cp_cheri_vio: coverpoint
      {g_cheriot_ex.u_ibex_cheriot_ex.perm_vio_vec, g_cheriot_ex.u_ibex_cheriot_ex.addr_bound_vio}
      iff (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i) {
      wildcard bins bound = {9'b?_????_???1};
      wildcard bins tag   = {9'b?_????_??1?};
      wildcard bins seal  = {9'b?_????_?1??};
      wildcard bins ex    = {9'b?_????_1???};
      wildcard bins ld    = {9'b?_???1_????};
      wildcard bins sd    = {9'b?_??1?_????};
      wildcard bins sc    = {9'b?_?1??_????};
      wildcard bins sr    = {9'b?_1???_????};
      wildcard bins align = {9'b1_????_????};
    }

    cp_cheri_vio_slc: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.perm_vio_slc
      iff (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i);

    // Tag clearing: cs1 had tag but result does not (CAND_PERM, CSetBounds, etc.)
    cp_cheri_tag_clear_cs1cd: coverpoint fcov_cheri_tag_clear_cs1cd
      iff (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i);

    // WB-stage exceptions (CJALR seal/tag, CCSR_RW bad address)
    cp_cheri_wb_exception_causes: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.cheriot_err_cause
      iff (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_wb_err_d) {
      bins tag     = {5'h2};
      bins seal    = {5'h3};
      bins perm_ex = {5'h11};
      bins perm_sr = {5'h18};
      bins other   = {5'h0};
      illegal_bins illegal = default;
    }

    // CLC/CSC CHERI exceptions
    cp_cheri_clsc_exception_causes: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.cheriot_err_cause
      iff (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_lsu_req & g_cheriot_ex.u_ibex_cheriot_ex.cheriot_lsu_err) {
      bins bounds     = {5'h1};
      bins tag        = {5'h2};
      bins seal       = {5'h3};
      bins perm_load  = {5'h12};
      bins perm_store = {5'h13};
      bins perm_sc    = {5'h15};
      bins other      = {5'h0};
      illegal_bins illegal = default;
    }

    // RV32 load/store CHERI exceptions (PCC-bound load/store)
    cp_cheri_rv32lsu_exception_causes: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.rv32_err_cause
      iff (g_cheriot_ex.u_ibex_cheriot_ex.rv32_lsu_req_i & g_cheriot_ex.u_ibex_cheriot_ex.rv32_lsu_err) {
      bins bounds     = {5'h1};
      bins tag        = {5'h2};
      bins seal       = {5'h3};
      bins perm_load  = {5'h12};
      bins perm_store = {5'h13};
      illegal_bins illegal = default;
    }

    // Register index in exception info [9:5]. With CCSR_RW excluded by the qualifier below,
    // this field is rf_raddr_a_i (ibex_cheriot_ex.sv:915). CHERI faults are raised only with
    // cheriot_enable_i on, where the decoder rejects any instruction naming x16-x31 as illegal
    // (CheriLimit16Regs, ibex_decoder.sv) -- RV32E=0 in ibex_configs.yaml does not matter
    // here. A CHERI fault against x16-x31 would mean such an instruction executed.
    cp_cheri_exception_reg_id: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.cheriot_wb_err_info_d[9:5]
      iff ((g_cheriot_ex.u_ibex_cheriot_ex.cheriot_wb_err_d & ~cheriot_operator.CCSR_RW) |
           (g_cheriot_ex.u_ibex_cheriot_ex.lsu_req_o & g_cheriot_ex.u_ibex_cheriot_ex.lsu_cheriot_err_o)) {
      bins x0        = {5'd0};
      bins x_lower[] = {[5'd1:5'd15]};
      illegal_bins x_upper = {[5'd16:5'd31]};
    }

    // ------------------------------------------------------------------
    // SCR (special capability register) access coverage
    // ------------------------------------------------------------------

    cp_cheri_scr_addr: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.csr_addr_o {
      bins good[] = {[28:31]};
      bins bad    = {[0:23]};
      ignore_bins ignore = {[24:26]};
    }

    cp_cheri_scr_read_only: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.csr_addr_o
      iff (fcov_cheri_scr_read_only) {
      bins good[] = {[28:31]};
      // illegal_scr_addr forces csr_access_o = 0 (ibex_cheriot_ex.sv CCSR_RW); the illegal-SCR
      // attempt itself is covered by cp_cheri_scr_addr
      illegal_bins bad = {[0:23], 27};
      ignore_bins ignore = {[24:26]};
    }

    cp_cheri_scr_write: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.csr_addr_o
      iff (fcov_cheri_scr_write) {
      bins good[] = {[28:31]};
      // illegal_scr_addr forces csr_op_en_raw = 0 (ibex_cheriot_ex.sv CCSR_RW)
      illegal_bins bad = {[0:23], 27};
      ignore_bins ignore = {[24:26]};
    }

    // ------------------------------------------------------------------
    // LSU coverage
    // ------------------------------------------------------------------

    cp_cheri_cpu_lsu_req: coverpoint fcov_cheri_cpu_lsu_req;
    cp_cheri_cpu_lsu_err: coverpoint fcov_cheri_cpu_lsu_err;

    cp_cheri_mshwm_set: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.csr_mshwm_set_o;

    // ------------------------------------------------------------------
    // Fetch violation (PCC bounds/tag) coverage
    // ------------------------------------------------------------------

    cp_cheri_fetch_tag_vio: coverpoint id_stage_i.instr_fetch_cheriot_acc_vio_i
      iff (id_stage_i.instr_valid_i);

    cp_cheri_fetch_bound_vio: coverpoint id_stage_i.instr_fetch_cheriot_bound_vio_i
      iff (id_stage_i.instr_valid_i);

    cheriot_fetch_cross: cross cp_cheri_fetch_tag_vio, cp_cheri_fetch_bound_vio;

    // REQ_BND_07, REQ_CFI_05, REQ_IFE_01: fetch-violation exception entry (controller FLUSH,
    // instr_fetch_err_prio, csr_save_cause_o) against the MEPCC tag-clear request. A PCC bounds
    // violation clears the saved MEPCC tag; a PCC tag/permission/seal violation (acc_vio, which
    // takes priority) does not. Expression is {acc_vio, bound_vio, csr_mepcc_clrtag_o}.
    cp_cheri_fetch_bound_mepcc_clrtag: coverpoint {id_stage_i.instr_fetch_cheriot_acc_vio_i,
                                                   id_stage_i.instr_fetch_cheriot_bound_vio_i,
                                                   id_stage_i.controller_i.csr_mepcc_clrtag_o}
      iff (cheriot_pmode & (id_stage_i.controller_i.ctrl_fsm_cs == FLUSH) &
           id_stage_i.controller_i.csr_save_cause_o &
           id_stage_i.controller_i.instr_fetch_err_prio) {
      bins          bound_vio_clrtag  = {3'b011};
      wildcard bins acc_vio_no_clrtag = {3'b1?0};
    }

    // ------------------------------------------------------------------
    // TRVK stall coverage
    // (Hardware stall only exists if TRVK stage is present; always 0 in ibex-private)
    // ------------------------------------------------------------------

    // cp_cheri_trvk_stall removed 2026-09-18 during the port from ibex-private.
    // It covered id_stage_i.stall_cheri_trvk, which does not exist in this tree:
    // TRVK is now a separate block (rtl/ibex_trvk.sv) sitting on the data bus
    // rather than a stall signal into the ID stage, and there is no equivalent
    // signal to point at. The original comment above already noted the stall was
    // always 0 in ibex-private, so nothing was being covered by it there either.
    // Covering the new block needs coverpoints on ibex_trvk's own state.

    // Register-file read hazards (load-use): both ports, gated by WritebackStage generate block
    cp_cheri_rd_a_hz: coverpoint id_stage_i.gen_stall_mem.rf_rd_a_hz;
    cp_cheri_rd_b_hz: coverpoint id_stage_i.gen_stall_mem.rf_rd_b_hz;

    // CLC clear-permission bits applied to the loaded capability.
    // cap_clrperm_t is three bits in this tree -- {CTAG[2], SD_LM[1], GL_LG[0]}, see
    // ibex_cheriot_pkg.sv. ibex-private had a four-bit field with a reserved bit, and the
    // ported version both read a [3:0] slice that does not exist and marked bit 2 as
    // reserved. Bit 2 is CTAG here: the tag-clear for an authority without MC. The three bits are
    // ~MC, ~LM and ~LG of the authority (ibex_cheriot_ex.sv CLOAD_CAP), and they are not
    // independent: cheriot_expand_perms gives LM and LG only to the MRW, MRO and EXE formats, all
    // of which have MC (ibex_cheriot_pkg.sv), so an authority without MC also lacks LM and LG.
    cp_cheri_clc_clrperm: coverpoint load_store_unit_i.resp_lc_clrperm_q[2:0]
      iff (~load_store_unit_i.data_we_q & load_store_unit_i.lsu_resp_valid_o) {
      bins none        = {3'b000};  // capability loaded unmodified
      bins gl_lg       = {3'b001};  // GL and LG cleared (authorising cap lacks LG)
      bins sd_lm       = {3'b010};  // SD and LM cleared (authorising cap lacks LM)
      // both: an MRW, MRO or EXE format authority with LM and LG both clear (an MWO one has no LD
      // and the CLC faults instead)
      bins sd_lm_gl_lg = {3'b011};
      bins ctag        = {3'b111};  // tag cleared (no MC, hence no LM and no LG either)
      // CTAG without both LM and LG cleared: no permission format has LM or LG without MC
      illegal_bins ctag_without_lm_lg = {3'b100, 3'b101, 3'b110};
    }

    // ------------------------------------------------------------------
    // CLC/CSC round-trip field coverage
    // Previously blocked on data_tag_i hardwired to 0 (E1). Now that
    // data_tag_i is driven from data_mem_vif.rtag, tagged capabilities can
    // be loaded back via CLC and these coverpoints are reachable.
    // Gate: CLC response valid with a tagged (valid) capability result.
    // ------------------------------------------------------------------

    // Exponent of loaded capability — exercises byte-precise, mid, and root bounds.
    cp_clc_csc_bounds_roundtrip: coverpoint cheriot_expand_exp(load_store_unit_i.lsu_rcap_o.cexp)
      iff (~load_store_unit_i.data_we_q & load_store_unit_i.resp_is_cap_q &
           load_store_unit_i.lsu_resp_valid_o & load_store_unit_i.lsu_rcap_o.valid) {
      bins exact  = {5'd0};           // exp=0: byte-precise bounds
      bins mid[]  = {[5'd1:5'd13]};   // standard sub-page granularity
      bins large_exp  = {5'd14};      // maximum sub-RESETEXP exponent
      bins root   = {5'd24};          // RESETEXP: full-address-space capability
    }

    // Permission class of loaded capability (cperms[5]=GL; [4:3]=type selector).
    // cperms[4:3]: 00=sealing/system, 01=execution, 10=data/seal-cap, 11=load-cap-mutable.
    cp_clc_csc_perm_roundtrip: coverpoint load_store_unit_i.lsu_rcap_o.cperms
      iff (~load_store_unit_i.data_we_q & load_store_unit_i.resp_is_cap_q &
           load_store_unit_i.lsu_resp_valid_o & load_store_unit_i.lsu_rcap_o.valid) {
      wildcard bins gl0_seal  = {6'b0_00???};  // local: sealing/system class
      wildcard bins gl0_exec  = {6'b0_01???};  // local: execution class (has EX)
      wildcard bins gl0_data  = {6'b0_10???};  // local: data/seal-cap class
      wildcard bins gl0_ldcap = {6'b0_11???};  // local: mutable load-cap class
      wildcard bins gl1_seal  = {6'b1_00???};  // global: sealing/system class
      wildcard bins gl1_exec  = {6'b1_01???};  // global: execution class (has EX)
      wildcard bins gl1_data  = {6'b1_10???};  // global: data/seal-cap class
      wildcard bins gl1_ldcap = {6'b1_11???};  // global: mutable load-cap class
    }

    // Object type of loaded capability — unsealed, sentry, or user-sealed.
    cp_clc_csc_otype_roundtrip: coverpoint load_store_unit_i.lsu_rcap_o.otype
      iff (~load_store_unit_i.data_we_q & load_store_unit_i.resp_is_cap_q &
           load_store_unit_i.lsu_resp_valid_o & load_store_unit_i.lsu_rcap_o.valid) {
      bins unsealed  = {3'd0};          // OTYPE_UNSEALED
      bins sentry[]  = {[3'd1:3'd5]};   // sentry types 1–5
      bins sealed[]  = {[3'd6:3'd7]};   // user/data-sealed types 6–7
    }

    // ------------------------------------------------------------------
    // MTCC / MEPCC legalization coverage
    // ------------------------------------------------------------------

    cp_cheri_mtcc_legalization_addr: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.rf_rdata_a[1:0]
      iff (cs_registers_i.mtvec_en_cheriot) {
      bins good  = {2'h0};
      bins bad[] = {[2'h1:2'h3]};
    }

    cp_cheri_mtcc_legalization_perm: coverpoint fcov_cheri_scr_wfcap.perms.EX
      iff (cs_registers_i.mtvec_en_cheriot);

    cp_cheri_mtcc_legalization_sealed: coverpoint fcov_cheri_scr_wfcap.otype
      iff (cs_registers_i.mtvec_en_cheriot) {
      bins good = {3'h0};
      bins bad  = {[3'h1:3'h7]};
    }

    cp_cheri_mepcc_legalization_addr: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.rf_rdata_a[0]
      iff (cs_registers_i.mepc_en_cheriot);

    cp_cheri_mepcc_legalization_perm: coverpoint fcov_cheri_scr_wfcap.perms.EX
      iff (cs_registers_i.mepc_en_cheriot);

    cp_cheri_mepcc_legalization_sealed: coverpoint fcov_cheri_scr_wfcap.otype
      iff (cs_registers_i.mepc_en_cheriot) {
      bins good = {3'h0};
      bins bad  = {[3'h1:3'h7]};
    }

    // ------------------------------------------------------------------
    // Illegal MRET (missing ASR permission)
    // ------------------------------------------------------------------

    cp_cheri_illegal_mret: coverpoint id_stage_i.controller_i.mret_cheriot_asr_err;

    // ------------------------------------------------------------------
    // Representability / bound-check case coverpoints
    // ------------------------------------------------------------------

    cp_cheri_cd_cs1_repr_cases: coverpoint fcov_cheri_cd_cs1_repr_cases {
      bins case0 = {3'd0};
      bins case1 = {3'd1};
      bins case2 = {3'd2};
    }

    cp_cheri_cd_pcc_repr_cases: coverpoint fcov_cheri_cd_pcc_repr_cases {
      bins case0 = {3'd0};
      bins case1 = {3'd1};
      bins case2 = {3'd2};
    }

    // Sampled only for an executing CJAL outside debug mode: unqualified, it compared PCC with
    // branch_target_o (0 by default) on every cycle. Outside debug mode an instruction is fetched
    // only if PCC.base <= PC and PC + 2 <= PCC.top (ibex_if_stage.sv base_ok/hdrm_ge2), and PCC
    // changes only through a flush, so PCC length >= 2; these values need a shorter PCC, or length
    // 2 with an odd target (targets are even)
    cp_cheri_cjal_bound: coverpoint fcov_cheri_cjal_bound
      iff (cheriot_pmode & cheriot_operator.CJAL &
           g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i & ~debug_mode) {
      `FCOV_BOUND_CASE_BINS
      `FCOV_EVEN_TARGET_IGNORE
      ignore_bins pcc_len_lt2 =
        {9'h00a, 9'h011, 9'h012, 9'h021, 9'h031, 9'h0a1, 9'h10a, 9'h112};
    }

    cp_cheri_cjalr_bound: coverpoint fcov_cheri_cjalr_bound {
      `FCOV_BOUND_CASE_BINS
      `FCOV_EVEN_TARGET_IGNORE
    }

    // Sampled only for a taken conditional branch outside debug mode, as cp_instr_branch (it
    // compared PCC with branch_target_ex on every cycle); pcc_len_lt2 as for cp_cheri_cjal_bound
    cp_cheri_branch_bound: coverpoint fcov_cheri_branch_bound
      iff (cheriot_pmode & id_stage_i.instr_executing & ~debug_mode &
           (id_stage_i.instr_rdata_i[6:0] == ibex_pkg::OPCODE_BRANCH) &
           id_stage_i.branch_decision_i) {
      `FCOV_BOUND_CASE_BINS
      `FCOV_EVEN_TARGET_IGNORE
      ignore_bins pcc_len_lt2 =
        {9'h00a, 9'h011, 9'h012, 9'h021, 9'h031, 9'h0a1, 9'h10a, 9'h112};
    }

    cp_cheri_clsc_bound: coverpoint fcov_cheri_clsc_bound {
      `FCOV_BOUND_CASE_BINS
    }

    cp_cheri_seal_bound: coverpoint fcov_cheri_seal_bound {
      wildcard ignore_bins ignore0 = {4'b??11};
      wildcard ignore_bins ignore1 = {4'b11??};
      wildcard ignore_bins ignore2 = {4'b?1?1};
      wildcard ignore_bins ignore3 = {4'b?11?};
      wildcard ignore_bins ignore4 = {4'b1??1};
    }

    // CLC/CSC address LSBs
    cp_cheri_clsc_addr_lsb: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.cheriot_ls_chkaddr[2:0];

    // SetBounds input configuration cases
    cp_cheri_setbounds_cases: coverpoint fcov_cheri_setbounds {
      wildcard ignore_bins ignore0 = {5'b???11};
      wildcard ignore_bins ignore1 = {5'b?11??};
      // 5, 6, 9 need top33 < base32, which makes the 33-bit length > 2^32, so b4 (a 32-bit
      // request <= length) is always set (fcov_setbounds_cases_fn)
      ignore_bins top_lt_base_b4_clear = {5'd5, 5'd6, 5'd9};
    }

    cp_cheri_setboundsimm_cases: coverpoint fcov_cheri_setboundsimm {
      wildcard ignore_bins ignore0 = {5'b???11};
      wildcard ignore_bins ignore1 = {5'b?11??};
      // As cp_cheri_setbounds_cases
      ignore_bins top_lt_base_b4_clear = {5'd5, 5'd6, 5'd9};
    }

    cp_cheri_rs2_req_len: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.rf_rdata_b {
      bins little[] = {[32'd0:32'd8]};
      bins other    = {[32'd9:$]};
    }

    // get_size() is the index of the highest set bit + 1 of a 32-bit value: 0..32. The coverpoint
    // is 6 bits wide, so without explicit bins 33..63 would be 31 unreachable auto bins.
    cp_cheri_rs1_bitsize: coverpoint fcov_cheri_rs1_bitsize {
      bins valid[] = {[0:32]};
    }

    cp_cheri_mstatus_mie: coverpoint cs_registers_i.csr_mstatus_mie_o;

    // ------------------------------------------------------------------
    // CHERIoT per-instruction cross coverage
    // ------------------------------------------------------------------

    // Gate individual instruction coverpoints on cheriot_exec_id_i
    cp_instr_cauicgp: coverpoint cheriot_operator.CAUICGP
      iff (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i) {
      bins bin1 = {1'b1};
    }
    // Not in debug mode: the PCC fetch bounds check is off there (ibex_if_stage.sv), so the PC
    // need not lie inside PCC, which the ignore_bins of cheriot_cauipcc_cross rely on
    cp_instr_cauipcc: coverpoint cheriot_operator.CAUIPCC
      iff (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i & ~debug_mode) {
      bins bin1 = {1'b1};
    }
    cp_instr_cincaddrimm: coverpoint cheriot_operator.CINC_ADDR_IMM
      iff (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i) {
      bins bin1 = {1'b1};
    }
    cp_instr_cincaddr: coverpoint cheriot_operator.CINC_ADDR
      iff (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i) {
      bins bin1 = {1'b1};
    }
    cp_instr_csetaddr: coverpoint cheriot_operator.CSET_ADDR
      iff (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i) {
      bins bin1 = {1'b1};
    }
    cp_instr_candperm: coverpoint cheriot_operator.CAND_PERM
      iff (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i) {
      bins bin1 = {1'b1};
    }
    cp_instr_ccleartag: coverpoint cheriot_operator.CCLEAR_TAG
      iff (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i) {
      bins bin1 = {1'b1};
    }
    cp_instr_cmove: coverpoint cheriot_operator.CMOVE_CAP
      iff (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i) {
      bins bin1 = {1'b1};
    }
    cp_instr_cseqx: coverpoint cheriot_operator.CIS_EQUAL
      iff (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i) {
      bins bin1 = {1'b1};
    }
    cp_instr_ctestsubset: coverpoint cheriot_operator.CIS_SUBSET
      iff (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i) {
      bins bin1 = {1'b1};
    }
    cp_instr_csub: coverpoint cheriot_operator.CSUB_CAP
      iff (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i) {
      bins bin1 = {1'b1};
    }
    cp_instr_csethigh: coverpoint cheriot_operator.CSET_HIGH
      iff (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i) {
      bins bin1 = {1'b1};
    }
    // CGET_* ops: all fold into CGET_FIELD + cap_field_sel
    cp_instr_cget_field: coverpoint cheriot_operator.CGET_FIELD
      iff (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i) {
      bins bin1 = {1'b1};
    }
    cp_instr_cspecialrw: coverpoint cheriot_operator.CCSR_RW
      iff (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i) {
      bins bin1 = {1'b1};
    }
    cp_instr_cjal: coverpoint cheriot_operator.CJAL
      iff (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i) {
      bins bin1 = {1'b1};
    }
    cp_instr_cjalr: coverpoint cheriot_operator.CJALR
      iff (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i) {
      bins bin1 = {1'b1};
    }
    cp_instr_clc: coverpoint cheriot_operator.CLOAD_CAP
      iff (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i) {
      bins bin1 = {1'b1};
    }
    cp_instr_csc: coverpoint cheriot_operator.CSTORE_CAP
      iff (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i) {
      bins bin1 = {1'b1};
    }
    cp_instr_cseal: coverpoint cheriot_operator.CSEAL
      iff (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i) {
      bins bin1 = {1'b1};
    }
    cp_instr_cunseal: coverpoint cheriot_operator.CUNSEAL
      iff (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i) {
      bins bin1 = {1'b1};
    }
    cp_instr_csetbounds: coverpoint cheriot_operator.CSET_BOUNDS
      iff (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i) {
      bins bin1 = {1'b1};
    }
    cp_instr_csetboundsexact: coverpoint cheriot_operator.CSET_BOUNDS_EX
      iff (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i) {
      bins bin1 = {1'b1};
    }
    cp_instr_csetboundsimm: coverpoint cheriot_operator.CSET_BOUNDS_IMM
      iff (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i) {
      bins bin1 = {1'b1};
    }
    cp_instr_csetboundsrndn: coverpoint cheriot_operator.CSET_BOUNDS_RNDN
      iff (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i) {
      bins bin1 = {1'b1};
    }
    cp_instr_cram: coverpoint cheriot_operator.CRAM
      iff (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i) {
      bins bin1 = {1'b1};
    }
    cp_instr_crrl: coverpoint cheriot_operator.CRRL
      iff (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i) {
      bins bin1 = {1'b1};
    }

    // -- Address arithmetic crosses --
    // Note on ignore_bins syntax: Xcelium/IMC does not support the !binsof() negation operator in
    // cross ignore_bins expressions. All ignore_bins here use only explicit positive binsof()
    // intersections, expanding "!binsof(cp.X)" into one line per remaining bin of cp.
    cheriot_cauicgp_cross: cross cp_cheri_cs1_tag, cp_cheri_cd_cs1_repr_cases,
      cp_cheri_cs1_sealed, cp_cheri_cs1_exp, cp_cheri_imm20, cp_instr_cauicgp {
      // fcov_repr_cases() returns case0 for E = 24 (its representable region, 2^33, covers the
      // address space), so case1/case2 cannot be sampled
      ignore_bins e24_nonrepr_c1 = binsof(cp_cheri_cs1_exp.bin2) && binsof(cp_cheri_cd_cs1_repr_cases.case1);
      ignore_bins e24_nonrepr_c2 = binsof(cp_cheri_cs1_exp.bin2) && binsof(cp_cheri_cd_cs1_repr_cases.case2);
      // Increment 0: cd.addr == cs1.addr, and the bounds are decoded from that address, so
      // addr - base < 2^(E+9) (no case2), and a tagged base never wraps above it (no tagged case1)
      ignore_bins inc0_above_e0    = binsof(cp_cheri_imm20.bin1) && binsof(cp_cheri_cs1_exp.bin0) && binsof(cp_cheri_cd_cs1_repr_cases.case2);
      ignore_bins inc0_above_e1    = binsof(cp_cheri_imm20.bin1) && binsof(cp_cheri_cs1_exp.bin1) && binsof(cp_cheri_cd_cs1_repr_cases.case2);
      ignore_bins inc0_tagbelow_e0 = binsof(cp_cheri_imm20.bin1) && binsof(cp_cheri_cs1_exp.bin0) && binsof(cp_cheri_cs1_tag) intersect {1'b1} && binsof(cp_cheri_cd_cs1_repr_cases.case1);
      ignore_bins inc0_tagbelow_e1 = binsof(cp_cheri_imm20.bin1) && binsof(cp_cheri_cs1_exp.bin1) && binsof(cp_cheri_cs1_tag) intersect {1'b1} && binsof(cp_cheri_cd_cs1_repr_cases.case1);
      // AUICGP adds imm20 << 11: a non-zero multiple of 2 KiB never stays in E = 0's 512 B region
      ignore_bins e0_imm_repr_b2 = binsof(cp_cheri_cs1_exp.bin0) && binsof(cp_cheri_imm20.bin2) && binsof(cp_cheri_cd_cs1_repr_cases.case0);
      ignore_bins e0_imm_repr_b3 = binsof(cp_cheri_cs1_exp.bin0) && binsof(cp_cheri_imm20.bin3) && binsof(cp_cheri_cd_cs1_repr_cases.case0);
      ignore_bins e0_imm_repr_b4 = binsof(cp_cheri_cs1_exp.bin0) && binsof(cp_cheri_imm20.bin4) && binsof(cp_cheri_cd_cs1_repr_cases.case0);
      ignore_bins e0_imm_repr_b5 = binsof(cp_cheri_cs1_exp.bin0) && binsof(cp_cheri_imm20.bin5) && binsof(cp_cheri_cd_cs1_repr_cases.case0);
      // imm20 = 0x80000 adds -2^30, larger than any E <= 14 region (at most 2^23)
      ignore_bins e14_m2p30_repr = binsof(cp_cheri_cs1_exp.bin1) && binsof(cp_cheri_imm20.bin3) && binsof(cp_cheri_cd_cs1_repr_cases.case0);
    }

    cheriot_cauipcc_cross: cross cp_cheri_cd_pcc_repr_cases, cp_cheri_pcc_exp,
      cp_cheri_imm20, cp_instr_cauipcc {
      // fcov_repr_cases() returns case0 for E = 24, so case1/case2 cannot be sampled
      ignore_bins e24_nonrepr_c1 = binsof(cp_cheri_pcc_exp.bin2) && binsof(cp_cheri_cd_pcc_repr_cases.case1);
      ignore_bins e24_nonrepr_c2 = binsof(cp_cheri_pcc_exp.bin2) && binsof(cp_cheri_cd_pcc_repr_cases.case2);
      // Increment 0: cd.addr == PC, and outside debug mode an AUIPCC executes only with
      // PCC.base <= PC < PCC.top <= base + 2^(E+9) (ibex_if_stage.sv fetch check), so case0
      ignore_bins inc0_nonrepr_c1 = binsof(cp_cheri_imm20.bin1) && binsof(cp_cheri_cd_pcc_repr_cases.case1);
      ignore_bins inc0_nonrepr_c2 = binsof(cp_cheri_imm20.bin1) && binsof(cp_cheri_cd_pcc_repr_cases.case2);
      // AUIPCC adds imm20 << 11 to a PC inside PCC: a non-zero multiple of 2 KiB never stays in
      // E = 0's 512 B region
      ignore_bins e0_imm_repr_b2 = binsof(cp_cheri_pcc_exp.bin0) && binsof(cp_cheri_imm20.bin2) && binsof(cp_cheri_cd_pcc_repr_cases.case0);
      ignore_bins e0_imm_repr_b3 = binsof(cp_cheri_pcc_exp.bin0) && binsof(cp_cheri_imm20.bin3) && binsof(cp_cheri_cd_pcc_repr_cases.case0);
      ignore_bins e0_imm_repr_b4 = binsof(cp_cheri_pcc_exp.bin0) && binsof(cp_cheri_imm20.bin4) && binsof(cp_cheri_cd_pcc_repr_cases.case0);
      ignore_bins e0_imm_repr_b5 = binsof(cp_cheri_pcc_exp.bin0) && binsof(cp_cheri_imm20.bin5) && binsof(cp_cheri_cd_pcc_repr_cases.case0);
      // imm20 = 0x80000 adds -2^30, larger than any E <= 14 region (at most 2^23)
      ignore_bins e14_m2p30_repr = binsof(cp_cheri_pcc_exp.bin1) && binsof(cp_cheri_imm20.bin3) && binsof(cp_cheri_cd_pcc_repr_cases.case0);
    }

    cheriot_cincaddrimm_cross: cross cp_cheri_cs1_tag, cp_cheri_cd_cs1_repr_cases,
      cp_cheri_cs1_sealed, cp_cheri_cs1_exp, cp_cheri_imm12, cp_instr_cincaddrimm {
      // fcov_repr_cases() returns case0 for E = 24 (its representable region, 2^33, covers the
      // address space), so case1/case2 cannot be sampled
      ignore_bins e24_nonrepr_c1 = binsof(cp_cheri_cs1_exp.bin2) && binsof(cp_cheri_cd_cs1_repr_cases.case1);
      ignore_bins e24_nonrepr_c2 = binsof(cp_cheri_cs1_exp.bin2) && binsof(cp_cheri_cd_cs1_repr_cases.case2);
      // Increment 0: cd.addr == cs1.addr, and the bounds are decoded from that address, so
      // addr - base < 2^(E+9) (no case2), and a tagged base never wraps above it (no tagged case1)
      ignore_bins inc0_above_e0    = binsof(cp_cheri_imm12.bin1) && binsof(cp_cheri_cs1_exp.bin0) && binsof(cp_cheri_cd_cs1_repr_cases.case2);
      ignore_bins inc0_above_e1    = binsof(cp_cheri_imm12.bin1) && binsof(cp_cheri_cs1_exp.bin1) && binsof(cp_cheri_cd_cs1_repr_cases.case2);
      ignore_bins inc0_tagbelow_e0 = binsof(cp_cheri_imm12.bin1) && binsof(cp_cheri_cs1_exp.bin0) && binsof(cp_cheri_cs1_tag) intersect {1'b1} && binsof(cp_cheri_cd_cs1_repr_cases.case1);
      ignore_bins inc0_tagbelow_e1 = binsof(cp_cheri_imm12.bin1) && binsof(cp_cheri_cs1_exp.bin1) && binsof(cp_cheri_cs1_tag) intersect {1'b1} && binsof(cp_cheri_cd_cs1_repr_cases.case1);
      // imm12 = -2048 never stays in E = 0's 512 B region
      ignore_bins e0_m2048_repr = binsof(cp_cheri_cs1_exp.bin0) && binsof(cp_cheri_imm12.bin3) && binsof(cp_cheri_cd_cs1_repr_cases.case0);
    }

    cheriot_cincaddr_cross: cross cp_cheri_cs1_tag, cp_cheri_cd_cs1_repr_cases,
      cp_cheri_cs1_sealed, cp_cheri_cs1_exp, cp_cheri_rs2_as_inc, cp_instr_cincaddr {
      // fcov_repr_cases() returns case0 for E = 24 (its representable region, 2^33, covers the
      // address space), so case1/case2 cannot be sampled
      ignore_bins e24_nonrepr_c1 = binsof(cp_cheri_cs1_exp.bin2) && binsof(cp_cheri_cd_cs1_repr_cases.case1);
      ignore_bins e24_nonrepr_c2 = binsof(cp_cheri_cs1_exp.bin2) && binsof(cp_cheri_cd_cs1_repr_cases.case2);
      // Increment 0: cd.addr == cs1.addr, and the bounds are decoded from that address, so
      // addr - base < 2^(E+9) (no case2), and a tagged base never wraps above it (no tagged case1)
      ignore_bins inc0_above_e0    = binsof(cp_cheri_rs2_as_inc.bin1) && binsof(cp_cheri_cs1_exp.bin0) && binsof(cp_cheri_cd_cs1_repr_cases.case2);
      ignore_bins inc0_above_e1    = binsof(cp_cheri_rs2_as_inc.bin1) && binsof(cp_cheri_cs1_exp.bin1) && binsof(cp_cheri_cd_cs1_repr_cases.case2);
      ignore_bins inc0_tagbelow_e0 = binsof(cp_cheri_rs2_as_inc.bin1) && binsof(cp_cheri_cs1_exp.bin0) && binsof(cp_cheri_cs1_tag) intersect {1'b1} && binsof(cp_cheri_cd_cs1_repr_cases.case1);
      ignore_bins inc0_tagbelow_e1 = binsof(cp_cheri_rs2_as_inc.bin1) && binsof(cp_cheri_cs1_exp.bin1) && binsof(cp_cheri_cs1_tag) intersect {1'b1} && binsof(cp_cheri_cd_cs1_repr_cases.case1);
      // rs2 = 0x80000000 adds 2^31, larger than any E <= 14 region (at most 2^23)
      ignore_bins e14_2p31_repr_e0 = binsof(cp_cheri_cs1_exp.bin0) && binsof(cp_cheri_rs2_as_inc.bin3) && binsof(cp_cheri_cd_cs1_repr_cases.case0);
      ignore_bins e14_2p31_repr_e1 = binsof(cp_cheri_cs1_exp.bin1) && binsof(cp_cheri_rs2_as_inc.bin3) && binsof(cp_cheri_cd_cs1_repr_cases.case0);
    }

    cheriot_csetaddr_cross: cross cp_cheri_cs1_tag, cp_cheri_cd_cs1_repr_cases,
      cp_cheri_cs1_sealed, cp_cheri_cs1_exp, cp_instr_csetaddr {
      // fcov_repr_cases() returns case0 for E = 24 (its representable region, 2^33, covers the
      // address space), so case1/case2 cannot be sampled
      ignore_bins e24_nonrepr_c1 = binsof(cp_cheri_cs1_exp.bin2) && binsof(cp_cheri_cd_cs1_repr_cases.case1);
      ignore_bins e24_nonrepr_c2 = binsof(cp_cheri_cs1_exp.bin2) && binsof(cp_cheri_cd_cs1_repr_cases.case2);
    }

    // -- Cap-mod/arithmetic crosses --
`ifdef CHERIOT_FCOV_LARGE_CROSSES  // cheriot_candperm_cross: see cheriot_uarch_cg note
    cheriot_candperm_cross: cross cp_cheri_cs1_tag, cp_cheri_cs1_sealed,
      cp_cheri_cs1_perms, cp_cheri_rs2_perm_mask, cp_instr_candperm;
`endif

    cheriot_ccleartag_cross: cross cp_cheri_cs1_tag, cp_cheri_cs1_sealed, cp_instr_ccleartag;

    cheriot_cmove_cross: cross cp_cheri_cs1_tag, cp_cheri_cs1_sealed, cp_instr_cmove;

    cheriot_cseqx_cross0: cross cp_cheri_cs1_tag, cp_cheri_cs1_otype,
      cp_cheri_cs2_tag, cp_cheri_cs2_otype, cp_instr_cseqx;
`ifdef CHERIOT_FCOV_LARGE_CROSSES  // cheriot_cseqx_cross1: see cheriot_uarch_cg note
    cheriot_cseqx_cross1: cross cp_cheri_cs1_perms, cp_cheri_cs1_cor,
      cp_cheri_cs2_perms, cp_cheri_cs2_cor, cp_instr_cseqx;
`endif
    cheriot_cseqx_cross2: cross cp_cheri_cs1_top, cp_cheri_cs1_base,
      cp_cheri_cs2_top, cp_cheri_cs2_base, cp_instr_cseqx;
`ifdef CHERIOT_FCOV_LARGE_CROSSES  // cheriot_cseqx_cross3: see cheriot_uarch_cg note
    cheriot_cseqx_cross3: cross cp_cheri_cs1_address, cp_cheri_cs2_address, cp_instr_cseqx;
`endif

    cheriot_ctestsubset_cross0: cross cp_cheri_cs1_tag, cp_cheri_cs1_otype,
      cp_cheri_cs2_tag, cp_cheri_cs2_otype, cp_instr_ctestsubset;
`ifdef CHERIOT_FCOV_LARGE_CROSSES  // cheriot_ctestsubset_cross1: see cheriot_uarch_cg note
    cheriot_ctestsubset_cross1: cross cp_cheri_cs1_perms, cp_cheri_cs1_cor,
      cp_cheri_cs2_perms, cp_cheri_cs2_cor, cp_instr_ctestsubset;
`endif
    cheriot_ctestsubset_cross2: cross cp_cheri_cs1_top, cp_cheri_cs1_base,
      cp_cheri_cs2_top, cp_cheri_cs2_base, cp_instr_ctestsubset;

`ifdef CHERIOT_FCOV_LARGE_CROSSES  // cheriot_csub_cross: see cheriot_uarch_cg note
    cheriot_csub_cross: cross cp_cheri_cs1_tag, cp_cheri_cs1_address,
      cp_cheri_cs2_tag, cp_cheri_cs2_address, cp_instr_csub;
`endif

    cheriot_csethigh_cross0: cross cp_cheri_cd_tag, cp_cheri_cd_otype,
      cp_cheri_cd_cperms, cp_instr_csethigh {
      // CSetHigh always clears the tag, so a tagged result is illegal -- but only while
      // CSET_HIGH is executing. cp_cheri_cd_tag has no `iff` and samples result_cap_o.valid
      // every cycle, so without the instruction term this condemns every ordinary cycle
      // that produces a valid capability.
      illegal_bins illegal = binsof(cp_instr_csethigh) intersect {1'b1} &&
                             binsof(cp_cheri_cd_tag) intersect {1'b1};
    }
`ifdef CHERIOT_FCOV_LARGE_CROSSES  // cheriot_csethigh_cross1: see cheriot_uarch_cg note
    cheriot_csethigh_cross1: cross cp_cheri_cd_cor, cp_cheri_cd_exp,
      cp_cheri_cd_top, cp_cheri_cd_base, cp_cheri_cd_address, cp_instr_csethigh;
`endif

    // -- CGET_FIELD cross (covers all CGET_* variants via field selector) --
    cheriot_cget_field_cross: cross cp_cheri_cs1_tag, cp_cheri_cs1_address,
      cp_cheri_cget_field, cp_instr_cget_field;

    // -- CSPECIALRW cross --
    cheriot_cspecialrw_cross: cross cp_cheri_scr_addr, cp_cheri_rs1_regaddr,
      cp_cheri_rd_regaddr, cp_cheri_pcc_perm_asr, cp_instr_cspecialrw;

    // REQ_SCR_08: CSpecialRW form, from the register index fields (CHERIoT-Sail
    // cheri_insts.sail:406-460: cs1 = c0 only reads, a write to cd = c0 is discarded).
    // {cd == c0, cs1 == c0}; rf_raddr_a_i is the cs1 index the RTL tests for is_write
    // (ibex_cheriot_ex.sv CCSR_RW), rf_waddr_id_o the cd index.
    cp_cheri_cspecialrw_mode: coverpoint {(id_stage_i.rf_waddr_id_o[4:0] == 5'd0),
                                          (g_cheriot_ex.u_ibex_cheriot_ex.rf_raddr_a_i == 5'd0)}
        iff (cheriot_pmode & cheriot_operator.CCSR_RW &
             g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i) {
      bins read_write = {2'b00};
      bins read_only  = {2'b01};
      bins write_only = {2'b10};
      bins no_op      = {2'b11};
    }
    cheriot_cspecialrw_mode_cross: cross cp_cheri_cspecialrw_mode, cp_cheri_scr_addr {
      ignore_bins undefined_scr = binsof(cp_cheri_scr_addr.bad);  // illegal, cheriot_scr_faults
    }

    // CSetHigh source capability: tagged/untagged x sealed/unsealed (cd is always untagged,
    // cheriot_csethigh_cross0; cheri_insts.sail:289-296 ignores cs1's tag and seal).
    cheriot_csethigh_src_cross: cross cp_cheri_cs1_tag, cp_cheri_cs1_sealed, cp_instr_csethigh;

    // -- Jump/branch crosses --
`ifdef CHERIOT_FCOV_LARGE_CROSSES  // cheriot_cjal_cross: see cheriot_uarch_cg note
    cheriot_cjal_cross: cross cp_cheri_rd_regaddr, cp_cheri_cjal_bound,
      cp_cheri_imm20, cp_cheri_mstatus_mie, cp_instr_cjal;
`endif

    cheriot_cjalr_cross0: cross cp_cheri_cs1_tag, cp_cheri_cs1_otype,
      cp_cheri_rd_regaddr, cp_cheri_mstatus_mie, cp_cheri_imm12, cp_instr_cjalr;
    // The illegal_bins are 172 bins no cs1 can produce (tech-notes/fcov_closure_2026-10-07.md;
    // gen_cjalr_det.py -v lists the same set as "unreachable <group>"). The target is
    // {(addr + imm)[31:1], 1'b0} (ibex_cheriot_ex.sv:522), and imm = -2048 needs
    // addr - target in {2048, 2049}.
    cheriot_cjalr_cross1: cross cp_cheri_cs1_tag, cp_cheri_cs1_perm_ex,
      cp_cheri_cjalr_bound, cp_cheri_imm12, cp_instr_cjalr {
      // An odd room needs an odd top33, so E = 0 and addr is in [base, base + 512): the target
      // is within 512 bytes of addr.
      illegal_bins m2048_oddroom = binsof(cp_cheri_imm12.bin3) &&
        binsof(cp_cheri_cjalr_bound) intersect {9'h010, 9'h011, 9'h030, 9'h031, 9'h050, 9'h051,
                                                9'h070, 9'h071, 9'h110, 9'h130, 9'h150, 9'h170};
      // Target at the base with room 1..7: base and top are multiples of 2^E, so E <= 2 and
      // addr - base < 2^(E+9) <= 2048.
      illegal_bins m2048_atbase_short = binsof(cp_cheri_imm12.bin3) &&
        binsof(cp_cheri_cjalr_bound) intersect {9'h012, 9'h022, 9'h032, 9'h042, 9'h052, 9'h062,
                                                9'h072, 9'h0a2, 9'h0c2, 9'h0e2, 9'h112, 9'h122,
                                                9'h132, 9'h142, 9'h152, 9'h162, 9'h172};
      // top33 = 2^32 with E < 24 needs base <= addr <= 2^32 - 1, and the target is 2^32 - 2/4/6,
      // so imm is in [-5, 1]; for room 2 (0x0a1, 0x0a2), base >= 2^32 - 2 limits imm to [-1, 1].
      illegal_bins top32_last_bytes = binsof(cp_cheri_cjalr_bound) intersect {9'h0a1, 9'h0c1, 9'h0e1} &&
        (binsof(cp_cheri_imm12.bin2) || binsof(cp_cheri_imm12.bin3));
      illegal_bins top32_last2_neg = binsof(cp_cheri_cjalr_bound) intersect {9'h0a1, 9'h0a2} &&
        binsof(cp_cheri_imm12.bin4);
      // A tagged capability with top - base <= 7 has E = 0 (CSetBounds picks e = 0 below 512)
      // and keeps addr in [base, base + 512), so a target below the base needs imm in
      // [-518, 0]. Untagged raw metadata reaches these, hence the tag = 1 rows only.
      illegal_bins tag_below_short = binsof(cp_cheri_cs1_tag) intersect {1'b1} &&
        binsof(cp_cheri_cjalr_bound) intersect {9'h011, 9'h021, 9'h031, 9'h041, 9'h051, 9'h061,
                                                9'h071} &&
        (binsof(cp_cheri_imm12.bin2) || binsof(cp_cheri_imm12.bin3));
      // A tagged zero-length capability has E = 0 too; untagged E >= 3 metadata reaches these.
      illegal_bins tag_zerolen_m2048 = binsof(cp_cheri_cs1_tag) intersect {1'b1} &&
        binsof(cp_cheri_cjalr_bound) intersect {9'h00a, 9'h10a} && binsof(cp_cheri_imm12.bin3);
    }

    // -- CLC/CSC load/store crosses --
    cheriot_clc_cross0: cross cp_cheri_cs1_tag, cp_cheri_cs1_sealed,
      cp_cheri_cs1_perms_load, cp_instr_clc;
`ifdef CHERIOT_FCOV_LARGE_CROSSES  // cheriot_clc_cross1: see cheriot_uarch_cg note
    cheriot_clc_cross1: cross cp_cheri_cs1_tag, cp_cheri_clsc_bound,
      cp_cheri_imm12, cp_cheri_clsc_addr_lsb, cp_instr_clc;
`endif

    cheriot_csc_cross0: cross cp_cheri_cs1_tag, cp_cheri_cs1_sealed,
      cp_cheri_cs1_perms_store, cp_cheri_cs2_perm_gl, cp_instr_csc;
`ifdef CHERIOT_FCOV_LARGE_CROSSES  // cheriot_csc_cross1: see cheriot_uarch_cg note
    cheriot_csc_cross1: cross cp_cheri_cs1_tag, cp_cheri_clsc_bound,
      cp_cheri_imm12, cp_cheri_clsc_addr_lsb, cp_instr_csc;
`endif

    // -- Seal/unseal crosses --
    cheriot_cseal_cross0: cross cp_cheri_cs1_tag, cp_cheri_cs1_sealed,
      cp_cheri_cs2_tag, cp_cheri_cs2_sealed, cp_instr_cseal;
    cheriot_cseal_cross1: cross cp_cheri_cs1_perm_ex, cp_cheri_cs2_tag,
      cp_cheri_cs2_perm_se, cp_cheri_cs2_seal_type, cp_cheri_seal_bound,
      cp_instr_cseal {
      // Address 0 (seal_type 0) cannot be above the base (b2) or the top, nor at the top without
      // being at the base (b3 alone, or nothing: top33 == 0 with base32 > 0 sets b0 too). Below the
      // base (b0) IS reachable, tagged too: at E = 24 cheriot_set_address() never clears the tag
      // (repr_mask == 0, ibex_cheriot_pkg.sv) and the base can decode above the address. The ignores
      // these replace (tagged_below, and b0 in zero_bounds) hid those reachable bins.
      ignore_bins zero_addr =
        (binsof(cp_cheri_cs2_seal_type) intersect {32'b0})
        with (cp_cheri_seal_bound inside {4'b0000, 4'b0100, 4'b1000});
    }

    cheriot_cunseal_cross0: cross cp_cheri_cs1_tag, cp_cheri_cs1_sealed, cp_cheri_cs1_perm_gl,
      cp_cheri_cs2_tag, cp_cheri_cs2_sealed, cp_cheri_cs2_perm_us, cp_cheri_cs2_perm_gl,
      cp_instr_cunseal;
`ifdef CHERIOT_FCOV_LARGE_CROSSES  // cheriot_cunseal_cross1: see cheriot_uarch_cg note
    cheriot_cunseal_cross1: cross cp_cheri_cs1_otype, cp_cheri_cs1_perm_ex,
      cp_cheri_cs2_tag, cp_cheri_cs2_seal_type, cp_cheri_seal_bound, cp_instr_cunseal;
`endif

    // -- SetBounds crosses --
`ifdef CHERIOT_FCOV_LARGE_CROSSES  // cheriot_csetbounds_cross0: see cheriot_uarch_cg note
    cheriot_csetbounds_cross0: cross cp_cheri_cs1_tag, cp_cheri_cs1_sealed,
      cp_cheri_setbounds_cases, cp_cheri_cs1_base32, cp_cheri_cs1_top33, cp_cheri_cs1_exp,
      cp_cheri_cd_tag, cp_instr_csetbounds {
      ignore_bins ignore = (binsof(cp_cheri_cs1_tag) intersect {1'b0}) ||
        ((!binsof(cp_cheri_cs1_exp) intersect {24}) &&
         (binsof(cp_cheri_setbounds_cases) with (cp_cheri_setbounds_cases % 2 == 1)));
    }
`endif
    // cp_cheri_setbounds_cases: b0 addr<base, b1 addr==base, b2 addr>top, b3 addr==top,
    // b4 req_len <= cs1 length (fcov_setbounds_cases_fn)
    cheriot_csetbounds_cross1: cross cp_cheri_cs1_tag, cp_cheri_setbounds_cases,
      cp_cheri_rs2_req_len, cp_cheri_cs1_exp, cp_cheri_cd_tag, cp_instr_csetbounds {
      ignore_bins ignore = (binsof(cp_cheri_cs1_tag) intersect {1'b0}) ||
        ((!binsof(cp_cheri_cs1_exp) intersect {24}) &&
         (binsof(cp_cheri_setbounds_cases) with (cp_cheri_setbounds_cases % 2 == 1)));
      // A zero request is never longer than cs1, so b4 is set
      ignore_bins len0_le = binsof(cp_cheri_rs2_req_len) intersect {0} &&
                            binsof(cp_cheri_setbounds_cases) intersect {[0:15]};
      // base < addr < top needs length >= 2; addr == base < top or base < addr == top needs >= 1
      ignore_bins minlen = (binsof(cp_cheri_setbounds_cases) intersect {0} &&
                            binsof(cp_cheri_rs2_req_len) intersect {[1:2]}) ||
                           (binsof(cp_cheri_setbounds_cases) intersect {2, 8} &&
                            binsof(cp_cheri_rs2_req_len) intersect {1});
      // Zero-length cs1 (addr == base == top) with b4 set means the request is 0
      ignore_bins zl_len = binsof(cp_cheri_setbounds_cases) intersect {26} &&
                           !binsof(cp_cheri_rs2_req_len) intersect {0};
      // These cases need top < base; the ISA keeps base <= top for tagged capabilities
      ignore_bins base_gt_top = binsof(cp_cheri_setbounds_cases) intersect {5, 6, 9, 21, 22, 25};
      // Exponent >= 1 means length >= 512: never zero length, never shorter than a request <= 8
      ignore_bins zl_exp = binsof(cp_cheri_setbounds_cases) intersect {10, 26} &&
                           binsof(cp_cheri_cs1_exp) intersect {[1:24]};
      ignore_bins len512 = binsof(cp_cheri_setbounds_cases) intersect {[0:15]} &&
                           binsof(cp_cheri_rs2_req_len) intersect {[0:8]} &&
                           binsof(cp_cheri_cs1_exp) intersect {[1:24]};
      // in_bound (ibex_cheriot_pkg.sv) clears the result tag when the cursor is below base or
      // above top, the request is longer than cs1, or the cursor is at top with a non-zero request
      illegal_bins cd_oob = binsof(cp_cheri_cd_tag) intersect {1'b1} &&
        (binsof(cp_cheri_setbounds_cases) intersect {[0:15], 17, 20} ||
         (binsof(cp_cheri_setbounds_cases) intersect {24, 26} &&
          !binsof(cp_cheri_rs2_req_len) intersect {0}));
    }

`ifdef CHERIOT_FCOV_LARGE_CROSSES  // cheriot_csetboundsexact_cross: see cheriot_uarch_cg note
    cheriot_csetboundsexact_cross: cross cp_cheri_cs1_tag, cp_cheri_cs1_sealed,
      cp_cheri_setbounds_cases, cp_cheri_cs1_base32, cp_cheri_cs1_top33, cp_cheri_cs1_exp,
      cp_cheri_cd_tag, cp_instr_csetboundsexact;
`endif

`ifdef CHERIOT_FCOV_LARGE_CROSSES  // cheriot_csetboundsimm_cross: see cheriot_uarch_cg note
    cheriot_csetboundsimm_cross: cross cp_cheri_cs1_tag, cp_cheri_cs1_sealed,
      cp_cheri_setboundsimm_cases, cp_cheri_cs1_base32, cp_cheri_cs1_top33, cp_cheri_cs1_exp,
      cp_cheri_cd_tag, cp_instr_csetboundsimm;
`endif

    cheriot_csetboundsrndn_cross: cross cp_cheri_cs1_tag, cp_cheri_rs1_bitsize,
      cp_instr_csetboundsrndn;

    // -- CRRL / CRAM crosses --
    cheriot_cram_cross: cross cp_cheri_cs1_tag, cp_cheri_rs1_bitsize, cp_instr_cram;
    cheriot_crrl_cross: cross cp_cheri_cs1_tag, cp_cheri_rs1_bitsize, cp_instr_crrl;

    // -- WB exception x instruction --
    cheriot_jump_exception_cross: cross cp_cheri_wb_exception_causes, cp_instr_cjalr {
      // Same qualification point as cheriot_csethigh_cross0. A CJALR faults on perm_vio only
      // (ibex_cheriot_ex.sv:539), so cause 0 and cause 0x18 (ASR) cannot come from a CJALR --
      // but they are both reachable on a CCSR_RW fault, which is cjalr == 0 and legal.
      illegal_bins illegal =
        binsof(cp_instr_cjalr) intersect {1'b1} &&
        binsof(cp_cheri_wb_exception_causes) intersect {5'h0, 5'h1, 5'h18};
    }

    cheriot_scr_exception_cross: cross cp_cheri_wb_exception_causes, cp_instr_cspecialrw {
      ignore_bins ignore = !binsof(cp_cheri_wb_exception_causes) intersect {5'h18};
    }

    // -- Tag clearing cross --
    cheriot_cs1cd_tag_cross: cross cp_cheri_cs1_tag, cp_cheri_cd_tag, cp_instr_cget_field {
      // CGET_FIELD drives result_cap_o = NULL_CAP (ibex_cheriot_ex.sv): the integer result is never
      // tagged, whatever cs1 (REQ_TAG_06)
      illegal_bins cget_cd_tagged = binsof(cp_instr_cget_field.bin1) &&
                                    binsof(cp_cheri_cd_tag) intersect {1'b1};
    }

    // ------------------------------------------------------------------
    // Instruction / error / interrupt sequence crosses
    // Ported from cheriot-ibex instr_error_sequence_cross0/1.
    // Tracks exception-cause and instruction-sequence combinations that are
    // hard to observe without explicit cross coverage.
    // Note: ID-stage errors do not reach WB, hence two separate crosses.
    // ------------------------------------------------------------------

`ifdef CHERIOT_FCOV_LARGE_CROSSES  // instr_error_sequence_cross0: see cheriot_uarch_cg note
    instr_error_sequence_cross0: cross id_instr_category, wb_instr_category,
      id_stage_i.controller_i.handle_irq, fcov_id_error, fcov_wb_error;
`endif

`ifdef CHERIOT_FCOV_LARGE_CROSSES  // instr_error_sequence_cross1: see cheriot_uarch_cg note
    instr_error_sequence_cross1: cross id_instr_category, id_instr_category_q,
      fcov_id_exc_int, fcov_id_exc_int_q;
`endif

    // ------------------------------------------------------------------
    // Missing crosses ported from cheriot-ibex/dv/cheriot/fcov/core_ibex_fcov_if.sv
    // ------------------------------------------------------------------

    // CS2 tag × sealed state cross
    cp_cs2_sealed_tagged_cross: cross cp_cheri_cs2_tag, cp_cheri_cs2_sealed;

    // RS1 × RS2 × RD register address triple cross
    rs_rd_cross: cross cp_cheri_rs1_regaddr, cp_cheri_rs2_regaddr, cp_cheri_rd_regaddr;

    // PCC valid × CD tag × PCC-to-CD instructions (CAUIPCC=21, CJAL=20, CJALR=19 in $clog2 bins)
    cheriot_pcc2cd_tag_cross: cross cp_cheri_pcc_tag, cp_cheri_cd_tag, cp_cheri_instr_set {
      ignore_bins ignore0 =
        ((!binsof(cp_cheri_instr_set) intersect {21, 20, 19}) ||
        ((binsof(cp_cheri_pcc_tag) intersect {1'b0})));
      illegal_bins illegal =
        ((binsof(cp_cheri_pcc_tag) intersect {1'b0}) && (binsof(cp_cheri_cd_tag) intersect {1'b1}) &&
         (binsof(cp_cheri_instr_set) intersect {21, 20, 19})) ||
        ((binsof(cp_cheri_pcc_tag) intersect {1'b1}) && (binsof(cp_cheri_cd_tag) intersect {1'b0}) &&
         (binsof(cp_cheri_instr_set) intersect {20, 19}));
    }

    // TRVK stall × register-file read-port A/B load-use hazards

    // Taken branch gate — used for branch-target PCC bounds cross
    cp_instr_branch: coverpoint
      ((id_stage_i.instr_rdata_i[6:0] == ibex_pkg::OPCODE_BRANCH) & id_stage_i.branch_decision_i)
      // Not in debug mode: the PCC fetch bounds check is off there (ibex_if_stage.sv)
      iff (id_stage_i.instr_executing & ~debug_mode) {
      bins bin1 = {1'b1};
    }

    // Taken branch × PCC bounds check — exercises in-/out-of-bounds jump targets. The PCC length
    // >= 2 exclusion (pcc_len_lt2, Sail inCapBounds(PCC, pc, 2)) is in cp_cheri_branch_bound.
    cheriot_instr_branch_cross: cross cp_cheri_branch_bound, cp_instr_branch;

    // ------------------------------------------------------------------
    // Gap coverpoints — spec names standardised, implementations below
    // ------------------------------------------------------------------

    // REQ_EXC_03: mtval[9:5] = GPR index of the faulting capability; mtval[10] (cp_exc_scr_flag)
    // marks PCC or an SCR (spec name cp_exc_cap_idx). cp_cheri_exception_reg_id covers the same
    // field; this adds the spec-mandated name.
    cp_exc_cap_idx: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.cheriot_wb_err_info_d[9:5]
      iff ((g_cheriot_ex.u_ibex_cheriot_ex.cheriot_wb_err_d & ~cheriot_operator.CCSR_RW) |
           (g_cheriot_ex.u_ibex_cheriot_ex.lsu_req_o & g_cheriot_ex.u_ibex_cheriot_ex.lsu_cheriot_err_o)) {
      bins x0        = {5'd0};
      bins x_lower[] = {[5'd1:5'd15]};
      illegal_bins x_upper = {[5'd16:5'd31]};
    }

    // REQ_EXC_04: mtval[10] = 1 when the faulting capability is PCC (index 0x20) or an SCR
    // (0x20 + SCR number); mtval[11] is always 0.
    cp_exc_scr_flag: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.cheriot_wb_err_info_d[10]
      iff (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_wb_err_d) {
      bins scr_fault = {1'b1};
      bins gpr_fault = {1'b0};
    }

    // REQ_SCR_02: any trap taken (exception or interrupt), causing MEPCC to be saved
    // and PCC to be replaced with MTCC.
    cp_mepcc_trap_save: coverpoint (fcov_id_error | fcov_wb_error | id_stage_i.controller_i.handle_irq) {
      bins trap_taken = {1'b1};
    }

    // REQ_SCR_03: legal MRET restores PCC from MEPCC.
    cp_mepcc_mret_restore: coverpoint id_stage_i.controller_i.csr_restore_mret_id_o
      iff (~id_stage_i.controller_i.mret_cheriot_asr_err) {
      bins mret_ok = {1'b1};
    }

    // REQ_TAG_03: CLC tag round-trip — observe both tagged and untagged capability loads.
    cp_clc_csc_tag_roundtrip: coverpoint load_store_unit_i.lsu_rcap_o.valid
      iff (~load_store_unit_i.data_we_q & load_store_unit_i.resp_is_cap_q &
           load_store_unit_i.lsu_resp_valid_o) {
      bins cap_tagged   = {1'b1};
      bins cap_untagged = {1'b0};
    }

    // REQ_TAG_02: integer store completing (always clears the memory tag word implicitly).
    cp_int_store_tag_clear: coverpoint load_store_unit_i.lsu_resp_valid_o
      iff (load_store_unit_i.data_we_q & ~load_store_unit_i.lsu_is_cap_i) {
      bins int_store_tag_clear = {1'b1};
    }

    // REQ_TAG_06: RV32 arith/logical instruction writing a GPR always clears the tag to 0.
    // Gated on cs1.valid so we observe the "tag was 1 before" path.
    cp_arith_tag_clear: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.valid
      iff (~g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i & id_stage_i.instr_executing) {
      bins src_tagged   = {1'b1};
      bins src_untagged = {1'b0};
    }

    // REQ_TAG_08: CMove copies the source capability unmodified — both tag=0 and tag=1.
    cp_cmove_full_copy: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.valid
      iff (cheriot_operator.CMOVE_CAP & g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i) {
      bins tag_0 = {1'b0};
      bins tag_1 = {1'b1};
    }

    // REQ_MON_04: CTestSubset integer result bit (0=not subset, 1=subset).
    cp_ctestsubset_result: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.result_data_o[0]
      iff (cheriot_operator.CIS_SUBSET & g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i) {
      bins not_subset = {1'b0};
      bins is_subset  = {1'b1};
    }

    // REQ_MON_05: CIsEqual integer result bit (0=not equal, 1=equal).
    cp_cisequal_result: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.result_data_o[0]
      iff (cheriot_operator.CIS_EQUAL & g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i) {
      bins not_equal = {1'b0};
      bins is_equal  = {1'b1};
    }

    // REQ_MON_06: CRRL — did the representable-length result round up from the input length?
    cp_crrl_rounding: coverpoint
        (g_cheriot_ex.u_ibex_cheriot_ex.result_data_o != g_cheriot_ex.u_ibex_cheriot_ex.rf_rdata_a)
      iff (cheriot_operator.CRRL & g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i) {
      bins exact   = {1'b0};
      bins rounded = {1'b1};
    }

    // REQ_SEL_05: CJALR to an unsealed, tagged, executable capability (normal indirect jump).
    cp_cjalr_unsealed: coverpoint
        (g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.otype == 3'd0)
      iff (cheriot_operator.CJALR & g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i &
           g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.valid) {
      bins unsealed_jump = {1'b1};
    }

    // REQ_SEL_06/07: CJALR to interrupt-affecting sentry x initial MIE state.
    // {otype[2:0], mie_o}: FWD/BWD-ID (otype 2/4) should clear MIE; FWD/BWD-IE (3/5) should set it.
    cp_cjalr_sentry_mie: coverpoint
        {g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.otype, cs_registers_i.csr_mstatus_mie_o}
      iff (cheriot_operator.CJALR & g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i &
           g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.valid &
           (g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.otype inside {3'd2, 3'd3, 3'd4, 3'd5})) {
      bins fwd_id_mie1 = {4'b0101};  // otype=2 FWD_ID, MIE=1 → clears MIE
      bins fwd_id_mie0 = {4'b0100};  // otype=2 FWD_ID, MIE=0
      bins fwd_ie_mie0 = {4'b0110};  // otype=3 FWD_IE, MIE=0 → sets MIE
      bins fwd_ie_mie1 = {4'b0111};  // otype=3 FWD_IE, MIE=1
      bins bwd_id_mie1 = {4'b1001};  // otype=4 BWD_ID, MIE=1 → clears MIE
      bins bwd_id_mie0 = {4'b1000};  // otype=4 BWD_ID, MIE=0
      bins bwd_ie_mie0 = {4'b1010};  // otype=5 BWD_IE, MIE=0 → sets MIE
      bins bwd_ie_mie1 = {4'b1011};  // otype=5 BWD_IE, MIE=1
    }

    // REQ_MON_03: non-monotonic op (CIncAddr/CSetAddr outside representable window,
    // CSetBoundsExact unrepresentable) clears tag from 1 to 0.
    // Excludes CClearTag (intentional clear, not a non-monotonic operation).
    cp_non_monotone_tag_clear: coverpoint fcov_cheri_tag_clear_cs1cd
      iff (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i &
           ~cheriot_operator.CCLEAR_TAG & ~cheriot_operator.CAND_PERM) {
      bins non_mono_clear = {1'b1};
    }

    // Metadata & Pointer Coverage Extensions: cursor position relative to [Base, Top).
    // REQ_BND_01, REQ_BND_02, REQ_BND_05
    cp_cs1_cursor_rel_bounds: coverpoint fcov_cs1_cursor_rel
      iff (cheriot_pmode & g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i) {
      bins below_base      = {3'd0};
      bins at_base         = {3'd1};
      bins in_range        = {3'd2};
      bins at_top_minus_1  = {3'd3};
      bins at_top_or_above = {3'd4};
    }

    cp_cs2_cursor_rel_bounds: coverpoint fcov_cs2_cursor_rel
      iff (cheriot_pmode & g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i) {
      bins below_base      = {3'd0};
      bins at_base         = {3'd1};
      bins in_range        = {3'd2};
      bins at_top_minus_1  = {3'd3};
      bins at_top_or_above = {3'd4};
    }

    // Metadata & Pointer Coverage Extensions: per-sentry-otype detail on CS1 and CS2.
    // REQ_SEL_07, REQ_SEL_08, REQ_INT_07
    cp_cs1_otype_sentry_detail: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.otype
      iff (cheriot_pmode & g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i &
           (g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.otype inside {3'd1, 3'd2, 3'd3, 3'd4, 3'd5})) {
      bins type_1 = {3'd1};   // plain sentry (CJALR target)
      bins type_2 = {3'd2};   // forward interrupt-disable sentry
      bins type_3 = {3'd3};   // forward interrupt-enable sentry
      bins type_4 = {3'd4};   // backward interrupt-disable sentry
      bins type_5 = {3'd5};   // backward interrupt-enable sentry
    }

    cp_cs2_otype_sentry_detail: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_b.otype
      iff (cheriot_pmode & g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i &
           (g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_b.otype inside {3'd1, 3'd2, 3'd3, 3'd4, 3'd5})) {
      bins type_1 = {3'd1};
      bins type_2 = {3'd2};
      bins type_3 = {3'd3};
      bins type_4 = {3'd4};
      bins type_5 = {3'd5};
    }

    // Metadata & Pointer Coverage Extensions: compressed permissions on input operands.
    // REQ_LOC_01, REQ_CFI_04 (mirrors cp_cheri_cd_cperms already in this covergroup)
    cp_cs1_cperms: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.cperms
      iff (cheriot_pmode & g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i);

    cp_cs2_cperms: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_b.cperms
      iff (cheriot_pmode & g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i);

    // Metadata & Pointer Coverage Extensions: CSC address alignment.
    // REQ_TAG_02, REQ_CSC_01
    cp_csc_alignment: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.cheriot_ls_chkaddr[2:0]
      iff (cheriot_operator.CSTORE_CAP & g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i) {
      bins aligned      = {3'd0};
      bins misaligned_4 = {3'd4};
      bins misaligned_2 = {3'd2};
      bins misaligned_1 = {3'd1};
      bins other[]      = {3'd3, 3'd5, 3'd6, 3'd7};
    }

    // ------------------------------------------------------------------
    // BLOCKED: TBRE / STKZ coverpoints
    //   cp_tbre_fsm, cp_tbre_os_cnt, cp_tbre_fifo_hazard, cp_tbre_mem_err,
    //   cp_concur_mem_reqs, cp_tbrewrp_blk1_cancel,
    //   cp_stkz_stall1, cp_stkz_stall0, cp_stkz_sm, cp_stkz_ztop_wr, cp_stkz_mem_err
    //   These reference cheriot_tbre_wrapper_i.*, which is instantiated at ibex_top
    //   level — outside ibex_core scope. Would need a separate bind to ibex_top.
    // ------------------------------------------------------------------

    // ------------------------------------------------------------------
    // BLOCKED: TRVK detailed coverpoints
    //   cp_trvk_addr, cp_trvk_cond, cp_trvk_stall_cause, cp_tsmap_addr
    //   ibex-private has stall_cheri_trvk (covered above) but no g_trvk_stage
    //   generate block or id_stage_dv_ext_i.fcov_trvk_stall_cause DV extension.
    // ------------------------------------------------------------------

    // ------------------------------------------------------------------
    // BLOCKED: CLC loaded-memory cap field coverage
    //   cp_clsc_mem_err, cp_clc_mem_cap_{perms,valid,exp,cor}
    //   Require load_store_unit_i.lsu_dv_ext_i.fcov_clc_mem_cap — DV extension
    //   interface not present in ibex-private RTL.
    //   Note: cp_cheri_clc_clrperm above uses resp_lc_clrperm_q directly (no dv_ext needed).
    // ------------------------------------------------------------------

    // ------------------------------------------------------------------
    // BLOCKED: pending fetch violation + interrupt cross
    //   cp_pending_vio_intr
    //   Requires if_stage_i.if_stage_dv_ext_i.fcov_pending_fetch_bound_vio — DV
    //   extension interface not present in ibex-private RTL.
    // ------------------------------------------------------------------

  endgroup

  `undef FCOV_BOUND_CASE_BINS
  `undef FCOV_EVEN_TARGET_IGNORE

  bit en_cheri_uarch_cov;

  initial begin
    void'($value$plusargs("enable_ibex_fcov=%d", en_cheri_uarch_cov));
    if (fcov_in_shadow_core()) en_cheri_uarch_cov = 1'b0;
  end

  `DV_FCOV_INSTANTIATE_CG(cheriot_uarch_cg, en_cheri_uarch_cov)

  // REQ_CAC_04 / REQ_BRA_06: iCache/branch-predictor speculative prefetch squash when
  // the fetched address is outside PCC bounds.
  // cheriot_bound_vio  = PCC bounds violated on the IF-stage instruction address
  // if_instr_valid   = an instruction is resident in the IF pipeline
  // prefetch_branch  = branch_req | nt_branch_mispredict_i — any redirect that squashes IF
  covergroup cheriot_cfi_detail_cg @(posedge clk_i);
    option.name = "cheriot_cfi_detail_cg";

    cp_pcc_bounds_squash : coverpoint (
        if_stage_i.cheriot_bound_vio &
        if_stage_i.if_instr_valid  &
        if_stage_i.prefetch_branch
      ) {
      bins squashed = {1'b1};
    }
  endgroup

  bit en_cheri_cfi_cov;

  initial begin
    void'($value$plusargs("enable_ibex_fcov=%d", en_cheri_cfi_cov));
    if (fcov_in_shadow_core()) en_cheri_cfi_cov = 1'b0;
  end

  `DV_FCOV_INSTANTIATE_CG(cheriot_cfi_detail_cg, en_cheri_cfi_cov)

  // OBI grant backpressure crossed with the LSU state machine.
  //
  // The only pre-existing bus coverpoint was dmem_req_gnt_rvalid, which fires
  // when req, gnt and rvalid are all high — i.e. the clean case.  The window of
  // interest is the opposite one: the interconnect withholding gnt while the
  // LSU is part-way through a CLC/CSC, which is where a capability transaction
  // could be left half-issued.  Three separate lines of enquiry point at that
  // window (OBI split transactions, a late interrupt between beats, and the
  // class of the published VeriCHERI LSU bug), and none of them was observable.
  covergroup cheriot_obi_backpressure_cg @(posedge clk_i);
    option.per_instance = 1;
    option.name = "cheriot_obi_backpressure_cg";

    // ls_fsm_e is 8 states wide, not a 2-bit encoding.  Only the states a
    // capability transaction passes through are enumerated; everything else is
    // folded into one bin so the cross stays readable.
    cp_lsu_fsm: coverpoint load_store_unit_i.ls_fsm_cs {
      bins idle          = {IDLE};
      bins ctx_wait_gnt1 = {CTX_WAIT_GNT1};
      bins ctx_wait_gnt2 = {CTX_WAIT_GNT2};
      bins ctx_wait_resp = {CTX_WAIT_RESP};
      bins rv32_states   = {WAIT_GNT_MIS, WAIT_RVALID_MIS, WAIT_GNT,
                            WAIT_RVALID_MIS_GNTS_DONE};
    }

    // REQ_BCK_06: cheriot_enable_i leaves On (cheriot_pmode reads the pin itself) while a
    // capability access waits for the grant of its first word, the change the pin contract forbids
    // (directed test cheriot_enable_on_off). The core holds CHERIoT mode for the access in flight
    // (ibex_core.sv cheriot_enable_ex), so the LSU keeps the request raised and goes on to the
    // second word. The CTX_WAIT_GNT1 -> IDLE exit, which abandoned a CSC and dropped a raised
    // request (OBI), was removed with that fix. Its own coverpoint: cp_lsu_fsm is crossed below,
    // and a transition bin does not belong in a cross.
    // A sample the iff skips does not reset the transition history, so the illegal bin can fire
    // falsely without the RTL exit: CTX_WAIT_GNT1 sampled with the pin Off, then the pin back On
    // (GNT2/RESP/IDLE unsampled), then Off again in IDLE, i.e. any Off->On->Off sequence, a reset
    // in the middle of the CSC included. The pin contract forbids the return to On
    // (CheriotEnableOneWaySwitch), and cheriot_enable_on_off keeps the pin Off once lowered.
    cp_lsu_ctx_abort: coverpoint load_store_unit_i.ls_fsm_cs iff (~cheriot_pmode) {
      bins         ctx_gnt1_held  = (CTX_WAIT_GNT1 => CTX_WAIT_GNT2);
      illegal_bins ctx_gnt1_abort = (CTX_WAIT_GNT1 => IDLE);
    }

    // REQ_BCK_06: the alert latch ibex_core.sv gen_cheriot_enable_check sets when the pin was On
    // in the previous cycle and is not On now (Off or an invalid encoding), cleared only by
    // rst_ni; it feeds alert_major_internal_o. The latch exists in CHERIoT configs only.
    cp_cheriot_disable_err: coverpoint cheriot_disable_err iff (CheriotIsa) {
      bins clear = {1'b0};
      bins set   = {1'b1};
    }

    // gnt asserted with req low is not illegal on OBI — an always-ready slave
    // may hold gnt high — so it is covered rather than excluded. It cannot reach ibex_core in a
    // CHERIoT config, though: there ibex_top connects data_gnt_i to TRVK's upstream_gnt_o, the
    // ready_o of stream_fork u_stream_fork_us2ds (ibex_trvk.sv) whose valid_i is the core's
    // data_req_o, and stream_fork.sv drives ready_o = 0 whenever valid_i = 0, in READY and in
    // WAITING alike, whatever the bus does. In RV32I configs ibex_top assigns trvk_gnt =
    // data_gnt_i and the bench's +dmem_gnt_when_idle_pct knob produces it, so it stays a bin.
    // The bin is ignored, not illegal: the same covergroup is built in every config.
    // A leading constant 0 widens the value to 3 bits so that the ignore has a value to name in
    // both configs: with TRVK it is gnt_no_req itself, without TRVK the unreachable 3'b100.
    cp_obi_handshake: coverpoint {1'b0, data_req_o, data_gnt_i} {
      bins quiet         = {3'b000};
      bins gnt_no_req    = {3'b001};
      bins backpressured = {3'b010};   // request outstanding, grant withheld
      bins accepted      = {3'b011};
      ignore_bins gnt_no_req_trvk = {GntNoReqUnreach};
    }

    // Is this a capability access?  Distinguishes a stalled CLC/CSC from a
    // stalled integer access sharing the same FSM states.
    cp_is_cap: coverpoint load_store_unit_i.lsu_is_cap_i {
      bins integer_access    = {1'b0};
      bins capability_access = {1'b1};
    }

    // The point of the covergroup: backpressure while a capability transaction
    // is in flight.  IDLE is deliberately NOT excluded — the first beat is
    // issued from IDLE in this design (data_req_o is asserted there), so
    // IDLE x backpressured is both reachable and the first-beat stall case.
    cheriot_obi_stall_cross: cross cp_lsu_fsm, cp_obi_handshake, cp_is_cap {
      bins beat1_stalled_in_idle = binsof(cp_lsu_fsm.idle) &&
                                   binsof(cp_obi_handshake.backpressured) &&
                                   binsof(cp_is_cap.capability_access);
      bins beat1_stalled         = binsof(cp_lsu_fsm.ctx_wait_gnt1) &&
                                   binsof(cp_obi_handshake.backpressured) &&
                                   binsof(cp_is_cap.capability_access);
      bins beat2_stalled         = binsof(cp_lsu_fsm.ctx_wait_gnt2) &&
                                   binsof(cp_obi_handshake.backpressured) &&
                                   binsof(cp_is_cap.capability_access);
      // CTX_WAIT_RESP never requests (ibex_load_store_unit.sv): the response stall is req low
      bins resp_stalled          = binsof(cp_lsu_fsm.ctx_wait_resp) &&
                                   binsof(cp_obi_handshake.quiet) &&
                                   binsof(cp_is_cap.capability_access);
      // A capability access cannot be in the RV32-only misaligned states.
      ignore_bins cap_in_rv32_states = binsof(cp_lsu_fsm.rv32_states) &&
                                       binsof(cp_is_cap.capability_access);
      // gnt without req never reaches the core with TRVK in front of it (cp_obi_handshake), so its
      // four rows (idle x 2, rv32_states, ctx_wait_resp) go with it in CHERIoT configs
      ignore_bins gnt_no_req_trvk = binsof(cp_obi_handshake) intersect {GntNoReqUnreach};
      // CTX_WAIT_GNT1/GNT2 drive data_req_o = 1 until granted, and the PMP_D gate stays forced off
      // while the access is in flight, also if cheriot_enable_i leaves On (ibex_core.sv
      // cheriot_enable_ex, REQ_BCK_06): req low there drops a raised request (OBI)
      illegal_bins no_req_in_ctx_gnt =
        (binsof(cp_lsu_fsm.ctx_wait_gnt1) || binsof(cp_lsu_fsm.ctx_wait_gnt2)) &&
        (binsof(cp_obi_handshake.quiet) || binsof(cp_obi_handshake.gnt_no_req));
      // CTX_WAIT_RESP drives data_req_o = 0 (ibex_load_store_unit.sv)
      illegal_bins req_in_ctx_wait_resp =
        binsof(cp_lsu_fsm.ctx_wait_resp) &&
        (binsof(cp_obi_handshake.backpressured) || binsof(cp_obi_handshake.accepted));
      // The CLC/CSC stays in ID until the LSU is back in IDLE (lsu_req_done), and ID keeps seeing
      // CHERIoT mode until then (cheriot_enable_ex), so lsu_is_cap_i is 1 in every CTX state
      illegal_bins int_in_ctx_states =
        (binsof(cp_lsu_fsm.ctx_wait_gnt1) || binsof(cp_lsu_fsm.ctx_wait_gnt2) ||
         binsof(cp_lsu_fsm.ctx_wait_resp)) &&
        binsof(cp_is_cap.integer_access);
    }
  endgroup

  bit en_cheri_obi_cov;

  initial begin
    void'($value$plusargs("enable_ibex_fcov=%d", en_cheri_obi_cov));
    if (fcov_in_shadow_core()) en_cheri_obi_cov = 1'b0;
  end

  `DV_FCOV_INSTANTIATE_CG(cheriot_obi_backpressure_cg, en_cheri_obi_cov)

  // REQ_BND_07: an instruction whose PC is 2 below PCC.Top. A 16-bit instruction there has both
  // its bytes in bounds and executes; a 32-bit one straddles Top and must take a bounds violation
  // (Length Violation, mtval 0x401) without executing.
  //
  // Sampled on any valid instruction in ID, not on instr_executing: an instruction with a fetch
  // bounds violation is killed, so instr_executing (which includes ~instr_kill) is never high
  // together with the violation, and the previous form of this covergroup could not be hit. It
  // also binned "16-bit with a violation", which REQ_BND_07 says must not happen. The two
  // combinations without a bin (16-bit faulting, 32-bit not faulting) would be RTL defects; the
  // cheriot_fetch_bounds self-checks catch those, so they are not made illegal_bins here.
  logic [32:0] fcov_pcc_top_minus_pc;
  assign fcov_pcc_top_minus_pc = cs_registers_i.pcc_cap_o.top33 - {1'b0, id_stage_i.pc_id_i};

  covergroup cheri_spatial_gap_cg @(posedge clk_i);
    option.name = "cheri_spatial_gap_cg";

    cp_compressed_pcc_top_cross: coverpoint {id_stage_i.instr_is_compressed_i,
                                             id_stage_i.instr_fetch_cheriot_bound_vio_i}
      iff (id_stage_i.instr_valid_i && cs_registers_i.pcc_cap_o.valid &&
           (fcov_pcc_top_minus_pc == 33'd2)) {
      bins compressed_at_top_executes  = {2'b10};
      bins uncompressed_at_top_faults  = {2'b01};
    }
  endgroup

  bit en_cheri_spatial_cov;

  initial begin
    void'($value$plusargs("enable_ibex_fcov=%d", en_cheri_spatial_cov));
    if (fcov_in_shadow_core()) en_cheri_spatial_cov = 1'b0;
  end

  `DV_FCOV_INSTANTIATE_CG(cheri_spatial_gap_cg, en_cheri_spatial_cov)

  // REQ_INT_06: interrupt pending while a CSC (capability store) bus transaction is
  // in flight.  A correctly-implemented CSC must complete both beats before the
  // interrupt is taken, or be rolled back entirely — no partial-store state visible.
  covergroup cheri_interrupt_cheri_cg @(posedge clk_i);
    option.name = "cheri_interrupt_cheri_cg";

    cp_csc_atomic_interrupt: coverpoint
        (load_store_unit_i.lsu_is_cap_i & load_store_unit_i.data_we_q &
         (id_stage_i.irq_pending_i | id_stage_i.irq_nm_i))
      iff (load_store_unit_i.ls_fsm_cs inside {CTX_WAIT_GNT1, CTX_WAIT_GNT2, CTX_WAIT_RESP}) {
      bins irq_during_csc = {1'b1};
    }
  endgroup

  bit en_cheri_interrupt_cov;

  initial begin
    void'($value$plusargs("enable_ibex_fcov=%d", en_cheri_interrupt_cov));
    if (fcov_in_shadow_core()) en_cheri_interrupt_cov = 1'b0;
  end

  `DV_FCOV_INSTANTIATE_CG(cheri_interrupt_cheri_cg, en_cheri_interrupt_cov)

  // ---- CHERIoT data-access bounds and permissions ----
  //
  // Every CHERIoT-mode data access, sampled once, in the first execute cycle, where
  // ibex_cheriot_ex checks it -- from the checker's own inputs, so the bins describe what was
  // actually checked:
  //   plain loads/stores through a capability  rv32_lsu_* (size from rv32_lsu_type_i), authority
  //                                            rf_fullcap_a; the second half of a misaligned
  //                                            access (addr_incr_req_i) is not checked, so skipped
  //   CLC / CSC                                cheriot_lsu_req, address cs1 + imm, 8 bytes
  // Two distances, one bin per byte within +-10:
  //   base distance  access start - base: < 0 is below the base
  //   top distance   access end (start + size) - top: > 0 overruns top. Using the *end* covers
  //                  accesses that straddle top (a word at top-2 has distance +2)
  // Crosses: each distance with the access type (load/store x byte/half/word/cap), and the fault
  // priority cross -- authority state x permission x bounds -- because when several checks fail
  // at once, which cause the core reports is where a core and its model disagree. Debug mode
  // disables CHERIoT data checks, so it is not sampled.
  logic               fcov_acc_valid, fcov_acc_we, fcov_acc_cap, fcov_acc_perm_ok;
  logic [1:0]         fcov_acc_size;      // 0 byte, 1 half, 2 word, 3 capability
  logic [1:0]         fcov_acc_auth;      // 0 untagged, 1 sealed, 2 tagged and unsealed
  logic [1:0]         fcov_acc_bounds;    // 0 starts below base, 1 inside, 2 ends above top
  logic [31:0]        fcov_acc_addr;
  logic [3:0]         fcov_acc_nbytes;
  logic signed [34:0] fcov_acc_d_base, fcov_acc_d_top;

  assign fcov_acc_cap   = g_cheriot_ex.u_ibex_cheriot_ex.cheriot_lsu_req;
  assign fcov_acc_valid = cheriot_pmode &
                          g_cheriot_ex.u_ibex_cheriot_ex.instr_first_cycle_i &
                          ~g_cheriot_ex.u_ibex_cheriot_ex.debug_mode_i &
                          (fcov_acc_cap |
                           (g_cheriot_ex.u_ibex_cheriot_ex.rv32_lsu_req_i &
                            ~g_cheriot_ex.u_ibex_cheriot_ex.addr_incr_req_i));
  assign fcov_acc_we    = fcov_acc_cap ? g_cheriot_ex.u_ibex_cheriot_ex.cheriot_operator_i.CSTORE_CAP
                                       : g_cheriot_ex.u_ibex_cheriot_ex.rv32_lsu_we_i;
  assign fcov_acc_addr  = fcov_acc_cap ? g_cheriot_ex.u_ibex_cheriot_ex.cheriot_ls_chkaddr
                                       : g_cheriot_ex.u_ibex_cheriot_ex.rv32_lsu_addr_i;
  always_comb begin
    if (fcov_acc_cap) begin
      fcov_acc_size = 2'd3; fcov_acc_nbytes = 4'd8;
    end else begin
      unique case (g_cheriot_ex.u_ibex_cheriot_ex.rv32_lsu_type_i)
        2'b00:   begin fcov_acc_size = 2'd2; fcov_acc_nbytes = 4'd4; end
        2'b01:   begin fcov_acc_size = 2'd1; fcov_acc_nbytes = 4'd2; end
        default: begin fcov_acc_size = 2'd0; fcov_acc_nbytes = 4'd1; end
      endcase
    end
  end
  assign fcov_acc_d_base = $signed({3'b000, fcov_acc_addr}) -
                           $signed({3'b000, g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.base32});
  assign fcov_acc_d_top  = $signed({3'b000, fcov_acc_addr}) + $signed({31'b0, fcov_acc_nbytes}) -
                           $signed({2'b00, g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.top33});
  // The permission this access needs: Load for loads, Store for stores. For CLC/CSC, MC only
  // decides whether the capability keeps its tag, not whether the access faults, so it is not part
  // of this.
  assign fcov_acc_perm_ok = fcov_acc_we ? g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.perms.SD
                                        : g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.perms.LD;
  assign fcov_acc_auth   = ~g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.valid              ? 2'd0 :
                           cheriot_is_sealed(g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a) ? 2'd1 :
                                                                                           2'd2;
  assign fcov_acc_bounds = (fcov_acc_d_base < 0) ? 2'd0 : (fcov_acc_d_top > 0) ? 2'd2 : 2'd1;

  covergroup cheri_access_bounds_cg @(posedge clk_i);
    option.per_instance = 1;
    option.name = "cheri_access_bounds_cg";

    cp_acc_type: coverpoint {fcov_acc_we, fcov_acc_size} iff (fcov_acc_valid) {
      bins load_byte  = {3'b000};
      bins load_half  = {3'b001};
      bins load_word  = {3'b010};
      bins load_cap   = {3'b011};
      bins store_byte = {3'b100};
      bins store_half = {3'b101};
      bins store_word = {3'b110};
      bins store_cap  = {3'b111};
    }
    cp_acc_base_dist: coverpoint fcov_acc_d_base iff (fcov_acc_valid) {
      bins d[] = {[-10:10]};
    }
    cp_acc_top_dist: coverpoint fcov_acc_d_top iff (fcov_acc_valid) {
      bins d[] = {[-10:10]};
    }
    cp_acc_perm_ok: coverpoint fcov_acc_perm_ok iff (fcov_acc_valid);
    cp_acc_auth: coverpoint fcov_acc_auth iff (fcov_acc_valid) {
      bins untagged = {2'd0};
      bins sealed   = {2'd1};
      bins valid    = {2'd2};
    }
    cp_acc_bounds: coverpoint fcov_acc_bounds iff (fcov_acc_valid) {
      bins below  = {2'd0};
      bins in_bounds = {2'd1};
      bins above  = {2'd2};
    }

    acc_base_edge_cross: cross cp_acc_type, cp_acc_base_dist;
    acc_top_edge_cross:  cross cp_acc_type, cp_acc_top_dist;
    acc_fault_priority_cross: cross cp_acc_type, cp_acc_auth, cp_acc_perm_ok, cp_acc_bounds;
  endgroup

  bit en_cheri_access_bounds_cov;

  initial begin
    void'($value$plusargs("enable_ibex_fcov=%d", en_cheri_access_bounds_cov));
    if (fcov_in_shadow_core()) en_cheri_access_bounds_cov = 1'b0;
  end

  `DV_FCOV_INSTANTIATE_CG(cheri_access_bounds_cg, en_cheri_access_bounds_cov)

  // ---- CHERIoT representability window edges ----
  //
  // CSetAddr, CIncAddr, CIncAddrImm, AUIPCC and AUICGP on a tagged, unsealed capability, sampled
  // in the execute cycle. The input capability is cs1 (rf_fullcap_a) for the first three, PCC
  // (pcc_cap_i) for AUIPCC and CGP, c3 (rf_fullcap_a: ibex_decoder.sv reads x3 for CAUICGP) for
  // AUICGP; AUIPCC/AUICGP add imm20 << 11 (CHERIoT-Sail cheri_insts.sail:70-88). The RTL keeps the
  // tag while the new address stays inside the representable window,
  // ibex_cheriot_pkg::cheriot_set_address: (newptr - base) mod 2^33 < 2^(9+E), i.e.
  // [base, base + 2^(9+E)), and the whole address space when E = 24. Coverage records how close
  // to each edge of that window the stimulus gets (one bin per byte within +-10), for each
  // exponent class, the tag outcome at the edges themselves, and for every instruction whether
  // the new address was inside or outside the window (the representability-failure case).
  //
  // AUIPCC cannot reach an odd distance from either edge: the PC is 2-byte aligned, the offset a
  // multiple of 2048, and a PCC whose window exceeds 2048 bytes has E >= 3, so an 8-aligned base.
  // Its edge bins are therefore at -2/0 (cp_rep_auipcc_edge), and the odd-distance edge bins are
  // ignored for it in rep_op_edge_cross.
  //
  // The window formula is the RTL's implementation, not the architecture's definition
  // (CHERIoT-Sail: the bounds decode the same with the new address); checked against Sail
  // getCapBoundsBits (cheri_cap_common.sail), the two agree. Whether the outcome is right is in
  // general for the cosim / TestRIG to judge against Sail; this says which edges were exercised.
  // The illegal_bins are the edge outcomes both definitions rule out for every input (a tag kept
  // past the window or on a sealed source, a tag cleared at the base or the last address), so
  // they also check that this window matches the RTL's. Representability could not be mutated in
  // the Sonata mutation check (the check is
  // inside a package function), and CHERI-C intcap tests one address in one window, so without
  // this group nothing shows whether these edges are reached at all.
  logic               fcov_rep_valid, fcov_rep_tag_out, fcov_rep_sealed, fcov_rep_outside;
  logic               fcov_rep_is_auipcc;
  logic [2:0]         fcov_rep_op;        // 0 CSetAddr, 1 CIncAddr, 2 CIncAddrImm, 3 AUIPCC, 4 AUICGP
  logic [1:0]         fcov_rep_eclass;    // 0 E=0, 1 E in 1..7, 2 E in 8..14, 3 E=24 (full)
  logic [2:0]         fcov_rep_edge;      // see cp_rep_edge_hit
  logic [4:0]         fcov_rep_exp;
  logic signed [35:0] fcov_rep_d_lo, fcov_rep_d_hi;
  decoded_cap_t       fcov_rep_in_cap;    // the capability whose address changes

  assign fcov_rep_is_auipcc = g_cheriot_ex.u_ibex_cheriot_ex.cheriot_operator_i.CAUIPCC;
  assign fcov_rep_in_cap = fcov_rep_is_auipcc ? g_cheriot_ex.u_ibex_cheriot_ex.pcc_cap_i
                                              : g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a;
  assign fcov_rep_valid = cheriot_pmode &
                          g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i &
                          g_cheriot_ex.u_ibex_cheriot_ex.instr_first_cycle_i &
                          (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_operator_i.CSET_ADDR |
                           g_cheriot_ex.u_ibex_cheriot_ex.cheriot_operator_i.CINC_ADDR |
                           g_cheriot_ex.u_ibex_cheriot_ex.cheriot_operator_i.CINC_ADDR_IMM |
                           g_cheriot_ex.u_ibex_cheriot_ex.cheriot_operator_i.CAUIPCC |
                           g_cheriot_ex.u_ibex_cheriot_ex.cheriot_operator_i.CAUICGP) &
                          fcov_rep_in_cap.valid;
  assign fcov_rep_sealed  = cheriot_is_sealed(fcov_rep_in_cap);
  assign fcov_rep_tag_out = g_cheriot_ex.u_ibex_cheriot_ex.result_cap_o.valid;
  assign fcov_rep_op      = g_cheriot_ex.u_ibex_cheriot_ex.cheriot_operator_i.CSET_ADDR ? 3'd0 :
                            g_cheriot_ex.u_ibex_cheriot_ex.cheriot_operator_i.CINC_ADDR ? 3'd1 :
                            g_cheriot_ex.u_ibex_cheriot_ex.cheriot_operator_i.CINC_ADDR_IMM ? 3'd2 :
                            fcov_rep_is_auipcc                                         ? 3'd3 :
                                                                                         3'd4;
  assign fcov_rep_exp     = cheriot_expand_exp(fcov_rep_in_cap.cexp);
  assign fcov_rep_eclass  = (fcov_rep_exp == 5'd0)  ? 2'd0 :
                            (fcov_rep_exp <= 5'd7)  ? 2'd1 :
                            (fcov_rep_exp <= 5'd14) ? 2'd2 : 2'd3;
  // Distance of the new address from the window's lower edge (base; -1 is just outside) and upper
  // edge (base + 2^(9+E); -1 is the last representable address, 0 the first outside).
  assign fcov_rep_d_lo = $signed({4'b0, g_cheriot_ex.u_ibex_cheriot_ex.result_data_o}) -
                         $signed({4'b0, fcov_rep_in_cap.base32});
  assign fcov_rep_d_hi = fcov_rep_d_lo - $signed(36'(64'd1 << (9 + fcov_rep_exp)));
  // New address outside [base, base + 2^(9+E)): the representability-failure case.
  assign fcov_rep_outside = (fcov_rep_d_lo < 0) | ((fcov_rep_eclass != 2'd3) & (fcov_rep_d_hi >= 0));
  // Which window edge the new address sits on, if any.
  assign fcov_rep_edge = (fcov_rep_d_lo == -1)                              ? 3'd1 :
                         (fcov_rep_d_lo == -2)                              ? 3'd2 :
                         (fcov_rep_d_lo == 0)                               ? 3'd3 :
                         ((fcov_rep_eclass != 2'd3) & (fcov_rep_d_hi == -1)) ? 3'd4 :
                         ((fcov_rep_eclass != 2'd3) & (fcov_rep_d_hi == -2)) ? 3'd5 :
                         ((fcov_rep_eclass != 2'd3) & (fcov_rep_d_hi == 0))  ? 3'd6 : 3'd0;

  covergroup cheri_representability_cg @(posedge clk_i);
    option.per_instance = 1;
    option.name = "cheri_representability_cg";

    cp_rep_op: coverpoint fcov_rep_op iff (fcov_rep_valid & ~fcov_rep_sealed) {
      bins setaddr    = {3'd0};
      bins incaddr    = {3'd1};
      bins incaddrimm = {3'd2};
      bins auipcc     = {3'd3};
      bins auicgp     = {3'd4};
    }
    cp_rep_eclass: coverpoint fcov_rep_eclass iff (fcov_rep_valid & ~fcov_rep_sealed) {
      bins e0    = {2'd0};
      bins e_small = {2'd1};
      bins e_large = {2'd2};
      bins full  = {2'd3};
    }
    cp_rep_lo_dist: coverpoint fcov_rep_d_lo iff (fcov_rep_valid & ~fcov_rep_sealed) {
      bins d[] = {[-10:10]};
    }
    // No upper edge when E = 24: the window is the whole address space.
    cp_rep_hi_dist: coverpoint fcov_rep_d_hi
        iff (fcov_rep_valid & ~fcov_rep_sealed & (fcov_rep_eclass != 2'd3)) {
      bins d[] = {[-10:10]};
    }
    // The tag outcome at the edges, as the core produced it. Below the base the outcome is binned
    // both ways (the reference model's call); at the base the new address equals the base, so the
    // bounds decode unchanged and the tag is kept (ibex_cheriot_pkg.sv cheriot_set_address: zero
    // distance from the base; Sail setCapAddr, capBoundsEqual).
    cp_rep_lo_edge: coverpoint {fcov_rep_d_lo == -1, fcov_rep_d_lo == 0, fcov_rep_tag_out}
        iff (fcov_rep_valid & ~fcov_rep_sealed) {
      bins below_cleared = {3'b100};
      bins below_kept    = {3'b101};
      illegal_bins base_cleared = {3'b010};
      bins base_kept     = {3'b011};
    }
    // E < 24: the last address of the window (distance 2^(9+E) - 1 from the base) is
    // representable and the first past it is not (ibex_cheriot_pkg.sv repr_mask; Sail window
    // [base, base + 2^(9+E)))
    cp_rep_hi_edge: coverpoint {fcov_rep_d_hi == -1, fcov_rep_d_hi == 0, fcov_rep_tag_out}
        iff (fcov_rep_valid & ~fcov_rep_sealed & (fcov_rep_eclass != 2'd3)) {
      illegal_bins last_cleared = {3'b100};
      bins last_kept     = {3'b101};
      bins past_cleared  = {3'b010};
      illegal_bins past_kept    = {3'b011};
    }
    // A sealed capability loses its tag on any address change, representable or not
    // (CSetAddr/CIncAddr/CIncAddrImm: clearTagIfSealed; AUICGP: isCapSealed(c3); PCC is never
    // sealed, so AUIPCC never samples this). The RTL clears it through clr_sealed
    // (ibex_cheriot_ex.sv); a kept tag would break sealing.
    cp_rep_sealed_out: coverpoint fcov_rep_tag_out iff (fcov_rep_valid & fcov_rep_sealed) {
      bins cleared = {1'b0};
      illegal_bins kept = {1'b1};
    }
    // The same for AUICGP alone (cheri_insts.sail:86).
    cp_rep_auicgp_sealed_out: coverpoint fcov_rep_tag_out
        iff (fcov_rep_valid & fcov_rep_sealed & (fcov_rep_op == 3'd4)) {
      bins cleared = {1'b0};
      illegal_bins kept = {1'b1};
    }
    // New address inside or outside the representable window.
    cp_rep_outside: coverpoint fcov_rep_outside iff (fcov_rep_valid & ~fcov_rep_sealed) {
      bins in_window = {1'b0};
      bins outside = {1'b1};
    }
    // Which edge the new address sits on.
    cp_rep_edge_hit: coverpoint fcov_rep_edge iff (fcov_rep_valid & ~fcov_rep_sealed) {
      bins lo_minus1 = {3'd1};
      bins lo_minus2 = {3'd2};
      bins lo_base   = {3'd3};
      bins hi_minus1 = {3'd4};
      bins hi_minus2 = {3'd5};
      bins hi_past   = {3'd6};
    }
    // AUIPCC edge outcomes at the even distances it can reach. AUIPCC never clears for a seal
    // (SETADDR_PCC_ARITH), so the tag follows representability alone: kept at the base and two
    // below the window's end, cleared past it (as cp_rep_lo_edge / cp_rep_hi_edge).
    cp_rep_auipcc_edge: coverpoint {fcov_rep_edge, fcov_rep_tag_out}
        iff (fcov_rep_valid & (fcov_rep_op == 3'd3)) {
      bins lo_minus2_cleared = {4'b010_0};
      bins lo_minus2_kept    = {4'b010_1};
      illegal_bins lo_base_cleared   = {4'b011_0};
      bins lo_base_kept      = {4'b011_1};
      illegal_bins hi_minus2_cleared = {4'b101_0};
      bins hi_minus2_kept    = {4'b101_1};
      bins hi_past_cleared   = {4'b110_0};
      illegal_bins hi_past_kept      = {4'b110_1};
    }

    rep_lo_edge_cross: cross cp_rep_eclass, cp_rep_lo_dist;
    rep_hi_edge_cross: cross cp_rep_eclass, cp_rep_hi_dist {
      ignore_bins full = binsof(cp_rep_eclass.full);  // never sampled: no upper edge at E = 24
    }
    rep_op_eclass_cross: cross cp_rep_op, cp_rep_eclass;
    // Every instruction with its address inside and outside the window (representability failure).
    rep_op_outside_cross: cross cp_rep_op, cp_rep_outside;
    // Every instruction at every edge; AUIPCC cannot reach an odd distance (see above).
    rep_op_edge_cross: cross cp_rep_op, cp_rep_edge_hit {
      ignore_bins auipcc_odd = binsof(cp_rep_op.auipcc) &&
                               (binsof(cp_rep_edge_hit.lo_minus1) || binsof(cp_rep_edge_hit.hi_minus1));
    }
  endgroup

  bit en_cheri_representability_cov;

  initial begin
    void'($value$plusargs("enable_ibex_fcov=%d", en_cheri_representability_cov));
    if (fcov_in_shadow_core()) en_cheri_representability_cov = 1'b0;
  end

  `DV_FCOV_INSTANTIATE_CG(cheri_representability_cg, en_cheri_representability_cov)

  // ---- CHERIoT stack high water mark (mshwm 0xBC1, mshwmb 0xBC2) ----
  //
  // CHERIoT ISA, section "Stack high water mark" (archdoc/chap-cheri-riscv.tex:773-791) and
  // CHERIoT-Sail: bits [3:0] of both CSRs read 0, writes are rounded down
  // (cheri_sys_regs.sail:98-119); a store whose address (lowest byte) lies in [mshwmb, mshwm)
  // sets mshwm to that address rounded down to 16 (cheri_addr_checks.sail:222-231); access needs
  // PCC.SR (cheri_addr_checks.sail:241-260); with cheriot_enable_i Off the CSRs do not exist
  // (ibex_cs_registers.sv CSR_MSHWM/CSR_MSHWMB). Directed stimulus: cheriot_mshwm (CHERIoT mode),
  // cheriot_illegal_rv_mode (pin Off).
  //   hwm_access_cross  CSR x read/write x PCC.SR, CHERIoT mode (no SR: capcause 0x18)
  //   cp_hwm_pin_off    the same CSRs touched with the pin Off (illegal instruction)
  //   cp_hwm_legalise   a write with bits [3:0] zero or nonzero, per CSR
  //   cp_hwm_store_pos  a store's address against the window: below mshwmb, inside, at or
  //                     above mshwm, or an empty window (mshwmb >= mshwm); crossed with the
  //                     store kind and with whether the store faults (a faulting store must not
  //                     update) and whether the core updated mshwm
  //   cp_hwm_split      the second half of a misaligned store, which the ISA does not count
  //                     (only the lowest byte's address is compared); an update on it is an
  //                     illegal bin
  logic        fcov_hwm_csr, fcov_hwm_csr_is_b, fcov_hwm_csr_wr;
  logic        fcov_hwm_store, fcov_hwm_split, fcov_hwm_store_err, fcov_hwm_set;
  logic [1:0]  fcov_hwm_pos;      // 0 below mshwmb, 1 inside, 2 at/above mshwm, 3 empty window
  logic [1:0]  fcov_hwm_kind;     // 0 byte, 1 half, 2 word, 3 capability
  logic [31:0] fcov_hwm_addr, fcov_hwm_mark, fcov_hwm_base;

  assign fcov_hwm_csr      = cs_registers_i.csr_access_i & id_stage_i.instr_valid_i &
                             id_stage_i.instr_first_cycle &
                             ((cs_registers_i.csr_addr_i == CSR_MSHWM) |
                              (cs_registers_i.csr_addr_i == CSR_MSHWMB));
  assign fcov_hwm_csr_is_b = (cs_registers_i.csr_addr_i == CSR_MSHWMB);
  assign fcov_hwm_csr_wr   = (cs_registers_i.csr_op_i != CSR_OP_READ);
  assign fcov_hwm_addr     = g_cheriot_ex.u_ibex_cheriot_ex.lsu_addr_o;
  assign fcov_hwm_mark     = g_cheriot_ex.u_ibex_cheriot_ex.csr_mshwm_i;
  assign fcov_hwm_base     = g_cheriot_ex.u_ibex_cheriot_ex.csr_mshwmb_i;
  assign fcov_hwm_store    = cheriot_pmode & g_cheriot_ex.u_ibex_cheriot_ex.lsu_req_o &
                             g_cheriot_ex.u_ibex_cheriot_ex.lsu_we_o &
                             g_cheriot_ex.u_ibex_cheriot_ex.instr_first_cycle_i &
                             ~g_cheriot_ex.u_ibex_cheriot_ex.addr_incr_req_i;
  assign fcov_hwm_split    = cheriot_pmode & g_cheriot_ex.u_ibex_cheriot_ex.lsu_req_o &
                             g_cheriot_ex.u_ibex_cheriot_ex.lsu_we_o &
                             ~g_cheriot_ex.u_ibex_cheriot_ex.lsu_is_cap_o &
                             g_cheriot_ex.u_ibex_cheriot_ex.addr_incr_req_i;
  assign fcov_hwm_store_err = g_cheriot_ex.u_ibex_cheriot_ex.lsu_cheriot_err_o;
  assign fcov_hwm_set      = g_cheriot_ex.u_ibex_cheriot_ex.csr_mshwm_set_o;
  assign fcov_hwm_pos      = (fcov_hwm_base[31:4] >= fcov_hwm_mark[31:4]) ? 2'd3 :
                             (fcov_hwm_addr[31:4] <  fcov_hwm_base[31:4]) ? 2'd0 :
                             (fcov_hwm_addr[31:4] >= fcov_hwm_mark[31:4]) ? 2'd2 : 2'd1;
  assign fcov_hwm_kind     = g_cheriot_ex.u_ibex_cheriot_ex.lsu_is_cap_o        ? 2'd3 :
                             (g_cheriot_ex.u_ibex_cheriot_ex.lsu_type_o == 2'b00) ? 2'd2 :
                             (g_cheriot_ex.u_ibex_cheriot_ex.lsu_type_o == 2'b01) ? 2'd1 : 2'd0;

  covergroup cheri_mshwm_cg @(posedge clk_i);
    option.per_instance = 1;
    option.name = "cheri_mshwm_cg";

    cp_hwm_csr: coverpoint fcov_hwm_csr_is_b iff (cheriot_pmode & fcov_hwm_csr) {
      bins mshwm  = {1'b0};
      bins mshwmb = {1'b1};
    }
    cp_hwm_csr_wr: coverpoint fcov_hwm_csr_wr iff (cheriot_pmode & fcov_hwm_csr) {
      bins read  = {1'b0};
      bins write = {1'b1};
    }
    cp_hwm_sr: coverpoint cs_registers_i.pcc_cap_o.perms.SR iff (cheriot_pmode & fcov_hwm_csr) {
      bins no_sr = {1'b0};
      bins sr    = {1'b1};
    }
    hwm_access_cross: cross cp_hwm_csr, cp_hwm_csr_wr, cp_hwm_sr;
    cp_hwm_pin_off: coverpoint {fcov_hwm_csr_is_b, fcov_hwm_csr_wr} iff (~cheriot_pmode & fcov_hwm_csr) {
      bins mshwm_read   = {2'b00};
      bins mshwm_write  = {2'b01};
      bins mshwmb_read  = {2'b10};
      bins mshwmb_write = {2'b11};
    }
    cp_hwm_legalise: coverpoint {cs_registers_i.mshwmb_en, (cs_registers_i.csr_wdata_int[3:0] != 4'h0)}
        iff (cheriot_pmode & (cs_registers_i.mshwm_en | cs_registers_i.mshwmb_en)) {
      bins mshwm_aligned    = {2'b00};
      bins mshwm_rounded    = {2'b01};
      bins mshwmb_aligned   = {2'b10};
      bins mshwmb_rounded   = {2'b11};
    }
    cp_hwm_store_pos: coverpoint fcov_hwm_pos iff (fcov_hwm_store) {
      bins below  = {2'd0};
      bins in_window = {2'd1};
      bins above  = {2'd2};
      bins empty  = {2'd3};
    }
    cp_hwm_store_kind: coverpoint fcov_hwm_kind iff (fcov_hwm_store) {
      bins byte_st = {2'd0};
      bins half_st = {2'd1};
      bins word_st = {2'd2};
      bins cap_st  = {2'd3};
    }
    cp_hwm_store_err: coverpoint fcov_hwm_store_err iff (fcov_hwm_store);
    cp_hwm_store_set: coverpoint fcov_hwm_set iff (fcov_hwm_store);
    hwm_store_kind_cross: cross cp_hwm_store_pos, cp_hwm_store_kind;
    hwm_store_err_cross: cross cp_hwm_store_pos, cp_hwm_store_err;
    // Inside & ~err must update, everything else must not; whether an inside store updated is
    // checked by the cosim against Sail and by cheriot_mshwm. An update outside the window cannot
    // be binned: csr_mshwm_set_o is the window compare itself, on the same lsu_addr_o, mshwmb and
    // mshwm in the same cycle (ibex_cheriot_ex.sv), so set implies in_window.
    hwm_store_set_cross: cross cp_hwm_store_pos, cp_hwm_store_set {
      illegal_bins set_outside_window =
        (binsof(cp_hwm_store_pos.below) || binsof(cp_hwm_store_pos.above) ||
         binsof(cp_hwm_store_pos.empty)) &&
        binsof(cp_hwm_store_set) intersect {1'b1};
    }
    cp_hwm_split: coverpoint {(fcov_hwm_pos == 2'd1), fcov_hwm_set} iff (fcov_hwm_split) {
      bins outside_no_update = {2'b00};
      bins inside_no_update  = {2'b10};
      // Only a store's start address counts (ISA stack high-water mark, Sail cheri_addr_checks.sail
      // ext_check_phys_mem_write): csr_mshwm_set_o is gated with ~addr_incr_req_i
      // (ibex_cheriot_ex.sv), so the second half never updates
      illegal_bins inside_update = {2'b11};
    }
  endgroup

  bit en_cheri_mshwm_cov;

  initial begin
    void'($value$plusargs("enable_ibex_fcov=%d", en_cheri_mshwm_cov));
    if (fcov_in_shadow_core()) en_cheri_mshwm_cov = 1'b0;
  end

  `DV_FCOV_INSTANTIATE_CG(cheri_mshwm_cg, en_cheri_mshwm_cov)

  // ---- CHERIoT zero-length and zero-permission capabilities ----
  //
  // A tagged operand whose length is 0 (top = base, e.g. CSetBounds(c, 0), also at the end of an
  // object: inCapBounds(c, top, 0) holds, cheri_cap_common.sail:711-715) or whose permissions are
  // all 0 (CAndPerm(c, 0)), by the instruction that uses it. Expected outcomes (CHERIoT-Sail):
  // every access of size >= 1 through a zero-length authority is a bounds violation; a
  // zero-permission authority fails its permission check first; CJALR does not check bounds, so
  // the fetch at the target faults; a zero-length or permission-less sealing authority makes
  // CSeal/CUnseal clear the tag. Directed stimulus: cheriot_zero_len_perm.
  //   cp_zl_cs1_use / cp_zp_cs1_use   instruction class using a zero-length / zero-perm cs1
  //   cp_zl_cs2_seal / cp_zp_cs2_seal zero-length / zero-perm sealing authority (cs2)
  //   cp_zl_setbounds                 CSetBounds* with length 0, cs1 address inside its bounds,
  //                                   at its top, or outside
  logic       fcov_zl_valid, fcov_zl_a, fcov_zp_a, fcov_zl_b, fcov_zp_b, fcov_zl_req;
  logic [3:0] fcov_zl_class;  // see cp_zl_cs1_use
  logic [1:0] fcov_zl_pos;    // 0 inside [base, top), 1 at top, 2 outside

  assign fcov_zl_valid = cheriot_pmode & g_cheriot_ex.u_ibex_cheriot_ex.instr_first_cycle_i &
                         ~g_cheriot_ex.u_ibex_cheriot_ex.debug_mode_i &
                         (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i |
                          g_cheriot_ex.u_ibex_cheriot_ex.rv32_lsu_req_i);
  assign fcov_zl_a = g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.valid &
                     (g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.top33 ==
                      {1'b0, g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.base32});
  assign fcov_zp_a = g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.valid &
                     (g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.perms == '0);
  assign fcov_zl_b = g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_b.valid &
                     (g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_b.top33 ==
                      {1'b0, g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_b.base32});
  assign fcov_zp_b = g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_b.valid &
                     (g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_b.perms == '0);
  always_comb begin
    if (g_cheriot_ex.u_ibex_cheriot_ex.rv32_lsu_req_i & ~g_cheriot_ex.u_ibex_cheriot_ex.instr_is_cheriot_i)
      fcov_zl_class = g_cheriot_ex.u_ibex_cheriot_ex.rv32_lsu_we_i ? 4'd1 : 4'd0;
    else if (cheriot_operator.CLOAD_CAP)                              fcov_zl_class = 4'd2;
    else if (cheriot_operator.CSTORE_CAP)                             fcov_zl_class = 4'd3;
    else if (cheriot_operator.CJALR)                                  fcov_zl_class = 4'd4;
    else if (cheriot_operator.CSET_BOUNDS | cheriot_operator.CSET_BOUNDS_EX |
             cheriot_operator.CSET_BOUNDS_IMM | cheriot_operator.CSET_BOUNDS_RNDN)
                                                                      fcov_zl_class = 4'd5;
    else if (cheriot_operator.CSET_ADDR | cheriot_operator.CINC_ADDR |
             cheriot_operator.CINC_ADDR_IMM)                          fcov_zl_class = 4'd6;
    else if (cheriot_operator.CSEAL)                                  fcov_zl_class = 4'd7;
    else if (cheriot_operator.CUNSEAL)                                fcov_zl_class = 4'd8;
    else if (cheriot_operator.CGET_FIELD)                             fcov_zl_class = 4'd9;
    else if (cheriot_operator.CAND_PERM)                              fcov_zl_class = 4'd10;
    else                                                              fcov_zl_class = 4'd15;
  end
  assign fcov_zl_req = ((cheriot_operator.CSET_BOUNDS | cheriot_operator.CSET_BOUNDS_EX |
                         cheriot_operator.CSET_BOUNDS_RNDN) &
                        (g_cheriot_ex.u_ibex_cheriot_ex.rf_rdata_b == 32'h0)) |
                       (cheriot_operator.CSET_BOUNDS_IMM &
                        (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_imm12_i == 12'h0));
  assign fcov_zl_pos = ({1'b0, g_cheriot_ex.u_ibex_cheriot_ex.rf_rdata_a} ==
                        g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.top33)              ? 2'd1 :
                       ((g_cheriot_ex.u_ibex_cheriot_ex.rf_rdata_a >=
                         g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.base32) &
                        ({1'b0, g_cheriot_ex.u_ibex_cheriot_ex.rf_rdata_a} <
                         g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.top33))             ? 2'd0 : 2'd2;

  covergroup cheri_zero_len_perm_cg @(posedge clk_i);
    option.per_instance = 1;
    option.name = "cheri_zero_len_perm_cg";

    cp_zl_cs1_use: coverpoint fcov_zl_class iff (fcov_zl_valid & fcov_zl_a) {
      bins load      = {4'd0};
      bins store     = {4'd1};
      bins clc       = {4'd2};
      bins csc       = {4'd3};
      bins cjalr     = {4'd4};
      bins setbounds = {4'd5};
      bins setaddr   = {4'd6};
      bins cseal     = {4'd7};
      bins cunseal   = {4'd8};
      bins cget      = {4'd9};
      bins candperm  = {4'd10};
    }
    cp_zp_cs1_use: coverpoint fcov_zl_class iff (fcov_zl_valid & fcov_zp_a) {
      bins load      = {4'd0};
      bins store     = {4'd1};
      bins clc       = {4'd2};
      bins csc       = {4'd3};
      bins cjalr     = {4'd4};
      bins setbounds = {4'd5};
      bins cseal     = {4'd7};
      bins cget      = {4'd9};
      bins candperm  = {4'd10};
    }
    cp_zl_cs2_seal: coverpoint fcov_zl_class
        iff (fcov_zl_valid & fcov_zl_b & (cheriot_operator.CSEAL | cheriot_operator.CUNSEAL)) {
      bins cseal   = {4'd7};
      bins cunseal = {4'd8};
    }
    cp_zp_cs2_seal: coverpoint fcov_zl_class
        iff (fcov_zl_valid & fcov_zp_b & (cheriot_operator.CSEAL | cheriot_operator.CUNSEAL)) {
      bins cseal   = {4'd7};
      bins cunseal = {4'd8};
    }
    cp_zl_setbounds: coverpoint fcov_zl_pos
        iff (fcov_zl_valid & fcov_zl_req & g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.valid &
             ~cheriot_is_sealed(g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a)) {
      bins in_bounds = {2'd0};
      bins at_top  = {2'd1};
      bins outside = {2'd2};
    }
  endgroup

  bit en_cheri_zero_len_perm_cov;

  initial begin
    void'($value$plusargs("enable_ibex_fcov=%d", en_cheri_zero_len_perm_cov));
    if (fcov_in_shadow_core()) en_cheri_zero_len_perm_cov = 1'b0;
  end

  `DV_FCOV_INSTANTIATE_CG(cheri_zero_len_perm_cg, en_cheri_zero_len_perm_cov)

  // ---- Illegal instructions by encoding class ----
  //
  // Sampled when the controller takes an illegal-instruction exception (FLUSH, csr_save_cause,
  // illegal_insn_prio), in CHERIoT mode and with the pin Off separately. The class is decided
  // from the instruction in ID: x16-x31 named in CHERIoT mode (decoder illegal_reg_16), an
  // illegal CSR access (illegal_csr_insn_i), a 16-bit encoding, otherwise the major opcode. In
  // CHERIoT mode mtval must be 0 (CHERIoT-Sail handle_illegal with the C platform's
  // plat_mtval_has_illegal_inst_bits() false; ibex_controller.sv illegal_insn_prio), hence the
  // illegal_bins. Directed stimulus: cheriot_illegal_sweep, cheriot_illegal_sweep_sail_only,
  // cheriot_illegal_rv_mode; random: riscv_illegal_instr_test (pin Off).
  logic       fcov_ill_valid;
  logic [3:0] fcov_ill_class;

  assign fcov_ill_valid = (id_stage_i.controller_i.ctrl_fsm_cs == FLUSH) &
                          id_stage_i.controller_i.csr_save_cause_o &
                          id_stage_i.controller_i.illegal_insn_prio;
  always_comb begin
    if (cheriot_pmode & id_stage_i.decoder_i.illegal_reg_16)      fcov_ill_class = 4'd10;
    else if (id_stage_i.illegal_csr_insn_i)                       fcov_ill_class = 4'd6;
    else if (id_stage_i.instr_is_compressed_i)                    fcov_ill_class = 4'd9;
    else begin
      unique case (id_stage_i.instr_rdata_i[6:0])
        ibex_pkg::OPCODE_CHERI:                                   fcov_ill_class = 4'd0;
        ibex_pkg::OPCODE_LOAD:                                    fcov_ill_class = 4'd1;
        ibex_pkg::OPCODE_STORE:                                   fcov_ill_class = 4'd2;
        ibex_pkg::OPCODE_JALR, ibex_pkg::OPCODE_BRANCH:           fcov_ill_class = 4'd3;
        ibex_pkg::OPCODE_MISC_MEM:                                fcov_ill_class = 4'd4;
        ibex_pkg::OPCODE_SYSTEM:                                  fcov_ill_class = 4'd5;
        ibex_pkg::OPCODE_OP, ibex_pkg::OPCODE_OP_IMM:             fcov_ill_class = 4'd7;
        ibex_pkg::OPCODE_AUICGP:                                  fcov_ill_class = 4'd11;
        default:                                                  fcov_ill_class = 4'd8;
      endcase
    end
  end

  covergroup cheri_illegal_insn_cg @(posedge clk_i);
    option.per_instance = 1;
    option.name = "cheri_illegal_insn_cg";

    cp_ill_class_cheriot: coverpoint fcov_ill_class iff (fcov_ill_valid & cheriot_pmode) {
      bins cheri_opcode  = {4'd0};
      bins load          = {4'd1};
      bins store         = {4'd2};
      bins jalr_branch   = {4'd3};
      bins misc_mem      = {4'd4};
      bins system        = {4'd5};
      bins csr           = {4'd6};
      bins op_op_imm     = {4'd7};
      bins other_opcode  = {4'd8};
      bins compressed    = {4'd9};
      bins reg_x16_x31   = {4'd10};
    }
    // With the pin Off, the encodings that only exist in CHERIoT mode.
    cp_ill_class_pin_off: coverpoint fcov_ill_class iff (fcov_ill_valid & ~cheriot_pmode) {
      bins cheri_opcode  = {4'd0};
      bins load          = {4'd1};    // includes CLC (ld)
      bins store         = {4'd2};    // includes CSC (sd)
      bins csr           = {4'd6};    // includes mshwm/mshwmb
      bins compressed    = {4'd9};    // includes c.clc/c.csc/c.clcsp/c.cscsp
      bins auicgp        = {4'd11};
    }
    cp_ill_mtval_cheriot: coverpoint (id_stage_i.controller_i.csr_mtval_o == 32'h0)
        iff (fcov_ill_valid & cheriot_pmode) {
      bins zero = {1'b1};
      illegal_bins nonzero = {1'b0};
    }
  endgroup

  bit en_cheri_illegal_insn_cov;

  initial begin
    void'($value$plusargs("enable_ibex_fcov=%d", en_cheri_illegal_insn_cov));
    if (fcov_in_shadow_core()) en_cheri_illegal_insn_cov = 1'b0;
  end

  `DV_FCOV_INSTANTIATE_CG(cheri_illegal_insn_cg, en_cheri_illegal_insn_cov)

endinterface

interface mem_monitor_if (
  input clk_i,
  input rst_ni,

  input req_i,
  input gnt_i,
  input rvalid_i,

  output int   outstanding_requests_o,
  output logic single_cycle_response_o
);

  int outstanding_requests;
  logic outstanding_requests_inc, outstanding_requests_dec;
  logic no_outstanding_requests_last_cycle;

  assign outstanding_requests_inc = req_i & gnt_i;
  assign outstanding_requests_dec = rvalid_i;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (~rst_ni) begin
      outstanding_requests               <= 0;
      no_outstanding_requests_last_cycle <= 1'b0;
    end else begin
      if (outstanding_requests_inc && !outstanding_requests_dec) begin
        outstanding_requests <= outstanding_requests + 1;
      end else if (!outstanding_requests_inc && outstanding_requests_dec) begin
        outstanding_requests <= outstanding_requests - 1;
      end

      no_outstanding_requests_last_cycle <= (outstanding_requests == 0) ||
        ((outstanding_requests == 1) && outstanding_requests_dec);
    end
  end

  assign outstanding_requests_o = outstanding_requests;
  assign single_cycle_response_o = no_outstanding_requests_last_cycle & rvalid_i;
endinterface
