# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

from typing import List, TextIO, Dict
from .util import gen_test_run_result_text
from test_run_result import TestRunResult

import io
import scripts_lib as ibex_lib

def box_comment(line: str) -> str:
    hr = '#' * 80
    return hr + '\n# ' + line + '\n' + hr


def is_declared_gap(gap: dict) -> bool:
    '''A known gap declared by the test itself (expected_failure, kind known_gap: an RTL gap), as
    opposed to a waivers/known_gaps.yaml waiver (a model, generator or upstream gap).'''
    return gap.get('kind') == 'known_gap'


def gap_counts(known_gap_tests) -> Dict[str, int]:
    '''Runs per gap reference, in reference order.'''
    counts: Dict[str, int] = {}
    for _, gap in known_gap_tests:
        counts[gap['id']] = counts.get(gap['id'], 0) + 1
    return dict(sorted(counts.items()))


def gen_summary_line(passing_tests: List[TestRunResult], failing_tests:
                     List[TestRunResult], known_gap_tests=(), expected_fail_tests=()) -> str:
    '''Generate a string summarising test results.

    "N PASSED, M FAILED" keeps its form for parsers; M counts only the failures that fail the run.
    Then, when there are any:
      ", K KNOWN-GAP WARNINGS"     failures waived by waivers/known_gaps.yaml
      ", G FAIL (known gap <ref>: <runs>, ...)"
                                   failures declared as known RTL gaps (expected_failure, kind
                                   known_gap), with each reference
      ", S PASS (must fail)"       self-checks that failed as declared
    Known gaps of both kinds count in the total and never as passing.'''
    total_tests = (len(passing_tests) + len(failing_tests) + len(known_gap_tests) +
                   len(expected_fail_tests))
    accepted = len(passing_tests) + len(expected_fail_tests)
    pass_pct = (accepted / total_tests) * 100 if total_tests else 0.0
    waivers = [t for t in known_gap_tests if not is_declared_gap(t[1])]
    declared = [t for t in known_gap_tests if is_declared_gap(t[1])]

    line = f'{pass_pct:0.2f}% PASS {len(passing_tests)} PASSED, ' \
           f'{len(failing_tests)} FAILED'
    if waivers:
        line += f', {len(waivers)} KNOWN-GAP WARNINGS'
    if declared:
        refs = ', '.join(f'{ref}: {n}' for ref, n in gap_counts(declared).items())
        line += f', {len(declared)} FAIL (known gap {refs})'
    if expected_fail_tests:
        line += f', {len(expected_fail_tests)} PASS (must fail)'
    return line


def output_results_text(passing_tests: List[TestRunResult],
                        failing_tests: List[TestRunResult],
                        summary_dict: Dict[str, str],
                        report_file: TextIO,
                        known_gap_tests=(), expected_fail_tests=()):
    '''Write results in text form to dest'''

    # Print a summary line right at the top of the file
    report_file.write(gen_summary_line(passing_tests, failing_tests, known_gap_tests,
                                       expected_fail_tests))
    report_file.write('\n')
    # Print a short TEST.SEED   PASS/FAILED summary
    summary_yaml = io.StringIO()
    ibex_lib.pprint_dict(summary_dict, summary_yaml)
    summary_yaml.seek(0)
    report_file.write(summary_yaml.getvalue())
    report_file.write('\n')
    # Print a longer summary with some more information

    print('\n'+box_comment('Details of failing tests'), file=report_file)
    if not bool(failing_tests):
        print("No failing tests. Nice job!", file=report_file)
    for trr in failing_tests:
        print(gen_test_run_result_text(trr), file=report_file)

    sections = (
        ('Known RTL gaps: failing tests declared with expected_failure, kind known_gap '
         '(not passes; requirement not met)', [t for t in known_gap_tests if is_declared_gap(t[1])]),
        ('Known-gap warnings (Gap Analysis in the verification spec)',
         [t for t in known_gap_tests if not is_declared_gap(t[1])]),
    )
    for title, tests in sections:
        if not tests:
            continue
        print('\n'+box_comment(title), file=report_file)
        for gid, n in gap_counts(tests).items():
            reason = next(g for _, g in tests if g['id'] == gid).get('reason', '')
            print(f"{gid}: {n} run(s) -- {reason}", file=report_file)
        print('', file=report_file)
        for trr, gap in tests:
            print(f"[{gap.get('grade', 'KNOWN-GAP ' + gap['id'])}]", file=report_file)
            print(gen_test_run_result_text(trr), file=report_file)

    if expected_fail_tests:
        print('\n'+box_comment('Passing tests that must fail'), file=report_file)
        for trr, expected in expected_fail_tests:
            print(f"[PASS (must fail) {expected['ref']}] {expected['reason']}", file=report_file)
            print(gen_test_run_result_text(trr), file=report_file)

    print('\n'+box_comment('Details of passing tests'), file=report_file)
    if not bool(passing_tests):
        print("No passing tests. Hmmmm...", file=report_file)
    for trr in passing_tests:
        print(gen_test_run_result_text(trr), file=report_file)
