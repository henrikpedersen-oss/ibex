#!/usr/bin/env bash

# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Conformal LEC of a genus/run_genus.sh run: the RTL against Genus's final netlist, with the dofile
# Genus wrote (lec/rtl2final.lec.do). Run from ibex/syn with lec on PATH (the parent's eda_shell).
#
#   genus/run_lec.sh [run_dir]     default: the newest genus_out/*/
#   LEC_STAGE=map                  RTL against the mapped design (rtl2map) instead of the netlist
#
# Exit 0 only if Conformal reports no non-equivalent points.

set -e
set -o pipefail
cd "$(dirname "$0")/.."

run=${1:-$(ls -1dt genus_out/*/ 2>/dev/null | head -1)}
run=${run%/}
[ -d "$run" ] || { echo "No Genus run directory (run make genus-synth first): ${run:-none}" >&2; exit 1; }
command -v lec >/dev/null || { echo "lec is not on PATH: run inside the eda_shell" >&2; exit 1; }
stage=${LEC_STAGE:-final}
do_file=$run/lec/rtl2${stage}.lec.do
[ -f "$do_file" ] || { echo "No dofile $do_file" >&2; exit 1; }

# Genus's dofile ends with its own report; exit afterwards in case it does not.
wrap=$run/lec/run_${stage}.do
printf 'dofile %s\nexit -force\n' "$(realpath "$do_file")" > "$wrap"
log=$run/lec/lec_${stage}.log
echo "Conformal: $do_file"
(cd "$run/lec" && lec -xl -nogui -dofile "$(realpath "$wrap")" -logfile "$log" </dev/null) || true

# The compare summary: the last "Non-equivalent" count Conformal printed.
noneq=$(grep -i "non-equivalent" "$log" | grep -oE "[0-9]+" | tail -1)
grep -iE "^ *(equivalent|non-equivalent|aborted|not-compared)" "$log" | tail -8 || true
if [ -z "$noneq" ]; then
    echo "LEC: no compare result in $log" >&2
    exit 1
fi
if [ "$noneq" -ne 0 ]; then
    echo "LEC: $noneq non-equivalent points ($log)" >&2
    exit 1
fi
echo "LEC: equivalent ($log)"
