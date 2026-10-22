#!/usr/bin/env bash
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Check that an upstream PR branch builds on its own: on a clean worktree of the branch, run what
# lowRISC/ibex CI runs on a PR, then build the UVM testbench and run the PR's own tests.
# Our tooling (dv/scripts is never upstreamed). See status/pr_plan.md, "Every PR builds".
#
#   dv/scripts/pr_check.sh <branch> [--base <ref>] [--configs "opentitan earlgrey"]
#                          [--tests "test1 test2"] [--seed N] [--skip-uvm] [--keep]
#
#   <branch>   the PR branch (e.g. upstream/spike-memory-map)
#   --base     what the PR targets: origin/master, or the branch of a PR it depends on that has not
#              merged yet (default origin/master)
#   --configs  IBEX_CONFIGs to build the UVM bench for (default: opentitan)
#   --tests    tests to run after the build (the PR's own tests); none by default
#   --skip-uvm only the upstream-CI checks (no commercial simulator)
#   --keep     keep the worktree afterwards (it is removed by default)
#
# Run inside a shell with fusesoc, verilator, verible, clang-format, git, and Xcelium for the UVM
# part (the parent repository's eda_shell). Exit status 0 only if every step passed.

set -u

branch=""
base="origin/master"
configs="opentitan"
tests=""
seed=1
skip_uvm=0
keep=0
while [ $# -gt 0 ]; do
  case "$1" in
    --base)     base="$2"; shift 2 ;;
    --configs)  configs="$2"; shift 2 ;;
    --tests)    tests="$2"; shift 2 ;;
    --seed)     seed="$2"; shift 2 ;;
    --skip-uvm) skip_uvm=1; shift ;;
    --keep)     keep=1; shift ;;
    -h|--help)  sed -n '5,22p' "$0"; exit 0 ;;
    *)          branch="$1"; shift ;;
  esac
done
[ -n "$branch" ] || { echo "usage: $0 <branch> [--base <ref>] [--configs ...] [--tests ...]"; exit 2; }

repo=$(git rev-parse --show-toplevel)
wt="${TMPDIR:-/tmp}/pr_check_$(echo "$branch" | tr '/' '_')"
results=()
fail=0

step() {   # step <name> <command...>
  local name="$1"; shift
  echo; echo "=== $name ==="
  if ( cd "$wt" && "$@" ); then results+=("PASS  $name"); else results+=("FAIL  $name"); fail=1; fi
}

# No fetch here: the remote refs are whatever was last fetched deliberately.
if [ -d "$wt" ]; then
  echo "worktree $wt exists; remove it with: git worktree remove --force $wt"; exit 2
fi
git -C "$repo" worktree add -q --detach "$wt" "$branch" || exit 2
echo "worktree: $wt ($(git -C "$wt" log -1 --format='%h %s'))"

# The PR must not carry anything that never goes upstream.
# Cell libraries are fetched (syn/lib/syn_lib.sh), never committed; only remove-outdated-formal
# (PR 34) may delete dv/formal/ or formal/.
step "nothing project-local in the diff" bash -c "
  bad=\$(git diff --name-only $base...HEAD | grep -E '^(syn/lib/.*\\.lib(\\.gz)?\$|dv/scripts/|nix/|flake\\.)' || true)
  del=''
  case '$branch' in
    *remove-outdated-formal) ;;
    *) del=\$(git diff --name-only --diff-filter=D $base...HEAD | grep -E '^(dv/formal/|formal/)' || true) ;;
  esac
  [ -z \"\$bad\$del\" ] || { echo \"\$bad\$del\"; exit 1; }"

# What lowRISC/ibex CI runs on a PR (.github/workflows/ci.yml).
step "commit messages (ci/lint-commits.sh)" ./ci/lint-commits.sh "$base"
step "C/C++ format (clang-format on the diff)" bash -c "
  out=\$(git clang-format --diff $base -- '*.cc' '*.h' '*.c' 2>&1)
  echo \"\$out\" | grep -qE '^(no modified files|clang-format did not modify)' || [ -z \"\$out\" ] || { echo \"\$out\"; exit 1; }"
step "Verible format (RTL)" fusesoc --cores-root . run --no-export --target=format \
  --tool=veribleformat lowrisc:ibex:ibex_top_tracing
step "CSR testbench (Verilator)" fusesoc --cores-root=. run --target=sim --tool=verilator \
  lowrisc:ibex:tb_cs_registers
step "Verilator lint (simple system)" fusesoc --cores-root . run --target=lint --tool=verilator \
  lowrisc:ibex:ibex_simple_system
step "Verible lint (simple system)" fusesoc --cores-root . run --target=lint --tool=veriblelint \
  lowrisc:ibex:ibex_simple_system
for cfg in $configs; do
  step "Verilator lint ibex_top_tracing ($cfg)" bash -c "
    fusesoc --cores-root . run --target=lint --tool=verilator lowrisc:ibex:ibex_top_tracing \
      \$(./util/ibex_config.py $cfg fusesoc_opts)"
done
step "simple system co-simulation build (Verilator)" fusesoc --cores-root=. run --target=sim \
  --setup --build lowrisc:ibex:ibex_simple_system_cosim

# The UVM bench builds for every configuration, then the PR's own tests run.
if [ "$skip_uvm" = 0 ]; then
  for cfg in $configs; do
    step "UVM build ($cfg)" make -C dv/uvm/core_ibex GOAL=rtl_tb_compile SIMULATOR=xlm \
      IBEX_CONFIG="$cfg" COV=0 SEED="$seed"
  done
  for t in $tests; do
    step "UVM test $t (seed $seed)" make -C dv/uvm/core_ibex SIMULATOR=xlm \
      IBEX_CONFIG="$(echo "$configs" | awk '{print $1}')" TEST="$t" ITERATIONS=1 SEED="$seed"
  done
fi

echo; echo "==== pr_check $branch (base $base) ===="
printf '%s\n' "${results[@]}"
if [ "$keep" = 0 ]; then
  git -C "$repo" worktree remove --force "$wt"
else
  echo "worktree kept: $wt"
fi
exit $fail
