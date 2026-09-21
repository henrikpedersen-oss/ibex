#!/usr/bin/env bash
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Xcelium elaboration for the Ibex RISC-V compliance testbench.
#
# Usage: ./build_xlm.sh [-c] [-e] [-o OUTDIR]
#   -c  Enable coverage instrumentation
#   -e  Assert CHERIOT_ENABLE define (enables CHERIoT capability mode)
#   -o  Output directory (default: xlm_compliance_out)

set -e
cd "$(dirname "$0")"

export PRJ_DIR=$(realpath ../../)
export LOWRISC_IP_DIR=$(realpath "${PRJ_DIR}/vendor/lowrisc_ip/")
export dv_root=$(realpath "${LOWRISC_IP_DIR}/dv")
export DUT_TOP="ibex_top"

OUTDIR="xlm_compliance_out"
cheriot_define=""
coverage_arg=""
while getopts "ceo:" opt; do
  case $opt in
    c) coverage_arg="-coverage all \
  -nowarn COVDEF \
  -covfile ${LOWRISC_IP_DIR}/dv/tools/xcelium/cover.ccf \
  -covdut ibex_top" ;;
    e) cheriot_define="+define+CHERIOT_ENABLE" ;;
    o) OUTDIR="$OPTARG" ;;
  esac
done

mkdir -p ${OUTDIR}
rm -rf ${OUTDIR}/xcelium.d

xrun \
  -64bit \
  -f ibex_compliance_xlm.f \
  "+incdir+${LOWRISC_IP_DIR}/dv/sv/dv_utils" \
  +define+RVFI \
  $cheriot_define \
  -l ${OUTDIR}/build.log \
  -xmlibdirname ${OUTDIR}/xcelium.d \
  -sv \
  -timescale 1ns/10ps \
  -elaborate \
  -access rwc \
  -licqueue \
  $coverage_arg

if [[ -n "$coverage_arg" ]]; then
  touch "${OUTDIR}/.coverage_enabled"
else
  rm -f "${OUTDIR}/.coverage_enabled"
fi
echo "Build complete. Logs: ${OUTDIR}/build.log"
