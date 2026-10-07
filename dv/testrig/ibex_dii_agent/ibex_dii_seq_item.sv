// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// One RVFI-DII instruction packet. Command values are TestRIG's (QuickCheckVEngine DII.hs).
typedef enum bit [7:0] {
  DII_CMD_RST          = 8'h00,  // end of test: drain, reset, report halt
  DII_CMD_INSN         = 8'h01,
  DII_CMD_INTR_REQ     = 8'h69,  // insn[3:0]: 3 = software, 7 = timer, 11 = external
  DII_CMD_INTR_BARRIER = 8'h49   // retire one NOP, then clear all interrupt requests
} ibex_dii_cmd_e;

class ibex_dii_seq_item extends uvm_sequence_item;
  rand ibex_dii_cmd_e cmd;
  rand bit [31:0]     insn;

  // Response fields, filled in by the driver.
  // The test has ended (reset done, or aborted) and the instruction source expects a halt.
  bit end_of_test;
  // The test was cut short because ibex stopped acknowledging instructions.
  bit aborted;

  `uvm_object_utils_begin(ibex_dii_seq_item)
    `uvm_field_enum(ibex_dii_cmd_e, cmd, UVM_DEFAULT)
    `uvm_field_int (insn,        UVM_DEFAULT)
    `uvm_field_int (end_of_test, UVM_DEFAULT | UVM_NOCOMPARE)
    `uvm_field_int (aborted,     UVM_DEFAULT | UVM_NOCOMPARE)
  `uvm_object_utils_end

  `uvm_object_new
endclass : ibex_dii_seq_item
