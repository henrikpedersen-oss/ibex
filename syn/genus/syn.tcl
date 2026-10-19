# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Genus synthesis of ibex_top, run by genus/run_genus.sh, which sets (environment):
#   GENUS_OUT         output directory (reports/, netlist/, lec/)
#   GENUS_LIB         the liberty file (lib/syn_lib.sh's, for the library and corner run_genus.sh chose)
#   GENUS_TIME_UNIT_PS   its time unit in ps: SDC times are in it (default 1000, ns; ASAP7 1)
#   GENUS_DRIVING_CELL   cell driving the inputs (default BUF_X2, NanGate45's)
#   GENUS_OUTPUT_LOAD    load on the outputs in its capacitance unit (default 10.0, NanGate45's fF)
#   GENUS_ICG_CELL       the clock gate genus/run_genus.sh instantiated in prim_clock_gating, if not
#                        NanGate45's: its dont_use (IHP's liberty sets it) is cleared
#   GENUS_CLK_PERIOD  clock period in ps
#   GENUS_FILES       SystemVerilog/Verilog sources in read order, packages first
#   GENUS_INCDIRS     include directories
#   GENUS_PARAMS      Tcl file: lr_synth_ibex_params {{Name value} ...}, lr_synth_ibex_secure_ibex
#   GENUS_CONF        the IO constraint file of the Yosys flow (ibex_top_cheriot_lr_synth_conf.tcl)
#
# The same configuration and IO constraints as the Yosys flow, from the SystemVerilog directly
# (no sv2v). Hierarchy is kept (auto_ungroup none) so the area splits by block as in area_compare.

proc env_or {name default} {
  if {[info exists ::env($name)] && $::env($name) ne ""} { return $::env($name) }
  return $default
}

set out    $env(GENUS_OUT)
# The SDC commands below take the library's units (ns and fF for NanGate45, ps and fF for ASAP7).
set period [expr {$env(GENUS_CLK_PERIOD) / double([env_or GENUS_TIME_UNIT_PS 1000])}]
file mkdir $out/reports $out/netlist $out/lec

set_db information_level 7
set_db hdl_error_on_blackbox false
set_db auto_ungroup none

#-------------------------------------------------------------------------
# Library and design
#-------------------------------------------------------------------------

read_libs $env(GENUS_LIB)
set icg [env_or GENUS_ICG_CELL ""]
if {$icg ne ""} {
  set icg_cells [get_db lib_cells */$icg]
  if {[llength $icg_cells] == 0} {
    puts "GENUS: ERROR: no clock gate $icg in $env(GENUS_LIB)"
    exit 1
  }
  set_db $icg_cells .dont_use false
}

set_db init_hdl_search_path $env(GENUS_INCDIRS)
read_hdl -language sv -define {SYNTHESIS} $env(GENUS_FILES)

source $env(GENUS_PARAMS)
elaborate ibex_top -parameters $lr_synth_ibex_params
check_design -unresolved > $out/reports/check_design_unresolved.rpt

# Module boundaries that no optimisation crosses: the module stays (ungroup_ok false) and nothing is
# propagated or shared through its ports (boundary_opto false). This is what the Yosys flow's
# keep_hierarchy does. Not 'preserve': Genus allows that only on a module that is already mapped
# (TUI-209 on every prim_buf right after elaborate, 2026-10-17).
proc keep_boundary {mods} {
  if {[llength $mods] > 0} {
    set_db $mods .ungroup_ok false
    set_db $mods .boundary_opto false
  }
}

# SecureIbex: the redundancy the security countermeasures rely on (the duplicated buffers, AND
# gates, flops and clock muxes of the hardened paths) must survive optimisation.
if {$lr_synth_ibex_secure_ibex} {
  foreach pattern {*prim_and2* *prim_buf* *prim_flop* *prim_clock_mux2*} {
    keep_boundary [get_db modules $pattern]
  }
}

