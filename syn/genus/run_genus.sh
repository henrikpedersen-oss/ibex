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
#   GENUS_LIBNAME=<library>              cell library, lib/<name>.cfg (default nangate45)
#   GENUS_CORNER=<corner>                its corner: typical, slow (the default) or fast
#   GENUS_LIB=<liberty>                  a liberty file to read instead of the library's own
#   GENUS_CLK_PERIOD=<ps>                default 6667 (150 MHz, Earl Grey 2's main clock)
#   GENUS_OVERRIDES="Name=value ..."     parameter overrides, as SYN_OVERRIDES
#
# Output: genus_out/<config>[_<library>]_<corner>_<period>ps_<time>/ (no library in the name for
# NanGate45) with reports/ (qor, area, area_hier, timing), netlist/ and lec/ (Conformal dofiles Genus
# wrote; genus/run_lec.sh runs them).

set -e
set -o pipefail
cd "$(dirname "$0")/.."

cfg=${1:-cheriot-min}
command -v genus >/dev/null || { echo "genus is not on PATH: run inside the eda_shell" >&2; exit 1; }
corner=${GENUS_CORNER:-slow}
period=${GENUS_CLK_PERIOD:-6667}

# The library (lib/syn_lib.sh): its liberty, prepared in lib/generated/ if it has to be (ASAP7's
# files merged, dont_use cells marked), and its driving cell, load, time unit and clock gate.
source lib/syn_lib.sh
syn_lib_select "${GENUS_LIBNAME:-nangate45}" "$corner" || exit 1
if [ -n "${GENUS_LIB:-}" ]; then
    liberty=$GENUS_LIB
else
    syn_lib_prepare_liberty
    liberty=$SYN_LIB_LIBERTY
fi
[ -f "$liberty" ] || { echo "No such liberty file: $liberty" >&2; exit 1; }

out=$(pwd)/genus_out/${cfg}${SYN_LIB_SUFFIX}_${corner}_${period}ps_$(date +%Y%m%d_%H%M%S)
mkdir -p "$out"

# The clock gate: NanGate45's genus/prim_clock_gating.v, else one for the library's cell.
clock_gating=$(syn_lib_cfg "$SYN_LIB_NAME" genus_clock_gating)
icg_cell=
if [ -z "$clock_gating" ]; then
    clock_gating=$out/prim_clock_gating.v
    syn_lib_genus_clock_gating "$clock_gating"
    icg_cell=${SYN_LIB_ICG%% *}
fi

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
add "$clock_gating"
incdirs=()
for d in "${LR_INCDIRS[@]}" ../rtl; do incdirs+=("$(realpath "$d")"); done

overrides=()
for o in ${GENUS_OVERRIDES:-}; do overrides+=(--override "$o"); done
python3 scripts/ibex_config_chparam.py "$cfg" "${overrides[@]}" > "$out/params.tcl"

{
    echo "flow=genus"
    echo "config=$cfg"
    echo "overrides=${GENUS_OVERRIDES:-}"
    syn_lib_run_info
    echo "corner=$corner"
    echo "library=$liberty"
    echo "clk_period_ps=$period"
} > "$out/run_info.txt"

echo "Genus: $cfg, $SYN_LIB_NAME $corner corner, ${period} ps; output $out"
GENUS_OUT=$out GENUS_CLK_PERIOD=$period GENUS_FILES="${files[*]}" GENUS_INCDIRS="${incdirs[*]}" \
GENUS_PARAMS=$out/params.tcl GENUS_CONF=$(realpath ibex_top_cheriot_lr_synth_conf.tcl) \
GENUS_LIB=$liberty GENUS_TIME_UNIT_PS=$SYN_LIB_TIME_UNIT_PS GENUS_DRIVING_CELL=$SYN_LIB_DRIVING_CELL \
GENUS_OUTPUT_LOAD=$SYN_LIB_OUTPUT_LOAD GENUS_ICG_CELL=$icg_cell \
    genus -batch -no_gui -files genus/syn.tcl -log "$out/genus" </dev/null

grep -q "GENUS-DONE" "$out/genus.log" || { echo "Genus did not finish: $out/genus.log" >&2; exit 1; }
echo "=== $out/reports/qor.rpt"
cat "$out/reports/qor.rpt"
echo "Run: $out"
