#!/usr/bin/env python3
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""Regrade a saved UVM regression with today's grading rules and test lists.

Reads the per-run results a regression left in out/metadata/<test>.<seed>.pickle (the same
TestRunResult objects collect_results.py reads; copy them anywhere, they need no other file) and
grades them with collect_results.grade_runs() against the directed testlists' expected_failure
declarations and waivers/known_gaps.yaml. Writes regr.log, regr_junit.xml, regr_junit_merged.xml,
report.html and report.json into --out-dir, as collect_results.py writes them into out/run, and
prints the summary line. Nothing is simulated and the saved results are not changed.

  regrade_saved_results.py --metadata-dir <copy of out/metadata> --out-dir <dir>
      [--runs <file of test.seed names, one per line>]

Exit status as collect_results.py: 1 if any run fails the regression, else 0.
"""

import argparse
import datetime
import sys
import types

import pathlib3x as pathlib

import collect_results
import expected_failures as xf
from known_gaps import load_known_gaps
from report_lib.text import gen_summary_line
from test_run_result import TestRunResult

DIRECTED_TESTLIST = (pathlib.Path(__file__).resolve().parent.parent /
                     'directed_tests' / 'directed_testlist.yaml')


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--metadata-dir', required=True, type=pathlib.Path,
                    help='directory of saved <test>.<seed>.pickle files')
    ap.add_argument('--runs', type=pathlib.Path,
                    help='only these runs (test.seed, one per line); default every pickle')
    ap.add_argument('--directed-testlist', type=pathlib.Path, default=DIRECTED_TESTLIST,
                    help='any directed_testlist*.yaml; its siblings are read too')
    ap.add_argument('--out-dir', required=True, type=pathlib.Path)
    args = ap.parse_args()

    if args.runs:
        names = [n.strip() for n in args.runs.read_text().splitlines() if n.strip()]
        pickles = [args.metadata_dir / f'{n}.pickle' for n in names]
        missing = [p.name for p in pickles if not p.exists()]
        if missing:
            print(f"ERROR: {len(missing)} listed run(s) have no pickle, e.g. {missing[0]}",
                  file=sys.stderr)
            return 1
    else:
        # metadata.pickle is the regression's own record, not a run.
        pickles = sorted(p for p in args.metadata_dir.glob('*.pickle')
                         if p.name != 'metadata.pickle')
    trrs = [TestRunResult.construct_from_pickle(p) for p in pickles]

    g = collect_results.grade_runs(trrs, load_known_gaps(),
                                   xf.load_expected_failures(args.directed_testlist))

    # The HTML and JSON writers want the regression's metadata; only these fields are read.
    md = types.SimpleNamespace(creation_datetime=datetime.datetime.now(datetime.timezone.utc),
                               git_commit='regraded', simulator='xlm')
    out = args.out_dir
    out.mkdir(parents=True, exist_ok=True)
    collect_results.write_reports(md, g, {}, out / 'regr.log', out / 'regr_junit.xml',
                                  out / 'regr_junit_merged.xml', out / 'report.html',
                                  out / 'report.json')
    print(f"{len(trrs)} saved run(s) from {args.metadata_dir} regraded -> {out}")
    print(gen_summary_line(g.passing_tests, g.failing_tests, g.known_gap_tests,
                           g.expected_fail_tests))
    return 1 if g.failing_tests else 0


if __name__ == '__main__':
    sys.exit(main())
