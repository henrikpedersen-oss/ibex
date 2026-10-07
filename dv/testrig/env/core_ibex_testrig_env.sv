// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class core_ibex_testrig_env extends uvm_env;
  ibex_dii_agent dii_agent;

  `uvm_component_utils(core_ibex_testrig_env)
  `uvm_component_new

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    dii_agent = ibex_dii_agent::type_id::create("dii_agent", this);
  endfunction : build_phase
endclass
