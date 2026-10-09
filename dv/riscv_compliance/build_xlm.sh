#!/usr/bin/env bash
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Xcelium elaboration for the Ibex RISC-V compliance testbench.
#
# Usage: ./build_xlm.sh [-c] [-e] [-o OUTDIR] [-C CONFIG]
#   -c  Enable coverage instrumentation
#   -e  Assert CHERIOT_ENABLE define (enables CHERIoT capability mode)
#   -o  Output directory (default: xlm_compliance_out)
#   -C  Ibex configuration from ibex_configs.yaml (default: $IBEX_CONFIG, else opentitan -- the
#       configuration the UVM testbench builds, so compliance checks the same core and its coverage
#       database merges with the UVM one)

set -e
cd "$(dirname "$0")"

export PRJ_DIR=$(realpath ../../)
export LOWRISC_IP_DIR=$(realpath "${PRJ_DIR}/vendor/lowrisc_ip/")
export dv_root=$(realpath "${LOWRISC_IP_DIR}/dv")
export DUT_TOP="ibex_top"

OUTDIR="xlm_compliance_out"
IBEX_CFG="${IBEX_CONFIG:-opentitan}"
cheriot_define=""
coverage_arg=""
while getopts "ceo:C:" opt; do
  case $opt in
    c) coverage_arg="-coverage all \
  -nowarn COVDEF \
  -covfile ${PRJ_DIR}/dv/coverage/ibex_cover.ccf \
  -covdut ibex_top" ;;
    e) cheriot_define="+define+CHERIOT_ENABLE" ;;
    o) OUTDIR="$OPTARG" ;;
    C) IBEX_CFG="$OPTARG" ;;
  esac
done

# Core parameters for the chosen configuration: -define IBEX_CFG_<enum>=... for the enum-typed ones
# (read by rtl/ibex_riscv_compliance.sv) and -defparam for the rest, on the u_dut instance.
config_opts=$(python3 "${PRJ_DIR}/util/ibex_config.py" --config_filename "${PRJ_DIR}/ibex_configs.yaml" \
                "${IBEX_CFG}" xlm_opts \
                --ins_hier_path tb_riscv_compliance.u_dut --string_define_prefix IBEX_CFG_)
echo "Ibex configuration: ${IBEX_CFG}"

mkdir -p ${OUTDIR}
rm -rf ${OUTDIR}/xcelium.d

xrun \
  -64bit \
  -f ibex_compliance_xlm.f \
  "+incdir+${LOWRISC_IP_DIR}/dv/sv/dv_utils" \
  +define+RVFI \
  $cheriot_define \
  ${config_opts} \
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
# What this library was built for, so a reuse check can refuse a library built for the other mode
# or configuration (the CHERIOT_ENABLE define changes the elaborated design).
echo "cheriot_enable=$( [[ -n "$cheriot_define" ]] && echo 1 || echo 0 ) config=${IBEX_CFG}" > "${OUTDIR}/.build_mode"
echo "Build complete. Logs: ${OUTDIR}/build.log"
