#!/usr/bin/env bash

# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# This script drives the experimental Ibex synthesis flow. More details can be
# found in README.md

set -e
set -o pipefail

error () {
    echo >&2 "$@"
    exit 1
}

teelog () {
    tee "$LR_SYNTH_OUT_DIR/log/$1.log"
}

if [ ! -f syn_setup.sh ]; then
    error "No syn_setup.sh file: see README.md for instructions"
fi

#-------------------------------------------------------------------------
# setup flow variables
#-------------------------------------------------------------------------
source syn_setup.sh

#-------------------------------------------------------------------------
# use sv2v to convert all SystemVerilog files to Verilog
#-------------------------------------------------------------------------

mkdir -p "$LR_SYNTH_OUT_DIR/generated"
mkdir -p "$LR_SYNTH_OUT_DIR/log"
mkdir -p "$LR_SYNTH_OUT_DIR/reports/timing"

# What this run was, in the same form as genus/run_genus.sh's (scripts/compare_flows.py matches the
# two flows' runs on it). The period is the conf file's default when LR_SYNTH_CLK_PERIOD is unset.
{
    echo "flow=yosys"
    echo "config=${LR_SYNTH_IBEX_CONFIG:-}"
    echo "overrides=${LR_SYNTH_IBEX_CONFIG_OVERRIDES:-}"
    echo "corner=${LR_SYNTH_CORNER:-}"
    echo "library=$LR_SYNTH_CELL_LIBRARY_PATH"
    echo "clk_period_ps=${LR_SYNTH_CLK_PERIOD:-4000}"
    echo "flatten=$LR_SYNTH_FLATTEN"
} > "$LR_SYNTH_OUT_DIR/run_info.txt"

./sv2v_convert.sh "$LR_SYNTH_OUT_DIR/generated"

# A named configuration (LR_SYNTH_IBEX_CONFIG, ibex_configs.yaml) sets every Ibex parameter;
# LR_SYNTH_IBEX_CONFIG_OVERRIDES="Name=value ..." changes individual ones.
if [ -n "${LR_SYNTH_IBEX_CONFIG:-}" ]; then
    overrides=()
    for o in ${LR_SYNTH_IBEX_CONFIG_OVERRIDES:-}; do overrides+=(--override "$o"); done
    scripts/ibex_config_chparam.py "$LR_SYNTH_IBEX_CONFIG" "${overrides[@]}" \
        > "$LR_SYNTH_OUT_DIR/generated/ibex_config_params.tcl"
fi

# remove tracer (not needed for synthesis)
rm -f "$LR_SYNTH_OUT_DIR"/generated/ibex_tracer.v

# remove the FPGA register file. The flip-flop one stays: configurations such as opentitan select
# it, and with read_verilog -defer an unused module is never elaborated.
rm -f "$LR_SYNTH_OUT_DIR"/generated/ibex_register_file_fpga.v

yosys -c ./tcl/yosys_run_synth.tcl |& teelog syn || {
    error "Failed to synthesize RTL with Yosys"
}

sta ./tcl/sta_run_reports.tcl |& teelog sta || {
    error "Failed to run static timing analysis"
}

./translate_timing_rpts.sh

python/get_kge.py "$LR_SYNTH_CELL_LIBRARY_PATH" "$LR_SYNTH_OUT_DIR"/reports/area.rpt

scripts/area_chart.py "$LR_SYNTH_OUT_DIR"/reports/area.rpt || echo "WARNING: area chart not written" >&2
