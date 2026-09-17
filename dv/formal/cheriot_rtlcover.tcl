# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# JasperGold COV App — RTL structural cover point analysis for ibex_top.
# Uses the Coverage (COV) App to formally measure branch/statement/toggle
# reachability across the CHERIoT-Ibex RTL without needing a BPS licence.
#
# Requires: make build/fusesoc (run once to generate the fusesoc filelist)
# Run:
#   make cheriot-rtlcover       (batch, logs to cheriot_rtlcover_run.log)
#   make cheriot-rtlcover-gui   (interactive GUI)

clear -all

# Init must come before analyze/elaborate so JG instruments the RTL.
check_cov -init -model {branch statement expression toggle} \
    -toggle_ports_only -exclude_bind_hierarchies

analyze -sv12 +define+SYNTHESIS \
  -f_relative_to_file_location build/fusesoc/lowrisc_ibex_ibex_formal_0.1/default-vcs/lowrisc_ibex_ibex_formal_0.1.scr

elaborate -top ibex_top -disable_auto_bbox

clock clk_i
reset ~rst_ni

# Disable ProofGrid bridge (EPF117 on this machine — bridge daemon cannot start).
set_proofgrid_bridge off

set_prove_time_limit 3600s
set_prove_per_property_time_limit 60s

# Formally measure coverage — the prover explores reachable states and
# determines which RTL branches/statements/toggles are structurally reachable.
check_cov -measure -time_limit 3600s

check_cov -report -report_file cheriot_rtlcover_results.rpt -force
