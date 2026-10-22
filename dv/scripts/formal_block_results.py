#!/usr/bin/env python3
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""Turn block-level JasperGold results into a dvsim sim_results file for a block formal testplan.

  --block icache  ibex/dv/formal_ibex_cheriot/formal-icache, formal_icache_testplan.hjson
  --block id      ibex/dv/formal_ibex_cheriot/formal-id, formal_id_testplan.hjson
  --block trvk    ibex/dv/formal_ibex_cheriot/formal-trvk, formal_trvk_testplan.hjson

Reads <block dir>/results_<config>.txt (Jasper `report -file`, one per configuration of the block
Makefile's `make configs`; results_e2e.txt from the iCache's check_e2e.tcl). Each testpoint lists
its testbench properties by name in the paragraph of its desc that starts with **Properties**
(backquoted; generate-loop copies share a name and count individually; a name may be a glob, for
Jasper's names of unnamed assumptions). A property belongs to the testpoint that lists the last
component of its name, without the ":precondition1"/":witness1" of Jasper's related covers.

  formal_<blk>_<testpoint>_<config>  passing/total over the testpoint's properties in
                                     results_<config>.txt, with the rule of the block Makefiles'
                                     summary and formal_results.py's block_result(): an assertion
                                     (no ':' in the name) counts when proven, cex or undetermined
                                     and passes when proven; a testbench cover (tb_i, including an
                                     assertion's or assumption's related covers) counts when
                                     covered or unreachable and passes when covered, or, for a
                                     cover listed in the block's must_be_unreachable.txt (the
                                     condition of a defect), when unreachable. A testpoint with no
                                     property in an existing file is 0/1.
  formal_<blk>_rtl_embedded_assertions_<config>
                                     the assertions outside tb_i with a verdict: the RTL's own,
                                     which formal-id's check.tcl proves too (RunEmbedded).
  formal_<blk>_properties_mapped     passing = property names (of formal_tb.sv and of every
                                     results file read) that exactly one testpoint lists, total =
                                     all of them. Unmapped and doubly mapped names are printed.

