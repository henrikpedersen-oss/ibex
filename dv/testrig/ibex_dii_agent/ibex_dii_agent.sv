// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// RVFI-DII agent. The sequencer and scoreboard are created through the factory so a test picks
// the ISA flavour (riscv / cheriot) and reference model with type overrides.
//
// While a socket sequence holds a TestRIG connection, every retired instruction is also sent back
// as an RVFI execution packet: QuickCheckVEngine needs one per instruction it sent, even in
// --single-implementation mode where the checking is done here.
class ibex_dii_agent extends uvm_agent;
  `uvm_component_utils(ibex_dii_agent)

  ibex_dii_sequencer  sequencer;
  ibex_dii_driver     driver;
  ibex_rvfi_monitor   rvfi_monitor;
  ibex_dii_scoreboard scoreboard;

  uvm_analysis_imp #(ibex_rvfi_seq_item, ibex_dii_agent) rvfi_imp;

  // Set by the driver at the end of a test: only the first hold_limit retirements since the last
  // reset answer the instruction source; the rest (the end-of-test probe) are the bench's own.
  protected bit          hold;
  protected int unsigned hold_limit;
  protected int unsigned num_retired;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    rvfi_imp = new("rvfi_imp", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sequencer    = ibex_dii_sequencer::type_id::create("sequencer", this);
    driver       = ibex_dii_driver::type_id::create("driver", this);
    rvfi_monitor = ibex_rvfi_monitor::type_id::create("rvfi_monitor", this);
    scoreboard   = ibex_dii_scoreboard::type_id::create("scoreboard", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    driver.seq_item_port.connect(sequencer.seq_item_export);
    driver.agent = this;
    rvfi_monitor.item_collected_port.connect(scoreboard.rvfi_imp);
    rvfi_monitor.item_collected_port.connect(rvfi_imp);
  endfunction

  virtual function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    if (sequencer.is_cheriot() != scoreboard.is_cheriot()) begin
      `uvm_fatal(`gfn, $sformatf("DII flavour mismatch: sequencer %s vs scoreboard %s",
                                 sequencer.get_type_name(), scoreboard.get_type_name()))
    end
    `uvm_info(`gfn, $sformatf("DII flavour: %s, reference model: %s", sequencer.get_type_name(),
                              scoreboard.get_type_name()), UVM_LOW)
  endfunction

  // The first call of a test sets the limit; later ones (a drain after an aborted probe) keep it.
  function void hold_rvfi(int unsigned limit);
    if (hold) return;
    hold       = 1'b1;
    hold_limit = limit;
  endfunction

  function void release_rvfi();
    hold        = 1'b0;
    num_retired = 0;
  endfunction

  virtual function void write(ibex_rvfi_seq_item item);
    if (item.irq_only) return;
    // A Zcmp instruction retires as several micro-ops; the instruction source sent one word and
    // expects one reply, so only the last micro-op (or one that traps) answers it.
    if (item.expanded_insn_valid && !item.expanded_insn_last && !item.trap) return;
    num_retired++;
    if (hold && num_retired > hold_limit) return;
    if (sequencer.testrig_conn == null) return;
    testrig_send_exec_pkt(sequencer.testrig_conn, exec_pkt_from_rvfi(item));
  endfunction

  // TestRIG's 64-bit data fields carry a capability's memory format in the upper half.
  static function testrig_rvfi_exec_pkt_t exec_pkt_from_rvfi(ibex_rvfi_seq_item item);
    return '{
      rvfi_intr:      8'(item.intr),
      rvfi_halt:      8'b0,
      rvfi_trap:      8'(item.trap),
      rvfi_rd_addr:   8'(item.rd_addr),
      rvfi_rs2_addr:  8'(item.rs2_addr),
      rvfi_rs1_addr:  8'(item.rs1_addr),
      rvfi_mem_wmask: (item.mem_is_cap && item.mem_wmask != 0) ? 8'hFF : 8'(item.mem_wmask),
      rvfi_mem_rmask: (item.mem_is_cap && item.mem_rmask != 0) ? 8'hFF : 8'(item.mem_rmask),
      rvfi_mem_wdata: {item.mem_wcap[31:0], item.mem_wdata},
      rvfi_mem_rdata: {item.mem_rcap[31:0], item.mem_rdata},
      rvfi_mem_addr:  64'(item.mem_addr),
      rvfi_rd_wdata:  {item.rd_wcap[31:0], item.rd_wdata},
      rvfi_rs2_data:  {item.rs2_rcap[31:0], item.rs2_data},
      rvfi_rs1_data:  {item.rs1_rcap[31:0], item.rs1_data},
      rvfi_insn:      64'(item.insn),
      rvfi_pc_wdata:  64'(item.pc_wdata),
      rvfi_pc_rdata:  64'(item.pc),
      rvfi_order:     item.order
    };
  endfunction
endclass : ibex_dii_agent
