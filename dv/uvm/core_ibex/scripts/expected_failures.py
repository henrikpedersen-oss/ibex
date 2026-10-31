# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""Load and grade directed tests' declared expected failures.

A directed test may declare `expected_failure` (directed_test_schema.ExpectedFailure): the failure
message it must fail with, and of which kind the failure is.

  self_check  The test is built to fail: an _inject_fail run whose failure proves that a checker
              works. A matching failure grades "PASS (must fail)" and counts as a pass.
  known_gap   The test fails because the RTL misses a requirement (a gap with a reference). A
              matching failure grades "FAIL (known gap <ref>)": it is a failure in every report and
              the requirement stays unmet, but it does not turn the regression red by itself.

Either way the failure must match the declared message, as strictly as before. A failure that does
not match is an ordinary failure, and a pass is a failure too: for a self-check the checker no
longer sees its fault, for a known gap the RTL has been fixed and the declaration must go.
"""

import re
from typing import Dict, Optional, Tuple

import directed_test_schema

# The grade spellings, shared with the reports (report_lib/text.py) and kept the same in the CMS and
# RTOS results scripts (ibex/dv/scripts/cheriot_mem_subsys_results.py, cheriot_rtos_results.py).
SELF_CHECK = 'self_check'
KNOWN_GAP = 'known_gap'
SELF_CHECK_GRADE = 'PASS (must fail)'
SELF_CHECK_PASSED_GRADE = 'FAILED (must fail, but passed)'
# No ': ' in a grade: regr.log's per-run table is YAML, and a colon would make it a block.
KNOWN_GAP_PASSED_GRADE = 'FAILED (known gap now passes, remove the declaration)'


def known_gap_grade(ref: str) -> str:
    """The grade of a run that fails with its declared known gap."""
    return f'FAIL (known gap {ref})'


def load_expected_failures(directed_test_data) -> Dict[str, dict]:
    """Return exact test-name -> expected-failure declaration from the testlists."""
    entries = {}
    model = directed_test_schema.import_model(directed_test_data)
    for test in model.get('tests', []):
        expected = test.get('expected_failure')
        if expected is None:
            continue
        # The schema fills in the default; a hand-made dict (a check script) may not have it.
        expected.setdefault('kind', KNOWN_GAP)
        try:
            expected['_message_re'] = re.compile(expected['message'])
        except re.error as err:
            raise RuntimeError(
                f"directed test {test['test']!r} has an invalid expected_failure.message: {err}")
        entries[test['test']] = expected
    return entries


def match_expected_failure(testname: str, failure_message: Optional[str],
                           entries: Dict[str, dict]) -> Optional[dict]:
    """Match by exact declared test name and the declared failure-message regular expression."""
    expected = entries.get(testname)
    if expected is None:
        return None
    return expected if expected['_message_re'].search(failure_message or '') else None


def grade_expected_failure(testname: str, passed: bool, failure_message: Optional[str],
                           entries: Dict[str, dict]) -> Tuple[str, Optional[dict]]:
    """Return (grade, declaration) for one run.

    grade is one of
      ordinary            no declaration: grade the run as usual
      self_check_failed   a self-check failed with its message: PASS (must fail)
      self_check_passed   a self-check passed: a failure
      known_gap_failed    a known gap failed with its message: FAIL (known gap <ref>)
      known_gap_passed    a known gap passed: a failure, "now passes, remove the declaration"
      unexpected_failure  either kind failed with some other message: a failure
    """
    expected = entries.get(testname)
    if expected is None:
        return 'ordinary', None
    kind = expected.get('kind', KNOWN_GAP)
    if passed:
        return f'{kind}_passed', expected
    if match_expected_failure(testname, failure_message, entries) is None:
        return 'unexpected_failure', expected
    return f'{kind}_failed', expected
