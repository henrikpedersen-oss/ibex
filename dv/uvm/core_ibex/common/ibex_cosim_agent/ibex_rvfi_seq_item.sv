// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class ibex_rvfi_seq_item extends uvm_sequence_item;
  bit        irq_only;
  bit        intr;
  bit        trap;
  bit [31:0] insn;
  bit [31:0] pc;
  bit [4:0]  rd_addr;
  bit [31:0] rd_wdata;
  bit [32:0] rd_wcap;
  bit [63:0] order;
  bit [31:0] pre_mip;
  bit [31:0] post_mip;
  // See core_ibex_rvfi_if.sv -- marks operations of an expanded (Zcmp)
  // instruction, with expanded_insn_last set on the final one.
  bit        expanded_insn_valid;
  bit [15:0] expanded_insn;
  bit        expanded_insn_last;
  bit        nmi;
  bit        nmi_int;
  bit        debug_req;
  bit        rf_wr_suppress;
  bit [63:0] mcycle;

  bit [31:0] mhpmcounters  [10];
  bit [31:0] mhpmcountersh [10];
  bit        ic_scr_key_valid;

  // Only used by the TestRIG (DII) flow; the Spike cosim ignores these.
  bit [31:0] pc_wdata;
  bit [4:0]  rs1_addr;
  bit [31:0] rs1_data;
  bit [32:0] rs1_rcap;
  bit [4:0]  rs2_addr;
  bit [31:0] rs2_data;
  bit [32:0] rs2_rcap;
  // mem_rdata/mem_wdata are masked to the valid bytes; mem_addr is 0 when there is no access.
  bit [31:0] mem_addr;
  bit [3:0]  mem_rmask;
  bit [3:0]  mem_wmask;
  bit [31:0] mem_rdata;
  bit [31:0] mem_wdata;
  bit        mem_is_cap;
  bit [32:0] mem_rcap;
  bit [32:0] mem_wcap;

  `uvm_object_utils_begin(ibex_rvfi_seq_item)
    `uvm_field_int (intr, UVM_DEFAULT)
    `uvm_field_int (trap, UVM_DEFAULT)
    `uvm_field_int (insn, UVM_DEFAULT)
    `uvm_field_int (pc, UVM_DEFAULT)
    `uvm_field_int (rd_addr, UVM_DEFAULT)
    `uvm_field_int (rd_wdata, UVM_DEFAULT)
    `uvm_field_int (rd_wcap, UVM_DEFAULT)
    `uvm_field_int (order, UVM_DEFAULT)
    `uvm_field_int (pre_mip, UVM_DEFAULT)
    `uvm_field_int (post_mip, UVM_DEFAULT)
    `uvm_field_int (expanded_insn_valid, UVM_DEFAULT)
    `uvm_field_int (expanded_insn, UVM_DEFAULT)
    `uvm_field_int (expanded_insn_last, UVM_DEFAULT)
    `uvm_field_int (nmi, UVM_DEFAULT)
    `uvm_field_int (nmi_int, UVM_DEFAULT)
    `uvm_field_int (debug_req, UVM_DEFAULT)
    `uvm_field_int (rf_wr_suppress, UVM_DEFAULT)
    `uvm_field_int (mcycle, UVM_DEFAULT)
    `uvm_field_sarray_int (mhpmcounters, UVM_DEFAULT)
    `uvm_field_sarray_int (mhpmcountersh, UVM_DEFAULT)
    `uvm_field_int (ic_scr_key_valid, UVM_DEFAULT)
    `uvm_field_int (pc_wdata, UVM_DEFAULT)
    `uvm_field_int (rs1_addr, UVM_DEFAULT)
    `uvm_field_int (rs1_data, UVM_DEFAULT)
    `uvm_field_int (rs1_rcap, UVM_DEFAULT)
    `uvm_field_int (rs2_addr, UVM_DEFAULT)
    `uvm_field_int (rs2_data, UVM_DEFAULT)
    `uvm_field_int (rs2_rcap, UVM_DEFAULT)
    `uvm_field_int (mem_addr, UVM_DEFAULT)
    `uvm_field_int (mem_rmask, UVM_DEFAULT)
    `uvm_field_int (mem_wmask, UVM_DEFAULT)
    `uvm_field_int (mem_rdata, UVM_DEFAULT)
    `uvm_field_int (mem_wdata, UVM_DEFAULT)
    `uvm_field_int (mem_is_cap, UVM_DEFAULT)
    `uvm_field_int (mem_rcap, UVM_DEFAULT)
    `uvm_field_int (mem_wcap, UVM_DEFAULT)
  `uvm_object_utils_end

  `uvm_object_new

endclass : ibex_rvfi_seq_item
