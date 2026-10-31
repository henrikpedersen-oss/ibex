# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""Load and match directed tests' declared expected failures."""

import re
from typing import Dict, Optional

import directed_test_schema


def load_expected_failures(directed_test_data) -> Dict[str, dict]:
    """Return exact test-name -> expected-failure declaration from the testlists."""
    entries = {}
    model = directed_test_schema.import_model(directed_test_data)
    for test in model.get('tests', []):
        expected = test.get('expected_failure')
        if expected is None:
            continue
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
                           entries: Dict[str, dict]):
    """Return (grade, declaration): ordinary, expected_failure, unexpected_pass/failure."""
    expected = entries.get(testname)
    if expected is None:
        return 'ordinary', None
    if passed:
        return 'unexpected_pass', expected
    matched = match_expected_failure(testname, failure_message, entries)
    return ('expected_failure', matched) if matched else ('unexpected_failure', expected)
