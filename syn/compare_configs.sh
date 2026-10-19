#!/usr/bin/env bash

# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Synthesise two ibex_configs.yaml configurations with the module hierarchy kept and compare their
# area block by block (scripts/area_compare.py). Run from ibex/syn inside `nix develop .#syn_shell`.
#
#   ./compare_configs.sh [config_a [config_b]]     default: opentitan cheriot-min
#   SYN_A_OVERRIDES / SYN_B_OVERRIDES="Name=value ..."  parameter overrides per side
#
# Both use the CHERIoT IO constraints (ibex_top_cheriot_lr_synth_conf.tcl); the ports exist in
# every configuration.

set -e
set -o pipefail
cd "$(dirname "$0")"

cfg_a=${1:-opentitan}
cfg_b=${2:-cheriot-min}
ts=$(date +%d_%m_%Y_%H_%M_%S)
# LR_SYNTH_LIB (lib/<name>.cfg) is in the run names unless it is NanGate45, as in syn_setup.sh.
lib_suffix=
[ "${LR_SYNTH_LIB:-nangate45}" = nangate45 ] || lib_suffix=_$LR_SYNTH_LIB

synth () {
    local cfg=$1 overrides=$2 dir=syn_out/ibex_${1}${lib_suffix}_${ts}
    echo "=== compare_configs: synthesising $cfg${overrides:+ ($overrides)} into $dir" >&2
    if ! LR_SYNTH_OUT_DIR=$dir LR_SYNTH_IBEX_CONFIG=$cfg LR_SYNTH_IBEX_CONFIG_OVERRIDES=$overrides \
         LR_SYNTH_FLATTEN=0 LR_SYNTH_CONFIG_FILE=ibex_top_cheriot_lr_synth_conf.tcl \
         ./syn_yosys.sh >&2; then
        # The area report is written by Yosys, before timing analysis.
        [ -f "$dir/reports/area.rpt" ] || { echo "compare_configs: $cfg did not synthesise" >&2; exit 1; }
        echo "compare_configs: WARNING: $cfg failed after Yosys; comparing its area report" >&2
    fi
    echo "$dir/reports/area.rpt"
}

rpt_a=$(synth "$cfg_a" "${SYN_A_OVERRIDES:-}")
rpt_b=$(synth "$cfg_b" "${SYN_B_OVERRIDES:-}")
scripts/area_compare.py "$rpt_a" "$rpt_b" -o "syn_out/compare_${cfg_a}_vs_${cfg_b}${lib_suffix}_${ts}.html"
