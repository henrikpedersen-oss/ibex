// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

`include "prim_assert.sv"
`include "core_ibex_csr_categories.svh"

interface core_ibex_fcov_if import ibex_pkg::*, ibex_cheriot_pkg::*; (
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
  input cheriot_op_t            cheriot_operator
);
  `include "dv_fcov_macros.svh"
  import uvm_pkg::*;

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

    cp_ls_error_exception: coverpoint load_store_unit_i.fcov_ls_error_exception;
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

    `DV_FCOV_EXPR_SEEN(rf_a_ecc_err, fcov_rf_ecc_err_a_id)
    `DV_FCOV_EXPR_SEEN(rf_b_ecc_err, fcov_rf_ecc_err_b_id)

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
      illegal_bins illegal =
        {InstrCategoryOther, InstrCategoryNone, InstrCategoryOtherIllegal
         // [Debug Spec v1.0.0-STABLE, p.95]
         // > dret is an instruction which only has meaning while Debug Mode
         // We want to step over this to at-least specify how the Ibex does behave.
         //
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

    cp_dmem_response_latency: coverpoint dmem_single_cycle_response iff (data_rvalid_i) {
      bins single_cycle = {1'b1};
      bins multi_cycle = {1'b0};
    }

    `DV_FCOV_EXPR_SEEN(dmem_req_gnt_rvalid, data_rvalid_i & data_req_o & data_gnt_i)

    misaligned_data_bus_err_cross: cross cp_misaligned_first_data_bus_err,
                                         cp_misaligned_second_data_bus_err {
      // Cannot see both bus errors together as they're signalled at different states of the load
      // store unit FSM
      illegal_bins illegal = binsof(cp_misaligned_first_data_bus_err) intersect {1'b1} &&
        binsof(cp_misaligned_second_data_bus_err) intersect {1'b1};
    }

    misaligned_insn_bus_err_cross: cross id_stage_i.instr_fetch_err_i,
                                         id_stage_i.instr_fetch_err_plus2_i;

    // Include both mstatus.mie enabled/disabled because it should not affect wakeup condition
    irq_wfi_cross: cross cp_controller_fsm_sleep, cs_registers_i.mstatus_q.mie iff
                         (id_stage_i.irq_pending_i | id_stage_i.irq_nm_i);

    debug_wfi_cross: cross cp_controller_fsm_sleep, cp_all_debug_req iff
                           (id_stage_i.controller_i.fcov_all_debug_req);

    priv_mode_instr_cross: cross cp_priv_mode_id, cp_id_instr_category {
      // No un-privileged CSRs on Ibex so no InstrCategoryCSRAccess in U mode (any CSR instruction
      // becomes InstrCategoryCSRIllegal).
      illegal_bins umode_csr_access_illegal =
        binsof(cp_id_instr_category) intersect {InstrCategoryCSRAccess} &&
        binsof(cp_priv_mode_id) intersect {PRIV_LVL_U};
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
        // Only ALU, Mul, Div, Branch, Jump, Load, Store and CSR Access can see a load hazard stall
        (!binsof(cp_id_instr_category) intersect {InstrCategoryALU, InstrCategoryMul,
                                                 InstrCategoryDiv, InstrCategoryBranch,
                                                 InstrCategoryJump, InstrCategoryLoad,
                                                 InstrCategoryStore, InstrCategoryCSRAccess} &&
         binsof(cp_stall_type_id) intersect {IdStallTypeLdHz});
    }

    wb_reg_no_load_hz_instr_cross: cross cp_id_instr_category, cp_wb_reg_no_load_hz {
      // Only ALU, Mul, Div, Branch, Jump, Load, Store and CSRAccess instructions can see a WB
      // register hazard
      illegal_bins illegal =
        !binsof(cp_id_instr_category) intersect {InstrCategoryALU, InstrCategoryMul,
          InstrCategoryDiv, InstrCategoryBranch, InstrCategoryJump, InstrCategoryLoad,
          InstrCategoryStore, InstrCategoryCSRAccess}                                  &&
        binsof(cp_wb_reg_no_load_hz) intersect {1'b1};
    }

    pipe_cross: cross cp_id_instr_category, cp_if_stage_state, cp_id_stage_state, wb_stage_state {
      // When ID stage is empty the only legal instruction category is InstrCategoryNone. Conversly
      // when the instruction category is InstrCategoryNone the only legal ID stage state is
      // PipeStageEmpty.
      illegal_bins illegal = (!binsof(cp_id_instr_category) intersect {InstrCategoryNone} &&
        binsof(cp_id_stage_state) intersect {PipeStageEmpty}) ||
      (binsof(cp_id_instr_category) intersect {InstrCategoryNone} &&
        !binsof(cp_id_stage_state) intersect {PipeStageEmpty});
    }

    interrupt_taken_instr_cross: cross cp_nmi_taken, instr_unstalled_last,
      cp_id_instr_category_last iff (id_stage_i.controller_i.fcov_interrupt_taken);

    debug_instruction_cross: cross cp_debug_mode, cp_id_instr_category;

    debug_entry_if_instr_cross: cross cp_debug_entry_if, instr_unstalled_last,
      cp_id_instr_category_last;
    pipe_flush_instr_cross: cross cp_pipe_flush, instr_unstalled, cp_id_instr_category;

    exception_stall_instr_cross: cross cp_ls_pmp_exception, cp_ls_error_exception,
      cp_id_instr_category, cp_stall_type_id, instr_unstalled, cp_irq_pending, cp_debug_req {
      illegal_bins illegal =
        // Only Div, Mul, Branch and Jump instructions can see an instruction stall
        (!binsof(cp_id_instr_category) intersect {InstrCategoryDiv, InstrCategoryMul,
                                                 InstrCategoryBranch, InstrCategoryJump,
                                                 InstrCategoryFenceI} &&
         binsof(cp_stall_type_id) intersect {IdStallTypeInstr})
    ||
        // Only ALU, Mul, Div, Branch, Jump, Load, Store and CSR Access can see a load hazard stall
        (!binsof(cp_id_instr_category) intersect {InstrCategoryALU, InstrCategoryMul,
                                                 InstrCategoryDiv, InstrCategoryBranch,
                                                 InstrCategoryJump, InstrCategoryLoad,
                                                 InstrCategoryStore, InstrCategoryCSRAccess} &&
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

    rf_ecc_err_cross: cross fcov_rf_ecc_err_a_id, fcov_rf_ecc_err_b_id
                                iff (id_stage_i.instr_valid_i);

    // Each stage sees a debug request while executing a dummy instruction.
    debug_req_dummy_instr_if_stage_cross: cross cp_debug_req, cp_dummy_instr_if_stage;
    debug_req_dummy_instr_id_stage_cross: cross cp_debug_req, cp_dummy_instr_id_stage;
    debug_req_dummy_instr_wb_stage_cross: cross cp_debug_req, cp_dummy_instr_wb_stage;

    // Each stage sees an interrupt request while executing a dummy instruction.
    irq_pending_dummy_instr_if_stage_cross: cross cp_irq_pending, cp_dummy_instr_if_stage;
    irq_pending_dummy_instr_id_stage_cross: cross cp_irq_pending, cp_dummy_instr_id_stage;
    irq_pending_dummy_instr_wb_stage_cross: cross cp_irq_pending, cp_dummy_instr_wb_stage;

  endgroup

  bit en_uarch_cov;

  initial begin
   void'($value$plusargs("enable_ibex_fcov=%d", en_uarch_cov));
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
      bins bin16to31 = {[16:31]};
    }

    cp_cheri_rs2_regaddr: coverpoint id_stage_i.rf_raddr_b_o[4:0]
      iff (cheriot_pmode & id_stage_i.rf_ren_b) {
      bins bin0      = {0};
      bins bin1to14  = {[1:14]};
      bins bin15     = {15};
      bins bin16to31 = {[16:31]};
    }

    cp_cheri_rd_regaddr: coverpoint id_stage_i.rf_waddr_id_o[4:0]
      iff (cheriot_pmode & (id_stage_i.rf_we_id_o | g_cheriot_ex.u_ibex_cheriot_ex.cheriot_rf_we_o)) {
      bins bin0      = {0};
      bins bin1to14  = {[1:14]};
      bins bin15     = {15};
      bins bin16to31 = {[16:31]};
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
    cp_cheri_instr_set: coverpoint $clog2({1'b0, cheriot_operator})
      iff ((|cheriot_operator) && g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i);

    // CGET_* field selector when CGET_FIELD is executing
    cp_cheri_cget_field: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.cheriot_cap_field_sel_i
      iff (cheriot_operator.CGET_FIELD && g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i);

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

    cp_cheri_cs1_cor: coverpoint {cheriot_get_base_correction(g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.cap_cor),
                                  cheriot_get_top_correction(g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a.cap_cor)} {
      bins bin0 = {3'b000};
      bins bin1 = {3'b001};
      bins bin3 = {3'b100};
      bins bin5 = {3'b111};
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

    cp_cheri_cs2_cor: coverpoint {cheriot_get_base_correction(g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_b.cap_cor),
                                  cheriot_get_top_correction(g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_b.cap_cor)} {
      bins bin0 = {3'b000};
      bins bin1 = {3'b001};
      bins bin3 = {3'b100};
      bins bin5 = {3'b111};
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

    cp_cheri_cd_cor: coverpoint {cheriot_get_base_correction(g_cheriot_ex.u_ibex_cheriot_ex.result_cap_o.cap_cor),
                                 cheriot_get_top_correction(g_cheriot_ex.u_ibex_cheriot_ex.result_cap_o.cap_cor)} {
      bins bin0 = {3'b000};
      bins bin1 = {3'b001};
      bins bin3 = {3'b100};
      bins bin5 = {3'b111};
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

    // Register index in exception info [9:5]
    cp_cheri_exception_reg_id: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.cheriot_wb_err_info_d[9:5]
      iff ((g_cheriot_ex.u_ibex_cheriot_ex.cheriot_wb_err_d & ~cheriot_operator.CCSR_RW) |
           (g_cheriot_ex.u_ibex_cheriot_ex.lsu_req_o & g_cheriot_ex.u_ibex_cheriot_ex.lsu_cheriot_err_o)) {
      wildcard illegal_bins illegal = {5'b1????};
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
      bins bad    = {[0:23]};
      ignore_bins ignore = {[24:26]};
    }

    cp_cheri_scr_write: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.csr_addr_o
      iff (fcov_cheri_scr_write) {
      bins good[] = {[28:31]};
      bins bad    = {[0:23]};
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

    // CLC clear-permission bits applied to loaded capability (bits [3:0] of resp_lc_clrperm_q)
    // bit[3]=lc_ctag (revocation), bit[1]=lc_csdlm (store-local/mutable clear)
    cp_cheri_clc_clrperm: coverpoint load_store_unit_i.resp_lc_clrperm_q[3:0]
      iff (~load_store_unit_i.data_we_q & load_store_unit_i.lsu_resp_valid_o) {
      wildcard illegal_bins rsvd = {4'b?1??};
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

    cp_cheri_cjal_bound: coverpoint fcov_cheri_cjal_bound {
      wildcard ignore_bins ignore_base    = {9'b?_????_??11};
      wildcard ignore_bins ignore_top     = {9'b?_????_11??};
      wildcard ignore_bins ignore_range_0 = {9'b?_????_?1?1};
      wildcard ignore_bins ignore_range_1 = {9'b?_????_?11?};
      wildcard ignore_bins ignore_range_2 = {9'b?_????_1??1};
      wildcard ignore_bins ignore_room_0  = {9'b?_???1_?1??};
      wildcard ignore_bins ignore_room_1  = {9'b?_??1?_?1??};
      wildcard ignore_bins ignore_room_2  = {9'b?_?1??_?1??};
      wildcard ignore_bins ignore_room_3  = {9'b?_???1_1???};
      wildcard ignore_bins ignore_room_4  = {9'b?_??1?_1???};
      wildcard ignore_bins ignore_room_5  = {9'b?_?1??_1???};
      wildcard ignore_bins ignore_below0  = {9'b1_????_???1};
    }

    cp_cheri_cjalr_bound: coverpoint fcov_cheri_cjalr_bound {
      wildcard ignore_bins ignore_base    = {9'b?_????_??11};
      wildcard ignore_bins ignore_top     = {9'b?_????_11??};
      wildcard ignore_bins ignore_range_0 = {9'b?_????_?1?1};
      wildcard ignore_bins ignore_range_1 = {9'b?_????_?11?};
      wildcard ignore_bins ignore_range_2 = {9'b?_????_1??1};
      wildcard ignore_bins ignore_room_0  = {9'b?_???1_?1??};
      wildcard ignore_bins ignore_room_1  = {9'b?_??1?_?1??};
      wildcard ignore_bins ignore_room_2  = {9'b?_?1??_?1??};
      wildcard ignore_bins ignore_room_3  = {9'b?_???1_1???};
      wildcard ignore_bins ignore_room_4  = {9'b?_??1?_1???};
      wildcard ignore_bins ignore_room_5  = {9'b?_?1??_1???};
      wildcard ignore_bins ignore_below0  = {9'b1_????_???1};
    }

    cp_cheri_branch_bound: coverpoint fcov_cheri_branch_bound {
      wildcard ignore_bins ignore_base    = {9'b?_????_??11};
      wildcard ignore_bins ignore_top     = {9'b?_????_11??};
      wildcard ignore_bins ignore_range_0 = {9'b?_????_?1?1};
      wildcard ignore_bins ignore_range_1 = {9'b?_????_?11?};
      wildcard ignore_bins ignore_range_2 = {9'b?_????_1??1};
      wildcard ignore_bins ignore_room_0  = {9'b?_???1_?1??};
      wildcard ignore_bins ignore_room_1  = {9'b?_??1?_?1??};
      wildcard ignore_bins ignore_room_2  = {9'b?_?1??_?1??};
      wildcard ignore_bins ignore_room_3  = {9'b?_???1_1???};
      wildcard ignore_bins ignore_room_4  = {9'b?_??1?_1???};
      wildcard ignore_bins ignore_room_5  = {9'b?_?1??_1???};
      wildcard ignore_bins ignore_below0  = {9'b1_????_???1};
    }

    cp_cheri_clsc_bound: coverpoint fcov_cheri_clsc_bound {
      wildcard ignore_bins ignore_base    = {9'b?_????_??11};
      wildcard ignore_bins ignore_top     = {9'b?_????_11??};
      wildcard ignore_bins ignore_range_0 = {9'b?_????_?1?1};
      wildcard ignore_bins ignore_range_1 = {9'b?_????_?11?};
      wildcard ignore_bins ignore_range_2 = {9'b?_????_1??1};
      wildcard ignore_bins ignore_room_0  = {9'b?_???1_?1??};
      wildcard ignore_bins ignore_room_1  = {9'b?_??1?_?1??};
      wildcard ignore_bins ignore_room_2  = {9'b?_?1??_?1??};
      wildcard ignore_bins ignore_room_3  = {9'b?_???1_1???};
      wildcard ignore_bins ignore_room_4  = {9'b?_??1?_1???};
      wildcard ignore_bins ignore_room_5  = {9'b?_?1??_1???};
      wildcard ignore_bins ignore_below0  = {9'b1_????_???1};
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
    }

    cp_cheri_setboundsimm_cases: coverpoint fcov_cheri_setboundsimm {
      wildcard ignore_bins ignore0 = {5'b???11};
      wildcard ignore_bins ignore1 = {5'b?11??};
    }

    cp_cheri_rs2_req_len: coverpoint g_cheriot_ex.u_ibex_cheriot_ex.rf_rdata_b {
      bins little[] = {[32'd0:32'd8]};
      bins other    = {[32'd9:$]};
    }

    cp_cheri_rs1_bitsize: coverpoint fcov_cheri_rs1_bitsize;

    cp_cheri_mstatus_mie: coverpoint cs_registers_i.csr_mstatus_mie_o;

    // ------------------------------------------------------------------
    // CHERIoT per-instruction cross coverage
    // ------------------------------------------------------------------

    // Gate individual instruction coverpoints on cheriot_exec_id_i
    cp_instr_cauicgp: coverpoint cheriot_operator.CAUICGP
      iff (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i) {
      bins bin1 = {1'b1};
    }
    cp_instr_cauipcc: coverpoint cheriot_operator.CAUIPCC
      iff (g_cheriot_ex.u_ibex_cheriot_ex.cheriot_exec_id_i) {
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
    cheriot_cauicgp_cross: cross cp_cheri_cs1_tag, cp_cheri_cd_cs1_repr_cases,
      cp_cheri_cs1_sealed, cp_cheri_cs1_exp, cp_cheri_imm20, cp_instr_cauicgp;

    cheriot_cauipcc_cross: cross cp_cheri_cd_pcc_repr_cases, cp_cheri_pcc_exp,
      cp_cheri_imm20, cp_instr_cauipcc;

    cheriot_cincaddrimm_cross: cross cp_cheri_cs1_tag, cp_cheri_cd_cs1_repr_cases,
      cp_cheri_cs1_sealed, cp_cheri_cs1_exp, cp_cheri_imm12, cp_instr_cincaddrimm;

    cheriot_cincaddr_cross: cross cp_cheri_cs1_tag, cp_cheri_cd_cs1_repr_cases,
      cp_cheri_cs1_sealed, cp_cheri_cs1_exp, cp_cheri_rs2_as_inc, cp_instr_cincaddr;

    cheriot_csetaddr_cross: cross cp_cheri_cs1_tag, cp_cheri_cd_cs1_repr_cases,
      cp_cheri_cs1_sealed, cp_cheri_cs1_exp, cp_instr_csetaddr;

    // -- Cap-mod/arithmetic crosses --
    cheriot_candperm_cross: cross cp_cheri_cs1_tag, cp_cheri_cs1_sealed,
      cp_cheri_cs1_perms, cp_cheri_rs2_perm_mask, cp_instr_candperm;

    cheriot_ccleartag_cross: cross cp_cheri_cs1_tag, cp_cheri_cs1_sealed, cp_instr_ccleartag;

    cheriot_cmove_cross: cross cp_cheri_cs1_tag, cp_cheri_cs1_sealed, cp_instr_cmove;

    cheriot_cseqx_cross0: cross cp_cheri_cs1_tag, cp_cheri_cs1_otype,
      cp_cheri_cs2_tag, cp_cheri_cs2_otype, cp_instr_cseqx;
    cheriot_cseqx_cross1: cross cp_cheri_cs1_perms, cp_cheri_cs1_cor,
      cp_cheri_cs2_perms, cp_cheri_cs2_cor, cp_instr_cseqx;
    cheriot_cseqx_cross2: cross cp_cheri_cs1_top, cp_cheri_cs1_base,
      cp_cheri_cs2_top, cp_cheri_cs2_base, cp_instr_cseqx;
    cheriot_cseqx_cross3: cross cp_cheri_cs1_address, cp_cheri_cs2_address, cp_instr_cseqx;

    cheriot_ctestsubset_cross0: cross cp_cheri_cs1_tag, cp_cheri_cs1_otype,
      cp_cheri_cs2_tag, cp_cheri_cs2_otype, cp_instr_ctestsubset;
    cheriot_ctestsubset_cross1: cross cp_cheri_cs1_perms, cp_cheri_cs1_cor,
      cp_cheri_cs2_perms, cp_cheri_cs2_cor, cp_instr_ctestsubset;
    cheriot_ctestsubset_cross2: cross cp_cheri_cs1_top, cp_cheri_cs1_base,
      cp_cheri_cs2_top, cp_cheri_cs2_base, cp_instr_ctestsubset;

    cheriot_csub_cross: cross cp_cheri_cs1_tag, cp_cheri_cs1_address,
      cp_cheri_cs2_tag, cp_cheri_cs2_address, cp_instr_csub;

    cheriot_csethigh_cross0: cross cp_cheri_cd_tag, cp_cheri_cd_otype,
      cp_cheri_cd_cperms, cp_instr_csethigh {
      illegal_bins illegal = (binsof(cp_cheri_cd_tag) intersect {1'b1});
    }
    cheriot_csethigh_cross1: cross cp_cheri_cd_cor, cp_cheri_cd_exp,
      cp_cheri_cd_top, cp_cheri_cd_base, cp_cheri_cd_address, cp_instr_csethigh;

    // -- CGET_FIELD cross (covers all CGET_* variants via field selector) --
    cheriot_cget_field_cross: cross cp_cheri_cs1_tag, cp_cheri_cs1_address,
      cp_cheri_cget_field, cp_instr_cget_field;

    // -- CSPECIALRW cross --
    cheriot_cspecialrw_cross: cross cp_cheri_scr_addr, cp_cheri_rs1_regaddr,
      cp_cheri_rd_regaddr, cp_cheri_pcc_perm_asr, cp_instr_cspecialrw;

    // -- Jump/branch crosses --
    cheriot_cjal_cross: cross cp_cheri_rd_regaddr, cp_cheri_cjal_bound,
      cp_cheri_imm20, cp_cheri_mstatus_mie, cp_instr_cjal;

    cheriot_cjalr_cross0: cross cp_cheri_cs1_tag, cp_cheri_cs1_otype,
      cp_cheri_rd_regaddr, cp_cheri_mstatus_mie, cp_cheri_imm12, cp_instr_cjalr;
    cheriot_cjalr_cross1: cross cp_cheri_cs1_tag, cp_cheri_cs1_perm_ex,
      cp_cheri_cjalr_bound, cp_cheri_imm12, cp_instr_cjalr;

    // -- CLC/CSC load/store crosses --
    cheriot_clc_cross0: cross cp_cheri_cs1_tag, cp_cheri_cs1_sealed,
      cp_cheri_cs1_perms_load, cp_instr_clc;
    cheriot_clc_cross1: cross cp_cheri_cs1_tag, cp_cheri_clsc_bound,
      cp_cheri_imm12, cp_cheri_clsc_addr_lsb, cp_instr_clc;

    cheriot_csc_cross0: cross cp_cheri_cs1_tag, cp_cheri_cs1_sealed,
      cp_cheri_cs1_perms_store, cp_cheri_cs2_perm_gl, cp_instr_csc;
    cheriot_csc_cross1: cross cp_cheri_cs1_tag, cp_cheri_clsc_bound,
      cp_cheri_imm12, cp_cheri_clsc_addr_lsb, cp_instr_csc;

    // -- Seal/unseal crosses --
    cheriot_cseal_cross0: cross cp_cheri_cs1_tag, cp_cheri_cs1_sealed,
      cp_cheri_cs2_tag, cp_cheri_cs2_sealed, cp_instr_cseal;
    cheriot_cseal_cross1: cross cp_cheri_cs1_perm_ex, cp_cheri_cs2_tag,
      cp_cheri_cs2_perm_se, cp_cheri_cs2_seal_type, cp_cheri_seal_bound,
      cp_instr_cseal {
      ignore_bins tagged_below =
        (binsof(cp_cheri_cs2_tag) intersect {1'b1})
        with (cp_cheri_seal_bound inside {4'b???1});
      ignore_bins zero_bounds =
        (binsof(cp_cheri_cs2_seal_type) intersect {32'b0})
        with (cp_cheri_seal_bound inside {4'b???1, 4'b?1??, 4'b0000, 4'b1?0?});
    }

    cheriot_cunseal_cross0: cross cp_cheri_cs1_tag, cp_cheri_cs1_sealed, cp_cheri_cs1_perm_gl,
      cp_cheri_cs2_tag, cp_cheri_cs2_sealed, cp_cheri_cs2_perm_us, cp_cheri_cs2_perm_gl,
      cp_instr_cunseal;
    cheriot_cunseal_cross1: cross cp_cheri_cs1_otype, cp_cheri_cs1_perm_ex,
      cp_cheri_cs2_tag, cp_cheri_cs2_seal_type, cp_cheri_seal_bound, cp_instr_cunseal;

    // -- SetBounds crosses --
    cheriot_csetbounds_cross0: cross cp_cheri_cs1_tag, cp_cheri_cs1_sealed,
      cp_cheri_setbounds_cases, cp_cheri_cs1_base32, cp_cheri_cs1_top33, cp_cheri_cs1_exp,
      cp_cheri_cd_tag, cp_instr_csetbounds {
      ignore_bins ignore = (binsof(cp_cheri_cs1_tag) intersect {1'b0}) ||
        ((!binsof(cp_cheri_cs1_exp) intersect {24}) &&
         (binsof(cp_cheri_setbounds_cases) with (cp_cheri_setbounds_cases % 2 == 1)));
    }
    cheriot_csetbounds_cross1: cross cp_cheri_cs1_tag, cp_cheri_setbounds_cases,
      cp_cheri_rs2_req_len, cp_cheri_cs1_exp, cp_cheri_cd_tag, cp_instr_csetbounds {
      ignore_bins ignore = (binsof(cp_cheri_cs1_tag) intersect {1'b0}) ||
        ((!binsof(cp_cheri_cs1_exp) intersect {24}) &&
         (binsof(cp_cheri_setbounds_cases) with (cp_cheri_setbounds_cases % 2 == 1)));
    }

    cheriot_csetboundsexact_cross: cross cp_cheri_cs1_tag, cp_cheri_cs1_sealed,
      cp_cheri_setbounds_cases, cp_cheri_cs1_base32, cp_cheri_cs1_top33, cp_cheri_cs1_exp,
      cp_cheri_cd_tag, cp_instr_csetboundsexact;

    cheriot_csetboundsimm_cross: cross cp_cheri_cs1_tag, cp_cheri_cs1_sealed,
      cp_cheri_setboundsimm_cases, cp_cheri_cs1_base32, cp_cheri_cs1_top33, cp_cheri_cs1_exp,
      cp_cheri_cd_tag, cp_instr_csetboundsimm;

    cheriot_csetboundsrndn_cross: cross cp_cheri_cs1_tag, cp_cheri_rs1_bitsize,
      cp_instr_csetboundsrndn;

    // -- CRRL / CRAM crosses --
    cheriot_cram_cross: cross cp_cheri_cs1_tag, cp_cheri_rs1_bitsize, cp_instr_cram;
    cheriot_crrl_cross: cross cp_cheri_cs1_tag, cp_cheri_rs1_bitsize, cp_instr_crrl;

    // -- WB exception x instruction --
    cheriot_jump_exception_cross: cross cp_cheri_wb_exception_causes, cp_instr_cjalr {
      illegal_bins illegal =
        (binsof(cp_cheri_wb_exception_causes) intersect {5'h0, 5'h1, 5'h18});
    }

    cheriot_scr_exception_cross: cross cp_cheri_wb_exception_causes, cp_instr_cspecialrw {
      ignore_bins ignore = !binsof(cp_cheri_wb_exception_causes) intersect {5'h18};
    }

    // -- Tag clearing cross --
    cheriot_cs1cd_tag_cross: cross cp_cheri_cs1_tag, cp_cheri_cd_tag, cp_instr_cget_field;

    // ------------------------------------------------------------------
    // Instruction / error / interrupt sequence crosses
    // Ported from cheriot-ibex instr_error_sequence_cross0/1.
    // Tracks exception-cause and instruction-sequence combinations that are
    // hard to observe without explicit cross coverage.
    // Note: ID-stage errors do not reach WB, hence two separate crosses.
    // ------------------------------------------------------------------

    instr_error_sequence_cross0: cross id_instr_category, wb_instr_category,
      id_stage_i.controller_i.handle_irq, fcov_id_error, fcov_wb_error;

    instr_error_sequence_cross1: cross id_instr_category, id_instr_category_q,
      fcov_id_exc_int, fcov_id_exc_int_q;

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
      iff (id_stage_i.instr_executing) {
      bins bin1 = {1'b1};
    }

    // Taken branch × PCC bounds check — exercises in-/out-of-bounds jump targets
    cheriot_instr_branch_cross: cross cp_cheri_branch_bound, cp_instr_branch;

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

  bit en_cheri_uarch_cov;

  initial begin
    void'($value$plusargs("enable_ibex_fcov=%d", en_cheri_uarch_cov));
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

    // gnt asserted with req low is not illegal on OBI — an always-ready slave
    // may hold gnt high — so it is covered rather than excluded.
    cp_obi_handshake: coverpoint {data_req_o, data_gnt_i} {
      bins quiet         = {2'b00};
      bins gnt_no_req    = {2'b01};
      bins backpressured = {2'b10};   // request outstanding, grant withheld
      bins accepted      = {2'b11};
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
      bins resp_stalled          = binsof(cp_lsu_fsm.ctx_wait_resp) &&
                                   binsof(cp_obi_handshake.backpressured) &&
                                   binsof(cp_is_cap.capability_access);
      // A capability access cannot be in the RV32-only misaligned states.
      ignore_bins cap_in_rv32_states = binsof(cp_lsu_fsm.rv32_states) &&
                                       binsof(cp_is_cap.capability_access);
    }
  endgroup

  bit en_cheri_obi_cov;

  initial begin
    void'($value$plusargs("enable_ibex_fcov=%d", en_cheri_obi_cov));
  end

  `DV_FCOV_INSTANTIATE_CG(cheriot_obi_backpressure_cg, en_cheri_obi_cov)
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
