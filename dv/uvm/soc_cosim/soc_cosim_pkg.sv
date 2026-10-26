// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// soc_cosim: the checking stack for an Ibex-based SoC, shared by Earl Grey 2's chip bench (through
// the vendored Ibex) and the CHERIoT RTOS test SoC. See soc_cosim_env.sv for how a SoC uses it.
//
// Defines: SOC_COSIM_SPIKE (Spike, RISC-V mode), SOC_COSIM_SAIL (CHERIoT-Sail, CHERIoT mode),
// SOC_COSIM_SYSMODEL (the SystemC model). Without a reference model the stack still logs and
// counts RVFI and records runs.

package soc_cosim_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

`ifndef gfn
  `define gfn get_full_name()
`endif
`ifndef uvm_object_new
  `define uvm_object_new \
    function new(string name = ""); \
      super.new(name); \
    endfunction
`endif
`ifndef uvm_component_new
  `define uvm_component_new \
    function new(string name = "", uvm_component parent = null); \
      super.new(name, parent); \
    endfunction
`endif

  // $bits(ibex_cheriot_pkg::cap_t) as RVFI reports it.
  localparam int unsigned SOC_CAP_W = 35;
  typedef virtual soc_cosim_if soc_cosim_vif;

  `include "soc_cosim_cfg.sv"
  `include "soc_rvfi_item.sv"
  `include "soc_cosim_tb_link.sv"
`ifdef SOC_COSIM_SYSMODEL
  `include "soc_sysmodel.sv"
`endif
  `include "soc_rvfi_monitor.sv"
  `include "soc_iss_wrapper.sv"
  `include "soc_cosim_scoreboard.sv"
  `include "soc_cosim_env.sv"
endpackage
