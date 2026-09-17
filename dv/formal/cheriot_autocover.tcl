# CHERIoT-Ibex: JasperGold BPS App — trace-driven property synthesis.
#
# The Behavioral Property Synthesis (BPS) App mines an Xcelium waveform dump
# (.fsdb) to infer functional boundaries and auto-generate cover, assume, and
# assert properties. It requires a prior simulation run to produce the trace.
#
# Workflow:
#   1. Run Xcelium with coverage to produce a waveform:
#        make uvm-cheriot-xlm COVERAGE=1
#      This produces a .fsdb file under the Xcelium output directory.
#   2. Set FSDB_FILE below to the path of that waveform, then run:
#        make cheriot-autocover
#
# The SPS App (pure RTL, no simulation needed) is not available in this
# JG installation. Use check_bps instead.
#
# Run:
#   cd dv/formal
#   jg cheriot_autocover.tcl -allow_unsupported_OS -acquire_proj -no_gui

clear -all

analyze -sv12 +define+SYNTHESIS \
  -f_relative_to_file_location build/fusesoc/lowrisc_ibex_ibex_formal_0.1/default-vcs/lowrisc_ibex_ibex_formal_0.1.scr

elaborate -top ibex_top -disable_auto_bbox

clock clk_i
reset ~rst_ni

# BPS App: mine simulation trace to synthesize behavioral cover/assert properties.
# Waveform is from the most recent Xcelium TestRIG run (Cadence IDA/SHM format).
# Override with env var BPS_WAVE_DB if your waveform is elsewhere.
set WAVE_DB [expr {[info exists ::env(BPS_WAVE_DB)] ? $::env(BPS_WAVE_DB) : "../uvm/core_ibex/xlm_testrig_out/waves.db"}]

check_bps -load_simulation_trace $WAVE_DB
check_bps -generate -output cheriot_bps_properties.sv

# Read the generated properties back and prove them.
analyze -sv12 cheriot_bps_properties.sv
elaborate -top ibex_top -disable_auto_bbox

set_prove_time_limit 3600s
set_prove_per_property_time_limit 60s

prove -covers -all

report -cover -file cheriot_autocover_results.rpt
