// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// VeriCHERI formal verification wrapper for CHERIoT-Ibex.
// Instantiates ibex_top (CHERIoT mode) and checks the VeriCHERI
// representability and monotonicity invariants from RPTU-EIS/VeriCHERI.
//
// Signal macros are overridden here (before VeriCHERI includes) to match the
// ibex_top_i hierarchy used by this formal flow.  VeriCHERI's signal_macros.sv
// guards every definition with `ifndef, so our definitions below take precedence
// over the upstream core_top.core1.* defaults.
//
// Capability encoding note (differs from the older cheri_pkg this flow began on):
// ibex_cheriot_pkg's cap_t has no `exp`, `top_cor` or `base_cor` fields.  It
// stores a 4-bit compressed exponent `cexp` and a single 2-bit `cap_cor`.  The
// package supplies the accessors that recover what VeriCHERI expects:
//   cheriot_expand_exp(cexp)              -> 5-bit exp      (symbolic_repr `exp`)
//   cheriot_get_top_correction(cap_cor)   -> 2-bit top_cor
//   cheriot_get_base_correction(cap_cor)  -> 2-bit base_cor (already sign-extended)
// Every *_EXP / *_TOP_COR / *_BASE_COR macro is therefore overridden below.

// ── Signal path overrides ─────────────────────────────────────────────────────
`define SECRET_ADDR secret_address_i

// In CHERIoT mode the register file is g_cheriot_rf, which is 16 entries
// (x0-x15): rf_data holds the addresses, rf_shared the capability metadata.
// VeriCHERI's invariants loop i over 1..31, so indices >= 16 must not read out
// of bounds — those registers do not exist in this configuration.
//
// These resolve to plain array selects on vc_rf_cap / vc_rf_addr (declared in
// the module below) rather than to the hierarchical reference directly.  The
// macros are field-selected by signal_macros.sv (`REGFILE_I_CAP.valid and so
// on), and a field cannot be selected from a parenthesised expression, so the
// index guard has to live in the array's driver, not in the macro.
`define REGFILE_I_CAP  vc_rf_cap[i]
`define REGFILE_I_ADDR vc_rf_addr[i]

`define WB_CAP  ibex_top_i.u_ibex_core.wb_stage_i.g_writeback_stage.cheriot_rf_wcap_q
`define WB_ADDR ibex_top_i.u_ibex_core.wb_stage_i.g_writeback_stage.cheriot_rf_wdata_q

`define FULLCAP_A_CAP ibex_top_i.u_ibex_core.g_cheriot_ex.u_ibex_cheriot_ex.rf_fullcap_a

`define PCC_CAP  ibex_top_i.u_ibex_core.cs_registers_i.pcc_cap_q

`define MEPC_CAP  ibex_top_i.u_ibex_core.cs_registers_i.mepc_cap
`define MEPC_ADDR ibex_top_i.u_ibex_core.cs_registers_i.mepc_q

`define DEPC_CAP  ibex_top_i.u_ibex_core.cs_registers_i.depc_cap
`define DEPC_ADDR ibex_top_i.u_ibex_core.cs_registers_i.depc_q

`define DSCRATCH0_CAP  ibex_top_i.u_ibex_core.cs_registers_i.dscratch0_cap
`define DSCRATCH0_ADDR ibex_top_i.u_ibex_core.cs_registers_i.dscratch0_q

`define DSCRATCH1_CAP  ibex_top_i.u_ibex_core.cs_registers_i.dscratch1_cap
`define DSCRATCH1_ADDR ibex_top_i.u_ibex_core.cs_registers_i.dscratch1_q

`define MTVEC_CAP  ibex_top_i.u_ibex_core.cs_registers_i.mtvec_cap
`define MTVEC_ADDR ibex_top_i.u_ibex_core.cs_registers_i.mtvec_q

`define MTDC_CAP  ibex_top_i.u_ibex_core.cs_registers_i.gen_scr.mtdc_cap
`define MTDC_ADDR ibex_top_i.u_ibex_core.cs_registers_i.gen_scr.mtdc_data

`define MSCRATCHC_CAP  ibex_top_i.u_ibex_core.cs_registers_i.gen_scr.mscratchc_cap
`define MSCRATCHC_ADDR ibex_top_i.u_ibex_core.cs_registers_i.gen_scr.mscratchc_data

