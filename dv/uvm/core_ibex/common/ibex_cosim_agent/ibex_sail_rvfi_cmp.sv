// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Compares one retired instruction as ibex reported it on RVFI against the RVFI execution packet
// a Sail model produced for the same instruction word. Shared by the TestRIG scoreboard
// (ibex_dii_scoreboard) and the UVM cosim scoreboard's RISC-V Sail checker, so the two benches
// cannot drift apart in what they accept as a match.
//
// Checked: trap, next PC, integer destination (address and data), capability destination
// (CHERIoT) and memory access (masks, address, data). Every exclusion is listed where it is made,
// with the RVFI quirk or model limitation that forces it.
//
// Fault injection (to prove the checks can fail): the owner reads +<prefix>_corrupt=<n> and
// +<prefix>_corrupt_field=rd|pc|trap|mem|insn|rdtag|wtag|intr through configure_corruption();
// maybe_corrupt() then flips one bit on the RTL side of the n-th retired instruction that
// exercises that field. insn is checked by the TestRIG scoreboard (against the injected word),
// rdtag/wtag only by CHERIoT runs (an integer write's tag, a capability store's tag). intr flips
// rvfi_intr of a non-trapping retirement that does not follow a trap, for the TestRIG
// scoreboard's interrupt check: on an
// ordinary instruction it is an interrupt entry the model did not take (n=1 always is: the first
// instruction of a run), on an interrupt handler's first instruction one the DUT did not take.
class ibex_sail_rvfi_cmp extends uvm_object;
  `uvm_object_utils(ibex_sail_rvfi_cmp)

  typedef struct {
    bit        trap;
    bit [31:0] pc_wdata;
    bit [4:0]  rd_addr;
    bit [31:0] rd_wdata;
    // Capability destination (CHERIoT only): cd_addr is 0 when none was written.
    bit [4:0]  cd_addr;
    bit [63:0] cd_wdata;   // memory-format metadata in [63:32], address in [31:0]
    bit        cd_wtag;
    bit [31:0] mem_addr;
    bit [7:0]  mem_rmask;
    bit [7:0]  mem_wmask;
    bit [63:0] mem_rdata;
    bit [63:0] mem_wdata;
    // Tag the model's memory holds for the granule a capability store wrote (CHERIoT only; the
    // RVFI memory record has no tag, so the owner reads it from the model's tag memory).
    bit        mem_wtag;
  } model_result_t;

  localparam bit [31:0] MRET_INSN = 32'h3020_0073;

  // Set by a trapping instruction or an mret; checked against the next retirement's PC.
  protected bit        trap_target_valid;
  protected bit [31:0] trap_target;

  protected int unsigned corrupt_at;
  protected string       corrupt_field = "rd";
  protected int unsigned corrupt_candidates;
  protected bit          corrupt_applied;
  // Whether the previous item passed to maybe_corrupt() trapped: rvfi_intr on the retirement after
  // a trap marks the synchronous handler's first instruction, which the interrupt check ignores.
  protected bit          corrupt_prev_trap;

  function new(string name = "ibex_sail_rvfi_cmp");
    super.new(name);
  endfunction

  // Forget any pending trap target: call when the model is re-initialised (core reset).
  function void reset();
    trap_target_valid = 1'b0;
  endfunction

  // ---- Fault injection ----------------------------------------------------------------------

  // Reads +<prefix>_corrupt and +<prefix>_corrupt_field. Returns an error message for an unknown
  // field, "" otherwise.
  function string configure_corruption(string prefix);
    void'($value$plusargs({prefix, "_corrupt=%d"}, corrupt_at));
    void'($value$plusargs({prefix, "_corrupt_field=%s"}, corrupt_field));
    if (corrupt_at != 0 &&
        !(corrupt_field inside {"rd", "pc", "trap", "mem", "insn", "rdtag", "wtag", "intr"})) begin
      return $sformatf("Unknown +%s_corrupt_field=%s", prefix, corrupt_field);
    end
    return "";
  endfunction

  function bit corruption_requested();
    return corrupt_at != 0;
  endfunction

  // Returns the item to check: the original, or a corrupted copy. info is set when the corruption
  // is applied, so the owner can log it.
  function ibex_rvfi_seq_item maybe_corrupt(ibex_rvfi_seq_item item, output string info);
    ibex_rvfi_seq_item c;
    bit applicable;
    bit prev_trap = corrupt_prev_trap;

    info = "";
    corrupt_prev_trap = item.trap;
    if (corrupt_at == 0 || corrupt_applied) return item;
    case (corrupt_field)
      "rd":    applicable = !item.trap && item.rd_addr != 0 && !is_counter_csr_read(item.insn);
      "mem":   applicable = !item.trap && is_mem_insn(item.insn) && item.mem_wmask != 0;
      "pc":    applicable = !item.trap;
      // An integer write: the model will report no capability write for it.
      "rdtag": applicable = !item.trap && item.rd_addr != 0 && !item.rd_wcap[32] &&
                            !is_counter_csr_read(item.insn);
      "wtag":  applicable = !item.trap && item.mem_is_cap && item.mem_wmask != 0;
      // Not after a trap either: ibex_dii_scoreboard check_interrupt() ignores rvfi_intr there, so
      // a flip would be applied and never seen.
      "intr":  applicable = !item.trap && !prev_trap;
      default: applicable = 1'b1;
    endcase
    if (!applicable || ++corrupt_candidates < corrupt_at) return item;

    $cast(c, item.clone());
    case (corrupt_field)
      "rd":   c.rd_wdata[0]  = ~c.rd_wdata[0];
      "pc":   c.pc_wdata[2]  = ~c.pc_wdata[2];
      "trap": c.trap         = ~c.trap;
      "mem":  c.mem_wdata[0] = ~c.mem_wdata[0];
      "insn": c.insn[7]      = ~c.insn[7];
      "rdtag": c.rd_wcap[32] = 1'b1;
      "wtag": c.mem_wcap[32] = ~c.mem_wcap[32];
      "intr": c.intr         = ~c.intr;
    endcase
    corrupt_applied = 1'b1;
    info = $sformatf("corrupted %s of pc=0x%08x insn=0x%08x", corrupt_field, item.pc, item.insn);
    return c;
  endfunction

  // "" if no corruption was requested or it was applied; otherwise why the run proves nothing.
  function string corruption_never_applied(string prefix);
    if (corrupt_at == 0 || corrupt_applied) return "";
    return $sformatf("+%s_corrupt=%0d (%s) never applied: only %0d candidates", prefix,
                     corrupt_at, corrupt_field, corrupt_candidates);
  endfunction

  // ---- Comparison ---------------------------------------------------------------------------

  // A trapping instruction or an mret recorded where the model went; this retirement must be
  // there. Call before stepping the model for rtl.
  function void check_trap_target(ibex_rvfi_seq_item rtl, ref string errs[$]);
    if (!trap_target_valid) return;
    if (rtl.pc != trap_target) begin
      errs.push_back($sformatf("trap/mret target: core went to 0x%08x, model 0x%08x",
                               rtl.pc, trap_target));
    end
    trap_target_valid = 1'b0;
  endfunction

  function void compare(ibex_rvfi_seq_item rtl, model_result_t model, ref string errs[$]);
    bit [7:0]  rtl_rmask, rtl_wmask;
    bit [63:0] rtl_rdata, rtl_wdata, model_rdata, model_wdata;

    if (rtl.trap != model.trap) begin
      errs.push_back($sformatf("trap: rtl=%0b model=%0b", rtl.trap, model.trap));
    end
    // ibex's RVFI (unchanged from upstream) reports the sequential next PC for a trapping
    // instruction or an mret; the redirect happens later, in writeback. So for those, check
    // where the core actually went: the next retired instruction must be at the model's target.
    if ((rtl.trap && model.trap) || (!rtl.trap && !model.trap && rtl.insn == MRET_INSN)) begin
      trap_target       = model.pc_wdata;
      trap_target_valid = 1'b1;
    end else if (!rtl.trap && !model.trap &&
                 {rtl.pc_wdata[31:1], 1'b0} != model.pc_wdata) begin
      // Bit 0 is ignored: for jalr ibex's RVFI reports the raw target (rs1 + imm); the fetch
      // clears bit 0 (ibex_if_stage.sv prefetch_addr), as the ISA requires.
      errs.push_back($sformatf("next pc: rtl=0x%08x model=0x%08x", rtl.pc_wdata, model.pc_wdata));
    end
    // Nothing else is architecturally committed by a trapping instruction.
    if (rtl.trap || model.trap) return;

    if (model.cd_addr != 0) begin
      // Capability write: the model reports it in its CHERI record, not as an integer write.
      if (rtl.rd_addr != model.cd_addr) begin
        errs.push_back($sformatf("cap rd addr: rtl=c%0d model=c%0d", rtl.rd_addr,
                                 model.cd_addr));
      end else begin
        if ({rtl.rd_wcap[31:0], rtl.rd_wdata} != model.cd_wdata) begin
          errs.push_back($sformatf("cap rd data (c%0d): rtl=0x%08x_%08x model=0x%016x",
                                   rtl.rd_addr, rtl.rd_wcap[31:0], rtl.rd_wdata,
                                   model.cd_wdata));
        end
        if (rtl.rd_wcap[32] != model.cd_wtag) begin
          errs.push_back($sformatf("cap rd tag (c%0d): rtl=%0b model=%0b", rtl.rd_addr,
                                   rtl.rd_wcap[32], model.cd_wtag));
        end
      end
    end else if (is_unchanged_rewrite(rtl, model)) begin
      // HINT executed as a no-op rewrite: nothing architectural to compare.
    end else if (rtl.rd_addr != model.rd_addr) begin
      errs.push_back($sformatf("rd addr: rtl=x%0d model=x%0d", rtl.rd_addr, model.rd_addr));
    end else begin
      if (rtl.rd_addr != 0 && !is_counter_csr_read(rtl.insn) &&
          rtl.rd_wdata != model.rd_wdata) begin
        errs.push_back($sformatf("rd data (x%0d): rtl=0x%08x model=0x%08x", rtl.rd_addr,
                                 rtl.rd_wdata, model.rd_wdata));
      end
      // The model wrote an integer, which clears a CHERIoT register's tag. An RTL that kept the
      // tag passes every data comparison and is only caught here.
      if (rtl.rd_addr != 0 && rtl.rd_wcap[32]) begin
        errs.push_back($sformatf("rd tag (x%0d): rtl=1 model=0 (integer write left the tag set)",
                                 rtl.rd_addr));
      end
    end

    // ibex's RVFI (unchanged from upstream, ibex_core.sv rvfi_stage_mem_rmask) derives the masks
    // from lsu_type for every instruction, so a non-memory instruction reports a 4-byte read.
    // Only trust them for instructions that really are loads or stores.
    // A capability access is one 8-byte access in the model and two beats on the RTL; the RVFI
    // record carries the capability's memory format in *_cap[31:0] (same packing as TestRIG's).
    if (is_mem_insn(rtl.insn)) begin
      rtl_rmask = rtl.mem_is_cap && rtl.mem_rmask != 0 ? 8'hFF : 8'(rtl.mem_rmask);
      rtl_wmask = rtl.mem_is_cap && rtl.mem_wmask != 0 ? 8'hFF : 8'(rtl.mem_wmask);
    end else begin
      rtl_rmask = '0;
      rtl_wmask = '0;
    end
    if (rtl_rmask != model.mem_rmask || rtl_wmask != model.mem_wmask) begin
      errs.push_back($sformatf("mem masks: rtl=r%02x/w%02x model=r%02x/w%02x", rtl_rmask,
                               rtl_wmask, model.mem_rmask, model.mem_wmask));
      return;
    end
    if (rtl_rmask == 0 && rtl_wmask == 0) return;

    if (rtl.mem_addr != model.mem_addr) begin
      errs.push_back($sformatf("mem addr: rtl=0x%08x model=0x%08x", rtl.mem_addr,
                               model.mem_addr));
    end
    rtl_rdata   = rtl.mem_is_cap ? {rtl.mem_rcap[31:0], rtl.mem_rdata} : 64'(rtl.mem_rdata);
    rtl_wdata   = rtl.mem_is_cap ? {rtl.mem_wcap[31:0], rtl.mem_wdata} : 64'(rtl.mem_wdata);
    model_rdata = model.mem_rdata & byte_mask(rtl_rmask);
    model_wdata = model.mem_wdata & byte_mask(rtl_wmask);
    if (rtl_wmask != 0 && rtl_wdata != model_wdata) begin
      errs.push_back($sformatf("mem wdata: rtl=0x%016x model=0x%016x", rtl_wdata, model_wdata));
    end
    if (rtl_rmask != 0 && rtl_rdata != model_rdata) begin
      errs.push_back($sformatf("mem rdata: rtl=0x%016x model=0x%016x", rtl_rdata, model_rdata));
    end
    // A capability store's tag. Without this it is checked only if a later load reads it back.
    if (rtl.mem_is_cap && rtl_wmask != 0 && rtl.mem_wcap[32] != model.mem_wtag) begin
      errs.push_back($sformatf("mem wtag: rtl=%0b model=%0b", rtl.mem_wcap[32], model.mem_wtag));
    end
  endfunction

  // ---- Helpers ------------------------------------------------------------------------------

  static function bit [63:0] byte_mask(bit [7:0] mask);
    for (int i = 0; i < 8; i++) byte_mask[8*i+:8] = {8{mask[i]}};
  endfunction

  // HINT encodings such as c.slli/c.srai rd, 0 must have no architectural effect. The model skips
  // the write; ibex executes them as a shift by zero and writes rd back with its own value. Accept
  // that only when nothing changed: same register read and written, same data, same capability
  // (an integer write would otherwise clear a CHERIoT tag, which is a real difference).
  static function bit is_unchanged_rewrite(ibex_rvfi_seq_item rtl, model_result_t model);
    return model.rd_addr == 0 && model.cd_addr == 0 && rtl.rd_addr != 0 &&
           rtl.rs1_addr == rtl.rd_addr && rtl.rd_wdata == rtl.rs1_data &&
           rtl.rd_wcap == rtl.rs1_rcap;
  endfunction

  // Loads and stores, including CHERIoT clc/csc (LOAD/STORE with funct3 011) and the compressed
  // forms: quadrants 0 and 2 with funct3 010 (lw/lwsp), 011 (clc/clcsp), 110 (sw/swsp) and 111
  // (csc/cscsp), and Zcb's c.lbu/c.lhu/c.lh/c.sb/c.sh (quadrant 0, funct3 100, insn[12] = 0).
  static function bit is_mem_insn(bit [31:0] insn);
    if (insn[1:0] == 2'b11) return insn[6:0] inside {7'h03, 7'h23};
    if (insn[1:0] == 2'b00 && insn[15:13] == 3'b100) return !insn[12];
    return insn[1:0] inside {2'b00, 2'b10} && insn[15:13] inside {3'b010, 3'b011, 3'b110, 3'b111};
  endfunction

  // mcycle/minstret/mhpmcounter* and their U-mode shadows (SYSTEM opcode, funct3 != 0).
  static function bit is_counter_csr_read(bit [31:0] insn);
    bit [11:0] csr = insn[31:20];
    if (insn[6:0] != 7'h73 || insn[14:12] == 3'b000) return 1'b0;
    return csr inside {[12'hB00:12'hB1F], [12'hB80:12'hB9F], [12'hC00:12'hC1F],
                       [12'hC80:12'hC9F]};
  endfunction
endclass : ibex_sail_rvfi_cmp