# The iCache's RAM arrays (prim_ram_1p, rtl/prim_ram_1p_blackbox.sv: an empty body) are SRAM macros:
# kept as instances, and no constant from their undriven outputs propagated into the logic around
# them, so that logic is synthesised and counted as with real macros.
set ram_mods {}
foreach m [get_db modules *prim_ram_1p*] {
  set n [get_db $m .name]
  # The ECC and scrambling wrappers around the array are logic, synthesised as usual.
  if {[string match *prim_ram_1p_adv* $n] || [string match *prim_ram_1p_scr* $n]} continue
  lappend ram_mods $m
  puts "GENUS: SRAM black box $n"
}
keep_boundary $ram_mods

#-------------------------------------------------------------------------
# Constraints: as the Yosys flow's write_sdc_out (flow_utils.tcl), from the same conf file
#-------------------------------------------------------------------------

source $env(GENUS_CONF)
create_clock -name $lr_synth_clk_input -period $period [get_ports $lr_synth_clk_input]
foreach o $lr_synth_outputs {
  set_output_delay -clock $lr_synth_clk_input [expr {(1.0 - [lindex $o 1] / 100.0) * $period}] [get_ports [lindex $o 0]]
}
foreach i $lr_synth_inputs {
  set_input_delay -clock $lr_synth_clk_input [expr {[lindex $i 1] / 100.0 * $period}] [get_ports [lindex $i 0]]
}
set_driving_cell -lib_cell [env_or GENUS_DRIVING_CELL BUF_X2] [all_inputs]
set_load [env_or GENUS_OUTPUT_LOAD 10.0] [all_outputs]
# The reset is asynchronous; its timing is not a single-cycle path from the inputs.
set_false_path -from [get_ports $lr_synth_rst_input]

# Path groups as the OpenSTA reports split them (reg2reg, in2reg, reg2out, in2out). Each is optimised
# on its own: with the one default group, Genus worked on its worst path only, an input-to-output
# path the IO budgets leave almost no time for (2026-10-17: data_rvalid_i -> instr_addr_o, -2312 ps),
# and reported no register-to-register slack to compare with the Yosys flow.
set design [get_db designs]
foreach {grp from to} [list reg2reg [all_registers] [all_registers] \
                            in2reg  [all_inputs]    [all_registers] \
                            reg2out [all_registers] [all_outputs]   \
                            in2out  [all_inputs]    [all_outputs]] {
  define_cost_group -name $grp -design $design
  path_group -from $from -to $to -group $grp -name $grp
}

#-------------------------------------------------------------------------
# Synthesis
#-------------------------------------------------------------------------

set_db syn_generic_effort medium
set_db syn_map_effort     high
set_db syn_opt_effort     high

syn_generic
syn_map
# Conformal: RTL against the mapped design (Genus's intermediate, fv_map).
write_do_lec -revised_design fv_map -logfile $out/lec/rtl2map.lec.log > $out/lec/rtl2map.lec.do
syn_opt

#-------------------------------------------------------------------------
# Results
#-------------------------------------------------------------------------

write_hdl > $out/netlist/ibex_top.v
write_sdc > $out/netlist/ibex_top.sdc
# Conformal: RTL against the final netlist.
write_do_lec -revised_design $out/netlist/ibex_top.v -logfile $out/lec/rtl2final.lec.log > $out/lec/rtl2final.lec.do

report_qor                > $out/reports/qor.rpt
report_area               > $out/reports/area.rpt
report_area -depth 4      > $out/reports/area_hier.rpt
report_gates              > $out/reports/gates.rpt
report_timing -max_paths 20 > $out/reports/timing.rpt
foreach grp {reg2reg in2reg reg2out in2out} {
  report_timing -group $grp -max_paths 10 > $out/reports/timing_$grp.rpt
}
report_timing -lint       > $out/reports/timing_lint.rpt
check_design -all         > $out/reports/check_design.rpt
report_messages           > $out/reports/messages.rpt

puts "GENUS-DONE: reports in $out/reports, netlist in $out/netlist, Conformal dofiles in $out/lec"
exit
