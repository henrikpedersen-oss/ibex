# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# SimVision probe for testrig_xlm_run.sh -w / -g: every signal below the TestRIG top.
ida_database -open -name xlm_testrig_out/waves.db
ida_probe -log -wave -wave_probe_args="core_ibex_testrig_tb_top -all -depth all -memories"
run