A missing results file leaves its tests NOT RUN; one older than --stale-days is reported, so an
old proof is not read as current.
"""

import argparse
import datetime
import fnmatch
import json
import re
import sys
import time
from pathlib import Path

import hjson

REPO = Path(__file__).resolve().parents[3]  # ibex/dv/scripts -> repository root

# block -> (flow directory relative to the repo, configuration tag pattern, earlier results files
# per configuration). check_e2e.tcl proves everything but the end-to-end targets in step 1
# (results_e2e_step1.txt), then turns the proven assertions into assumptions for step 2
# (results_e2e.txt): a property without a verdict in results_e2e.txt takes step 1's.
BLOCKS = {
    "icache": ("ibex/dv/formal_ibex_cheriot/formal-icache", re.compile(r"ecc[01]_tweak[01]_bc[01]|e2e"),
               {"e2e": ["results_e2e_step1.txt"]}),
    "id": ("ibex/dv/formal_ibex_cheriot/formal-id", re.compile(r"wb[01]_btalu[01]_cheriot[01](_live)?"), {}),
    "trvk": ("ibex/dv/formal_ibex_cheriot/formal-trvk", re.compile(r"out\d+_ecc[01]_bmw\d+(_live)?"), {}),
}
EMBEDDED = "rtl_embedded_assertions"
MAPPED = "properties_mapped"
ASSERT_STATUS = ("proven", "cex", "undetermined")
COVER_STATUS = ("covered", "unreachable")
VERDICTS = ("proven", "cex", "covered", "unreachable")
# "[n]  name  status ...": the RESULTS table. The ASSUMPTIONS table has an expression there instead.
RESULT_LINE = re.compile(r"^\[\d+\]\s+(\S+)\s+([a-z_]+)(?:\s|$)")
# `ASSERT(name, ...), `COVER(name, ...), `ASSUME(name, ...) in formal_tb.sv, and the testbench's own
# one-argument macros around them (`define M(x) `ASSERT(x``_suffix, ...)).
SV_PROP = re.compile(r"`(?:ASSERT|ASSUME|COVER)\(\s*(\w+)\s*,")
SV_MACRO = re.compile(r"`define\s+(\w+)\((\w+)\)\s*\\\s*\n\s*`(?:ASSERT|ASSUME|COVER)\(\2``(\w+)\s*,")
# The shared OBI checker (ibex/dv/sva/ibex_obi_assert.sv), bound by blocks that list it in files.f:
# its rules are declared through its own two macros.
OBI_CHECKER = REPO / "ibex/dv/sva/ibex_obi_assert.sv"
OBI_RULE = re.compile(r"`IBEX_OBI_(?:HOST|DEVICE)_RULE\(\s*(\w+)\s*,")


def plan_properties(testpoints):
    """{testpoint: [name or glob]} from the **Properties** paragraph of each desc."""
    props = {}
    for tp in testpoints:
        _, found, rest = tp.get("desc", "").partition("**Properties**")
        props[tp["name"]] = re.findall(r"`([^`]+)`", rest) if found else []
    return props


def tb_names(path):
    """Property names declared in formal_tb.sv (assertions, covers, assumptions)."""
    text = path.read_text(errors="replace")
    macros = {m.group(1): m.group(3) for m in SV_MACRO.finditer(text)}
    text = re.sub(r"//.*", "", text)
    names = set(SV_PROP.findall(text))
    for macro, suffix in macros.items():
        names |= {n + suffix for n in re.findall(rf"`{macro}\(\s*(\w+)\s*\)", text)}
    return names


def read_results(path):
    """{name: status} of the property lines of one Jasper report file."""
    status = {}
    for line in path.read_text(errors="replace").splitlines():
        m = RESULT_LINE.match(line)
        if m:
            status[m.group(1)] = m.group(2)
    return status


def leaf(name):
    return name.split(":", 1)[0].rsplit(".", 1)[-1]


def must_be_unreachable(block_dir):
    """Cover names listed in <block dir>/must_be_unreachable.txt: covers of a defect's condition,
    which pass when unreachable and fail when covered (the file's header explains)."""
    path = Path(block_dir) / "must_be_unreachable.txt"
    if not path.exists():
        return set()
    return {line.split("#", 1)[0].strip() for line in path.read_text().splitlines()} - {""}


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--block", required=True, choices=sorted(BLOCKS))
    ap.add_argument("--testplan", required=True, type=Path)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--stale-days", type=float, default=7)
    ap.add_argument("--root", type=Path, default=REPO, help="where the flow directories are")
    args = ap.parse_args()

    rel, cfg_pattern, earlier = BLOCKS[args.block]
    bdir = args.root / rel
    prefix = f"formal_{args.block}"
    testpoints = hjson.loads(args.testplan.read_text()).get("testpoints", [])
    listed = plan_properties(testpoints)

    # test -> (testpoint, configuration); configuration None for properties_mapped.
    tests = {}
    for tp in testpoints:
        for test in tp.get("tests", []):
            if tp["name"] == MAPPED:
                tests[test] = (MAPPED, None)
                continue
            cfg = test[len(f"{prefix}_{tp['name']}_"):]
            if not test.startswith(f"{prefix}_{tp['name']}_") or not cfg_pattern.fullmatch(cfg):
                print(f"WARNING  test {test} of testpoint {tp['name']} is not "
                      f"{prefix}_{tp['name']}_<config>; it stays NOT RUN")
                continue
            tests[test] = (tp["name"], cfg)
        if tp["name"] not in (EMBEDDED, MAPPED) and not listed[tp["name"]]:
            print(f"WARNING  testpoint {tp['name']} lists no **Properties**")

    exact, globs = {}, []
    for tp, names in listed.items():
        for n in names:
            if any(c in n for c in "*?["):
                globs.append((n, tp))
            else:
                exact.setdefault(n, []).append(tp)

    def owners(name):
        return exact.get(name, []) + [tp for g, tp in globs if fnmatch.fnmatchcase(name, g)]

    seen = tb_names(bdir / "formal_tb.sv")  # every testbench property name, for properties_mapped
    if "ibex_obi_assert.sv" in (bdir / "files.f").read_text(errors="replace"):
        obi = re.sub(r"//.*", "", OBI_CHECKER.read_text(errors="replace"))
        seen |= {n for n in set(OBI_RULE.findall(obi)) | set(SV_PROP.findall(obi))
                 if not n.startswith("__")}  # not the macros' own parameters
    unreachable_ok = must_be_unreachable(bdir)
    for name in sorted(unreachable_ok - seen):
        print(f"WARNING  must_be_unreachable.txt lists {name}, which formal_tb.sv does not declare")
    stale_listed = sorted(n for n in exact if n not in seen)

    measured = {}  # test -> (passing, total)
    for cfg in sorted({c for _, c in tests.values() if c}):
        cfg_tests = sorted(t for t, (_, c) in tests.items() if c == cfg)
        res = bdir / f"results_{cfg}.txt"
        if not res.exists():
            print(f"{cfg:24s} no {rel}/{res.name} -- its {len(cfg_tests)} test(s) are NOT RUN")
            continue
        mtime = res.stat().st_mtime
        age = (time.time() - mtime) / 86400
        when = datetime.datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M")
        status = {}
        for name in earlier.get(cfg, []):
            step = bdir / name
            if not step.exists():
                continue
            if step.stat().st_mtime > mtime:
                print(f"{cfg:24s} {name} is newer than {res.name} (a later run stopped before its "
                      f"last step): not used")
                continue
            status.update(read_results(step))
        # A verdict in the last report wins; "undetermined" there only fills a gap. Step 2 of
        # check_e2e.tcl resets every property it does not prove again to undetermined -- the
        # environment's witness covers among them -- so letting it override step 1 left the
        # e2e environment testpoint with nothing graded (2026-10-15). Step 1's verdicts still
        # hold in step 2: it adds only proven assertions as assumptions, which removes no
        # reachable state.
        for name, st in read_results(res).items():
            if st in VERDICTS or name not in status:
                status[name] = st
        # Assertions the run took from its checkpoint (scripts/checkpoint.tcl) are assumptions in
        # the report. The run writes this list after the report, so an older one is another run's.
        loaded = bdir / f"checkpoint-{args.block}-{cfg}-loaded.txt"
        if loaded.exists() and loaded.stat().st_mtime >= mtime:
            for name in loaded.read_text().split():
                if status.get(name) not in VERDICTS:
                    status[name] = "proven"

        groups = {}   # testpoint -> [passing, total, [failures]]
        other = {}    # testbench property status not counted -> number
        for name, st in status.items():
            tb = "tb_i" in name
            if st in ASSERT_STATUS and ":" not in name:
                ok = st == "proven"
            elif st in COVER_STATUS and tb:
                ok = st == ("unreachable" if leaf(name) in unreachable_ok else "covered")
            else:
                if tb:
                    other[st] = other.get(st, 0) + 1
                continue
            if tb:
                seen.add(leaf(name))
                tps = owners(leaf(name))
                tp = tps[0] if tps else None
            else:
                tp = EMBEDDED
            g = groups.setdefault(tp, [0, 0, []])
            g[0] += ok
            g[1] += 1
            if not ok:
                g[2].append(f"{st} {name}")

        stale = f"  STALE ({age:.0f} days old)" if age > args.stale_days else ""
        print(f"{cfg:24s} {when}: {res.name}{stale}")
        for test in cfg_tests:
            tp = tests[test][0]
            p, t, bad = groups.get(tp, (0, 0, []))
            if t == 0:
                # An empty or setup-failed report, or properties renamed: nothing graded is not a pass.
                print(f"  {test:58s} no property of {tp} in {res.name}")
                measured[test] = (0, 1)
                continue
            print(f"  {test:58s} {p}/{t}")
            for b in bad[:6]:
                print(f"      {b}")
            if len(bad) > 6:
                print(f"      ... {len(bad) - 6} more")
            measured[test] = (p, t)
        graded = {tests[t][0] for t in cfg_tests}
        rest = [f"{tp} {p}/{t}" for tp, (p, t, _) in sorted(groups.items(), key=lambda g: str(g[0]))
                if tp not in graded and tp is not None]
        if rest:
            print(f"  not graded for {cfg}: {', '.join(rest)}")
        if None in groups:
            print(f"  UNMAPPED: {groups[None][1]} testbench properties in no testpoint "
                  f"(see properties_mapped)")
        if other:
            print("  not counted: " + ", ".join(f"{n} testbench properties {st}"
                                                for st, n in sorted(other.items())))

    unmapped = sorted(n for n in seen if not owners(n))
    doubled = sorted(n for n in seen if len(owners(n)) > 1)
    for n in unmapped:
        print(f"UNMAPPED  {n}: in no testpoint's **Properties**")
    for n in doubled:
        print(f"DOUBLE    {n}: in {', '.join(owners(n))}")
    for n in stale_listed:
        print(f"NOTE      {n}: listed in the testplan, not declared in formal_tb.sv")
    for test, (tp, _) in tests.items():
        if tp == MAPPED:
            measured[test] = (len(seen) - len(unmapped) - len(doubled), len(seen))

    results = []
    for test in sorted(tests):
        if test in measured:
            p, t = measured[test]
            results.append({"name": test, "passing": p, "total": t})
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps({
        "timestamp": datetime.datetime.now().strftime("%Y-%m-%d %H:%M"),
        "test_results": results,
    }, indent=2) + "\n")
    passing = sum(r["passing"] for r in results)
    total = sum(r["total"] for r in results)
    print(f"{len(results)}/{len(tests)} tests measured: {passing}/{total} properties or checks "
          f"pass -> {args.out}")


if __name__ == "__main__":
    sys.exit(main())
