#!/usr/bin/env bash

# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Genus synthesis of ibex_top from the SystemVerilog (no sv2v), with an ibex_configs.yaml
# configuration and the Yosys flow's IO constraints. Run from ibex/syn inside an environment with
# genus on PATH (the parent repository's eda_shell; make genus-synth sets everything up).
#
#   genus/run_genus.sh [config]          default cheriot-min
#
#   GENUS_LIB=<liberty>                  required: the NanGate45 corner (make passes the slow one)
#   GENUS_CORNER=<name>                  for the output directory's name only (default slow)
#   GENUS_CLK_PERIOD=<ps>                default 6667 (150 MHz, Earl Grey 2's main clock)
#   GENUS_OVERRIDES="Name=value ..."     parameter overrides, as SYN_OVERRIDES
#
# Output: genus_out/<config>_<corner>_<period>ps_<time>/ with reports/ (qor, area, area_hier,
# timing), netlist/ and lec/ (Conformal dofiles Genus wrote; genus/run_lec.sh runs them).

set -e
set -o pipefail
cd "$(dirname "$0")/.."

cfg=${1:-cheriot-min}
: "${GENUS_LIB:?set GENUS_LIB to the liberty file (make genus-synth does)}"
[ -f "$GENUS_LIB" ] || { echo "GENUS_LIB: no such file: $GENUS_LIB" >&2; exit 1; }
command -v genus >/dev/null || { echo "genus is not on PATH: run inside the eda_shell" >&2; exit 1; }
corner=${GENUS_CORNER:-slow}
period=${GENUS_CLK_PERIOD:-6667}

out=$(pwd)/genus_out/${cfg}_${corner}_${period}ps_$(date +%Y%m%d_%H%M%S)
mkdir -p "$out"

# The Yosys flow's file lists (sv2v_convert.sh), read here as SystemVerilog.
source ./sv2v_convert.sh
skip='ibex_tracer|ibex_top_tracing|ibex_register_file_fpga'
files=()
add () { local f; for f in "$@"; do f=$(realpath "$f"); [[ " ${files[*]} " == *" $f "* ]] || files+=("$f"); done; }
add "${LR_DEP_PKGS[@]}" "${LR_ICACHE_PKGS[@]}" "${LR_CORE_PKGS[@]}"
add "${LR_DEP_SOURCES[@]}" "${LR_ICACHE_SOURCES[@]}" "$LR_RAM_BLACKBOX"
for f in "${LR_CORE_SOURCES[@]}"; do
    [[ $(basename -s .sv "$f") =~ ^($skip)$ ]] || add "$f"
done
add genus/prim_clock_gating.v
incdirs=()
for d in "${LR_INCDIRS[@]}" ../rtl; do incdirs+=("$(realpath "$d")"); done

overrides=()
for o in ${GENUS_OVERRIDES:-}; do overrides+=(--override "$o"); done
python3 python/ibex_config_chparam.py "$cfg" "${overrides[@]}" > "$out/params.tcl"

{
    echo "config=$cfg"
    echo "overrides=${GENUS_OVERRIDES:-}"
    echo "corner=$corner"
    echo "library=$GENUS_LIB"
    echo "clk_period_ps=$period"
} > "$out/run_info.txt"

echo "Genus: $cfg, $corner corner, ${period} ps; output $out"
GENUS_OUT=$out GENUS_CLK_PERIOD=$period GENUS_FILES="${files[*]}" GENUS_INCDIRS="${incdirs[*]}" \
GENUS_PARAMS=$out/params.tcl GENUS_CONF=$(realpath ibex_top_cheriot_lr_synth_conf.tcl) \
    genus -batch -no_gui -files genus/syn.tcl -log "$out/genus" </dev/null

grep -q "GENUS-DONE" "$out/genus.log" || { echo "Genus did not finish: $out/genus.log" >&2; exit 1; }
echo "=== $out/reports/qor.rpt"
cat "$out/reports/qor.rpt"
echo "Run: $out"
