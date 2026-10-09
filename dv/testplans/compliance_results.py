#!/usr/bin/env python3
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""Turn the compliance signatures into a dvsim sim_results file for compliance_testplan.hjson.

Per configuration -- enable_low: ibex/dv/riscv_compliance/xlm_compliance_out/work/<isa>/,
enable_high: .../xlm_compliance_cheriot_out/work/<isa>/ -- each test's signature is compared with
the suite's reference output (the same normalisation gen_html_report.py uses). Per test, total is
the number of configurations (2) and passing the number where it is accepted:

  PASS    the signature matches the reference
  XFAIL   it does not, and the test is in EXPECTED_FAIL (gen_compliance_testplan.py): accepted
  XPASS   it matches although listed as expected to fail: accepted, and reported so the entry goes
  FAIL    it does not match, or there is no signature
A configuration with no signatures at all did not run; its tests are NOT RUN, not failures.
"""

import argparse
import datetime
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]  # ibex/dv/testplans -> repository root
sys.path.insert(0, str(REPO))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_html_report import normalize_sig  # noqa: E402
from gen_compliance_testplan import EXCLUDED, EXPECTED_FAIL, ISAS, SUITE  # noqa: E402

CONFIGS = {"enable_low": "xlm_compliance_out", "enable_high": "xlm_compliance_cheriot_out"}
COMPLIANCE = REPO / "ibex/dv/riscv_compliance"


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--compliance-dir", type=Path, default=COMPLIANCE,
                    help="ibex/dv/riscv_compliance (holds the per-configuration work dirs)")
    args = ap.parse_args()

    tests = {}   # test -> {config: verdict}
    for isa in ISAS:
        for ref in sorted((SUITE / isa / "references").glob("*.reference_output")):
            name = f"{isa}_{ref.name[:-len('.reference_output')]}"
            if name not in EXCLUDED:   # not in the testplan (gen_compliance_testplan.py)
                tests[name] = {}

    for cfg, outdir in CONFIGS.items():
        work = args.compliance_dir / outdir / "work"
        sigs = list(work.glob("*/*.signature.output"))
        if not sigs:
            print(f"{cfg:12s} no signatures in {work} -- NOT RUN")
            continue
        newest = max(p.stat().st_mtime for p in sigs)
        counts = {"PASS": 0, "XFAIL": 0, "XPASS": 0, "FAIL": 0}
        for test in tests:
            isa, name = test.split("_", 1)
            ref = SUITE / isa / "references" / f"{name}.reference_output"
            sig = work / isa / f"{name}.signature.output"
            match = sig.exists() and normalize_sig(sig.read_text()) == normalize_sig(ref.read_text())
            if test in EXPECTED_FAIL and cfg in EXPECTED_FAIL[test][0]:
                verdict = "XPASS" if match else "XFAIL"
            else:
                verdict = "PASS" if match else "FAIL"
            tests[test][cfg] = verdict
            counts[verdict] += 1
            if verdict in ("FAIL", "XPASS"):
                why = ("no signature" if not sig.exists() else "signature differs") \
                    if verdict == "FAIL" else "passes although listed as expected to fail"
                print(f"  {verdict:5s} {cfg}: {test}: {why}")
        when = datetime.datetime.fromtimestamp(newest).strftime("%Y-%m-%d %H:%M")
        print(f"{cfg:12s} {when}: " + ", ".join(f"{v} {k}" for k, v in counts.items()))

    results = []
    for test, verdicts in tests.items():
        results.append({"name": test,
                        "passing": sum(1 for v in verdicts.values() if v != "FAIL"),
                        "total": len(CONFIGS)})
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps({
        "timestamp": datetime.datetime.now().strftime("%Y-%m-%d %H:%M"),
        "test_results": results,
    }, indent=2) + "\n")
    passing = sum(r["passing"] for r in results)
    total = sum(r["total"] for r in results)
    print(f"{len(results)} tests: {passing}/{total} test x configuration results accepted "
          f"-> {args.out}")


if __name__ == "__main__":
    main()
