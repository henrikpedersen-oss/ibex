# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# IMC batch script: per-signal toggle coverage report for ibex_top's ports.
# Run with make cov-toggle-report [COVDB=] in ibex_cheriot_verification.
#
# Produces:
#   toggle_all.txt        -- all toggle bins with their coverage status
#
# env: FC_SIM_COVDB  coverage database to report on (the make target defaults it to coverage_combined)
#      FC_OUT        output directory

set sim $env(FC_SIM_COVDB)
set out $env(FC_OUT)

load -run $sim

# All bins, covered and not, of ibex_top's own ports (no "...": top level only). Waivers are
# not loaded here, so waived ports appear too.
report -detail -metrics toggle -inst ibex_top -all \
    -out $out/toggle_all.txt -overwrite

puts "TOGGLE_REPORT: wrote $out/toggle_all.txt"
exit
