#!/usr/bin/env bash

# TestRIG Verilator BUILD script: the same UVM testbench as testrig_xlm_build.sh, compiled
# with Verilator (needs `nix develop .#vlt_shell`, which provides Verilator 5.052 and UVM_HOME).
#
# Usage: call this script from the directory it is stored in. [-C <config>] picks the core
# configuration from ibex/ibex_configs.yaml (default: $IBEX_CONFIG, else opentitan), as
# testrig_xlm_build.sh does; the parameters reach the top through -G and +define+.
#
# Differences from the Xcelium build, and why:
#   - UVM is Accellera 1800.2-2017 (Antmicro's Verilator-patched copy), not Cadence UVM 1.2.
#     UVM_ENABLE_DEPRECATED_API is deliberately NOT set: with it, the library's own classes miss
#     the Verilator type_id_create path and fail to compile, and the TestRIG bench builds without
#     it. It may be needed later if code using the UVM 1.2-only API is added to this build (the
#     riscv-dv tests would be the likely case).
#   - UVM DPI is on except uvm_hdl (UVM_HDL_NO_DPI + tb/testrig_vlt_uvm_dpi.cc): the command-line
#     processor needs DPI, or +uvm_set_type_override is silently ignored and no flavour is picked.
#     UVM_NO_DPI must not be used. The TestRIG path makes no uvm_hdl_* calls.
#   - The fcov/ covergroup interfaces are left out: Verilator does not collect functional
#     coverage, and nothing else in the TestRIG top depends on them.

set -euo pipefail

export PRJ_DIR=$(realpath ../../)
export LOWRISC_IP_DIR=$(realpath ${PRJ_DIR}/vendor/lowrisc_ip/)
export DUT_TOP="ibex_top"
: "${UVM_HOME:?UVM_HOME is not set; run inside nix develop .#vlt_shell}"

IBEX_CFG="${IBEX_CONFIG:-opentitan}"
while getopts "C:" opt; do
  case $opt in
    C) IBEX_CFG="$OPTARG" ;;
    *) exit 1 ;;
  esac
done
# Core parameters (see core_ibex_testrig_tb_top.sv). vlt_opts gives -G<param> for the top's
# parameters and +define+IBEX_CFG_<enum> for the enum-typed ones.
config_opts=$(python3 "${PRJ_DIR}/util/ibex_config.py" --config_filename "${PRJ_DIR}/ibex_configs.yaml" \
                "${IBEX_CFG}" vlt_opts --string_define_prefix IBEX_CFG_)
echo "Ibex configuration: ${IBEX_CFG}"

OUT=vlt_testrig_out
# Always build from a clean object dir: Verilator's incremental make reuses its dependency files,
# which hold absolute paths, so an obj/ from another checkout or machine breaks the build (and a
# partly stale one is a stale build).
rm -rf ${OUT}/obj ${OUT}/.ibex_config
mkdir -p ${OUT}

# Same file list as the Xcelium build, minus the covergroup files, plus the $unit import
# prelude straight after common_ifs_pkg.sv (see tb/testrig_vlt_prelude.sv).
grep -v -E '/fcov/[^/]+\.sv$' ibex_testrig_dv.f \
  | sed '/common_ifs\/common_ifs_pkg\.sv$/a ${PRJ_DIR}/dv/testrig/tb/testrig_vlt_prelude.sv' \
  > ${OUT}/ibex_testrig_dv_vlt.f
grep -q testrig_vlt_prelude.sv ${OUT}/ibex_testrig_dv_vlt.f \
  || { echo "ERROR: could not place testrig_vlt_prelude.sv after common_ifs_pkg.sv" >&2; exit 1; }

verilator \
  --binary \
  --timing \
  -j 0 \
  --build-jobs ${VLT_BUILD_JOBS:-8} \
  --top-module core_ibex_testrig_tb_top \
  --Mdir ${OUT}/obj \
  -o Vtestrig_tb \
  --timescale 1ns/10ps \
  -Wno-fatal -Wno-lint -Wno-style -Wno-SYMRSVDWORD -Wno-ZERODLY \
  --vpi \
  ${config_opts} \
  +define+UVM \
  +define+UVM_HDL_NO_DPI \
  +define+UVM_REPORT_DISABLE_FILE_LINE \
  ${PRJ_DIR}/lint/verilator_waiver.vlt \
  testrig_vlt_waiver.vlt \
  +incdir+${UVM_HOME} \
  +incdir+${LOWRISC_IP_DIR}/dv/sv/dv_utils \
  ${UVM_HOME}/uvm_pkg.sv \
  ${LOWRISC_IP_DIR}/dv/sv/dv_utils/dv_macros.svh \
  ${PRJ_DIR}/dv/testrig/tb/testrig_vlt_uvm_dpi.cc \
  -f ${OUT}/ibex_testrig_dv_vlt.f \
  -CFLAGS "-I${PRJ_DIR}/vendor/SocketPacketUtils -I${PRJ_DIR}/dv/cosim/cheriot_sail -I${PRJ_DIR}/dv/cosim/riscv_sail -I${UVM_HOME}/dpi" \
  -LDFLAGS "-L${PRJ_DIR}/dv/cosim/cheriot_sail -lcheriotsail_rvfi -Wl,-rpath,${PRJ_DIR}/dv/cosim/cheriot_sail" \
  -LDFLAGS "-L${PRJ_DIR}/dv/cosim/riscv_sail -lriscvsail_rvfi -Wl,-rpath,${PRJ_DIR}/dv/cosim/riscv_sail" \
  2>&1 | tee ${OUT}/build.log
# Recorded for testrig_vlt_run.sh, which refuses a binary built for another configuration.
echo "${IBEX_CFG}" > ${OUT}/.ibex_config
