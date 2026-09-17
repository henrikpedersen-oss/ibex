# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# JasperGold SuperLint flow for ibex_top RTL.
# Run with: jg superlint.tcl -allow_unsupported_OS -acquire_proj -no_gui
# Requires: make fusesoc (run once to generate the fusesoc filelist)

clear -all

# Init must come before analyze/elaborate.
check_superlint -init

# Load the standard superlint rule set (LINT domain; exclude DFT).
config_rtlds -rule -load [get_install_dir]/etc/res/rtlds/rules/superlint.def
config_rtlds -rule -disable -domain {DFT}

analyze -sv12 +define+SYNTHESIS \
  -f_relative_to_file_location build/fusesoc/lowrisc_ibex_ibex_formal_0.1/default-vcs/lowrisc_ibex_ibex_formal_0.1.scr

elaborate -top ibex_top -disable_auto_bbox

clock clk_i
reset ~rst_ni

# Extract the structural lint checks from the elaborated design.
check_superlint -extract

# Prove all extracted SuperLint tasks.
check_superlint -prove -task {<SL_*}

report
