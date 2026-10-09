# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""Known-gap waivers: classify a failing test as a known model/generator gap.

See waivers/known_gaps.yaml and the "Gap Analysis" chapter of the verification spec. A failure is a
known gap only if both the test-name and the failure-message patterns of one entry match.
"""

import pathlib
import re
from typing import Dict, List, Optional

import yaml

KNOWN_GAPS_FILE = pathlib.Path(__file__).resolve().parent.parent / 'waivers' / 'known_gaps.yaml'


def load_known_gaps(path: pathlib.Path = KNOWN_GAPS_FILE) -> List[Dict[str, str]]:
    if not path.exists():
        return []
    entries = yaml.safe_load(path.read_text()) or []
    for e in entries:
        for key in ('id', 'test', 'message'):
            if not e.get(key):
                raise RuntimeError(f'{path}: known-gap entry {e!r} has no {key!r}')
        e['_test_re'] = re.compile(e['test'])
        e['_msg_re'] = re.compile(e['message'])
    return entries


def match_known_gap(testname: str, failure_message: Optional[str],
                    gaps: List[Dict[str, str]]) -> Optional[Dict[str, str]]:
    """Return the first gap entry whose test and message patterns both match, else None."""
    msg = failure_message or ''
    for e in gaps:
        if e['_test_re'].fullmatch(testname or '') and e['_msg_re'].search(msg):
            return e
    return None
