#!/usr/bin/env python3
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""Turn kept CHERIoT memory subsystem bench runs into a dvsim sim_results file.

Reads <bench>/xlm_out/results/<name>.<seed>.result and .log (written by cms_xlm_run.sh for every
run) and the expected runs of <bench>/cms_regress.list, judges each run, and writes
{timestamp, test_results: [{name, passing, total}]} for cheriot_mem_subsys_testplan.hjson.

  ordinary run   status PASS on the CMS_RESULT line, errors=0, the scoreboard checked something
                 (core + revbm + csr transactions > 0 and at least one meta SRAM compare), no
                 Xcelium error (*E / *F) and no SVA failure in the log
  _corrupt_ run  scoreboard fault injection: the run FAILED, the "CMS_CORRUPT ... corrupted <kind>"
                 line is present, and no CMS_ERROR precedes it (the injection is the first error)

Per test, total is the number of seeds cms_regress.list asks for (at least 1) and passing the
number of those seeds whose kept run is accepted; a seed with no kept run counts as not passing.
"""

import argparse
import datetime
import json
import re
from pathlib import Path

import hjson

RESULT = re.compile(r"CMS_RESULT test=(\S+) seed=(\d+) status=(\w+) errors=(\d+) cycles=(\d+) (.*)")
STAT = re.compile(r"(\w+)=(\d+)")
TOOL_ERR = re.compile(r"^\s*xmsim: \*[EF],|^\s*\*[EF],|Assertion .* has failed|ASSERT FAILED", re.M)


def read_kv(path):
    fields = {}
    for line in path.read_text(errors="replace").splitlines():
        key, _, value = line.partition("=")
        fields[key] = value
    return fields


def read_list(path):
    runs = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        name, _test, seeds = line.split()[:3]
        runs[name] = int(seeds)
    return runs


def judge(name, log):
    """Return (accepted, reason) for one kept run."""
    m = None
    for m in RESULT.finditer(log):
        pass
    if m is None:
        fatal = TOOL_ERR.search(log)
        return False, "no CMS_RESULT line" + (f" ({fatal.group(0).strip()[:80]})" if fatal else "")
    status, errors = m.group(3), int(m.group(4))
    stats = {k: int(v) for k, v in STAT.findall(m.group(6))}
    if "_corrupt_" in name:
        kind = name.rsplit("_corrupt_", 1)[1]
        corrupt = re.search(rf"^CMS_CORRUPT .*corrupted {kind}\b", log, re.M)
        if status != "FAIL":
            return False, "fault-injection run did not fail"
        if not corrupt:
            return False, f"no 'corrupted {kind}' line (injection never applied)"
        first_err = re.search(r"^CMS_ERROR", log, re.M)
        if first_err and first_err.start() < corrupt.start():
            return False, "a CMS_ERROR precedes the injection"
        return True, f"corrupted {kind}, {errors} error(s) after it"
    if status != "PASS" or errors:
        first = re.search(r"^CMS_ERROR.*$", log, re.M)
        return False, f"FAIL, {errors} error(s)" + (f": {first.group(0)[:120]}" if first else "")
    tool = TOOL_ERR.search(log)
    if tool:
        return False, f"simulator error: {tool.group(0).strip()[:100]}"
    checked = stats.get("core", 0) + stats.get("revbm", 0) + stats.get("csr", 0)
    if checked == 0:
        return False, "the scoreboard checked nothing"
    if stats.get("backdoor_compares", 0) == 0:
        return False, "no meta SRAM compare"
    return True, f"{checked} transactions, {stats.get('tag_checks', 0)} tag checks, " \
                 f"{stats.get('sweeps', 0)} sweeps, {stats.get('swept_caps', 0)} swept capabilities"


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--testplan", required=True, type=Path)
    ap.add_argument("--bench-dir", required=True, type=Path,
                    help="ibex/dv/cheriot-mem-subsys (holds cms_regress.list and xlm_out/results/)")
    ap.add_argument("--seed-base", type=int, default=1)
    ap.add_argument("--out", required=True, type=Path)
    args = ap.parse_args()

    in_plan = set()
    for tp in hjson.loads(args.testplan.read_text()).get("testpoints", []):
        in_plan.update(tp.get("tests", []))
    expected = read_list(args.bench_dir / "cms_regress.list")
    for name in sorted(in_plan - set(expected)):
        print(f"WARNING  testplan test '{name}' is not in cms_regress.list")
    for name in sorted(set(expected) - in_plan):
        print(f"WARNING  cms_regress.list run '{name}' is in no testpoint")

    rdir = args.bench_dir / "xlm_out" / "results"
    kept = sorted(rdir.glob("*.result")) if rdir.exists() else []
    print(f"{len(kept)} kept run(s) in {rdir}")
    verdict = {}
    for rpath in kept:
        res = read_kv(rpath)
        name, seed = res.get("name", ""), int(res.get("seed", "0") or 0)
        log = rpath.with_suffix(".log")
        if not log.exists():
            ok, why = False, f"no kept log {log.name}"
        else:
            ok, why = judge(name, log.read_text(errors="replace"))
        print(f"  {'ACCEPT' if ok else 'REJECT'}  {name:32s} seed {seed:<4d} {res.get('date', '')}  {why}")
        verdict[(name, seed)] = ok

    results = []
    for name in sorted(in_plan | set(expected)):
        seeds = range(args.seed_base, args.seed_base + max(1, expected.get(name, 1)))
        passing = sum(1 for s in seeds if verdict.get((name, s)) is True)
        missing = [s for s in seeds if (name, s) not in verdict]
        if missing:
            print(f"NOT RUN  {name}: seed(s) {', '.join(map(str, missing))}")
        results.append({"name": name, "passing": passing, "total": len(seeds)})

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps({
        "timestamp": datetime.datetime.now().strftime("%Y-%m-%d %H:%M"),
        "test_results": results,
    }, indent=2) + "\n")
    total = sum(r["total"] for r in results)
    passing = sum(r["passing"] for r in results)
    print(f"{len(results)} tests: {passing}/{total} test x seed results accepted -> {args.out}")


if __name__ == "__main__":
    main()
