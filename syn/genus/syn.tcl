# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Genus synthesis of ibex_top, run by genus/run_genus.sh, which sets (environment):
#   GENUS_OUT         output directory (reports/, netlist/, lec/)
#   GENUS_LIB         the liberty file (NanGate45, the corner run_genus.sh chose)
#   GENUS_CLK_PERIOD  clock period in ps
#   GENUS_FILES       SystemVerilog/Verilog sources in read order, packages first
#   GENUS_INCDIRS     include directories
#   GENUS_PARAMS      Tcl file: lr_synth_ibex_params {{Name value} ...}, lr_synth_ibex_secure_ibex
#   GENUS_CONF        the IO constraint file of the Yosys flow (ibex_top_cheriot_lr_synth_conf.tcl)
#
# The same configuration and IO constraints as the Yosys flow, from the SystemVerilog directly
# (no sv2v). Hierarchy is kept (auto_ungroup none) so the area splits by block as in area_compare.

set out    $env(GENUS_OUT)
set period [expr {$env(GENUS_CLK_PERIOD) / 1000.0}]
file mkdir $out/reports $out/netlist $out/lec

set_db information_level 7
set_db hdl_error_on_blackbox false
set_db auto_ungroup none

#-------------------------------------------------------------------------
# Library and design
#-------------------------------------------------------------------------

read_libs $env(GENUS_LIB)

set_db init_hdl_search_path $env(GENUS_INCDIRS)
read_hdl -language sv -define {SYNTHESIS} $env(GENUS_FILES)

source $env(GENUS_PARAMS)
elaborate ibex_top -parameters $lr_synth_ibex_params
check_design -unresolved > $out/reports/check_design_unresolved.rpt

# SecureIbex: the redundancy the security countermeasures rely on (the duplicated buffers, AND
# gates, flops and clock muxes of the hardened paths) must survive optimisation, as the Yosys flow's
# keep_hierarchy on these modules ensures.
if {$lr_synth_ibex_secure_ibex} {
  foreach pattern {*prim_and2* *prim_buf* *prim_flop* *prim_clock_mux2*} {
    set mods [get_db modules $pattern]
    if {[llength $mods] > 0} { set_db $mods .preserve true }
  }
}

# The iCache's RAM arrays (prim_ram_1p, rtl/prim_ram_1p_blackbox.sv: an empty body) are SRAM macros:
# kept as instances, and no constant from their undriven outputs propagated into the logic around
# them, so that logic is synthesised and counted as with real macros.
foreach m [get_db modules *prim_ram_1p*] {
  set n [get_db $m .name]
  # The ECC and scrambling wrappers around the array are logic, synthesised as usual.
  if {[string match *prim_ram_1p_adv* $n] || [string match *prim_ram_1p_scr* $n]} continue
  set_db $m .preserve true
  set_db $m .boundary_opto false
  puts "GENUS: SRAM black box $n"
}

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
set_driving_cell -lib_cell BUF_X2 [all_inputs]
set_load 10.0 [all_outputs]
# The reset is asynchronous; its timing is not a single-cycle path from the inputs.
set_false_path -from [get_ports $lr_synth_rst_input]

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
report_timing -lint       > $out/reports/timing_lint.rpt
check_design -all         > $out/reports/check_design.rpt
report_messages           > $out/reports/messages.rpt

puts "GENUS-DONE: reports in $out/reports, netlist in $out/netlist, Conformal dofiles in $out/lec"
exit
