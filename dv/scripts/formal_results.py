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
  formal_<flow>_complete   1/1 when the run finished and every property reached a verdict: the
                           log holds the verify script's final report (report_results) with
                           "UNDETERMINED: 0" and "NOT RUN (14h budget used up...): 0", and no
                           SUMMARY block (one per proof step) reports an undetermined assertion.
                           A run killed before its final report (OOM, SIGTERM) is 0/1.
  <prefix>_<property>      named properties (transition, vericheri): an assertion passes when
                           proven, a cover when covered. total = 1.
  formal_block_<blk>_<cfg> block-level checks (ibex/dv/formal_ibex_cheriot/formal-icache, -id, -dit, -trvk), one per
                           configuration of their `make configs`, read from results_<cfg>.txt
                           (Jasper `report -file`): total = the checked assertions (no ':' in the
                           name, status proven, cex or undetermined) plus the testbench covers
                           (tb_i, covered or unreachable; an assertion's :precondition cover
                           counts too, as an unreachable one means a vacuous proof); passing =
                           proven assertions plus covered covers (unreachable ones for a cover
                           listed in the block's must_be_unreachable.txt). The same rule as
                           run_all_tests.sh and the block Makefiles' summary. Per property group:
                           formal_block_results.py with formal_icache/formal_id/formal_trvk_testplan.hjson.

A flow whose log is missing leaves its tests NOT RUN; a log older than --stale-days is reported,
so a months-old proof is not read as current. The output's timestamp is the time of the oldest
log or results file read, not of this script's run.
"""

import argparse
import datetime
import json
import re
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]  # ibex/dv/scripts -> repository root
sys.path.insert(0, str(REPO))
from gen_html_report import parse_formal_results  # noqa: E402
from formal_block_results import leaf, must_be_unreachable  # noqa: E402

import hjson  # noqa: E402

# flow tag -> (JasperGold project relative to the repo, how tests are named)
FLOWS = {
    "riscv": ("ibex/dv/formal_ibex_cheriot/formal-riscv/jgproject-riscv", "family"),
    "cheriot": ("ibex/dv/formal_ibex_cheriot/formal-cheriot/jgproject-cheriot", "family"),
    "transition": ("ibex/dv/formal_ibex_cheriot/formal-cheriot/jgproject-cheriot-transition", "named"),
    "vericheri": ("ibex/dv/formal_ibex_cheriot/formal-vericheri/jgproject-vericheri", "named"),
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
# Block-level checks: test prefix -> directory holding their results_<cfg>.txt.
BLOCK_FLOWS = {"formal_block_icache": "ibex/dv/formal_ibex_cheriot/formal-icache",
               "formal_block_id": "ibex/dv/formal_ibex_cheriot/formal-id",
               "formal_block_dit": "ibex/dv/formal_ibex_cheriot/formal-dit",
               "formal_block_trvk": "ibex/dv/formal_ibex_cheriot/formal-trvk"}
COVERED = re.compile(r'The cover property "([^"]+)" was covered')
SUMMARY_UNDET = re.compile(r"={20,}\nSUMMARY\n={20,}.*?assertions\s*:.*?- undetermined\s*:\s*(\d+)",
                           re.S)
# The verify scripts' final report (report_results), printed only when the whole run finished.
# formal-cheriot writes "NOT RUN (14h budget used up, or STOP): n", formal-riscv without ", or STOP".
FINAL_UNDET = re.compile(r"^UNDETERMINED: (\d+)$", re.M)
FINAL_NOT_RUN = re.compile(r"^NOT RUN \(14h budget used up[^)]*\): (\d+)$", re.M)


def run_complete(text, undet):
    """(complete, reason) for a family flow's session log text; see the module docstring."""
    not_run = FINAL_NOT_RUN.findall(text)
    final_undet = FINAL_UNDET.findall(text)
    if not not_run or not final_undet:
        return False, "no final report: the run did not finish (killed, or still running)"
    if int(not_run[-1]):
        return False, f"{not_run[-1]} prove(s) not run (budget or STOP)"
    if int(final_undet[-1]):
        return False, f"{final_undet[-1]} undetermined assertion(s) in the final report"
    if any(undet):
        return False, f"{sum(undet)} undetermined in the step summaries"
    return True, "finished, every property reached a verdict"


def block_result(path):
    """(passing, total, failures) of one block-level results_<cfg>.txt, see the module docstring."""
    unreachable_ok = must_be_unreachable(path.parent)
    passing = total = 0
    bad = []
    for line in path.read_text(errors="replace").splitlines():
        f = line.split()
        if len(f) < 3:
            continue
        name, status = f[1], f[2]
        if status in ("proven", "cex", "undetermined") and ":" not in name:
            total += 1
            passing += status == "proven"
            if status != "proven":
                bad.append(f"{status} {name}")
        elif status in ("covered", "unreachable") and "tb_i" in name:
            want = "unreachable" if leaf(name) in unreachable_ok else "covered"
            total += 1
            passing += status == want
            if status != want:
                bad.append(f"{status} {name}")
    return passing, total, bad


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
    source_mtimes = []  # every log and results file read: the output's timestamp is the oldest
    for flow, (rel, style) in FLOWS.items():
        proj = args.root / rel
        log = proj / "sessionLogs/session_0/jg_session_0.log"
        prefix = TEST_PREFIX[flow]
        if not log.exists():
            print(f"{flow:10s} no session log ({rel}) -- its tests are NOT RUN")
            continue
        source_mtimes.append(log.stat().st_mtime)
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
            complete, why = run_complete(text, undet)
            measured[f"{prefix}_complete"] = (1 if complete else 0, 1)
            print(f"           complete: {'yes' if complete else 'NO'} -- {why}")
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

    for prefix, rel in BLOCK_FLOWS.items():
        for test in sorted(t for t in required if t.startswith(prefix + "_")):
            cfg = test[len(prefix) + 1:]
            res = args.root / rel / f"results_{cfg}.txt"
            if not res.exists():
                print(f"{test:40s} no {rel}/results_{cfg}.txt -- NOT RUN")
                continue
            source_mtimes.append(res.stat().st_mtime)
            age = (time.time() - res.stat().st_mtime) / 86400
            when = datetime.datetime.fromtimestamp(res.stat().st_mtime).strftime("%Y-%m-%d %H:%M")
            p, t, bad = block_result(res)
            if t == 0:
                # An empty or setup-failed report: no checked assertion at all is not a pass.
                print(f"{test:40s} {when}: no checked assertions in {res.name} (setup failed?)")
                measured[test] = (0, 1)
                continue
            stale = f"  STALE ({age:.0f} days old)" if age > args.stale_days else ""
            print(f"{test:40s} {when}: {p}/{t}{stale}")
            for b in bad[:6]:
                print(f"           {b}")
            measured[test] = (p, t)

    results = []
    for test in sorted(required):
        if test in measured:
            p, t = measured[test]
            results.append({"name": test, "passing": p, "total": t})
        else:
            print(f"NOT RUN  {test}")
    for test in sorted(set(measured) - set(required)):
        print(f"         ({test} measured but not in the testplan)")
    # The oldest input, so the report's date is never newer than the data in it; with no input at
    # all (everything NOT RUN) there is nothing to date, so the time of this run.
    stamp = min(source_mtimes) if source_mtimes else time.time()
    if source_mtimes and max(source_mtimes) - min(source_mtimes) > 86400:
        print(f"Inputs span {datetime.datetime.fromtimestamp(min(source_mtimes)):%Y-%m-%d %H:%M} .. "
              f"{datetime.datetime.fromtimestamp(max(source_mtimes)):%Y-%m-%d %H:%M}; "
              f"timestamp = the oldest")
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps({
        "timestamp": datetime.datetime.fromtimestamp(stamp).strftime("%Y-%m-%d %H:%M"),
        "test_results": results,
    }, indent=2) + "\n")
    passing = sum(r["passing"] for r in results)
    total = sum(r["total"] for r in results)
    print(f"{len(results)}/{len(required)} tests measured: {passing}/{total} properties or checks "
          f"pass -> {args.out}")


if __name__ == "__main__":
    main()
