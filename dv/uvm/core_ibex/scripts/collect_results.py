#!/usr/bin/env python3
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

import argparse
import sys
import io
import pathlib3x as pathlib
import dataclasses
from metadata import RegressionMetadata, LockedMetadata
from test_run_result import TestRunResult, Failure_Modes
import scripts_lib as ibex_lib
from typing import List, TextIO, Dict

from report_lib.util import create_test_summary_dict, create_cov_summary_dict
from report_lib.text import output_results_text, gen_summary_line
from report_lib.html import output_results_html
from report_lib.junit_xml import output_run_results_junit_xml
from report_lib.dvsim_json import output_results_dvsim_json
from known_gaps import load_known_gaps, match_known_gap
import expected_failures as xf

try:
    # SVG requires python 3.7 and above, for environments that don't have python
    # 3.7 (e.g. CentOS 7) detect failure to import and just skip any svg
    # generation.
    import svg
    from report_lib.svg import output_results_svg
    SVG_MODULE_PRESENT = True
except ImportError:
    SVG_MODULE_PRESENT = False


@dataclasses.dataclass
class GradedRuns:
    """The runs of one regression, sorted by grade (grade_runs())."""
    summary_dict: Dict[str, str] = dataclasses.field(default_factory=dict)
    passing_tests: List[TestRunResult] = dataclasses.field(default_factory=list)
    failing_tests: List[TestRunResult] = dataclasses.field(default_factory=list)
    # (run, gap): failures that are known gaps, each gap a dict with 'id', 'reason' and 'grade'.
    # Two sources: waivers/known_gaps.yaml (model, generator or upstream gaps, "KNOWN-GAP <id>")
    # and directed tests declaring an expected_failure of kind known_gap (RTL gaps,
    # "FAIL (known gap <ref>)"). Both stay failures in every report; neither fails the exit status.
    known_gap_tests: list = dataclasses.field(default_factory=list)
    # (run, declaration): self-checks that failed as declared, "PASS (must fail)".
    expected_fail_tests: list = dataclasses.field(default_factory=list)


def grade_runs(trrs, known_gaps, expected_failures) -> GradedRuns:
    """Grade each run: pass, failure, known gap or pass (must fail).

    Shared by collect_results.py and regrade_saved_results.py, so a saved regression is regraded
    by exactly the rules of a live one.
    """
    g = GradedRuns()
    for trr in trrs:
        key = f"{trr.testname}.{trr.seed}"
        g.summary_dict[key] = \
            ('PASS' if trr.passed else
             'FAILED' + (" {T}" if (trr.failure_mode == Failure_Modes.TIMEOUT) else ""))
        grade, expected = xf.grade_expected_failure(
            trr.testname, trr.passed, trr.failure_message, expected_failures)
        if grade == 'self_check_passed':
            # A must-fail test going green means its checker is no longer exercising the
            # declared condition.  Keep the simulator result intact on disk, but grade the
            # regression red with an explicit reason.
            trr.passed = False
            trr.failure_message = (f"[FAILED]: expected failure did not occur "
                                   f"({expected['ref']}): {expected['reason']}\n")
            g.summary_dict[key] = xf.SELF_CHECK_PASSED_GRADE
            g.failing_tests.append(trr)
        elif grade == 'known_gap_passed':
            # The RTL gap the test showed is closed. That is good news, but the declaration now
            # hides nothing and claims a gap that is gone: fail until it is removed.
            trr.passed = False
            trr.failure_message = (f"[FAILED]: known gap {expected['ref']} now passes: remove the "
                                   f"expected_failure declaration of {trr.testname} "
                                   f"({expected['reason']})\n")
            g.summary_dict[key] = xf.KNOWN_GAP_PASSED_GRADE
            g.failing_tests.append(trr)
        elif trr.passed:
            g.passing_tests.append(trr)
        elif grade == 'self_check_failed':
            g.summary_dict[key] = f"{xf.SELF_CHECK_GRADE} {expected['ref']}"
            g.expected_fail_tests.append((trr, expected))
        elif grade == 'known_gap_failed':
            label = xf.known_gap_grade(expected['ref'])
            g.summary_dict[key] = label
            # The grade and reason head the failure text, so junit and the HTML report say why
            # this failure does not fail the run.
            trr.failure_message = f"[{label}]: {expected['reason']}\n{trr.failure_message or ''}"
            g.known_gap_tests.append((trr, {'id': expected['ref'], 'reason': expected['reason'],
                                            'grade': label, 'kind': xf.KNOWN_GAP}))
        else:
            gap = match_known_gap(trr.testname, trr.failure_message, known_gaps)
            if grade == 'unexpected_failure':
                # Say so: the run failed, but not the way its declaration says it must.
                trr.failure_message = (f"[FAILED]: not the declared failure of {trr.testname} "
                                       f"({expected['kind']} {expected['ref']}), which must match "
                                       f"/{expected['message']}/\n{trr.failure_message or ''}")
            if gap is not None:
                g.summary_dict[key] = f"KNOWN-GAP {gap['id']}"
                g.known_gap_tests.append((trr, {**gap, 'grade': f"KNOWN-GAP {gap['id']}",
                                                'kind': 'waiver'}))
            else:
                g.failing_tests.append(trr)
    return g


