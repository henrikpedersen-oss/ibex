# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# JasperGold BPS App — trace-driven behavioral property synthesis for ibex_top.
# Mines an Xcelium .fsdb waveform to auto-generate cover/assert properties.
# Requires a prior Xcelium simulation run with waveform dumping enabled.
#
# Run: jg autocover.tcl -allow_unsupported_OS -acquire_proj -no_gui
# Requires: make build/fusesoc, and a .fsdb waveform from an Xcelium run.

clear -all

analyze -sv12 +define+SYNTHESIS \
  -f_relative_to_file_location build/fusesoc/lowrisc_ibex_ibex_formal_0.1/default-vcs/lowrisc_ibex_ibex_formal_0.1.scr

elaborate -top ibex_top -disable_auto_bbox

clock clk_i
reset ~rst_ni

# Waveform from the most recent Xcelium TestRIG run (Cadence IDA/SHM format).
# Override with env var BPS_WAVE_DB if the waveform is in a different location.
set WAVE_DB [expr {[info exists ::env(BPS_WAVE_DB)] ? $::env(BPS_WAVE_DB) : "../uvm/core_ibex/xlm_testrig_out/waves.db"}]

check_bps -load_simulation_trace $WAVE_DB
check_bps -generate -output autocover_bps_properties.sv

analyze -sv12 autocover_bps_properties.sv
elaborate -top ibex_top -disable_auto_bbox

set_prove_time_limit 3600s
set_prove_per_property_time_limit 60s

prove -covers -all

report -cover -file autocover_results.rpt
