// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

import uvm_pkg::*;
import ibex_dii_agent_pkg::*;
import core_ibex_testrig_env_pkg::*;

// Runs a TestRIG instruction stream until the vengine stops sending. The flavour comes from the
// factory, e.g. for CHERIoT:
//   +uvm_set_type_override=ibex_dii_sequencer,ibex_dii_cheriot_sequencer
//   +uvm_set_type_override=ibex_dii_scoreboard,ibex_dii_cheriot_sail_scoreboard
class core_ibex_testrig_test extends uvm_test;
  `uvm_component_utils(core_ibex_testrig_test)
  `uvm_component_new

  core_ibex_testrig_env testrig_env;

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    testrig_env = core_ibex_testrig_env::type_id::create("testrig_env", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    ibex_dii_socket_seq seq = ibex_dii_socket_seq::type_id::create("seq");

    phase.raise_objection(this);
    seq.start(testrig_env.dii_agent.sequencer);
    `uvm_info(`gfn, $sformatf("%0d tests run, %0d aborted", seq.num_tests, seq.num_aborted),
              UVM_NONE)
    phase.drop_objection(this);
  endtask
endclass
