#!/usr/bin/env bash
# CHERIoT memory subsystem bench: every run of cms_regress.list (build first unless -k).
#
# Usage: ./cms_regress.sh [-c] [-k] [-b <seed base>] [-f <name regex>]
#   -c  coverage: build instrumented, collect every run, merge into xlm_out/coverage_merged
#   -k  keep the existing build
#   -b  first seed (default 1)
#   -f  only the list entries whose name matches the regex
# Goes on after a failing run; the verdict is make testplan-cheriot-mem-subsys's
# (cheriot_mem_subsys_results.py), which also requires the _corrupt_ runs to fail. Exit status: 0
# iff every ordinary run passed and every _corrupt_ run failed.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUPER_DIR="$(realpath "${SCRIPT_DIR}/../../..")"
if ! command -v xrun >/dev/null 2>&1; then
  exec nix develop "${SUPER_DIR}#eda_shell" --command "${BASH_SOURCE[0]}" "$@"
fi

COV=0; KEEP=0; BASE=1; FILTER="."
while getopts "ckb:f:" opt; do
  case $opt in
    c) COV=1 ;;
    k) KEEP=1 ;;
    b) BASE="$OPTARG" ;;
    f) FILTER="$OPTARG" ;;
    *) exit 2 ;;
  esac
done
cov_flag=$([[ ${COV} -eq 1 ]] && echo "-c" || true)

if [[ ${KEEP} -eq 0 ]]; then
  "${SCRIPT_DIR}/cms_xlm_build.sh" ${cov_flag} || { echo "[cms_regress] build failed" >&2; exit 1; }
fi
[[ ${COV} -eq 1 ]] && rm -rf "${SCRIPT_DIR}/xlm_out/cov_work"

pass=0; fail=0; bad=()
# Counted from the file up front, not in the loop: a run that eats the loop's stdin would hide
# the entries it swallowed from an in-loop count as well.
expected=0
while read -r name test seeds plusargs; do
  [[ -z "${name}" || "${name}" == \#* ]] && continue
  [[ "${name}" =~ ${FILTER} ]] && expected=$((expected + seeds))
done < "${SCRIPT_DIR}/cms_regress.list"
while read -r name test seeds plusargs; do
  [[ -z "${name}" || "${name}" == \#* ]] && continue
  [[ "${name}" =~ ${FILTER} ]] || continue
  for ((s = BASE; s < BASE + seeds; s++)); do
    # </dev/null: xmsim reads stdin as Tcl, so without it the run swallows the rest of
    # cms_regress.list (the loop's stdin) and every later entry is silently skipped.
    # shellcheck disable=SC2086
    "${SCRIPT_DIR}/cms_xlm_run.sh" -t "${test}" -s "${s}" -n "${name}" ${cov_flag} -- ${plusargs} </dev/null
    rc=$?
    if [[ "${name}" == *_corrupt_* ]]; then
      if [[ ${rc} -ne 0 ]]; then pass=$((pass + 1)); else fail=$((fail + 1)); bad+=("${name}.${s} (passed; must fail)"); fi
    else
      if [[ ${rc} -eq 0 ]]; then pass=$((pass + 1)); else fail=$((fail + 1)); bad+=("${name}.${s}"); fi
    fi
  done
done < "${SCRIPT_DIR}/cms_regress.list"

if [[ ${COV} -eq 1 ]]; then
  IMC_TCL=$(mktemp /tmp/cms_imc_XXXXXX.tcl)
  # Then the per-covergroup report the testplan report reads (xlm_out/cg_detail.txt).
  printf 'merge %s/xlm_out/cov_work/cms/* -out %s/xlm_out/coverage_merged -overwrite -initial_model union_all\nload -run %s/xlm_out/coverage_merged\ncatch {report -detail -type -all -metrics covergroup -source off -out %s/xlm_out/cg_detail.txt -overwrite}\nexit\n' \
    "${SCRIPT_DIR}" "${SCRIPT_DIR}" "${SCRIPT_DIR}" "${SCRIPT_DIR}" > "${IMC_TCL}"
  imc -64bit -licqueue -exec "${IMC_TCL}" -logfile "${SCRIPT_DIR}/xlm_out/coverage_merge.log" \
    || echo "[cms_regress] WARNING: coverage merge failed; see xlm_out/coverage_merge.log" >&2
  rm -f "${IMC_TCL}"
fi

echo "[cms_regress] ${pass} as expected, ${fail} not"
if [[ $((pass + fail)) -ne ${expected} ]]; then
  echo "[cms_regress] ERROR: $((pass + fail)) runs, ${expected} listed: entries were skipped" >&2
  fail=$((fail + 1))
fi
for b in "${bad[@]+"${bad[@]}"}"; do echo "  FAILED: ${b}"; done
echo "[cms_regress] Report: make testplan-cheriot-mem-subsys (from the repository root)"
[[ ${fail} -eq 0 ]]