def write_reports(md, g: GradedRuns, cov_summary_dict, regr_log, junit_path, junit_merged_path,
                  html_path, json_path, svg_path=None) -> None:
    """Write regr.log, junit, HTML, dvsim JSON and SVG for graded runs."""
    # Self-checks that failed as declared count as passing in the machine-readable reports; the
    # detailed text report keeps the original failed TestRunResult and its matching log extract.
    # Known gaps stay failures everywhere: they are never a pass.
    accepted_expected = [dataclasses.replace(trr, passed=True)
                         for trr, _ in g.expected_fail_tests]
    known_gap_runs = [t for t, _ in g.known_gap_tests]

    #  Write results as junit_xml
    with open(junit_path, 'w', encoding='UTF-8') as junit_xml,\
         open(junit_merged_path, 'w', encoding='UTF-8') as junit_merged_xml:
        # junit keeps known-gap tests as failures: it is a per-test record, not the verdict.
        output_run_results_junit_xml(g.passing_tests + accepted_expected,
                                     g.failing_tests + known_gap_runs,
                                     junit_xml,
                                     junit_merged_xml)

    with open(regr_log, 'w', encoding='UTF-8') as outfile:
        #  Write results as regr.log (custom logfile format)
        output_results_text(g.passing_tests, g.failing_tests, g.summary_dict,
                            outfile, g.known_gap_tests, g.expected_fail_tests)

    test_summary_dict = create_test_summary_dict(g.passing_tests + g.failing_tests +
            known_gap_runs + accepted_expected)

    with open(html_path, 'w') as outfile:
        output_results_html(md, g.passing_tests + accepted_expected + g.failing_tests +
                known_gap_runs,
                test_summary_dict, cov_summary_dict, outfile)

    with open(json_path, 'w') as json_report_file:
        output_results_dvsim_json(md, test_summary_dict, cov_summary_dict,
                                  json_report_file)

    if svg_path is not None:
        if SVG_MODULE_PRESENT:
            with open(svg_path, 'w') as svg_summary_file:
                output_results_svg(test_summary_dict, cov_summary_dict,
                        svg_summary_file)
        else:
            print('WARNING: svg module not available, skipping SVG results output')


def main() -> int:
    """Collect all test results into summary files.

    Locate all the individual test results, and combine them into higher level
    summaries, while parsing for errors and other salient information.
    """
    parser = argparse.ArgumentParser()
    parser.add_argument('--dir-metadata',
                        type=pathlib.Path, required=True)

    args = parser.parse_args()

    with LockedMetadata(args.dir_metadata, __file__) as md:
        # Failures that match a known model/generator gap (waivers/known_gaps.yaml), and declared
        # RTL gaps (expected_failure of kind known_gap): reported as known gaps, kept out of the
        # exit status. Anything that matches no entry stays a failure.
        known_gaps = load_known_gaps()
        expected_failures = xf.load_expected_failures(md.directed_test_data)
        trrs = []
        broken = []
        for f in md.tests_pickle_files:
            try:
                trrs.append(TestRunResult.construct_from_pickle(f))
            except RuntimeError as e:
                broken.append(
                    TestRunResult(
                        name='broken_test',
                        failure_message=str(e)
                    ))
        g = grade_runs(trrs, known_gaps, expected_failures)
        g.failing_tests += broken

        md.regr_log = md.dir_run/'regr.log'
        md.regr_log_junit = md.dir_run/'regr_junit.xml'
        md.regr_log_junit_merged = md.dir_run/'regr_junit_merged.xml'

        cov_summary_dict = {}
        if md.simulator == "xlm":
            cov_summary_dict = create_cov_summary_dict(md)
        else:
            print("Warning: Not generating coverage summary, unsupported " \
                    f"simulator {md.simulator}")

        write_reports(md, g, cov_summary_dict, md.regr_log, md.regr_log_junit,
                      md.regr_log_junit_merged, md.dir_run/'report.html',
                      md.dir_run/'report.json', md.dir_run/'summary.svg')

        # Print a summary line to the terminal
        print(gen_summary_line(g.passing_tests, g.failing_tests, g.known_gap_tests,
                               g.expected_fail_tests))

    # Succeed if no test failed; known gaps do not fail the run (they are counted in the
    # summary line and listed in regr.log).
    return 1 if g.failing_tests else 0


if __name__ == '__main__':
    sys.exit(main())
