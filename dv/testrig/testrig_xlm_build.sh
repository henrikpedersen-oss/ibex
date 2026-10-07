#!/usr/bin/env bash

# Prototype TestRIG Xcelium BUILD script
#
# Usage:
#   Call this script from the directory it is stored in.
#   Add '-c' for coverage collection.
#   Add '-C <config>' to pick the core configuration from ibex/ibex_configs.yaml (default:
#   $IBEX_CONFIG, else opentitan -- the configuration the UVM testbench, compliance and the RTOS SoC
#   build, so the coverage databases are of the same model and merge).


export PRJ_DIR=$(realpath ../../)
export LOWRISC_IP_DIR=$(realpath ${PRJ_DIR}/vendor/lowrisc_ip/)

# Needed for tcl files that are used with Cadence tools.
export dv_root=$(realpath ${LOWRISC_IP_DIR}/dv)
export DUT_TOP="ibex_top"

mkdir -p xlm_testrig_out

coverage_arg=""
IBEX_CFG="${IBEX_CONFIG:-opentitan}"

while getopts "cC:" opt; do
  case $opt in
      C) IBEX_CFG="$OPTARG" ;;
      c) coverage_arg="\
  -coverage all \
  -nowarn COVDEF \
  -covfile ${PRJ_DIR}/dv/coverage/ibex_cover.ccf \
  -covdut ibex_top" ;;
   esac
done

# Core parameters (see core_ibex_testrig_tb_top.sv): IBEX_CFG_* defines for the enum-typed ones,
# -defparam on the top for the rest.
config_opts=$(python3 "${PRJ_DIR}/util/ibex_config.py" --config_filename "${PRJ_DIR}/ibex_configs.yaml" \
                "${IBEX_CFG}" xlm_opts \
                --ins_hier_path core_ibex_testrig_tb_top --string_define_prefix IBEX_CFG_) \
  || { echo "ERROR: no Ibex configuration '${IBEX_CFG}' in ${PRJ_DIR}/ibex_configs.yaml" >&2; exit 1; }
echo "Ibex configuration: ${IBEX_CFG}"
# Recorded for the run scripts, which refuse a snapshot built for another configuration.
rm -f xlm_testrig_out/.ibex_config

xrun \
  -64bit \
  -f ibex_testrig_dv.f \
  -l xlm_testrig_out/build.log \
  -xmlibdirname xlm_testrig_out/xcelium.d \
  -sv \
  -uvmhome CDNS-1.2 \
  +define+XCELIUM \
  -licqueue \
  -timescale 1ns/10ps \
  -elaborate \
  -access rwc \
  -I"${PRJ_DIR}/vendor/SocketPacketUtils" \
  -I"${PRJ_DIR}/dv/cosim/cheriot_sail" \
  -L"${PRJ_DIR}/dv/cosim/cheriot_sail" -lcheriotsail_rvfi \
  -Wld,-Xlinker,-rpath,-Xlinker,"${PRJ_DIR}/dv/cosim/cheriot_sail" \
  -I"${PRJ_DIR}/dv/cosim/riscv_sail" \
  -L"${PRJ_DIR}/dv/cosim/riscv_sail" -lriscvsail_rvfi \
  -Wld,-Xlinker,-rpath,-Xlinker,"${PRJ_DIR}/dv/cosim/riscv_sail" \
  -lstdc++ \
  ${config_opts} \
  $coverage_arg \
  && echo "${IBEX_CFG}" > xlm_testrig_out/.ibex_config
