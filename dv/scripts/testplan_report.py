#!/usr/bin/env python3
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""Testplan report: descriptions from the testplan hjson, pass/fail and coverage from the run.

Same arguments as ibex/vendor/lowrisc_ip/util/dvsim/testplanner.py, plus coverage options. The
testplan is loaded with dvsim's Testplan class.

  without -s   dvsim's testplan document (Markdown), unchanged
  with -s      an HTML report with two parts only:
                 Testpoints  each testpoint's description and every test's passing/total
                 Coverage    each covergroup of the --cg-detail report: its coverpoints and crosses
                             with their coverage, and their description from the testplan's
                             covergroups (a bullet that names the item, else the covergroup's)
--cg-detail     IMC 'report -detail -type -metrics covergroup' text (none: no coverage part)
--cov-testplan  further testplan(s) to take covergroup descriptions from (e.g. TestRIG, whose
                testplan has no covergroups, uses core_ibex_testplan.hjson)
"""

import argparse
import html
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "vendor/lowrisc_ip/util/dvsim"))
import hjson  # noqa: E402
import mistletoe  # noqa: E402
import Testplan  # noqa: E402

CG_ROW = re.compile(r"^(\w+)\s+(\d+\.?\d*)%,\s+(\d+\.?\d*)%\s+\((\d+)/(\d+)\)")
CG_ITEM = re.compile(r"^\|--(\w+)\s+(\d+\.?\d*)%\s+\((\d+)/(\d+)\)")
VENDOR_CGS = ("push_pull_cg",)

CSS = """<style>
body { font-family: sans-serif; margin: 1.5em; }
table { border-collapse: collapse; margin-bottom: 1.2em; width: 100%; }
th, td { border: 1px solid #ccc; padding: 4px 8px; vertical-align: top; text-align: left; }
th { background: #eee; }
td.num { white-space: nowrap; text-align: right; }
.pass { color: #1a7f37; font-weight: bold; } .fail { color: #cf222e; font-weight: bold; }
.notrun { color: #888; font-weight: bold; }
.desc p { margin: 0 0 0.4em 0; } .desc ul { margin: 0 0 0.4em 1.2em; padding: 0; }
</style>"""


def md(text):
    return mistletoe.markdown(text.strip())


def desc_lines(desc):
    return [line.strip() for line in desc.strip().splitlines()]


def blocks(desc):
    """Paragraphs and bullets of a desc, each joined into one line."""
    out, cur = [], None
    for line in desc_lines(desc):
        if not line:
            cur = None
        elif line.startswith("- "):
            cur = [line[2:]]
            out.append(cur)
        elif cur is None:
            cur = [line]
            out.append(cur)
        else:
            cur.append(line)
    return [" ".join(b) for b in out]


def item_descriptions(cg_desc):
    """{item: text} from a covergroup desc: a bullet 'a, b: text' describes a and b; a paragraph
    'Described in ... section 'S': a, b.' points a and b there; otherwise the first bullet or
    paragraph that names the item."""
    found, bs = {}, blocks(cg_desc)
    for b in bs:
        m = re.match(r"([\w ,/()]+?):\s+(.*)", b)
        if m and re.search(r"\b(cp_|\w+_cross\b|\w+_cp\b)", m.group(1)):
            for n in re.findall(r"\w+", m.group(1)):
                found.setdefault(n, m.group(2))
        m = re.match(r"Described in the verification spec, section '([^']+)': (.*)\.$", b)
        if m:
            for n in re.findall(r"\w+", m.group(2)):
                found.setdefault(n, f"Described in the verification spec, section '{m.group(1)}'.")
    for b in bs:
        for n in re.findall(r"\b\w+\b", b):
            found.setdefault(n, b)
    return found


def parse_cg_detail(path):
    """[(covergroup, average, covered%, covered, total, [(item, pct, covered, total)])]."""
    cgs = []
    for line in Path(path).read_text(errors="replace").splitlines():
        m = CG_ROW.match(line)
        if m:
            cgs.append((m.group(1), m.group(2) + "%", m.group(3) + "%", int(m.group(4)),
                        int(m.group(5)), []))
            continue
        m = CG_ITEM.match(line)
        if m and cgs:
            cgs[-1][5].append((m.group(1), m.group(2) + "%", int(m.group(3)), int(m.group(4))))
    seen, uniq = set(), []
    for cg in cgs:  # a type reported twice (per-instance repeats) is listed once
        if cg[0] not in seen and cg[0] not in VENDOR_CGS:
            seen.add(cg[0])
            uniq.append(cg)
    return uniq


def verdict(passing, total):
    if total == 0:
        return '<span class="notrun">NOT RUN</span>'
    if passing == total:
        return '<span class="pass">PASS</span>'
    return '<span class="fail">FAIL</span>'


def report(testplan_path, results_path, cg_detail, cov_testplans):
    tp = Testplan.Testplan(testplan_path)
    results = hjson.loads(Path(results_path).read_text())
    res = {r["name"]: (r["passing"], r["total"]) for r in results.get("test_results", [])}

    out = ["<!DOCTYPE html><html><head><meta charset=\"utf-8\">",
           f"<title>{html.escape(tp.name)} testplan report</title>", CSS, "</head><body>",
           f"<h1>{html.escape(tp.name)}: testplan report</h1>",
           f"<p>Run of {html.escape(str(results.get('timestamp', '?')))}.</p>"]

    # Testpoints
    n_pass = n_fail = n_notrun = 0
    rows = []
    for t in tp.testpoints:
        tests, p_sum, t_sum, cells = list(t.tests), 0, 0, []
        for name in tests:
            p, tot = res.get(name, (0, 0))
            p_sum += p
            t_sum += tot
            cells.append(f"<code>{html.escape(name)}</code> {verdict(p, tot)} {p}/{tot}")
        v = verdict(p_sum, t_sum) if tests else '<span class="notrun">NO TESTS</span>'
        n_pass += t_sum > 0 and p_sum == t_sum
        n_fail += t_sum > 0 and p_sum < t_sum
        n_notrun += t_sum == 0
        rows.append(f"<tr><td><code>{html.escape(t.name)}</code><br>{html.escape(t.stage)}</td>"
                    f"<td class=\"desc\">{md(t.desc)}</td><td>{'<br>'.join(cells)}</td>"
                    f"<td>{v}<br>{p_sum}/{t_sum}</td></tr>")
    out.append("<h2>Testpoints</h2>")
    out.append(f"<p>{len(tp.testpoints)} testpoints: <span class=\"pass\">{n_pass} pass</span>, "
               f"<span class=\"fail\">{n_fail} fail</span>, "
               f"<span class=\"notrun\">{n_notrun} not run</span>.</p>")
    out.append("<table><tr><th>Testpoint</th><th>Description</th><th>Tests (passing/total)</th>"
               "<th>Result</th></tr>" + "".join(rows) + "</table>")

    # Code coverage (uvm_results.py: the merged regression's ibex_top/u_ibex_core row, then the code
    # metrics with the JasperGold UNR exclusions when that report exists).
    cov = results.get("cov_results", [])
    if cov:
        out.append("<h2>Code coverage</h2>")
        out.append("<p>Main core (<code>ibex_top/u_ibex_core</code>) of the merged regression. "
                   "\"jasper unr excl.\" rows: the same database with "
                   "<code>formal_cov/unr/unr_excludes.vRefine</code> applied, so items JasperGold UNR "
                   "proved unreachable leave the denominator; a secondary view until those exclusions "
                   "are reviewed.</p>")
        out.append("<table><tr><th>Metric</th><th>Covered</th></tr>"
                   + "".join(f"<tr><td>{html.escape(c['name'])}</td><td>{html.escape(c['result'])}</td></tr>"
                             for c in cov) + "</table>")

    # Coverage
    if cg_detail:
        descs = {c.name: c.desc for c in tp.covergroups}
        for extra in cov_testplans or []:
            for c in Testplan.Testplan(extra).covergroups:
                descs.setdefault(c.name, c.desc)
        out.append("<h2>Functional coverage</h2>")
        if not Path(cg_detail).exists():
            out.append(f"<p>No coverage report ({html.escape(str(cg_detail))}).</p>")
        for name, avg, pct, cov, tot, items in parse_cg_detail(cg_detail) if Path(cg_detail).exists() else []:
            desc = descs.get(name, "")
            title = desc_lines(desc)[0] if desc else "not in the testplan"
            out.append(f"<h3><code>{html.escape(name)}</code>: {pct} ({cov}/{tot} bins), "
                       f"average {avg}</h3><p>{html.escape(title)}</p>")
            idesc = item_descriptions(desc) if desc else {}
            out.append("<table><tr><th>Coverpoint / cross</th><th>Description</th>"
                       "<th>Coverage</th></tr>" + "".join(
                           f"<tr><td><code>{html.escape(n)}</code></td>"
                           f"<td class=\"desc\">{md(idesc.get(n, ''))}</td>"
                           f"<td class=\"num\">{p} ({c}/{t})</td></tr>"
                           for n, p, c, t in items) + "</table>")
    out.append("</body></html>")
    return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("testplan", metavar="<hjson-file>")
    ap.add_argument("-s", "--sim_results", metavar="<hjson-file>")
    ap.add_argument("--outfile", "-o", type=argparse.FileType("w"), default=sys.stdout)
    ap.add_argument("--cg-detail", metavar="<txt>")
    ap.add_argument("--cov-testplan", metavar="<hjson-file>", action="append")
    args = ap.parse_args()

    with args.outfile as out:
        if not args.sim_results:
            Testplan.Testplan(args.testplan).write_testplan_doc(out)
            out.write("\n")
            return
        out.write(report(args.testplan, args.sim_results, args.cg_detail, args.cov_testplan))


if __name__ == "__main__":
    main()
