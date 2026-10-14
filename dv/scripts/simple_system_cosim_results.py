#!/usr/bin/env python3
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""Turn the simple_system co-simulation runs into a dvsim sim_results file.

Reads <outdir>/<test>/{rc,sim.log,ibex_simple_system.log} as run_cosim_tests.sh leaves them
(make simple-system-cosim-vlt) and writes {timestamp, test_results: [{name, passing, total}]} for
simple_system_cosim_testplan.hjson. Each run is graded from those files, as ci/run-cosim-test.sh
grades it, so the report always matches the logs:

  passing  the simulator exited 0 (rc), neither log has a FAILURE, the program printed PASS
           (not required of coremark and pmp_smoke_test, which upstream runs with
           --skip-pass-check), and the co-simulation matched > 0 instructions

A test with no run directory (not run, or not in the configuration) is total 1, passing 0.
"""

import argparse
import datetime
import json
import re
from pathlib import Path

TESTS = ["coremark", "pmp_smoke_test", "dit_test", "dummy_instr_test"]
SKIP_PASS_CHECK = {"coremark", "pmp_smoke_test"}
MATCHED = re.compile(r"Co-simulation matched (\d+) instructions")


def read(path):
    return path.read_text(errors="replace") if path.exists() else ""


def grade(test, d):
    """(passed, reason) for one run directory."""
    why = []
    rc = read(d / "rc").strip()
    if not rc:
        why.append("simulator exit not recorded (no rc: a run by an older run_cosim_tests.sh;"
                   " re-run make simple-system-cosim-vlt)")
    elif rc != "0":
        why.append(f"simulator exit {rc}")
    sim, uart = read(d / "sim.log"), read(d / "ibex_simple_system.log")
    if "FAILURE" in sim or "FAILURE" in uart:
        why.append("FAILURE in the log")
    if test not in SKIP_PASS_CHECK and "PASS" not in uart:
        why.append("no PASS")
    matched = [int(n) for n in MATCHED.findall(sim)]
    if not matched or matched[-1] == 0:
        why.append("co-simulation matched no instructions")
    return not why, ", ".join(why) or f"{matched[-1]} instructions matched"


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out-dir", type=Path,
                    default=Path(__file__).resolve().parents[1] / "verilator/simple_system_cosim/vlt_out",
                    help="run_cosim_tests.sh's output directory")
    ap.add_argument("--out", type=Path, required=True)
    args = ap.parse_args()

    config = read(args.out_dir / "config.txt").split(":")[0].strip()
    if config:
        print(f"  {config}")
    results = []
    for test in TESTS:
        d = args.out_dir / test
        if not d.is_dir():
            print(f"  NOTRUN {test}")
            results.append({"name": test, "passing": 0, "total": 1})
            continue
        passed, why = grade(test, d)
        stamp = d / "sim.log"
        when = (datetime.datetime.fromtimestamp(stamp.stat().st_mtime).strftime("%Y-%m-%d %H:%M")
                if stamp.exists() else "?")
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
