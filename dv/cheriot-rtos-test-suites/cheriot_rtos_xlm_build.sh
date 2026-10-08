#!/usr/bin/env bash
# CHERIoT RTOS test SoC: Xcelium BUILD script
#
# Elaborates the testbench (tb/cheriot_rtos_tb.sv around rtl/cheriot_rtos_soc.sv) with the uartdpi
# DPI library. Run it from anywhere; paths are relative to this script.
#
# Usage: ./cheriot_rtos_xlm_build.sh [-c] [-o <outdir>] [-C <config>]
#   -c           instrument for coverage (cheriot_rtos_cover.ccf: ibex_top + cheriot_mem_subsys)
#   -o <outdir>  output directory, relative to this directory (default xlm_rtos_out)
#   -C <config>  core configuration from ibex/ibex_configs.yaml (default: $IBEX_CONFIG, else
#                opentitan -- the configuration the UVM testbench, compliance and TestRIG build, so
#                the coverage databases are of the same model and merge). The testbench's
#                mutation forces name the lockstep shadow core, so only SecureIbex = 1
#                configurations elaborate.
#
# Needs xrun on PATH (the superproject's run_all_tests.sh calls it inside run_in_eda_shell). The
# Sonata IP is vendored under vendor/sonata-system/ (vendor/fetch.sh). The CHERIoT memory subsystem
# comes from the ibex_cheriot_verification superproject this ibex checkout is a submodule of
# (opentitan-cheriot/); override its location with OT_CHERIOT_DIR.
#
# There is one build. The Sonata flow's compile-time knobs are gone: the CHERIoT memory subsystem
# is always in (its CHERIOT_MEM=1), and the REVOCATION=1 bitmap-RAM stub no longer exists.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUPER_DIR="$(realpath "${SCRIPT_DIR}/../../..")"

# The filelist refers to these as ${...}; xrun expands environment variables in -f files, so they
# must be exported, not just set.
export RTOS_TB_DIR="${SCRIPT_DIR}"
export IBEX_ROOT_DIR="${IBEX_ROOT_DIR:-$(realpath "${SCRIPT_DIR}/../..")}"
export OT_CHERIOT_DIR="${OT_CHERIOT_DIR:-${SUPER_DIR}/opentitan-cheriot}"

VENDOR_DIR="${SCRIPT_DIR}/vendor/sonata-system"
for d in "${VENDOR_DIR}/rtl/bus" "${OT_CHERIOT_DIR}/hw/ip/cheriot/rtl"; do
  if [[ ! -d "$d" ]]; then
    echo "[cheriot_rtos_xlm_build] ERROR: $d not found. This flow builds IP from the" >&2
    echo "  ibex_cheriot_verification superproject (set OT_CHERIOT_DIR) and the vendored Sonata IP" >&2
    echo "  (vendor/fetch.sh)." >&2
    exit 1
  fi
done

# A caller still passing the Sonata flow's build knobs would otherwise get a build that silently
# differs from the one it asked for.
if [[ "${REVOCATION:-0}" != "0" ]] || [[ "${CHERIOT_MEM:-1}" != "1" ]]; then
  echo "[cheriot_rtos_xlm_build] ERROR: REVOCATION=${REVOCATION:-} CHERIOT_MEM=${CHERIOT_MEM:-}:" >&2
  echo "  this flow has one build, with the CHERIoT memory subsystem; the other modes are gone." >&2
  exit 2
fi

OUT_DIR_NAME="xlm_rtos_out"
COVERAGE=0
IBEX_CFG="${IBEX_CONFIG:-opentitan}"
while getopts "co:C:" opt; do
  case $opt in
    C) IBEX_CFG="$OPTARG" ;;
    c) COVERAGE=1 ;;
    o) OUT_DIR_NAME="$OPTARG" ;;
    *) echo "[cheriot_rtos_xlm_build] unknown option: -$opt" >&2; exit 2 ;;
  esac
