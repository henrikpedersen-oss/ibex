// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

package ibex_dii_agent_pkg;
  import uvm_pkg::*;
  import ibex_rvfi_pkg::*;

  `include "uvm_macros.svh"
  `include "dv_macros.svh"

  `include "testrig_dpi.svh"
  `include "cheriot_sail_cosim_dpi.svh"
  `include "riscv_sail_cosim_dpi.svh"

  `include "ibex_dii_seq_item.sv"
  `include "ibex_dii_sequencer.sv"
  `include "ibex_dii_socket_seq.sv"
  `include "ibex_dii_driver.sv"
  `include "ibex_dii_scoreboard.sv"
  `include "ibex_dii_agent.sv"
endpackage
