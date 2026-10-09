#!/usr/bin/env bash
# CHERIoT memory subsystem bench: Xcelium RUN of one test.
#
# Usage: ./cms_xlm_run.sh -t <test> [-s <seed>] [-n <name>] [-c] [-g] [-o <outdir>] [-r <resdir>]
#                        [-- <plusargs>]
#   -t <test>    test (cms_tests.svh run_test), e.g. cms_tbre_sweep
#   -s <seed>    seed (default 1): xrun -svseed, and +seed for the log
#   -n <name>    result name (default the test); cms_regress.list gives fault-injection runs theirs
#   -c           collect coverage (build with -c) into <outdir>/cov_work/<name>.<seed>
#   -g           SimVision
#   -o <outdir>  output directory of the build (default xlm_out)
#   -r <resdir>  results directory under <outdir> (default results; cms_mutation.sh keeps each
#                mutation's runs in their own)
# Keeps <outdir>/<resdir>/<name>.<seed>.log and <name>.<seed>.result (key=value), which
# ibex/dv/testplans/cheriot_mem_subsys_results.py reads. Exit status: 0 iff the log's CMS_RESULT
# line says PASS.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUPER_DIR="$(realpath "${SCRIPT_DIR}/../../..")"
if ! command -v xrun >/dev/null 2>&1; then
  exec nix develop "${SUPER_DIR}#eda_shell" --command "${BASH_SOURCE[0]}" "$@"
fi

TEST=""; SEED=1; NAME=""; COVERAGE=0; GUI=0; OUT_DIR_NAME="xlm_out"; RES_DIR_NAME="results"
while getopts "t:s:n:cgo:r:" opt; do
  case $opt in
    t) TEST="$OPTARG" ;;
    s) SEED="$OPTARG" ;;
    n) NAME="$OPTARG" ;;
    c) COVERAGE=1 ;;
    g) GUI=1 ;;
    o) OUT_DIR_NAME="$OPTARG" ;;
    r) RES_DIR_NAME="$OPTARG" ;;
    *) echo "[cms_xlm_run] unknown option" >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))
[[ "${1:-}" == "--" ]] && shift
EXTRA_ARGS=("$@")
[[ -n "${TEST}" ]] || { echo "usage: $0 -t <test> [-s <seed>] ..." >&2; exit 2; }
NAME="${NAME:-${TEST}}"

OUT_DIR="${SCRIPT_DIR}/${OUT_DIR_NAME}"
RES_DIR="${OUT_DIR}/${RES_DIR_NAME}"
LOG="${RES_DIR}/${NAME}.${SEED}.log"
RESULT="${RES_DIR}/${NAME}.${SEED}.result"
if [[ ! -f "${OUT_DIR}/.elab_ok" ]]; then
  echo "[cms_xlm_run] ERROR: no build in ${OUT_DIR} (run cms_xlm_build.sh)" >&2
  exit 1
fi
if [[ ${COVERAGE} -eq 1 && ! -f "${OUT_DIR}/.coverage_enabled" ]]; then
  echo "[cms_xlm_run] ERROR: -c needs a build with coverage (cms_xlm_build.sh -c)" >&2
  exit 1
fi
mkdir -p "${RES_DIR}"
# A run that dies before simulating must not leave an earlier run's verdict under this name.
rm -f "${LOG}" "${RESULT}"

if [[ ${COVERAGE} -eq 1 ]]; then
  COV_ARGS="-covworkdir ${OUT_DIR}/cov_work -covscope cms -covtest ${NAME}.${SEED} +enable_ibex_fcov=1"
else
  # An instrumented snapshot writes a database even without -c; keep it out of the way.
  COV_SCRATCH=$(mktemp -d /tmp/cms_xlm_cov_XXXXXX)
  trap 'rm -rf "${COV_SCRATCH}"' EXIT
  COV_ARGS="-covworkdir ${COV_SCRATCH} -covtest t"
fi
GUI_ARG=""
[[ ${GUI} -eq 1 ]] && GUI_ARG="-gui -input ${SCRIPT_DIR}/waves.tcl"

# librun's RUNPATH points at an older Nix glibc than xmsim's (see cheriot_rtos_xlm_run.sh).
export LD_LIBRARY_PATH="/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

cd "${SUPER_DIR}"
rc=0
xrun \
  -64bit \
  -R \
  -xmlibdirname "${OUT_DIR}/xcelium.d" \
  -l "${LOG}" \
  -licqueue \
  -covoverwrite \
  -svseed "${SEED}" \
  ${GUI_ARG} \
  ${COV_ARGS} \
  ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"} \
  +test="${TEST}" \
  +seed="${SEED}" || rc=$?

status=$(grep -o 'CMS_RESULT .* status=[A-Z]*' "${LOG}" 2>/dev/null | sed 's/.*status=//' | tail -1)
status="${status:-NORESULT}"
{
  echo "name=${NAME}"
  echo "test=${TEST}"
  echo "seed=${SEED}"
  echo "status=${status}"
  echo "rc=${rc}"
  echo "plusargs=${EXTRA_ARGS[*]-}"
  echo "coverage=${COVERAGE}"
  echo "date=$(date +%F_%H%M%S)"
} > "${RESULT}"
echo "[cms_xlm_run] ${NAME} seed ${SEED}: ${status} (log ${LOG})"
[[ "${status}" == "PASS" ]]