done
OUT_DIR="${SCRIPT_DIR}/${OUT_DIR_NAME}"

# Core parameters (see rtl/cheriot_rtos_soc.sv): IBEX_CFG_* defines for the enum-typed ones,
# -defparam on the SoC instance for the rest.
config_opts=$(python3 "${IBEX_ROOT_DIR}/util/ibex_config.py" \
                --config_filename "${IBEX_ROOT_DIR}/ibex_configs.yaml" "${IBEX_CFG}" xlm_opts \
                --ins_hier_path cheriot_rtos_tb.u_soc --string_define_prefix IBEX_CFG_)

coverage_arg=""
if [[ ${COVERAGE} -eq 1 ]]; then
  # ibex's dv/tools/xcelium ccf files. (The Sonata flow's copy was locally modified to request
  # covergroup scoring, which Xcelium 24.03 rejects: *E,CGNMWC, *E,ICFUC.) The functional
  # covergroups are sampled regardless (+enable_ibex_fcov=1 at run time).
  export dv_root="${IBEX_ROOT_DIR}/vendor/lowrisc_ip/dv"
  if [[ ! -f "${dv_root}/tools/xcelium/common.ccf" ]]; then
    echo "[cheriot_rtos_xlm_build] ERROR: common.ccf not found at ${dv_root}/tools/xcelium/" >&2
    exit 1
  fi
  coverage_arg="-coverage all -nowarn COVDEF -covfile ${SCRIPT_DIR}/cheriot_rtos_cover.ccf -covdut cheriot_rtos_soc"
  echo "[cheriot_rtos_xlm_build] Coverage enabled (ibex_top, cheriot_mem_subsys)"
fi

mkdir -p "${OUT_DIR}"
# Always start from a clean slate: a stale incremental snapshot is a stale build.
rm -rf "${OUT_DIR}/xcelium.d"
rm -f  "${OUT_DIR}/.elab_ok" "${OUT_DIR}/.coverage_enabled" "${OUT_DIR}/.ibex_config"

echo "[cheriot_rtos_xlm_build] Elaborating the CHERIoT RTOS test SoC..."
echo "  ibex:             ${IBEX_ROOT_DIR}"
echo "  Sonata IP:        ${VENDOR_DIR} ($(head -1 "${SCRIPT_DIR}/vendor/VENDORED_FROM" | cut -d" " -f1-2))"
echo "  opentitan-cheriot:${OT_CHERIOT_DIR}"
echo "  Ibex configuration: ${IBEX_CFG}"
# uartdpi.c is compiled inline by xrun.
xrun \
  -64bit \
  -f "${SCRIPT_DIR}/cheriot_rtos_dv.f" \
  -l "${OUT_DIR}/build.log" \
  -xmlibdirname "${OUT_DIR}/xcelium.d" \
  -sv \
  +define+RVFI \
  +define+PRIM_DEFAULT_IMPL=prim_pkg::ImplGeneric \
  -licqueue \
  -timescale 1ns/10ps \
  -elaborate \
  -access rwc \
  ${config_opts} \
  ${coverage_arg} \
  -I"${VENDOR_DIR}/vendor/lowrisc_ip/dv/dpi/uartdpi" \
  "${VENDOR_DIR}/vendor/lowrisc_ip/dv/dpi/uartdpi/uartdpi.c" \
  -top cheriot_rtos_tb

touch "${OUT_DIR}/.elab_ok"
# Recorded for cheriot_rtos_xlm_run.sh, which refuses a snapshot built for another configuration.
echo "${IBEX_CFG}" > "${OUT_DIR}/.ibex_config"
# run_all_tests.sh treats this as "the cached build has coverage instrumented" and re-elaborates
# a COVERAGE=1 run when it is absent.
if [[ ${COVERAGE} -eq 1 ]]; then
  touch "${OUT_DIR}/.coverage_enabled"
fi
echo "[cheriot_rtos_xlm_build] Build complete: ${OUT_DIR}"
