#!/usr/bin/env bash
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Upstream CI's Verilator co-simulation tests (.github/actions/ibex-rtl-ci-steps, "Run Verilator
# co-sim tests"), runnable locally: builds the four programs, builds simple_system with Spike
# co-simulation for one ibex configuration, and runs each program on it.
#
#   coremark          examples/sw/benchmarks/coremark (SUPPRESS_PCOUNT_DUMP=1: Spike's counters
#                     differ, so the dump would mismatch)
#   pmp_smoke_test    only with PMPEnable=1
#   dit_test          only with SecureIbex=1
#   dummy_instr_test  only with SecureIbex=1
#
# Usage: run_cosim_tests.sh [-c <ibex config>] [-o <outdir>]
#   -c  ibex_configs.yaml configuration (default opentitan)
#   -o  output directory (default vlt_out beside this script)
#
# Needs fusesoc, verilator, riscv32-unknown-elf-gcc and the ibex_cosim Spike (pkg-config): ibex's
# own nix shell (nix develop ./ibex#shell; make simple-system-cosim-vlt in ibex_cheriot_verification).
#
# A test passes, as in ci/run-cosim-test.sh, when the simulator exits 0 and its log has no FAILURE
# and (except coremark and pmp_smoke_test, which CI runs with --skip-pass-check) a PASS; and, here,
# when the co-simulation matched at least one instruction. Each test runs in <outdir>/<test>/
# (ibex_simple_system.log, simple_system_cosim.log, trace); <outdir>/results.txt holds one
# "PASS|FAIL|SKIP <test> <reason>" line per test. Exits 0 only if none failed.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IBEX_ROOT="$(cd "${HERE}/../../.." && pwd)"
CONFIG=opentitan
OUT="${HERE}/vlt_out"
while getopts "c:o:" opt; do
  case $opt in
    c) CONFIG="$OPTARG" ;;
    o) OUT="$OPTARG" ;;
    *) exit 2 ;;
  esac
done
for t in fusesoc verilator riscv32-unknown-elf-gcc pkg-config; do
  command -v "$t" >/dev/null || { echo "run_cosim_tests.sh: $t not on PATH (nix develop ./ibex#shell)" >&2; exit 1; }
done
mkdir -p "${OUT}"
OUT="$(cd "${OUT}" && pwd)"
cd "${IBEX_ROOT}" || exit 1

OPTS=$(./util/ibex_config.py "${CONFIG}" fusesoc_opts) || exit 1
field() { ./util/ibex_config.py "${CONFIG}" query_fields "$1" | grep -q "$1=1"; }
echo "Configuration ${CONFIG}: ${OPTS}" | tee "${OUT}/config.txt"

# name | elf | skip pass check | runs in this configuration
TESTS=("coremark|examples/sw/benchmarks/coremark/coremark.elf|1|1")
if field PMPEnable; then pmp=1; else pmp=0; fi
if field SecureIbex; then sec=1; else sec=0; fi
TESTS+=("pmp_smoke_test|examples/sw/simple_system/pmp_smoke_test/pmp_smoke_test.elf|1|${pmp}"
        "dit_test|examples/sw/simple_system/dit_test/dit_test.elf|0|${sec}"
        "dummy_instr_test|examples/sw/simple_system/dummy_instr_test/dummy_instr_test.elf|0|${sec}")

echo "== Building the programs"
# CoreMark is rebuilt from clean: one built earlier without SUPPRESS_PCOUNT_DUMP would not be.
make -C examples/sw/benchmarks/coremark clean > "${OUT}/sw_build.log" 2>&1
for d in "benchmarks/coremark SUPPRESS_PCOUNT_DUMP=1" simple_system/pmp_smoke_test \
         simple_system/dit_test simple_system/dummy_instr_test; do
  # shellcheck disable=SC2086  # directory plus make variables
  make -C examples/sw/${d} >> "${OUT}/sw_build.log" 2>&1 \
    || { echo "run_cosim_tests.sh: building examples/sw/${d} failed, see ${OUT}/sw_build.log" >&2; exit 1; }
done

echo "== Building simple_system with co-simulation (Verilator)"
# shellcheck disable=SC2086  # OPTS is a list of fusesoc options
fusesoc --cores-root=. run --target=sim --setup --build --build-root "${OUT}/fusesoc" \
  lowrisc:ibex:ibex_simple_system_cosim ${OPTS} > "${OUT}/build.log" 2>&1 \
  || { echo "run_cosim_tests.sh: simulator build failed, see ${OUT}/build.log" >&2; exit 1; }
SIM=$(find "${OUT}/fusesoc" -type f -name Vibex_simple_system -perm -u+x | head -1)
[[ -n "${SIM}" ]] || { echo "run_cosim_tests.sh: no Vibex_simple_system in ${OUT}/fusesoc" >&2; exit 1; }

: > "${OUT}/results.txt"
fails=0
for entry in "${TESTS[@]}"; do
  IFS='|' read -r name elf skip_pass runs <<< "${entry}"
  if [[ ${runs} -ne 1 ]]; then
    echo "SKIP ${name} not in configuration ${CONFIG}" | tee -a "${OUT}/results.txt"
    continue
  fi
  dir="${OUT}/${name}"
  mkdir -p "${dir}"
  rm -f "${dir}/ibex_simple_system.log"
  echo "== ${name}"
  (cd "${dir}" && "${SIM}" --meminit=ram,"${IBEX_ROOT}/${elf}" > sim.log 2>&1)
  rc=$?
  log="${dir}/ibex_simple_system.log"
  why=""
  [[ ${rc} -eq 0 ]] || why="simulator exit ${rc}"
  grep -q 'FAILURE' "${dir}/sim.log" "${log}" 2>/dev/null && why="${why:+${why}, }FAILURE in the log"
  if [[ ${skip_pass} -ne 1 ]] && ! grep -q 'PASS' "${log}" 2>/dev/null; then
    why="${why:+${why}, }no PASS"
  fi
  matched=$(sed -n 's/.*Co-simulation matched \([0-9]*\) instructions.*/\1/p' "${dir}/sim.log" | tail -1)
  [[ "${matched:-0}" -gt 0 ]] || why="${why:+${why}, }co-simulation matched no instructions"
  if [[ -z "${why}" ]]; then
    echo "PASS ${name} ${matched} instructions matched" | tee -a "${OUT}/results.txt"
  else
    echo "FAIL ${name} ${why}" | tee -a "${OUT}/results.txt"
    fails=$((fails + 1))
  fi
done
echo "Results: ${OUT}/results.txt (${fails} failed)"
[[ ${fails} -eq 0 ]]
