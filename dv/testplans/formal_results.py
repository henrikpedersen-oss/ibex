#!/usr/bin/env python3
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""Turn JasperGold session logs into a dvsim sim_results file for formal_testplan.hjson.

Per flow, reads <project>/sessionLogs/session_0/jg_session_0.log with gen_html_report.py's own
parse_formal_results(), so the formal gate in run_all_tests.sh, the HTML report and this report
count the same things:

  formal_<flow>_<Family>   passing = proven assertions of the family, total = proven + cex.
                           Family = the name up to the first "_" (the top-level lemma groups of
                           thm/riscv.proof: Ibex, Arith, MType, Mem, ...). No properties: NOT RUN.
  formal_<flow>_cover_<n> 1/1 when cover property <n> is covered, 0/1 when proven unreachable.
  formal_<flow>_complete   1/1 when no SUMMARY block (one per proof step) reports an undetermined
                           assertion -- undetermined properties are not named in the log.
  <prefix>_<property>      named properties (transition, vericheri): an assertion passes when
                           proven, a cover when covered. total = 1.

A flow whose log is missing leaves its tests NOT RUN; a log older than --stale-days is reported,
so a months-old proof is not read as current.
"""

import argparse
import datetime
import json
import re
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]  # ibex/dv/testplans -> repository root
sys.path.insert(0, str(REPO))
from gen_html_report import parse_formal_results  # noqa: E402

import hjson  # noqa: E402

# flow tag -> (JasperGold project relative to the repo, how tests are named)
FLOWS = {
    "riscv": ("formal/formal-riscv/jgproject-riscv", "family"),
    "cheriot": ("formal/formal-cheriot/jgproject-cheriot", "family"),
    "transition": ("formal/formal-cheriot/jgproject-cheriot-transition", "named"),
    "vericheri": ("formal/formal-vericheri/jgproject-vericheri", "named"),
}
TEST_PREFIX = {"riscv": "formal_riscv", "cheriot": "formal_cheriot",
               "transition": "formal_transition", "vericheri": "vericheri"}
# Sanity checks that a proof can fail. test -> (cover that must be covered, or None; assertion
# copy that must give a counterexample, or None), names as parse_formal_results() returns them
# (side tasks prefixed "<task>::"). verify-cheriot-transition.tcl writes the decoder-gate check as
# the cover Sanity::cheri_opcode_with_gate_cut; runs before 2026-10-09 wrote it as a copy of
# a_cheri_opcode_requires_enable in task Sanity that had to give a CEX.
EXPECT_SANITY = {"formal_transition_sanity_decoder_gate":
                 ("cheri_opcode_with_gate_cut", "Sanity::a_cheri_opcode_requires_enable")}
COVERED = re.compile(r'The cover property "([^"]+)" was covered')
SUMMARY_UNDET = re.compile(r"={20,}\nSUMMARY\n={20,}.*?assertions\s*:.*?- undetermined\s*:\s*(\d+)",
                           re.S)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--testplan", required=True, type=Path)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--stale-days", type=float, default=7)
    ap.add_argument("--root", type=Path, default=REPO, help="where the flow directories are")
    args = ap.parse_args()

    required = {}
    for tp in hjson.loads(args.testplan.read_text()).get("testpoints", []):
        for test in tp.get("tests", []):
            required.setdefault(test, 0)
            required[test] += 1

    measured = {}  # test -> (passing, total)
    for flow, (rel, style) in FLOWS.items():
        proj = args.root / rel
        log = proj / "sessionLogs/session_0/jg_session_0.log"
        prefix = TEST_PREFIX[flow]
        if not log.exists():
            print(f"{flow:10s} no session log ({rel}) -- its tests are NOT RUN")
            continue
        age = (time.time() - log.stat().st_mtime) / 86400
        when = datetime.datetime.fromtimestamp(log.stat().st_mtime).strftime("%Y-%m-%d %H:%M")
        props, _ = parse_formal_results(proj)
        text = log.read_text(errors="replace")
        covered = {m.group(1).removeprefix("top.") for m in COVERED.finditer(text)}
        undet = [int(n) for n in SUMMARY_UNDET.findall(text)]
        n_prov = sum(1 for p in props if p[2] == "proven")
        n_cex = sum(1 for p in props if p[2] == "cex")
        stale = f"  STALE ({age:.0f} days old)" if age > args.stale_days else ""
        print(f"{flow:10s} {when}: {n_prov} proven, {n_cex} cex, {len(covered)} covers covered, "
              f"{sum(undet)} undetermined over {len(undet)} step summaries{stale}")
        if style == "named":
            # The transition and VeriCHERI flows load the whole checker, so the session also holds
            # Sail-equivalence properties it does not prove (CEX with cheriot_enable_i Off): only the
            # testplan's named properties count.
            named = {t[len(prefix) + 1:] for t in required if t.startswith(prefix + "_")}
            named |= {n for c, x in EXPECT_SANITY.values() for n in (c, x) if n}
            n_other = sum(1 for p in props if p[2] == "cex" and p[0] not in named)
            if n_other:
                print(f"           {n_other} of the cex are properties this flow does not prove "
                      f"(not in the testplan; ignored)")

        if style == "family":
            fam = {}
            for name, kind, status, _ in props:
                if kind != "assert":
                    continue
                # The DTI lemma is proved inside the Ibex lemma (formal-cheriot/thm/ibex.proof:
                # lemmas after it need it), so psgen names its properties Ibex_DTI_*.
                f = "Dti" if name.startswith("Ibex_DTI_") else name.split("_", 1)[0]
                p, t = fam.get(f, (0, 0))
                fam[f] = (p + (status == "proven"), t + 1)
            for f, pt in fam.items():
                measured[f"{prefix}_{f}"] = pt
            measured[f"{prefix}_complete"] = (1 if undet and not any(undet) else 0, 1)
            # Cover properties: formal_<flow>_cover_<name> passes when <name> is covered, fails
            # when it is proven unreachable, and stays NOT RUN when the log does not mention it.
            unreachable = {n for n, k, st, _ in props if k == "cover" and st == "unreachable"}
            for test in required:
                if test.startswith(prefix + "_cover_"):
                    name = test[len(prefix) + len("_cover_"):]
                    if name in covered:
                        measured[test] = (1, 1)
                    elif name in unreachable:
                        measured[test] = (0, 1)
            for f, (p, t) in sorted(fam.items()):
                if p < t:
                    cex = sorted(n for n, k, s, _ in props if s == "cex" and n.startswith(f + "_"))
                    print(f"           {f}: {t - p} cex: {', '.join(cex[:6])}"
                          f"{' ...' if len(cex) > 6 else ''}")
        else:
            status = {n: s for n, k, s, _ in props}
            for test in required:
                if not test.startswith(prefix + "_"):
                    continue
                if test in EXPECT_SANITY:
                    cover, cex_copy = EXPECT_SANITY[test]
                    if cover in covered:
                        measured[test] = (1, 1)
                    elif cover in status:  # proven unreachable: the proof cannot fail
                        measured[test] = (0, 1)
                    elif cex_copy in status:
                        measured[test] = (1 if status[cex_copy] == "cex" else 0, 1)
                    continue
                name = test[len(prefix) + 1:]
                if name in covered:
                    measured[test] = (1, 1)
                elif name in status:
                    measured[test] = (1 if status[name] == "proven" else 0, 1)

    results = []
    for test in sorted(required):
        if test in measured:
            p, t = measured[test]
            results.append({"name": test, "passing": p, "total": t})
        else:
            print(f"NOT RUN  {test}")
    for test in sorted(set(measured) - set(required)):
        print(f"         ({test} measured but not in the testplan)")
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps({
        "timestamp": datetime.datetime.now().strftime("%Y-%m-%d %H:%M"),
        "test_results": results,
    }, indent=2) + "\n")
    passing = sum(r["passing"] for r in results)
    total = sum(r["total"] for r in results)
    print(f"{len(results)}/{len(required)} tests measured: {passing}/{total} properties or checks "
          f"pass -> {args.out}")


if __name__ == "__main__":
    main()
