#!/usr/bin/env bash
# CHERIoT memory subsystem bench: the mutation check. One build, then every run of
# ibex/dv/testplans/cms_mutation_check.py --list-runs with +cms_mutate=<mutation>, then the grade.
#
# Usage: ./cms_mutation.sh [-k] [-m <mutation>]
#   -k  keep the existing build in xlm_mutation_out
#   -m  this mutation only
# Everything goes to xlm_mutation_out/: the build, and results/<mutation>/<name>.<seed>.{log,result}.
# The regression's xlm_out/ (its build, results and coverage, which the testplan report reads) is
# never touched. No coverage: a mutant's coverage must never reach a merged database.
# Every run is expected to fail, so a failing run does not stop the loop. Exit status: the
# grader's (non-zero on any MISSED, NO LOG or INACTIVE, or a mutation no test caught).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUPER_DIR="$(realpath "${SCRIPT_DIR}/../../..")"
if ! command -v xrun >/dev/null 2>&1; then
  exec nix develop "${SUPER_DIR}#eda_shell" --command "${BASH_SOURCE[0]}" "$@"
fi

KEEP=0; ONLY=""
while getopts "km:" opt; do
  case $opt in
    k) KEEP=1 ;;
    m) ONLY="$OPTARG" ;;
    *) exit 2 ;;
  esac
done

OUT=xlm_mutation_out
PY="${SUPER_DIR}/ibex/dv/testplans/py.sh"
CHECK="${SUPER_DIR}/ibex/dv/testplans/cms_mutation_check.py"
only_arg=()
[[ -n "${ONLY}" ]] && only_arg=(--only "${ONLY}")

# Read the whole list first: xmsim reads stdin, and the grader must not be half-read either.
mapfile -t runs < <("${PY}" "${CHECK}" --list-runs "${only_arg[@]+"${only_arg[@]}"}")
[[ ${#runs[@]} -gt 0 ]] || { echo "[cms_mutation] no runs listed" >&2; exit 1; }

if [[ ${KEEP} -eq 0 ]]; then
  "${SCRIPT_DIR}/cms_xlm_build.sh" -o "${OUT}" || { echo "[cms_mutation] build failed" >&2; exit 1; }
fi
# No log of an earlier round may stand in for a run of this one.
if [[ -n "${ONLY}" ]]; then
  rm -rf "${SCRIPT_DIR:?}/${OUT}/results/${ONLY}"
else
  rm -rf "${SCRIPT_DIR:?}/${OUT}/results"
fi

for r in "${runs[@]}"; do
  IFS='|' read -r mut test name seed plusargs <<< "${r}"
  echo "=== cms_mutation: ${mut}: ${name} (${test}) seed ${seed}"
  # shellcheck disable=SC2086
  "${SCRIPT_DIR}/cms_xlm_run.sh" -o "${OUT}" -r "results/${mut}" -t "${test}" -s "${seed}" \
    -n "${name}" -- +cms_mutate="${mut}" ${plusargs} </dev/null \
    || echo "    (run failed -- expected for a mutation)"
done

"${PY}" "${CHECK}" --check --results "${SCRIPT_DIR}/${OUT}/results" "${only_arg[@]+"${only_arg[@]}"}"
