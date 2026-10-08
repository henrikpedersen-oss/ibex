#!/usr/bin/env bash
# CHERIoT RTOS test SoC: Xcelium RUN script
#
# Converts the boot stub and the firmware ELF to one vmem per memory, then runs the elaborated
# snapshot. uartdpi writes UART0 to UART_LOG and ends the run when the firmware sends the CHERIoT
# RTOS exit string; the testbench's cycle timeout ends it otherwise.
#
# Usage: ./cheriot_rtos_xlm_run.sh [-c] [-g] [-o <outdir>] [-- <extra xrun args / plusargs>]
#   -c           collect coverage (build with -c) and merge it into <outdir>/coverage_merged
#   -g           open SimVision instead of running in batch
#   -o <outdir>  output directory, relative to this directory (default xlm_rtos_out)
#
# Environment:
#   SONATA_BOOT_STUB   sim_boot_stub ELF (owns the reset vector at 0x0010_0000). Default:
#                      firmware/sim_boot_stub/sim_boot_stub (make -C firmware/sim_boot_stub, in the
#                      superproject's nix develop .#cheriot_sw_shell)
#   SONATA_TEST_ELF    firmware ELF (required)
#   UART_LOG           UART0 log (default <outdir>/uart0.log)
#   SONATA_MAX_CYCLES  cycle timeout (+max_cycles); unset keeps the testbench's own
#   SONATA_MUTATE      break one hardware check (+sonata_mutate; see tb/cheriot_rtos_tb.sv)
# The variable names are the Sonata flow's, which run_all_tests.sh and the root Makefile set.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUPER_DIR="$(realpath "${SCRIPT_DIR}/../../..")"

OUT_DIR_NAME="xlm_rtos_out"
COVERAGE=0
GUI=0
while getopts "cgo:" opt; do
  case $opt in
    c) COVERAGE=1 ;;
    g) GUI=1 ;;
    o) OUT_DIR_NAME="$OPTARG" ;;
    *) echo "[cheriot_rtos_xlm_run] unknown option: -$opt" >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))
[[ "${1:-}" == "--" ]] && shift
EXTRA_ARGS=("$@")

OUT_DIR="${SCRIPT_DIR}/${OUT_DIR_NAME}"
UART_LOG="${UART_LOG:-${OUT_DIR}/uart0.log}"
SRAM_VMEM="${OUT_DIR}/sram.vmem"
CODE_VMEM="${OUT_DIR}/code.vmem"

BOOT_STUB="${SONATA_BOOT_STUB:-${SCRIPT_DIR}/firmware/sim_boot_stub/sim_boot_stub}"
TEST_ELF="${SONATA_TEST_ELF:-}"

if [[ ! -f "${OUT_DIR}/.elab_ok" ]]; then
  echo "[cheriot_rtos_xlm_run] ERROR: no build in ${OUT_DIR} (run cheriot_rtos_xlm_build.sh)" >&2
  exit 1
fi
# The build records its ibex_configs.yaml configuration. A build from before the core parameters
# came from ibex_configs.yaml has no record, and one for another configuration than $IBEX_CONFIG
# (default opentitan) is the wrong core: refuse both.
_want_cfg="${IBEX_CONFIG:-opentitan}"
_have_cfg="$(cat "${OUT_DIR}/.ibex_config" 2>/dev/null || true)"
if [[ "${_have_cfg}" != "${_want_cfg}" ]]; then
  echo "[cheriot_rtos_xlm_run] ERROR: ${OUT_DIR} was built for configuration '${_have_cfg:-unknown}'," \
       "not '${_want_cfg}': rebuild (cheriot_rtos_xlm_build.sh, or --rebuild / REBUILD=1)" >&2
  exit 1
fi
if [[ ! -f "${BOOT_STUB}" ]]; then
  echo "[cheriot_rtos_xlm_run] ERROR: boot stub not found: ${BOOT_STUB}" >&2
  echo "  (cd ${SUPER_DIR} && nix develop .#cheriot_sw_shell --command make -C ${SCRIPT_DIR}/firmware/sim_boot_stub sim_boot_stub)" >&2
  exit 1
fi
if [[ -z "${TEST_ELF}" ]] || [[ ! -f "${TEST_ELF}" ]]; then
  echo "[cheriot_rtos_xlm_run] ERROR: SONATA_TEST_ELF not set or not found: ${TEST_ELF}" >&2
  exit 1
fi

echo "[cheriot_rtos_xlm_run] Converting ELFs to vmem..."
echo "  boot stub:     ${BOOT_STUB}"
echo "  test ELF:      ${TEST_ELF}"

PYTHON3=$(command -v python3 2>/dev/null || \
          find /nix/store -maxdepth 4 -name "python3" -type f 2>/dev/null | head -1)

# SRAM: 0x0010_0000, 128 KiB -- boot stub (reset vector +0x80) and SRAM-resident firmware.
"${PYTHON3}" "${SCRIPT_DIR}/elf_to_vmem.py" \
  --base-addr 0x100000 --size 0x20000 --fill \
  "${BOOT_STUB}" "${TEST_ELF}" > "${SRAM_VMEM}"
if [[ ! -s "${SRAM_VMEM}" ]]; then
  echo "[cheriot_rtos_xlm_run] ERROR: SRAM vmem is empty -- ELF segments outside SRAM?" >&2
  exit 1
