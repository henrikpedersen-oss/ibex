#!/usr/bin/env bash
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# The CS registers testbench (this directory; upstream builds it for Verilator and VCS) on Xcelium:
# FuseSoC writes the file list (setup only, VCS target, as the formal flows do), and xrun compiles
# the C++ register model, drivers and environment itself (the DPI side of tb_cs_registers.sv) and
# runs it. tb_cs_registers.sv makes its own clock and calls $finish after the driver's 10000
# transactions; its final block prints // TEST PASSED // or // TEST FAILED //.
#
# Usage: csr_xlm.sh [-c] [-s <seed>]
#   -c         collect code coverage of ibex_cs_registers (xlm_out/cov_work)
#   -s <seed>  +ntb_random_seed (default 1)
#
# Needs xrun and fusesoc on PATH: the ibex_cheriot_verification eda_shell (make csr-tb-xlm there).
# Output in xlm_out/: run.log, and result ("PASS|FAIL seed=<n> <date>"), which the UVM testplan
# report reads. Exits 0 only on // TEST PASSED //.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IBEX_ROOT="$(cd "${HERE}/../.." && pwd)"
OUT="${HERE}/xlm_out"
COVERAGE=0
SEED=1
while getopts "cs:" opt; do
  case $opt in
    c) COVERAGE=1 ;;
    s) SEED="$OPTARG" ;;
    *) exit 2 ;;
  esac
done
command -v xrun >/dev/null && command -v fusesoc >/dev/null || {
  echo "csr_xlm.sh: needs xrun and fusesoc (nix develop .#eda_shell of ibex_cheriot_verification)" >&2
  exit 1
}

mkdir -p "${OUT}"
rm -f "${OUT}/result"
fusesoc --cores-root "${IBEX_ROOT}" run --build-root "${OUT}/fusesoc" --target sim --tool vcs \
  --setup lowrisc:ibex:tb_cs_registers > "${OUT}/fusesoc.log" 2>&1 \
  || { echo "csr_xlm.sh: fusesoc setup failed, see ${OUT}/fusesoc.log" >&2; exit 1; }
SCR=$(find "${OUT}/fusesoc" -name 'lowrisc_ibex_tb_cs_registers_0.scr' | head -1)
[[ -n "${SCR}" ]] || { echo "csr_xlm.sh: no file list from fusesoc in ${OUT}/fusesoc" >&2; exit 1; }
# The VCS list's -pvalue+ parameter lines are VCS syntax (xrun gets -defparam below); its paths are
# relative to its own directory, so the filtered copy stays beside it and is read with -F.
FILES="$(dirname "${SCR}")/xcelium_files.f"
grep -v '^-pvalue+' "${SCR}" > "${FILES}"

# The C++ side, as the bench's Makefile builds it for Verilator and VCS (everything outside tb/).
mapfile -t CC_SRCS < <(find "${HERE}/env" "${HERE}/reg_driver" "${HERE}/rst_driver" "${HERE}/model" \
                         -name '*.cc' | sort)

cov_args=()
if [[ ${COVERAGE} -eq 1 ]]; then
  cov_args=(-coverage all -covdut ibex_cs_registers -covworkdir "${OUT}/cov_work" -covscope csr
            -covtest "csr_${SEED}" -covoverwrite)
fi

# Parameters: the core file's defaults for the sim target (PMP on, 4 regions, 8 counters of 40 bits).
xrun -64bit -sv -licqueue -timescale 1ns/1ps \
  -F "${FILES}" \
  -top tb_cs_registers \
  -defparam tb_cs_registers.PMPEnable=1 -defparam tb_cs_registers.PMPNumRegions=4 \
  -defparam tb_cs_registers.PMPGranularity=0 -defparam tb_cs_registers.MHPMCounterNum=8 \
  -defparam tb_cs_registers.MHPMCounterWidth=40 \
  -I"${HERE}/env" -I"${HERE}/reg_driver" -I"${HERE}/rst_driver" -I"${HERE}/model" \
  "${CC_SRCS[@]}" \
  -xmlibdirname "${OUT}/xcelium.d" -l "${OUT}/run.log" \
  "${cov_args[@]+"${cov_args[@]}"}" \
  +ntb_random_seed="${SEED}" || true

if grep -q '// TEST PASSED //' "${OUT}/run.log"; then
  echo "PASS seed=${SEED} $(date '+%F %T')" > "${OUT}/result"
  echo "csr_xlm.sh: PASS (seed ${SEED}); log ${OUT}/run.log"
else
  echo "FAIL seed=${SEED} $(date '+%F %T')" > "${OUT}/result"
  echo "csr_xlm.sh: FAIL (seed ${SEED}); log ${OUT}/run.log" >&2
  exit 1
fi
