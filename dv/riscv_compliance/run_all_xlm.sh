#!/usr/bin/env bash
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Run the full RISC-V compliance suite against Ibex using Xcelium.
# Mirrors what the GitHub Actions CI does but uses xrun instead of Verilator.
#
# Prerequisites:
#   1. Run build_xlm.sh (with -c if you want coverage) first.
#   2. The riscv-compliance repo must be cloned at COMPLIANCE_DIR
#      (default: ../../build/riscv-compliance, matching the CI convention).
#   3. RISCV_PREFIX must point to a riscv32 bare-metal toolchain in PATH.
#
# Usage: ./run_all_xlm.sh [-c] [-d <compliance_dir>] [-p <riscv_prefix>] [-o <outdir>] [-g <extra_gcc_opts>]
#   -c  Collect coverage (requires build_xlm.sh -c)
#   -d  Path to riscv-compliance repo checkout
#   -p  RISC-V toolchain prefix (default: riscv32-unknown-elf-)
#   -o  Xcelium library output directory (default: xlm_compliance_out)
#   -g  Extra GCC options appended to RISCV_GCC_OPTS when compiling test programs
#       e.g. -g "-DCHERIOT" for CHERIoT-aware compilation

set -e
cd "$(dirname "$0")"

SCRIPT_DIR=$(pwd)
COMPLIANCE_DIR="$(realpath ../../../riscv-compliance 2>/dev/null || echo "")"
RISCV_PREFIX="${RISCV_PREFIX:-riscv32-unknown-elf-}"
COVERAGE=0
OUTDIR="xlm_compliance_out"
EXTRA_GCC_OPTS=""

while getopts "cd:p:o:g:" opt; do
  case $opt in
    c) COVERAGE=1 ;;
    d) COMPLIANCE_DIR="$OPTARG" ;;
    p) RISCV_PREFIX="$OPTARG" ;;
    o) OUTDIR="$OPTARG" ;;
    g) EXTRA_GCC_OPTS="$OPTARG" ;;
  esac
done

if [ -z "$COMPLIANCE_DIR" ] || [ ! -d "$COMPLIANCE_DIR" ]; then
  echo "Error: riscv-compliance directory not found at '${COMPLIANCE_DIR}'" >&2
  echo "Clone it first:" >&2
  echo "  cd ../../build && git clone https://github.com/riscv/riscv-compliance.git" >&2
  echo "  cd riscv-compliance && git checkout 844c6660ef3f0d9b96957991109dfd80cc4938e2" >&2
  echo "Or pass -d <path>." >&2
  exit 1
fi

export RISCV_PREFIX
export RISCV_TARGET=ibex
export RISCV_DEVICE=rv32imc
export TARGET_SIM="${SCRIPT_DIR}/run_xlm.sh"

if [ "$COVERAGE" -eq 1 ]; then
  # -covtest is NOT set here; run_xlm.sh derives a per-test unique name from the vmem filename.
  export COVERAGE_ARGS="-covmodeldir ${SCRIPT_DIR}/${OUTDIR}/coverage \
    -covworkdir ${SCRIPT_DIR}/${OUTDIR} \
    -covscope compliance \
    -covoverwrite"
fi

echo "Running RISC-V compliance suite (RISCV_TARGET=${RISCV_TARGET}, RISCV_DEVICE=${RISCV_DEVICE})"
echo "TARGET_SIM=${TARGET_SIM}"
echo ""

BASE_GCC_OPTS="-static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles"
GCC_OPTS_OVERRIDE="${BASE_GCC_OPTS}${EXTRA_GCC_OPTS:+ ${EXTRA_GCC_OPTS}}"

fail=0
for isa in rv32i rv32im rv32imc rv32Zicsr rv32Zifencei; do
  echo "=== ISA: ${isa} ==="
  if ! make -C "${COMPLIANCE_DIR}" RISCV_ISA="${isa}" \
       RISCV_GCC_OPTS="${GCC_OPTS_OVERRIDE}" simulate 2>&1; then
    echo "FAIL: compliance test failed for ${isa}"
    fail=1
  fi
done

if [ "$COVERAGE" -eq 1 ]; then
  echo ""
  echo "=== Merging coverage ==="
  # Each test writes one .ucd to <covworkdir>/<covscope>/<test_name>/.
  # imc -load only accepts one dir on the command line; use a runfile passed to
  # the TCL 'merge -runfile' command instead (the correct multi-DB merge path).
  RUNFILE=$(mktemp /tmp/compliance_cov_runs_XXXXXX.txt)
  IMC_TCL=$(mktemp /tmp/imc_merge_XXXXXX.tcl)
  trap 'rm -f "$RUNFILE" "$IMC_TCL"' EXIT
  for d in "${SCRIPT_DIR}/${OUTDIR}/compliance"/*/; do
    [ -d "$d" ] && echo "${d%/}" >> "$RUNFILE"
  done
  if [ ! -s "$RUNFILE" ]; then
    echo "WARNING: no per-test coverage databases found under ${OUTDIR}/compliance/" >&2
  else
    printf 'merge -runfile %s -out %s -overwrite -initial_model union_all\nexit\n' \
      "${RUNFILE}" "${SCRIPT_DIR}/${OUTDIR}/coverage_merged" > "${IMC_TCL}"
    imc -64bit -licqueue \
      -exec "${IMC_TCL}" \
      -logfile "${SCRIPT_DIR}/${OUTDIR}/coverage_merge.log"
    echo "Merged coverage: ${SCRIPT_DIR}/${OUTDIR}/coverage_merged"
  fi
fi

exit $fail
