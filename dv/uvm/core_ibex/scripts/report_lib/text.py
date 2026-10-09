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


def gen_summary_line(passing_tests: List[TestRunResult], failing_tests:
                     List[TestRunResult], known_gap_tests=()) -> str:
    '''Generate a string summarising test results.

    Known-gap warnings (failures waived by waivers/known_gaps.yaml) are counted in the total and
    appended as ", K KNOWN-GAP WARNINGS", so "N PASSED, M FAILED" keeps its form for parsers.'''
    total_tests = len(passing_tests) + len(failing_tests) + len(known_gap_tests)
    pass_pct = (len(passing_tests) / total_tests) * 100 if total_tests else 0.0

    line = f'{pass_pct:0.2f}% PASS {len(passing_tests)} PASSED, ' \
           f'{len(failing_tests)} FAILED'
    if known_gap_tests:
        line += f', {len(known_gap_tests)} KNOWN-GAP WARNINGS'
    return line


def output_results_text(passing_tests: List[TestRunResult],
                        failing_tests: List[TestRunResult],
                        summary_dict: Dict[str, str],
                        report_file: TextIO,
                        known_gap_tests=()):
    '''Write results in text form to dest'''

    # Print a summary line right at the top of the file
    report_file.write(gen_summary_line(passing_tests, failing_tests, known_gap_tests))
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

    if known_gap_tests:
        print('\n'+box_comment('Known-gap warnings (Gap Analysis in the verification spec)'),
              file=report_file)
        counts: Dict[str, int] = {}
        for _, gap in known_gap_tests:
            counts[gap['id']] = counts.get(gap['id'], 0) + 1
        for gid in sorted(counts):
            reason = next(g for _, g in known_gap_tests if g['id'] == gid).get('reason', '')
            print(f"{gid}: {counts[gid]} run(s) -- {reason}", file=report_file)
        print('', file=report_file)
        for trr, gap in known_gap_tests:
            print(f"[KNOWN-GAP {gap['id']}]", file=report_file)
            print(gen_test_run_result_text(trr), file=report_file)

    print('\n'+box_comment('Details of passing tests'), file=report_file)
    if not bool(passing_tests):
        print("No passing tests. Hmmmm...", file=report_file)
    for trr in passing_tests:
        print(gen_test_run_result_text(trr), file=report_file)