`define PC_IF_O     ibex_top_i.u_ibex_core.if_stage_i.pc_if_o
`define WB_ERR      ibex_top_i.u_ibex_core.g_cheriot_ex.u_ibex_cheriot_ex.cheriot_wb_err_q
`define CTRL_FSM    ibex_top_i.u_ibex_core.id_stage_i.controller_i.ctrl_fsm_cs
`define BOUND_VIO   ibex_top_i.u_ibex_core.if_stage_i.cheriot_bound_vio
`define IF_ERR      ibex_top_i.u_ibex_core.if_stage_i.if_instr_err
`define FETCH_ERR   ibex_top_i.u_ibex_core.if_stage_i.instr_fetch_err_o
`define FETCH_VALID ibex_top_i.u_ibex_core.if_stage_i.fetch_valid

// ── Exponent and correction-factor overrides ──────────────────────────────────
// See the encoding note at the top of this file.  Without these, every macro
// below would resolve to cap_t.exp / .top_cor / .base_cor, none of which exist.
`define REGFILE_I_EXP       cheriot_expand_exp(`REGFILE_I_CAP.cexp)
`define REGFILE_I_TOP_COR   cheriot_get_top_correction(`REGFILE_I_CAP.cap_cor)
`define REGFILE_I_BASE_COR  cheriot_get_base_correction(`REGFILE_I_CAP.cap_cor)

`define WB_EXP       cheriot_expand_exp(`WB_CAP.cexp)
`define WB_TOP_COR   cheriot_get_top_correction(`WB_CAP.cap_cor)
`define WB_BASE_COR  cheriot_get_base_correction(`WB_CAP.cap_cor)

`define MEPC_EXP       cheriot_expand_exp(`MEPC_CAP.cexp)
`define MEPC_TOP_COR   cheriot_get_top_correction(`MEPC_CAP.cap_cor)
`define MEPC_BASE_COR  cheriot_get_base_correction(`MEPC_CAP.cap_cor)

`define DEPC_EXP       cheriot_expand_exp(`DEPC_CAP.cexp)
`define DEPC_TOP_COR   cheriot_get_top_correction(`DEPC_CAP.cap_cor)
`define DEPC_BASE_COR  cheriot_get_base_correction(`DEPC_CAP.cap_cor)

`define DSCRATCH0_EXP       cheriot_expand_exp(`DSCRATCH0_CAP.cexp)
`define DSCRATCH0_TOP_COR   cheriot_get_top_correction(`DSCRATCH0_CAP.cap_cor)
`define DSCRATCH0_BASE_COR  cheriot_get_base_correction(`DSCRATCH0_CAP.cap_cor)

`define DSCRATCH1_EXP       cheriot_expand_exp(`DSCRATCH1_CAP.cexp)
`define DSCRATCH1_TOP_COR   cheriot_get_top_correction(`DSCRATCH1_CAP.cap_cor)
`define DSCRATCH1_BASE_COR  cheriot_get_base_correction(`DSCRATCH1_CAP.cap_cor)

`define MTVEC_EXP       cheriot_expand_exp(`MTVEC_CAP.cexp)
`define MTVEC_TOP_COR   cheriot_get_top_correction(`MTVEC_CAP.cap_cor)
`define MTVEC_BASE_COR  cheriot_get_base_correction(`MTVEC_CAP.cap_cor)

`define MTDC_EXP       cheriot_expand_exp(`MTDC_CAP.cexp)
`define MTDC_TOP_COR   cheriot_get_top_correction(`MTDC_CAP.cap_cor)
`define MTDC_BASE_COR  cheriot_get_base_correction(`MTDC_CAP.cap_cor)

`define MSCRATCHC_EXP       cheriot_expand_exp(`MSCRATCHC_CAP.cexp)
`define MSCRATCHC_TOP_COR   cheriot_get_top_correction(`MSCRATCHC_CAP.cap_cor)
`define MSCRATCHC_BASE_COR  cheriot_get_base_correction(`MSCRATCHC_CAP.cap_cor)

// pcc_cap_q is a decoded_cap_t, so top33/base32 resolve directly; only the
// exponent needs expanding.
`define PCC_EXP cheriot_expand_exp(`PCC_CAP.cexp)

// Capability arriving from memory on a CLC, with its cursor.  Used by the
// LoadedCapRepr environment constraint below.
`define LSU_RCAP  ibex_top_i.u_ibex_core.load_store_unit_i.lsu_rcap_o
`define LSU_RDATA ibex_top_i.u_ibex_core.load_store_unit_i.lsu_rdata_o

// ─────────────────────────────────────────────────────────────────────────────

module vericcheri_top
    import ibex_pkg::*;
    import ibex_cheriot_pkg::*;
  #(
    parameter int unsigned DmHaltAddr      = 32'h1A110800,
    parameter int unsigned DmExceptionAddr = 32'h1A110808,
    parameter bit          SecureIbex      = 1'b0,
    parameter bit          WritebackStage  = 1'b1,
    parameter int unsigned PMPNumRegions   = 4,
    parameter bit          RV32E           = 1'b0,
    parameter rv32zc_e     RV32ZC          = RV32Zca
) (
    input  logic                                                          clk_i,
    input  logic                                                          rst_ni,

    input  logic                                                          test_en_i,
    input  prim_ram_1p_pkg::ram_1p_cfg_req_t [ibex_pkg::IC_NUM_WAYS-1:0]  ram_cfg_icache_tag_i,
    output prim_ram_1p_pkg::ram_1p_cfg_rsp_t [ibex_pkg::IC_NUM_WAYS-1:0]  ram_cfg_icache_tag_o,
    input  prim_ram_1p_pkg::ram_1p_cfg_req_t [ibex_pkg::IC_NUM_WAYS-1:0]  ram_cfg_icache_data_i,
    output prim_ram_1p_pkg::ram_1p_cfg_rsp_t [ibex_pkg::IC_NUM_WAYS-1:0]  ram_cfg_icache_data_o,

    input  logic [31:0]                                                   hart_id_i,
    input  logic [31:0]                                                   boot_addr_i,

    // TRVK revocation-bitmap interface.  ibex_trvk is a bus-level filter in
    // ibex_top, outside the core state the VeriCHERI invariants inspect; these
    // are left as free formal inputs so the proof stays general.
    input  logic [31:0]                                                   trvk_heap_base_addr_i,
    output logic                                                          trvk_revbm_req_o,
    input  logic                                                          trvk_revbm_gnt_i,
    input  logic                                                          trvk_revbm_rvalid_i,
    output logic [31:0]                                                   trvk_revbm_addr_o,
    input  logic [31:0]                                                   trvk_revbm_rdata_i,
    input  logic [6:0]                                                    trvk_revbm_rdata_intg_i,
    input  logic                                                          trvk_revbm_err_i,

    output logic                                                          instr_req_o,
    input  logic                                                          instr_gnt_i,
    input  logic                                                          instr_rvalid_i,
    output logic [31:0]                                                   instr_addr_o,
    input  logic [31:0]                                                   instr_rdata_i,
    input  logic [6:0]                                                    instr_rdata_intg_i,
    input  logic                                                          instr_err_i,

    output logic                                                          data_req_o,
    input  logic                                                          data_gnt_i,
    input  logic                                                          data_rvalid_i,
    output logic                                                          data_we_o,
    output logic [3:0]                                                    data_be_o,
    output logic [31:0]                                                   data_addr_o,
    output logic [31:0]                                                   data_wdata_o,
    output logic [6:0]                                                    data_wdata_intg_o,
    input  logic [31:0]                                                   data_rdata_i,
    input  logic [6:0]                                                    data_rdata_intg_i,
    input  logic                                                          data_err_i,

    input  logic                                                          irq_software_i,
    input  logic                                                          irq_timer_i,
    input  logic                                                          irq_external_i,
    input  logic [14:0]                                                   irq_fast_i,
    input  logic                                                          irq_nm_i,

    input  logic                                                          scramble_key_valid_i,
    input  logic [SCRAMBLE_KEY_W-1:0]                                     scramble_key_i,
    input  logic [SCRAMBLE_NONCE_W-1:0]                                   scramble_nonce_i,
    output logic                                                          scramble_req_o,

    input  logic                                                          debug_req_i,
    output crash_dump_t                                                   crash_dump_o,
    output logic                                                          double_fault_seen_o,

    input  ibex_mubi_t                                                    cheriot_enable_i,

    input  ibex_mubi_t                                                    fetch_enable_i,
    input  ibex_mubi_t                                                    mcounteren_writable_i,
    output logic                                                          core_sleep_o,
    output logic                                                          alert_minor_o,
    output logic                                                          alert_major_internal_o,
    output logic                                                          alert_major_bus_o,

    input  logic                                                          scan_rst_ni,
    output ibex_mubi_t                                                    lockstep_cmp_en_o,

    output logic                                                          data_req_shadow_o,
    output logic                                                          data_we_shadow_o,
    output logic [3:0]                                                    data_be_shadow_o,
    output logic [31:0]                                                   data_addr_shadow_o,
    output logic [31:0]                                                   data_wdata_shadow_o,
    output logic [6:0]                                                    data_wdata_intg_shadow_o,

    output logic                                                          instr_req_shadow_o,
    output logic [31:0]                                                   instr_addr_shadow_o,

    // Free formal input: represents any one secret address in memory, held
    // constant for the duration of a proof by ConstSecretAddr below.  The
    // solver picks it, so the result is universal over addresses; without the
    // stability assume it would vary per cycle and MonoStep becomes vacuously
    // falsifiable.
    input  logic [31:0]                                                   secret_address_i
);

  localparam logic [31:0] CSR_MVENDORID_VALUE = 32'b0;
  localparam logic [31:0] CSR_MIMPID_VALUE    = 32'b0;

  default clocking @(posedge clk_i); endclocking

  // data_tag ports added by the CHERIoT cap-tagging extension.
  logic data_tag_o;
  logic data_tag_i;
  assign data_tag_i = 1'b0;

  ibex_top #(
      .DmHaltAddr      (DmHaltAddr),
      .DmExceptionAddr (DmExceptionAddr),
      .SecureIbex      (SecureIbex),
      .WritebackStage  (WritebackStage),
      .BaseIsa         (BaseIsaRV32IorCHERIoT),
      .RV32E           (RV32E),
      .RV32ZC          (RV32ZC),
      .BranchTargetALU (1'b1),
      // PMP off.  CHERIoT enforces through capabilities, and none of the
      // VeriCHERI invariants reference PMP state -- enabling it only added 4
      // regions of cfg/addr CSRs plus check logic on the fetch and load/store
      // paths to the proof's state space.  cheriot_formal/check/top.sv does not
      // enable it either, so this also brings the two flows into line.
      .PMPEnable       (1'b0),
      .PMPNumRegions   (PMPNumRegions),
      .CsrMvendorId    (CSR_MVENDORID_VALUE),
      .CsrMimpId       (CSR_MIMPID_VALUE)
  ) ibex_top_i (.*);

  // Core constraints (matching cheriot_formal/check/top.sv)
  NotDebug:  assume property (!ibex_top_i.u_ibex_core.debug_mode & !debug_req_i);
  ConstBoot: assume property (boot_addr_i == $past(boot_addr_i));
  CHERIoTOn: assume property (cheriot_enable_i == IbexMuBiOn);

  // secret_address_i must be free but CONSTANT.  It stands for one arbitrary
  // location, and MonoStep says: if nothing can reach that location now,
  // nothing can reach it next cycle.  Leaving it a free *signal* makes it free
  // per cycle, which falsifies the property without any capability changing --
  // the antecedent holds for address A, the address then becomes B, and B is
  // reachable.  The MonoStep counterexample was exactly this: secret_address_i
  // ran 0xFFFFFFFF -> 0x00000000 -> 0x7FFFFC00 -> 0xFFFFFFFF across the trace.
  //
  // With this assume the address is still universally quantified -- the solver
  // proves confinement for every value simultaneously, which is the intent
  // recorded in the spec -- it simply cannot change mid-proof.
  ConstSecretAddr: assume property (secret_address_i == $past(secret_address_i));

  // ── Memory interface protocol ─────────────────────────────────────────────
  // Without these the response signals are free inputs and the engine can
  // fabricate a memory response for a request the core never issued.  That is
  // not hypothetical: it produced the first ReprStep_Regfile counterexample.
  // An invented load completion raised rf_we_lsu_i in the same cycle a
  // CSetBoundsImm was in writeback, so rf_wdata_wb_mux_we went to 2'b11.  That
  // mux is a one-hot AND-OR (ibex_wb_stage.sv:182-220), and ibex asserts the
  // invariant itself:
  //
  //   `ASSERT(RFWriteFromOneSourceOnly, $onehot0(rf_wdata_wb_mux_we))
  //
  // With both enables set the two sources OR together — 0x7F7F_7E80 |
  // 0x8080_80FF = 0xFFFF_FEFF — yielding a cursor belonging to neither source,
  // paired with the CHERIoT path's mantissas.  The resulting capability decodes
  // to a top of 0x1_0000_0004 and breaks regfile_repr(), with no RTL defect
  // involved.
  //
  // Only the two soundness constraints from cheriot_formal/check/protocol/mem.sv
  // are taken.  Its GntBound / MemValidTimer bounded-response assumptions are
  // deliberately NOT copied: they exist for the Sail flow's liveness proofs,
  // VeriCHERI's properties are all safety invariants, and importing them would
  // restrict the environment more than soundness requires — the spec already
  // records TIME_LIMIT as a load-bearing limitation of that flow.  Bus errors
  // are likewise left free rather than assumed away.
  logic [7:0] data_outstanding_q;
  logic [7:0] instr_outstanding_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      data_outstanding_q  <= 8'h0;
      instr_outstanding_q <= 8'h0;
    end else begin
      data_outstanding_q  <= data_outstanding_q  + 8'(data_gnt_i)  - 8'(data_rvalid_i);
      instr_outstanding_q <= instr_outstanding_q + 8'(instr_gnt_i) - 8'(instr_rvalid_i);
    end
  end

  // A response is only legal while a granted request is outstanding.  The grant
  // is counted from the previous cycle, so a grant does not licence a response
  // in the same cycle.
  DataRvalidNeedsReq:  assume property (data_outstanding_q  == 8'h0 |-> ~data_rvalid_i);
  InstrRvalidNeedsReq: assume property (instr_outstanding_q == 8'h0 |-> ~instr_rvalid_i);

  // A grant is only legal in response to a request.
  DataGntNeedsReq:  assume property (~data_req_o  |-> ~data_gnt_i);
  InstrGntNeedsReq: assume property (~instr_req_o |-> ~instr_gnt_i);

  // ── Register file view for the VeriCHERI invariants ───────────────────────
  // VeriCHERI loops i over 1..31 with a runtime index, but CHERIoT's
  // g_cheriot_rf holds only 16 entries (x0-x15).  Mirror the 16 real registers
  // and tie 16..31 to a null capability: those registers do not exist in this
  // configuration, and an untagged capability trivially satisfies both the
  // representability and the protection predicates.
  cap_t        vc_rf_cap  [0:31];
  logic [31:0] vc_rf_addr [0:31];

  for (genvar g = 0; g < 16; g++) begin : g_vc_rf
    assign vc_rf_cap[g]  =
        cheriot_vec_to_regcap(ibex_top_i.gen_regfile_ff.register_file_i.g_cheriot_rf.rf_shared[g]);
    assign vc_rf_addr[g] =
        ibex_top_i.gen_regfile_ff.register_file_i.g_cheriot_rf.rf_data[g];
  end
  for (genvar g = 16; g < 32; g++) begin : g_vc_rf_absent
    assign vc_rf_cap[g]  = '0;
    assign vc_rf_addr[g] = '0;
  end

  // ── VeriCHERI property functions ─────────────────────────────────────────
  // Included inside the module so that hierarchical references to ibex_top_i.*
  // resolve correctly.  signal_macros.sv is pulled in transitively; `ifndef
  // guards ensure our overrides above take precedence.
  `include "symbolic_representability.sv"
  `include "symbolic_monotonicity.sv"

  // ── Representability invariant ────────────────────────────────────────────
  // Proved by induction: (1) the invariant holds immediately after reset, and
  // (2) if it holds now it still holds one cycle later.

  // ── Environment constraint: capabilities arriving from memory ───────────────
  //
  // This replaces the earlier WbReprAssume / RegfileReprAssume, which assumed
  // wb_repr() and regfile_repr() at every cycle — the very predicates ReprStep
  // asserts.  That made two of ReprStep's four conjuncts vacuous (it reported
  // "proven in 0.00 s"), and simply deleting them produced a counterexample at
  // 7 cycles instead: neither outcome proves anything.
  //
  // The hypothesis was that the invariant covers PCC, the register file, the
  // writeback stage and the SCRs but says nothing about *memory*, so the engine
  // could conjure a tagged word whose (exp, top, base, top_cor, base_cor)
  // fields are not a representable capability, have a CLC load it, and break
  // regfile_repr() on the next cycle.  Constraining the value arriving from
  // memory is sound — tags are unforgeable, so a tagged capability in memory
  // can only have been placed there by a CSC of a valid capability — and,
  // unlike the assumes it replaces, it constrains an environment input rather
  // than the property being proved.
  //
  // ⚠ THE HYPOTHESIS WAS WRONG, AND THIS ASSUME IS CURRENTLY VACUOUS.
  //
  // `data_tag_i` is tied to 1'b0 above, so the capability the LSU reconstructs
  // from a memory response can never be tagged: this antecedent never fires,
  // and adding the assume changed nothing — ReprStep still produced the same
  // counterexample at 7 cycles in 5.72 s.  Memory cannot inject a tagged
  // capability in this testbench at all, so the load path was never the source.
  //
  // Two consequences, both open:
  //
  //  1. The real source of the ReprStep counterexample is elsewhere.  With
  //     memory unable to supply tags, the only sources of a tagged capability
  //     are the reset state and the capability-manipulating instructions, so
  //     the engine must be building a sequence that writes a non-representable
  //     capability into the regfile, WB, an SCR or PCC.  The
  //     VeriCHERI_ReprStep_* split below exists to say which.
  //
  //  2. `data_tag_i = 1'b0` is itself a hole in this proof setup.  It means the
  //     proof never explores loading a capability from memory — which is
  //     exactly where the published RPTU-EIS LSU bounds bug lived.  Freeing
  //     data_tag_i would widen coverage substantially and would also make this
  //     assume meaningful.  Do it as a separate change, after the counter-
  //     example below is understood, so the two effects stay distinguishable.
  //
  // LoadedCapRepr is kept rather than deleted because it becomes the correct
  // and necessary guard the moment data_tag_i is freed.  LoadedCapRepr_NotVacuous
  // below fails loudly if it is still dead, so it cannot quietly mislead again.
  LoadedCapRepr: assume property (
      @(posedge clk_i) disable iff (!rst_ni)
      `LSU_RCAP.valid |-> symbolic_repr(
          `LSU_RCAP.valid,
          cheriot_expand_exp(`LSU_RCAP.cexp),
          cheriot_get_top_correction(`LSU_RCAP.cap_cor),
          cheriot_get_base_correction(`LSU_RCAP.cap_cor),
          `LSU_RCAP.top,
          `LSU_RCAP.base,
          `LSU_RDATA)
  );

  // Vacuity guard for the assume above.  If this cover is unreachable, no
  // tagged capability can ever arrive from memory and LoadedCapRepr constrains
  // nothing.  It is unreachable today, by construction (data_tag_i == 1'b0);
  // it is here so that state is reported by the flow rather than rediscovered.
  LoadedCapRepr_NotVacuous: cover property (
      @(posedge clk_i) disable iff (!rst_ni) `LSU_RCAP.valid
  );

  VeriCHERI_ReprBase: assert property (
      @(posedge clk_i)
      $rose(rst_ni) |=>
      regfile_repr() && wb_repr() && scrs_repr() && pcc_repr()
  );

  VeriCHERI_ReprStep: assert property (
      @(posedge clk_i)
      (regfile_repr() && wb_repr() && scrs_repr() && pcc_repr()) |=>
      (regfile_repr() && wb_repr() && scrs_repr() && pcc_repr())
  );

  // ── Diagnostic split of ReprStep ──────────────────────────────────────────
  // ReprStep is a four-way conjunction, so a counterexample says only "the
  // invariant broke" and not which part of the state broke it.  These four
  // assert the same antecedent against one conjunct each; their conjunction is
  // exactly equivalent to ReprStep, so proving all four proves it, and a CEX on
  // one of them localises the failure to a single piece of architectural state.
  //
  // They cost almost nothing: ReprStep's CEX is found in under six seconds.
  // Keep them — the signoff property is VeriCHERI_ReprStep, but debugging it
  // without these means reading a 7-cycle waveform to work out the same thing.
  `define REPR_ANTECEDENT \
      (regfile_repr() && wb_repr() && scrs_repr() && pcc_repr())

  VeriCHERI_ReprStep_Regfile: assert property (
      @(posedge clk_i) `REPR_ANTECEDENT |=> regfile_repr());
  VeriCHERI_ReprStep_Wb: assert property (
      @(posedge clk_i) `REPR_ANTECEDENT |=> wb_repr());
  VeriCHERI_ReprStep_Scrs: assert property (
      @(posedge clk_i) `REPR_ANTECEDENT |=> scrs_repr());
  VeriCHERI_ReprStep_Pcc: assert property (
      @(posedge clk_i) `REPR_ANTECEDENT |=> pcc_repr());

  // ── Monotonicity (non-interference) invariant ─────────────────────────────
  // If no capability in the register file, WB stage, or CSRs can access the
  // secret address, the same holds one cycle later — unless a compartment
  // switch just occurred (in which case the PCC may change).
  // secret_address_i is a free formal variable: the proof holds for all values.

  // compartment_switch() in symbolic_monotonicity.sv hardcodes otypes 1/2/3 --
  // the forward sentries of the CHERIoT revision VeriCHERI was written for.
  // This RTL also has backward sentries (OTYPE_SENTRY_ID_BKWD = 3'd4,
  // OTYPE_SENTRY_IE_BKWD = 3'd5); a CJALR through one is a compartment
  // *return*, an equally legitimate PCC transition.  Upstream does not match
  // them, so every such return was reported as a monotonicity violation -- the
  // MonoStep counterexample at bound 12 is exactly this case (the trace shows
  // chk_cs1_otype_45 with csr_clr_mie_o and branch_req_o asserted).
  //
  // Same failure class as the `4'b0110` CTRL_FSM literal in pcc_repr(): an
  // upstream encoding assumption that is silently wrong for this design.  The
  // named parameters are used here rather than numeric literals so that a
  // future change to the otype encoding is a compile error, not a silent one.
  //
  // NOTE: this sits in MonoStep's *consequent*, so widening it weakens the
  // property -- more transitions are excused.  That is correct only because
  // backward sentries genuinely are compartment switches.  It is not a
  // workaround for a failing proof and must not be widened further without the
  // same justification.
  function automatic compartment_switch_cheriot();
      return (
          ($past(`FULLCAP_A_OTYPE) inside {OTYPE_SENTRY_II_FWD,
                                           OTYPE_SENTRY_ID_FWD,
                                           OTYPE_SENTRY_IE_FWD,
                                           OTYPE_SENTRY_ID_BKWD,
                                           OTYPE_SENTRY_IE_BKWD}) &&
          ($past(`FULLCAP_A_TOP33)  == `PCC_TOP33) &&
          ($past(`FULLCAP_A_BASE32) == `PCC_BASE32)
      );
  endfunction

  VeriCHERI_MonoStep: assert property (
      @(posedge clk_i)
      (regfile_protected() && wb_protected() && scrs_protected() && pcc_protected()) |=>
      (regfile_protected() && wb_protected() && scrs_protected() && pcc_protected()) ||
      compartment_switch_cheriot()
  );

  // ── Antecedent reachability (vacuity) covers ──────────────────────────────
  //
  // Both inductive steps are implications.  If the antecedent is unreachable
  // the implication holds trivially and the proof means nothing, so each
  // antecedent needs a reachability cover.
  //
  // These must be SVA `cover property` here, not `cover` commands in
  // verify-vericcheri.tcl.  A TCL-level cover over an expression cannot
  // resolve calls to the SystemVerilog functions these predicates are built
  // from; JasperGold rejects them with
  //
  //   ERROR (ENL002): Unable to find signal "vericcheri_top.regfile_repr()".
  //
  // and — because a TCL error aborts the script — everything after that point
  // is skipped, including `prove -wait` and the results capture.  The
  // background proofs are left orphaned and the run appears to die with no
  // summary.  Same failure class as the earlier
  // `assume {vericcheri_top.VeriCHERI_ReprBase}` attempt.  Anything referring
  // to these predicates belongs in this file, where the calls resolve.
  ReprStepAntecedentReachable: cover property (
      @(posedge clk_i) disable iff (!rst_ni)
      regfile_repr() && wb_repr() && scrs_repr() && pcc_repr()
  );

  MonoStepAntecedentReachable: cover property (
      @(posedge clk_i) disable iff (!rst_ni)
      regfile_protected() && wb_protected() && scrs_protected() && pcc_protected()
  );

endmodule
