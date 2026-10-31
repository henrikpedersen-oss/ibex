#!/usr/bin/env python3
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""Regrade an aggregate UVM result after its per-seed out/ directory was archived away.

The aggregate file says how many seeds failed but not why.  Consequently this tool requires a
saved-evidence YAML entry for every failed seed.  It loads the grading policy from the directed
testlists; the evidence file contains observations only and cannot declare an expected failure.
"""

import argparse
import json
import sys

import pathlib3x as pathlib
import yaml

from expected_failures import load_expected_failures, match_expected_failure


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--results', required=True, type=pathlib.Path)
    ap.add_argument('--evidence', required=True, type=pathlib.Path)
    ap.add_argument('--directed-testlist', required=True, type=pathlib.Path)
    args = ap.parse_args()

    results = json.loads(args.results.read_text())['test_results']
    observations = yaml.safe_load(args.evidence.read_text()) or []
    declared = load_expected_failures(args.directed_testlist)
    by_test = {}
    seen_runs = set()
    for observation in observations:
        for field in ('test', 'seed', 'message'):
            if field not in observation:
                raise RuntimeError(f'{args.evidence}: evidence entry has no {field}: {observation}')
        run = (observation['test'], observation['seed'])
        if run in seen_runs:
            raise RuntimeError(f'{args.evidence}: duplicate evidence for {run[0]}.{run[1]}')
        seen_runs.add(run)
        by_test.setdefault(observation['test'], []).append(observation)

    # A simulator PASS in a declared must-fail test is not accepted.  Start with passes from
    # ordinary tests only; matching failure observations are added below.
    accepted = sum(r['passing'] for r in results if r['name'] not in declared)
    failed = 0
    must_fail = 0
    for result in results:
        deficit = result['total'] - result['passing']
        evidence = by_test.pop(result['name'], [])
        if result['name'] in declared and result['passing']:
            print(f"FAIL {result['name']}: {result['passing']} must-fail seed(s) passed unexpectedly")
            failed += result['passing']
        if not deficit and evidence:
            print(f"FAIL {result['name']}: evidence supplied for an aggregate result with no failure")
            failed += len(evidence)
            continue
        if len(evidence) != deficit:
            if deficit:
                print(f"FAIL {result['name']}: {deficit} failed seed(s), {len(evidence)} evidence entry/entries")
                failed += deficit
            continue
        for observation in evidence:
            expected = match_expected_failure(result['name'], observation['message'], declared)
            if expected is None:
                print(f"FAIL {result['name']}.{observation['seed']}: failure does not match its declaration")
                failed += 1
            else:
                print(f"PASS (must fail) {result['name']}.{observation['seed']}: "
                      f"{expected['ref']} -- {expected['reason']}")
                must_fail += 1
                accepted += 1
    for name, evidence in sorted(by_test.items()):
        print(f"FAIL {name}: {len(evidence)} evidence entry/entries for a test absent from the results")
        failed += len(evidence)

    total = sum(r['total'] for r in results)
    pct = accepted / total * 100 if total else 0
    print(f"{pct:.2f}% PASS {accepted - must_fail} PASSED, {failed} FAILED, "
          f"{must_fail} PASS (must fail)")
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
