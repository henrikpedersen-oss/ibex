// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class irq_seq_item extends uvm_sequence_item;

  rand bit          irq_software;
  rand bit          irq_timer;
  rand bit          irq_external;
  rand bit [14:0]   irq_fast;
  rand bit          irq_nm;
  rand int          num_of_interrupt;

  // Which lines the driver updates from this item; the others keep their current value. Both
  // default to 1 (every line, as before). Two sequences sharing the irq sequencer clear each
  // other's lines otherwise: in core_ibex_nmi_at_exc_test the random interrupts' drop-all item cut
  // an NMI pulse to 2 cycles (seed 24865, 2026-10-06).
  bit               drive_nm       = 1'b1;  // irq_nm
  bit               drive_maskable = 1'b1;  // irq_software, irq_timer, irq_external, irq_fast

  constraint num_of_interrupt_c {
    num_of_interrupt inside {[0:DATA_WIDTH-1]};
    $countones({irq_software, irq_timer, irq_external, irq_fast, irq_nm}) == num_of_interrupt;
  }

  constraint bring_up_c {
    soft num_of_interrupt == 1;
  }

  `uvm_object_utils_begin(irq_seq_item)
    `uvm_field_int(irq_software, UVM_DEFAULT)
    `uvm_field_int(irq_timer,    UVM_DEFAULT)
    `uvm_field_int(irq_external, UVM_DEFAULT)
    `uvm_field_int(irq_fast,     UVM_DEFAULT)
    `uvm_field_int(irq_nm,       UVM_DEFAULT)
    // Registered so that the driver's clone() keeps them.
    `uvm_field_int(drive_nm,       UVM_DEFAULT)
    `uvm_field_int(drive_maskable, UVM_DEFAULT)
  `uvm_object_utils_end

  `uvm_object_new

endclass : irq_seq_item
