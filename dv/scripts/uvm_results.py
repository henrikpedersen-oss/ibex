#!/usr/bin/env python3
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""Turn one core_ibex UVM regression into a dvsim sim_results file for core_ibex_testplan.hjson.

Reads <run-dir>/<test>.<seed>/rtl_sim.log for the regression whose base seed is --seed (default:
see detect_seed) and takes the seeds SEED..SEED+--seed-span. Each log is judged as nyx_uvm_results.sh does:

  pass     "TEST PASSED" (the UVM report summary always has "UVM_FATAL reports" lines, so a
           UVM_FATAL pattern must not veto it)
  fail     any other log: TEST FAILED, a fatal, or no verdict
  not run  no rtl_sim.log yet: not counted

Per test, total is the number of judged seeds and passing the number that passed.

Coverage, from --cov-dir (coverage_combined/): the ibex_top.u_ibex_core row of cov_riscv.txt (the
UVM regression merge), every metric including CoverGroup, goes into dvsim's cov_results table. With
--html-extra, the per-type and per-covergroup functional coverage (cg_summary*.txt,
cg_detail*.txt) is written as an HTML section to append to the report: dvsim's table has one
CoverGroup cell only.
"""

import argparse
import datetime
import html
import json
import re
from pathlib import Path

import hjson

import gen_core_ibex_testplan as tpgen

SEED_SPAN = 2000
PASSED = re.compile(r"TEST PASSED")
PCT = re.compile(r"(n/a|\d+(?:\.\d+)?%)(?:\s*\(([\d/]+)\))?")
CORE_ROWS = ("ibex_top.u_ibex_core", "ibex_top/u_ibex_core", "|--u_ibex_core", "u_ibex_core")
VENDOR_CG_TYPES = ("push_pull_agent_pkg",)
CG_DETAIL_TYPE = re.compile(r"^Type name:\s*(\S+)")
CG_DETAIL_ROW = re.compile(r"^(\w+)\s+(\d+\.?\d*)%,\s+(\d+\.?\d*)%\s+\((\d+)/(\d+)\)")
CG_DETAIL_ITEM = re.compile(r"^\|--(\w+)\s+(\d+\.?\d*)%\s+\((\d+)/(\d+)\)")


def parse_cg_items(path):
    """Coverpoints/crosses per covergroup from IMC 'report -detail -type -metrics covergroup':
    {covergroup: [(item, pct, covered, total), ...]} in report order (bins are skipped)."""
    items, cur = {}, None
    if not path.exists():
        return items
    for line in path.read_text(errors="replace").splitlines():
        m = CG_DETAIL_ROW.match(line)
        if m:
            cur = m.group(1)
            items.setdefault(cur, [])
            continue
        m = CG_DETAIL_ITEM.match(line)
        if m and cur:
            items[cur].append((m.group(1), m.group(2) + "%", int(m.group(3)), int(m.group(4))))
    return items


def item_descriptions():
    """{item: (description, requirements)} from the verification spec's coverage tables, and for
    items it does not describe, the hand-written bullets of the testplan generator (CG_DETAILS)."""
    rows, prose = tpgen.read_spec_coverage(tpgen.SPEC)
    desc = dict(rows)
    texts = []  # hand-written bullets and paragraphs, in order
    for paras in tpgen.CG_DETAILS.values():
        for p in paras:
            texts += p if isinstance(p, list) else [p]
    for t in texts:  # a bullet led by the item's name describes exactly that item
        m = re.match(r"(\w+)(?:\s*\([^)]*\))?:\s*(.*)", t)
        if m and m.group(1) not in desc:
            desc[m.group(1)] = (m.group(2), "")
    for t in texts:  # otherwise the first bullet or paragraph that names it
        for name in re.findall(r"\b(c?p?_?\w+)\b", t):
            if name not in desc and (name.startswith("cp_") or name.endswith("_cross")):
                desc[name] = (t, "")
    for name, section in prose.items():
        desc.setdefault(name, (f"Described in the verification spec, section '{section}'", ""))
    return desc


def md_cell(text):
    """Spec Markdown (backticks, bold) to escaped HTML for a table cell."""
    t = html.escape(text)
    t = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", t)
    return re.sub(r"`([^`]+)`", r"<code>\1</code>", t)


def detect_seed(run_dir):
    """A base seed has (nearly) every test: of the seeds with at least half the directories of the
    busiest one, the one with the newest directory (nyx_uvm_results.sh uses the same rule)."""
    counts, newest = {}, {}
    for d in run_dir.iterdir():
        s = d.name.rsplit(".", 1)[-1]
        if d.is_dir() and s.isdigit():
            counts[s] = counts.get(s, 0) + 1
            newest[s] = max(newest.get(s, 0), d.stat().st_mtime)
    if not counts:
        return None
    top = max(counts.values())
    return int(max((s for s in counts if 2 * counts[s] >= top), key=newest.get))


def parse_summary(path):
    """IMC 'report -summary' text -> [(row_name, [(metric, pct, detail), ...]), ...]."""
    if not path.exists():
        return []
    lines = [l for l in path.read_text(errors="replace").splitlines() if l.strip()]
    header = next((l for l in lines if l.startswith("name")), None)
    if header is None:
        return []
    metrics = re.findall(r"(\w+)\*?\s+(?:Covered|Average)", header)
    rows = []
    for line in lines[lines.index(header) + 1:]:
        if line.startswith("-") or line.startswith("Legend"):
            continue
        m = re.match(r"(\S.*?)\s{2,}(\S.*)$", line)
        if not m:
            continue
        cells = PCT.findall(m.group(2))
        rows.append((m.group(1).strip(),
                     [(metrics[i] if i < len(metrics) else f"col{i}", pct, det)
                      for i, (pct, det) in enumerate(cells)]))
    return rows


def parse_cg_detail(path):
    """IMC 'report -detail -type -metrics covergroup' -> [(type, cg, avg, pct, covered, total)]."""
    if not path.exists():
        return []
    rows, cur = [], None
    for line in path.read_text(errors="replace").splitlines():
        m = CG_DETAIL_TYPE.match(line)
        if m:
            cur = m.group(1)
            continue
        m = CG_DETAIL_ROW.match(line)
        if m and cur:
            rows.append((cur, m.group(1), m.group(2) + "%", m.group(3) + "%",
                         int(m.group(4)), int(m.group(5))))
    return rows


def html_table(header, rows):
    out = ['<table class="dv">', "<thead><tr>" + "".join(f"<th>{h}</th>" for h in header)
           + "</tr></thead>", "<tbody>"]
    for r in rows:
        out.append("<tr>" + "".join(f"<td>{c}</td>" for c in r) + "</tr>")
    out.append("</tbody></table>")
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--testplan", required=True, type=Path)
    ap.add_argument("--run-dir", required=True, type=Path,
                    help="ibex/dv/uvm/core_ibex/out/run/tests")
    ap.add_argument("--cov-dir", type=Path, help="coverage_combined/")
    ap.add_argument("--seed", type=int)
    ap.add_argument("--seed-span", type=int, default=SEED_SPAN)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--html-extra", type=Path,
                    help="write the functional coverage section here (appended to the report)")
    args = ap.parse_args()

    in_plan = set()
    for tp in hjson.loads(args.testplan.read_text()).get("testpoints", []):
        in_plan.update(tp.get("tests", []))

    verdicts = {}
    seed = None
    if args.run_dir.is_dir():
        seed = args.seed if args.seed is not None else detect_seed(args.run_dir)
    if seed is None:
        print(f"No UVM test directories in {args.run_dir}")
    else:
        print(f"UVM regression: base seed {seed}, seeds {seed}..{seed + args.seed_span - 1}")
        # Seeds alone do not identify the regression: an earlier one with a base seed inside this
        # span leaves matching directories. Keep those at least as new as this regression's first
        # directory (5 minutes slack), as nyx_uvm_results.sh does.
        base_dirs = [d for d in args.run_dir.iterdir() if d.name.endswith(f".{seed}") and d.is_dir()]
        first_t = min(d.stat().st_mtime for d in base_dirs) - 300 if base_dirs else 0
        for d in sorted(args.run_dir.iterdir()):
            name, _, s = d.name.rpartition(".")
            if not name or not s.isdigit() or not seed <= int(s) < seed + args.seed_span:
                continue
            if d.stat().st_mtime < first_t:
                continue
            log = d / "rtl_sim.log"
            if not log.exists():
                continue
            text = log.read_text(errors="replace")
            verdicts.setdefault(name, []).append(bool(PASSED.search(text)))
    for name in sorted(set(verdicts) - in_plan):
        print(f"WARNING  test '{name}' ran but is in no testpoint")

    results = [{"name": n, "passing": sum(verdicts.get(n, [])), "total": len(verdicts.get(n, []))}
               for n in sorted(in_plan | set(verdicts))]

    cov_results, cg_types, cg_rows, cg_items = [], [], [], {}
    if args.cov_dir and args.cov_dir.is_dir():
        code = parse_summary(args.cov_dir / "cov_riscv.txt")
        top = next((cells for n, cells in code if n in CORE_ROWS), None)
        # Toggle is scored on ibex_top's ports only (ibex_cover.ccf): the core row has none.
        top_row = next((cells for n, cells in parse_summary(args.cov_dir / "cov_riscv_top.txt")
                        if n == "ibex_top"), [])
        port_toggle = next(((p, d) for m, p, d in top_row if m == "Toggle" and p != "n/a"), None)
        if top:
            seen = set()
            for metric, pct, det in top:
                if metric == "Toggle" and pct == "n/a" and port_toggle:
                    pct, det = port_toggle
                if metric in seen or pct == "n/a":     # IMC prints Statement twice
                    continue
                seen.add(metric)
                cov_results.append({"name": metric.lower(),
                                    "result": pct + (f" ({det})" if det else "")})
            print("Coverage (cov_riscv.txt, ibex_top.u_ibex_core): "
                  + ", ".join(f"{c['name']} {c['result']}" for c in cov_results))
            # The code metrics again with the JasperGold UNR exclusions applied
            # (formal_cov/unr/unr_excludes.vRefine). run_all_tests.sh deletes cov_combined_unr.txt
            # before every merge and writes it only when the UNR run's coverage model matches, so
            # present means current. A secondary view: the columns above stay the headline.
            unr = next((cells for n, cells in parse_summary(args.cov_dir / "cov_combined_unr.txt")
                        if n in CORE_ROWS), None)
            if unr:
                seen = set()
                for metric, pct, det in unr:
                    if metric in ("Block", "Branch", "Statement", "Expression") \
                            and metric not in seen and pct != "n/a":
                        seen.add(metric)
                        cov_results.append({"name": f"{metric.lower()} (jasper unr excl.)",
                                            "result": pct + (f" ({det})" if det else "")})
                print("Coverage with JasperGold UNR exclusions (cov_combined_unr.txt): "
                      + ", ".join(f"{c['name']} {c['result']}" for c in cov_results if "unr" in c["name"]))
        else:
            print(f"No ibex_top.u_ibex_core row in {args.cov_dir / 'cov_riscv.txt'}")
        for suffix in ("_combined", ""):
            cg_types = cg_types or [(n, c) for n, c in
                                    parse_summary(args.cov_dir / f"cg_summary{suffix}.txt")
                                    if n not in VENDOR_CG_TYPES]
            cg_rows = cg_rows or [r for r in parse_cg_detail(args.cov_dir / f"cg_detail{suffix}.txt")
                                  if r[0] not in VENDOR_CG_TYPES]
            cg_items = cg_items or parse_cg_items(args.cov_dir / f"cg_detail{suffix}.txt")

    if args.html_extra:
        parts = ["<h2>Functional coverage (covergroups)</h2>",
                 "<p>From coverage_combined/ (cg_summary*.txt, cg_detail*.txt). Average is IMC's "
                 "mean over a covergroup's coverpoints and crosses; Covered is bins hit / bins, "
                 "dominated by a few large crosses.</p>"]
        if cg_types:
            parts.append("<h3>Per covergroup type</h3>")
            parts.append(html_table(["Type", "Average", "Covered"],
                                    [[n] + [p + (f" ({d})" if d else "") for _, p, d in cells]
                                     for n, cells in cg_types]))
        if cg_rows:
            parts.append(f"<h3>Per covergroup ({len(cg_rows)})</h3>")
            parts.append(html_table(["Type", "Covergroup", "Average", "Covered"],
                                    [[t, cg, avg, f"{pct} ({c}/{tot})"]
                                     for t, cg, avg, pct, c, tot in cg_rows]))
        if cg_rows and cg_items:
            descs = item_descriptions()
            parts.append("<h3>Per coverpoint and cross</h3>")
            parts.append("<p>Each covergroup's coverpoints and crosses with their coverage (bins hit "
                         "/ bins) and their description and requirements from the verification "
                         "spec's Functional Coverage chapter.</p>")
            for _, cg, avg, pct, c, tot in cg_rows:
                parts.append(f"<h4>{cg}: average {avg}, covered {pct} ({c}/{tot})</h4>")
                parts.append(html_table(
                    ["Coverpoint / cross", "Covered", "Description", "Requirements"],
                    [[f"<code>{n}</code>", f"{p} ({ic}/{it})",
                      md_cell(descs.get(n, ("not described in the spec", ""))[0]),
                      md_cell(descs.get(n, ("", ""))[1])]
                     for n, p, ic, it in cg_items.get(cg, [])]))
        if not cg_types and not cg_rows:
            parts.append("<p>No functional coverage report in the coverage directory.</p>")
        args.html_extra.parent.mkdir(parents=True, exist_ok=True)
        args.html_extra.write_text("\n".join(parts) + "\n")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps({
        "timestamp": datetime.datetime.now().strftime("%Y-%m-%d %H:%M"),
        "test_results": results,
        "cov_results": cov_results,
        # dvsim checks the testplan's covergroups off against these (its progress table)
        "covergroups": sorted(cg for _, cg, *_ in cg_rows),
    }, indent=2) + "\n")
    total = sum(r["total"] for r in results)
    passing = sum(r["passing"] for r in results)
    print(f"{len(results)} tests: {passing}/{total} seeds passed -> {args.out}")


if __name__ == "__main__":
    main()
