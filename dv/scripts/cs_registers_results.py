#!/usr/bin/env python3
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""Turn the CS registers testbench's last runs into a dvsim sim_results file.

Reads <bench>/xlm_out/run.log (make csr-tb-xlm) and <bench>/vlt_out/run.log (make csr-tb-vlt) and
writes {timestamp, test_results: [{name, passing, total}]} for cs_registers_testplan.hjson. Each
log is graded from its contents, not from xlm_out/result, so the report always matches the log:

  passing  the bench printed // TEST PASSED //, the log has no simulator error (Xcelium *E/*F,
           Verilator %Error) and no SVA failure, and the register driver drove > 0 transactions

A missing log is a test that has not run: total 1, passing 0.
"""

import argparse
import datetime
import json
import re
from pathlib import Path

RUNS = {"tb_cs_registers": "xlm_out/run.log", "tb_cs_registers_vlt": "vlt_out/run.log"}
TOOL_ERR = re.compile(r"^\s*((xmsim: )?\*[EF],|%Error|.*ASSERT FAILED|.*Assertion .* has failed).*", re.M)
DRIVEN = re.compile(r"drove: (\d+) register transactions")


def grade(log):
    """(passed, reason) for one run log."""
    text = log.read_text(errors="replace")
    why = []
    if "// TEST PASSED //" not in text:
        why.append("no TEST PASSED")
    err = TOOL_ERR.search(text)
    if err:
        why.append(f"simulator error or SVA failure ({err.group(0).strip()[:100]})")
    driven = [int(n) for n in DRIVEN.findall(text)]
    if not driven or driven[-1] == 0:
        why.append("no register transactions driven")
    return not why, ", ".join(why) or f"{driven[-1]} transactions"


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--bench-dir", type=Path, default=Path(__file__).resolve().parents[1] / "cs_registers")
    ap.add_argument("--out", type=Path, required=True)
    args = ap.parse_args()

    results = []
    for test, rel in RUNS.items():
        log = args.bench_dir / rel
        if not log.exists():
            print(f"  NOTRUN {test}: no {rel}")
            results.append({"name": test, "passing": 0, "total": 1})
            continue
        passed, why = grade(log)
        when = datetime.datetime.fromtimestamp(log.stat().st_mtime).strftime("%Y-%m-%d %H:%M")
        print(f"  {'PASS' if passed else 'FAIL':6s} {test} ({when}): {why}")
        results.append({"name": test, "passing": int(passed), "total": 1})

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps({
        "timestamp": datetime.datetime.now().strftime("%Y-%m-%d %H:%M"),
        "test_results": results,
    }, indent=2) + "\n")
    print(f"{sum(r['passing'] for r in results)}/{len(results)} runs passing -> {args.out}")


if __name__ == "__main__":
    main()
