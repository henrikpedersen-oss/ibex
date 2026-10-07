// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// The sequencer carries the ISA flavour of a DII run. The base class is not usable on its own:
// a test selects the flavour with a factory override, e.g.
//   +uvm_set_type_override=ibex_dii_sequencer,ibex_dii_cheriot_sequencer
// and must pair it with the matching scoreboard (checked in ibex_dii_agent).
class ibex_dii_sequencer extends uvm_sequencer #(ibex_dii_seq_item);
  `uvm_component_utils(ibex_dii_sequencer)
  `uvm_component_new

  // Set by ibex_dii_socket_seq while it owns the TestRIG connection; used by the agent to send
  // RVFI execution packets back over the same socket.
  chandle testrig_conn;

  protected virtual core_ibex_dii_intf dii_vif;

  virtual function bit is_cheriot();
    `uvm_fatal(`gfn, {"No DII flavour selected: override ibex_dii_sequencer with ",
                      "ibex_dii_riscv_sequencer or ibex_dii_cheriot_sequencer"})
    return 1'b0;
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual core_ibex_dii_intf)::get(this, "", "dii_if", dii_vif)) begin
      `uvm_fatal(`gfn, "dii_if must be provided")
    end
    // Still inside the initial reset, so the core comes out of it in the right mode.
    dii_vif.set_cheriot_enable(is_cheriot());
  endfunction
endclass : ibex_dii_sequencer

class ibex_dii_riscv_sequencer extends ibex_dii_sequencer;
  `uvm_component_utils(ibex_dii_riscv_sequencer)
  `uvm_component_new

  virtual function bit is_cheriot();
    return 1'b0;
  endfunction
endclass : ibex_dii_riscv_sequencer

class ibex_dii_cheriot_sequencer extends ibex_dii_sequencer;
  `uvm_component_utils(ibex_dii_cheriot_sequencer)
  `uvm_component_new

  virtual function bit is_cheriot();
    return 1'b1;
  endfunction
endclass : ibex_dii_cheriot_sequencer