fi
# Code RAM: 0x4000_0000, 1 MiB -- where the RTOS firmware's code lives (Sonata's HyperRAM).
"${PYTHON3}" "${SCRIPT_DIR}/elf_to_vmem.py" \
  --base-addr 0x40000000 --size 0x100000 --fill \
  "${TEST_ELF}" > "${CODE_VMEM}"
echo "  SRAM vmem:     ${SRAM_VMEM} ($(wc -l < "${SRAM_VMEM}") lines)"
echo "  code vmem:     ${CODE_VMEM} ($(wc -l < "${CODE_VMEM}") lines)"

rm -f "${UART_LOG}"
echo "[cheriot_rtos_xlm_run] Running Xcelium simulation..."
echo "  uart log:      ${UART_LOG}"

# Without coverage args an instrumented snapshot still writes a database, so route it to a
# scratch dir when not collecting -- same approach as dv/riscv_compliance/run_xlm.sh.
if [[ ${COVERAGE} -eq 1 ]]; then
  # One coverage run per firmware: with a fixed -covtest every suite overwrote the previous one's
  # database, so the merge could only ever see the last suite run.
  _cov_test="$(basename "${TEST_ELF:-boot_stub}")"
  _cov_test="cheriot_rtos_${_cov_test%.*}"
  _cov_test="${_cov_test//[^A-Za-z0-9_]/_}"
  COV_ARGS="-covworkdir ${OUT_DIR}/cov_work -covtest ${_cov_test}"
  # The functional covergroups (fcov/, core_ibex_trvk_fcov_if) sample only with this set.
  COV_ARGS+=" +enable_ibex_fcov=1"
else
  COV_SCRATCH=$(mktemp -d /tmp/cheriot_rtos_xlm_cov_XXXXXX)
  trap 'rm -rf "${COV_SCRATCH}"' EXIT
  COV_ARGS="-covworkdir ${COV_SCRATCH} -covtest t"
fi

# librun's RUNPATH starts with a Nix glibc-2.31 (from the Cadence link environment), while xmsim
# runs on the xrun FHS sandbox's own, newer glibc in /lib; librt then came from the RUNPATH and
# could not bind to the already-loaded libpthread (*F,FLDRUN, "GLIBC_PRIVATE not found").
# LD_LIBRARY_PATH is searched before RUNPATH. (Found in the Sonata flow, 2026-09-22.)
export LD_LIBRARY_PATH="/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

MAX_CYCLES_ARG=""
if [[ -n "${SONATA_MAX_CYCLES:-}" ]]; then
  MAX_CYCLES_ARG="+max_cycles=${SONATA_MAX_CYCLES}"
  echo "  max cycles:    ${SONATA_MAX_CYCLES}"
fi
MUTATE_ARG=""
if [[ -n "${SONATA_MUTATE:-}" ]]; then
  MUTATE_ARG="+sonata_mutate=${SONATA_MUTATE}"
  echo "  MUTATION:      ${SONATA_MUTATE}"
fi
GUI_ARG=""
[[ ${GUI} -eq 1 ]] && GUI_ARG="-gui"

# EXTRA_ARGS come first: $value$plusargs takes the first match, so they override the defaults
# after them (e.g. +ibex_tracer_enable=1).
rc=0
xrun \
  -64bit \
  -xmlibdirname "${OUT_DIR}/xcelium.d" \
  -l "${OUT_DIR}/run.log" \
  -licqueue \
  -covoverwrite \
  -R \
  ${GUI_ARG} \
  ${COV_ARGS} \
  ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"} \
  ${MAX_CYCLES_ARG} \
  ${MUTATE_ARG} \
  +sram_vmem="${SRAM_VMEM}" \
  +code_vmem="${CODE_VMEM}" \
  +ibex_tracer_enable=0 \
  +UARTDPI_LOG_uart0="${UART_LOG}" || rc=$?

echo "[cheriot_rtos_xlm_run] Simulation complete -- exit ${rc}"

# Merge into the path run_all_tests.sh looks for (<outdir>/coverage_merged).
if [[ ${COVERAGE} -eq 1 ]]; then
  echo "[cheriot_rtos_xlm_run] Merging coverage into ${OUT_DIR}/coverage_merged"
  IMC_TCL=$(mktemp /tmp/cheriot_rtos_xlm_imc_XXXXXX.tcl)
  # Then the per-covergroup report the Sonata testplan report reads (<outdir>/cg_detail.txt).
  # cov_work/<scope>/<run>: merging cov_work/* passed the scope directory, not the runs (IMC
  # *W,MGURTS, nothing merged, no coverage_merged).
  printf 'merge %s/cov_work/*/* -out %s/coverage_merged -overwrite -initial_model union_all\nload -run %s/coverage_merged\ncatch {report -detail -type -all -metrics covergroup -source off -out %s/cg_detail.txt -overwrite}\nexit\n' \
    "${OUT_DIR}" "${OUT_DIR}" "${OUT_DIR}" "${OUT_DIR}" > "${IMC_TCL}"
  imc -64bit -licqueue -exec "${IMC_TCL}" -logfile "${OUT_DIR}/coverage_merge.log" \
    || echo "[cheriot_rtos_xlm_run] WARNING: coverage merge failed -- see ${OUT_DIR}/coverage_merge.log" >&2
  rm -f "${IMC_TCL}"
fi
exit ${rc}
