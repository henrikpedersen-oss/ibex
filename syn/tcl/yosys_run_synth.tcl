# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

source ./tcl/yosys_common.tcl

if { $lr_synth_flatten } {
  set flatten_opt "-flatten"
} else {
  set flatten_opt ""
}

if { $lr_synth_timing_run } {
  write_sdc_out $lr_synth_sdc_file_in $lr_synth_sdc_file_out
}

# Black boxes (sv2v_convert.sh: the iCache's bare RAM arrays, SRAM macros in silicon).
foreach lib_file [glob -nocomplain $lr_synth_out_dir/generated/lib/*.v] {
  yosys "read_verilog -lib $lib_file"
}

yosys "read_verilog -defer -sv ./rtl/prim_clock_gating.v $lr_synth_out_dir/generated/*.v"

if { $lr_synth_ibex_config ne "" } {
  # Written by syn_yosys.sh (scripts/ibex_config_chparam.py): every parameter of the configuration.
  source $lr_synth_out_dir/generated/ibex_config_params.tcl
  foreach param $lr_synth_ibex_params {
    yosys "chparam -set [lindex $param 0] [lindex $param 1] $lr_synth_top_module"
  }
} else {
  if { $lr_synth_ibex_branch_target_alu } {
    yosys "chparam -set BranchTargetALU 1 $lr_synth_top_module"
  }

  if { $lr_synth_ibex_writeback_stage } {
    yosys "chparam -set WritebackStage 1 $lr_synth_top_module"
  }

  yosys "chparam -set BaseIsa $lr_synth_ibex_base_isa $lr_synth_top_module"

  yosys "chparam -set RV32B $lr_synth_ibex_bitmanip $lr_synth_top_module"

  yosys "chparam -set RV32M $lr_synth_ibex_multiplier $lr_synth_top_module"

  yosys "chparam -set RegFile $lr_synth_ibex_regfile $lr_synth_top_module"
}

if { $lr_synth_ibex_secure_ibex } {
  yosys "chparam -set SecureIbex 1 $lr_synth_top_module"
  # Place keep_hierarchy contraints on relevant modules to prevent aggressive
  # synthesis optimzations across the boundaries of these modules.
  yosys "hierarchy -check -top $lr_synth_top_module"
  yosys "setattr -mod -set keep_hierarchy 1 *prim_and2*"
  yosys "setattr -mod -set keep_hierarchy 1 *prim_buf*"
  yosys "setattr -mod -set keep_hierarchy 1 *prim_clock_mux2*"
  yosys "setattr -mod -set keep_hierarchy 1 *prim_flop*"
}

yosys "synth $flatten_opt -top $lr_synth_top_module"
yosys "opt -purge"

yosys "write_verilog $lr_synth_pre_map_out"

# Map latch primitives onto latch cells (rtl/latch_map.v for NanGate45, else lib/syn_lib.sh's)
yosys "techmap -map $lr_synth_latch_map"

yosys "dfflibmap -liberty $lr_synth_cell_library_path"
yosys "opt"

set yosys_abc_clk_period [expr $lr_synth_clk_period - $lr_synth_abc_clk_uprate]

if { $lr_synth_timing_run } {
  yosys "abc -liberty $lr_synth_cell_library_path -constr $lr_synth_abc_sdc_file_in -D $yosys_abc_clk_period"
} else {
  yosys "abc -liberty $lr_synth_cell_library_path"
}

if { $lr_synth_ibex_secure_ibex } {
  # Remove keep_hierarchy constraints before the final flattening step.
  # We're done optimizing.
  yosys "setattr -mod -set keep_hierarchy 0 *prim_and2*"
  yosys "setattr -mod -set keep_hierarchy 0 *prim_buf*"
  yosys "setattr -mod -set keep_hierarchy 0 *prim_clock_mux2*"
  yosys "setattr -mod -set keep_hierarchy 0 *prim_flop*"
}

# Final flattening.
if { $lr_synth_flatten } {
  yosys "flatten"
}

yosys "clean"
yosys "write_verilog $lr_synth_netlist_out"

if { $lr_synth_timing_run } {
  # Produce netlist that OpenSTA can use
  # The SRAM black boxes (prim_ram_1p, ICache=1) carry their parameters into the netlist, among
  # them an empty string written as ".MemInitFile()", which OpenSTA's Verilog reader rejects
  # (syntax error, 2026-10-17 opentitan). It links them as black boxes and needs none of them.
  foreach p {Width Depth DataBitsPerMask MemInitFile} {
    yosys "setparam -unset $p t:prim_ram_1p"
  }
  yosys "setundef -zero"
  yosys "splitnets"
  yosys "clean"
  yosys "write_verilog -noattr -noexpr -nohex -nodec $lr_synth_sta_netlist_out"
}

yosys "check"
yosys "log ======== Yosys Stat Report ========"
yosys "tee -o $lr_synth_out_dir/reports/area.rpt stat -liberty $lr_synth_cell_library_path"
yosys "log ====== End Yosys Stat Report ======"

