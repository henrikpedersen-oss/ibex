# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# JasperGold formal check for ibex_cs_registers (debug/CSR control).
# Run with: jg debug-ctrl/check.tcl -allow_unsupported_OS -acquire_proj [-no_gui]
# Requires: make build/fusesoc (run once to generate the fusesoc filelist)

clear -all

analyze -sv12 +define+SYNTHESIS \
  -f_relative_to_file_location ../build/fusesoc/lowrisc_ibex_ibex_formal_0.1/default-vcs/lowrisc_ibex_ibex_formal_0.1.scr

elaborate -top ibex_cs_registers -disable_auto_bbox

clock clk_i
reset ~rst_ni

# TODO: add assert/cover/assume properties here

report

exit
