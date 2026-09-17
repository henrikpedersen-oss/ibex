# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# JasperGold X-Propagation flow for ibex_top RTL.
# Run with: jg xprop.tcl -allow_unsupported_OS -acquire_proj -no_gui
# Requires: make fusesoc (run once to generate the fusesoc filelist)

clear -all

check_xprop -init

analyze -sv12 +define+SYNTHESIS \
  -f_relative_to_file_location build/fusesoc/lowrisc_ibex_ibex_formal_0.1/default-vcs/lowrisc_ibex_ibex_formal_0.1.scr

elaborate -top ibex_top -disable_auto_bbox

clock clk_i
reset ~rst_ni

check_xprop

report
