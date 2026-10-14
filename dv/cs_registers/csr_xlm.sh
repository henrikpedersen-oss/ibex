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
# Output in xlm_out/: build.log, run.log (the run's stdout), and result ("PASS|FAIL seed=<n> ...
# <date>"), which the UVM testplan report reads. Exits 0 only on a pass (see the grading at the end).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IBEX_ROOT="$(cd "${HERE}/../.." && pwd)"
export IBEX_ROOT  # csr_cover.ccf includes ${IBEX_ROOT}/vendor/.../common.ccf
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

elab_cov=()
run_cov=()
if [[ ${COVERAGE} -eq 1 ]]; then
  # One model per run: -covoverwrite replaces the test's data but leaves the models of earlier
  # builds beside it, and the coverage merge takes this directory as it finds it.
  rm -rf "${OUT}/cov_work"
  elab_cov=(-coverage all -covdut ibex_cs_registers -covfile "${HERE}/csr_cover.ccf")
  run_cov=(-covworkdir "${OUT}/cov_work" -covscope csr -covtest "csr_${SEED}" -covoverwrite)
fi

# Build and run are two xrun calls, as in the RTOS flow (cheriot_rtos_xlm_build.sh / _run.sh), for
# the LD_LIBRARY_PATH below: with it set, the Cadence gcc compiling the C++ fails (*E,CCERR, no
# compiler message); without it, the simulation cannot load librun.
# Parameters: the core file's defaults for the sim target (PMP on, 4 regions, 8 counters of 40 bits).
# -clean: a fresh xcelium.d every build (a few seconds).
rm -f "${OUT}/run.log"
if ! xrun -64bit -sv -licqueue -timescale 1ns/1ps -clean -elaborate \
       -F "${FILES}" \
       -top tb_cs_registers \
       -defparam tb_cs_registers.PMPEnable=1 -defparam tb_cs_registers.PMPNumRegions=4 \
       -defparam tb_cs_registers.PMPGranularity=0 -defparam tb_cs_registers.MHPMCounterNum=8 \
       -defparam tb_cs_registers.MHPMCounterWidth=40 \
       -I"${HERE}/env" -I"${HERE}/reg_driver" -I"${HERE}/rst_driver" -I"${HERE}/model" \
       "${CC_SRCS[@]}" \
       "${elab_cov[@]+"${elab_cov[@]}"}" \
       -xmlibdirname "${OUT}/xcelium.d" -l "${OUT}/build.log"; then
  echo "FAIL seed=${SEED} transactions=0 build failed $(date '+%F %T')" > "${OUT}/result"
  echo "csr_xlm.sh: FAIL (build); log ${OUT}/build.log" >&2
  exit 1
fi

# librun's RUNPATH starts with a Nix glibc-2.31 while xmsim runs on the FHS sandbox's newer glibc in
# /lib, so librt from the RUNPATH cannot bind to the loaded libpthread (*F,FLDRUN, "GLIBC_PRIVATE
# not found"). LD_LIBRARY_PATH is searched first; as in cheriot_rtos_xlm_run.sh.
# run.log is the whole of the run's stdout: the bench prints its verdict and transaction count from
# C++ (std::cout), which xrun's -l log (xrun_run.log) does not capture.
LD_LIBRARY_PATH="/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" \
  xrun -64bit -licqueue -R \
    -xmlibdirname "${OUT}/xcelium.d" -l "${OUT}/xrun_run.log" \
    "${run_cov[@]+"${run_cov[@]}"}" \
    +ntb_random_seed="${SEED}" 2>&1 | tee "${OUT}/run.log" || true

# PASS needs all three: the bench's own verdict, no Xcelium error or SVA failure (the model compares
# CSR read data only; 2804 IbexCSREnValid failures once came with a run that got far), and the
# driver having driven transactions (a bench that checks nothing is not a pass).
LOG="${OUT}/run.log"
[[ -f "${LOG}" ]] || : > "${LOG}"  # xrun -R did not start: graded as empty
why=""
grep -q '// TEST PASSED //' "${LOG}" || why="no TEST PASSED"
if grep -qE '^\s*([a-z_]+: )?\*[EF],|ASSERT FAILED|Assertion .* has failed' "${LOG}"; then
  why="${why:+${why}, }Xcelium error or SVA failure"
fi
driven=$(sed -n 's/.*drove: \([0-9]*\) register transactions.*/\1/p' "${LOG}" | tail -1)
[[ "${driven:-0}" -gt 0 ]] || why="${why:+${why}, }no register transactions driven"
if [[ -z "${why}" ]]; then
  echo "PASS seed=${SEED} transactions=${driven} $(date '+%F %T')" > "${OUT}/result"
  echo "csr_xlm.sh: PASS (seed ${SEED}, ${driven} transactions); log ${LOG}"
else
  echo "FAIL seed=${SEED} transactions=${driven:-0} ${why} $(date '+%F %T')" > "${OUT}/result"
  echo "csr_xlm.sh: FAIL (seed ${SEED}: ${why}); log ${LOG}" >&2
  exit 1
fi
