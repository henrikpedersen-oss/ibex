#!/usr/bin/env python3
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""Turn kept TestRIG runs into a dvsim sim_results file for testrig_testplan.hjson.

Reads xlm_testrig_out/results/<name>.result and <name>.run.log (written by run_all_tests.sh
after every TestRIG run), judges each run against the closure rules in
ibex_cheriot_verification_spec.md, and writes {timestamp, test_results: [{name, passing, total}]}.
Only Xcelium runs are graded; Verilator runs (vlt_testrig_out) are not read.

  clean run      testrig_<flavour>: the run passed, the scoreboard compared > 0 instructions with
                 0 mismatches, and it ran at full size (not pipeclean, N unset or >= 100)
  fault injection testrig_<flavour>_corrupt_<field>: the run FAILED, the
                 "+dii_sb_corrupt: corrupted <field>" line is present, the first mismatch is at
                 the corrupted PC, and there is no "never applied" error

Per test, total is the number of simulators the testplan requires (its tags) and passing the number
whose kept run is accepted. A simulator with no kept run counts as not passing.

Also reported, when present:
  reference models  the sail_* fields every kept run records (model, vendored source, tree state and
                    a hash of the DPI library it loaded), grouped per simulator and flavour; runs
                    that disagree are flagged
  coverage          the merged TestRIG database's reports in xlm_testrig_out/coverage_report/
                    (written by run_all_tests.sh's coverage merge): code coverage of ibex_top goes
                    into dvsim's cov_results table; functional coverage per covergroup type, and the
                    Sail models, into an HTML section (--html-extra) appended to the report
"""

import argparse
import datetime
import json
import re
from pathlib import Path

import hjson

SIMS = ("xlm",)
COMPARED = re.compile(r"(\w+): (\d+) instructions compared, (\d+) mismatches")
INJECTED = re.compile(r"\+dii_sb_corrupt: corrupted (\w+) of pc=0x([0-9a-fA-F]{8})")
MISMATCH = re.compile(r"UVM_ERROR .*pc=0x([0-9a-fA-F]{8}) insn=0x[0-9a-fA-F]{8}: ")
FULL_SIZE_N = 100
SAIL_FIELDS = ("sail_model", "sail_source", "sail_tree", "sail_lib_sha256")
PCT = re.compile(r"(n/a|\d+(?:\.\d+)?%)(?:\s*\(([\d/]+)\))?")


def read_result(path):
    fields = {}
    for line in path.read_text(errors="replace").splitlines():
        key, _, value = line.partition("=")
        fields[key] = value
    return fields


def judge(result, log_text):
    """Return (accepted, reason) for one kept run."""
    name = result.get("name", "")
    m = re.search(r"_corrupt_(\w+)$", name)
    compared = [(t, int(n), int(k)) for t, n, k in COMPARED.findall(log_text)]
    if not compared:
        # No scoreboard report: the simulation never got going (e.g. *F,C58EXS on 2026-09-30).
        fatal = re.search(r"\*[EF],\w+:[^\n]*", log_text)
        return False, "simulation did not run" + (f": {fatal.group(0)[:100]}" if fatal else "")
    if m:
        field = m.group(1)
        inj = INJECTED.search(log_text)
        if result.get("status") != "FAIL":
            return False, "fault-injection run did not fail"
        if "never applied" in log_text:
            return False, "injection never applied"
        if not inj or inj.group(1) != field:
            return False, f"no '+dii_sb_corrupt: corrupted {field}' line"
        # First mismatch of the whole run: a genuine mismatch before the injection must not hide.
        first = MISMATCH.search(log_text)
        if not first:
            return False, "no scoreboard mismatch reported"
        if first.group(1).lower() != inj.group(2).lower():
            return False, (f"first mismatch at pc=0x{first.group(1)}, "
                           f"corruption at pc=0x{inj.group(2)}")
        return True, f"corrupted {field} at pc=0x{inj.group(2)} was the first mismatch"
    if result.get("status") != "PASS":
        return False, f"run failed (rc {result.get('rc', '?')})"
    if not compared or max(n for _, n, _ in compared) == 0:
        return False, "no instructions compared"
    if any(k for _, _, k in compared):
        return False, "mismatches reported"
    if result.get("pipeclean") == "1":
        return False, "pipeclean run (not full size)"
    n = result.get("n", "")
    if n and int(n) < FULL_SIZE_N:
        return False, f"N={n} (full size is N >= {FULL_SIZE_N})"
    total = max(n for _, n, _ in compared)
    return True, f"{total} instructions compared, 0 mismatches"


def parse_summary(path):
    """IMC 'report -summary' text: header names, then rows of 'pct (covered/total)' cells.

    Returns [(row_name, [(metric, pct, detail), ...]), ...]; [] if the file is missing."""
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
    """Per-covergroup rows from IMC 'report -detail -type -metrics covergroup'.

    The text form of that report is not yet proven on the nyx IMC version, so this only takes lines
    that name a covergroup (ending in _cg) and carry a percentage; returns [] otherwise."""
    if not path.exists():
        return []
    rows = []
    for line in path.read_text(errors="replace").splitlines():
        m = re.match(r"\s*(?:[|`-]+\s*)?([\w.:]*?(\w+_cg))\b\s+(.*)$", line)
        if not m:
            continue
        cells = PCT.findall(m.group(3))
        if cells:
            rows.append((m.group(2), cells))
    seen, uniq = set(), []
    for name, cells in rows:
        if name not in seen:
            seen.add(name)
            uniq.append((name, cells))
    return uniq


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
    ap.add_argument("--testrig-dir", required=True, type=Path,
                    help="ibex/dv/testrig (holds <sim>_testrig_out/results/)")
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--html-extra", type=Path,
                    help="write an HTML section (reference models, coverage) to append to the report")
    args = ap.parse_args()

    required = {}
    for tp in hjson.loads(args.testplan.read_text()).get("testpoints", []):
        sims = {t for t in tp.get("tags", []) if t in SIMS}
        for test in tp.get("tests", []):
            required.setdefault(test, set()).update(sims)

    verdict = {}
    models = {}   # (sim, flavour) -> {sail tuple: [run names]}
    for sim in SIMS:
        rdir = args.testrig_dir / f"{sim}_testrig_out" / "results"
        results = sorted(rdir.glob("*.result"))
        print(f"{sim}: {len(results)} kept run(s) in {rdir}")
        for rpath in results:
            result = read_result(rpath)
            test = "testrig_" + result.get("name", rpath.stem)
            sail = tuple(result.get(f, "") for f in SAIL_FIELDS)
            models.setdefault((sim, result.get("flavour", "?")), {}).setdefault(
                sail, []).append(result.get("name", rpath.stem))
            log = rpath.with_suffix(".run.log")
            if not log.exists():
                ok, why = False, f"no kept log {log.name}"
            else:
                ok, why = judge(result, log.read_text(errors="replace"))
            print(f"  {'ACCEPT' if ok else 'REJECT'}  {test:32s} {result.get('date', '')}  {why}")
            if test in required:
                verdict[(test, sim)] = ok
            else:
                print(f"           ('{test}' is not in the testplan)")

    results = []
    for test in sorted(required):
        sims = required[test]
        passing = sum(1 for s in sims if verdict.get((test, s)) is True)
        results.append({"name": test, "passing": passing, "total": len(sims)})
        missing = sorted(s for s in sims if (test, s) not in verdict)
        if missing:
            print(f"NOT RUN  {test}: {', '.join(missing)}")
    # Reference models behind the kept runs.
    print("Reference models (Sail) of the kept runs:")
    model_rows = []
    for (sim, flavour), variants in sorted(models.items()):
        for sail, names in sorted(variants.items()):
            model, source, tree, sha = sail
            if not model:
                model, source, tree, sha = ("not recorded", "run kept before the model was logged",
                                            "", "")
            flag = " (MIXED: kept runs used different models)" if len(variants) > 1 else ""
            print(f"  {sim}/{flavour}: {model} {source} [{tree}] lib {sha or '?'} "
                  f"({len(names)} run(s)){flag}")
            model_rows.append((sim, flavour, model + flag, source, tree, sha, len(names)))

    # Merged coverage (xlm only: Verilator collects none).
    cov_dir = args.testrig_dir / "xlm_testrig_out" / "coverage_report"
    code = parse_summary(cov_dir / "cov_summary.txt")
    cg_types = parse_summary(cov_dir / "cg_summary.txt")
    cg_detail = parse_cg_detail(cov_dir / "cg_detail.txt")
    info = read_result(cov_dir / "merge_info.txt") if (cov_dir / "merge_info.txt").exists() else {}
    cov_results = []
    top = next((cells for name, cells in code if name == "ibex_top"), None)
    if top:
        seen = set()
        for metric, pct, det in top:
            if metric in seen:          # IMC prints Statement twice
                continue
            seen.add(metric)
            cov_results.append({"name": metric.lower(),
                                "result": pct + (f" ({det})" if det else "")})
        print("Merged code coverage (ibex_top): "
              + ", ".join(f"{c['name']} {c['result']}" for c in cov_results))
    else:
        print(f"No merged TestRIG coverage report in {cov_dir} (run TestRIG with COVERAGE=1)")
    if cg_detail:
        print(f"Functional coverage: {len(cg_detail)} covergroup type(s) in cg_detail.txt")
    elif cg_types:
        print("Functional coverage: per covergroup interface type only (cg_detail.txt has no "
              "covergroup rows)")

    if args.html_extra:
        parts = ["<h2>Reference models</h2>",
                 "<p>The Sail model each kept run was checked against (the flavour selects the "
                 "scoreboard: cheriot uses CHERIoT-Sail, riscv uses RISC-V Sail).</p>"]
        parts.append(html_table(["Simulator", "Flavour", "Model", "Vendored from", "Tree",
                                 "DPI library sha256", "Kept runs"], model_rows)
                     if model_rows else "<p>No kept runs.</p>")
        parts.append("<h2>Merged coverage (Xcelium)</h2>")
        if top:
            runs = info.get("runs", "?")
            flav = {}
            for line in (cov_dir / "merge_info.txt").read_text().splitlines():
                if line.startswith("run="):
                    f = line[4:].split("_", 1)[0]
                    flav[f] = flav.get(f, 0) + 1
            parts.append(f"<p>{runs} run database(s) merged on {info.get('merged', '?')} ("
                         + ", ".join(f"{n} {f}" for f, n in sorted(flav.items()))
                         + "), both flavours in one union, so these numbers are for the whole "
                         "TestRIG campaign, not one flavour. Fault-injection runs are included: "
                         "the injector corrupts only the scoreboard's copy of a record.</p>")
            parts.append("<h3>Code coverage, ibex_top</h3>")
            parts.append(html_table([c["name"].capitalize() for c in cov_results],
                                    [[c["result"] for c in cov_results]]))
        else:
            parts.append(f"<p>No merged coverage report in {cov_dir}: run TestRIG with "
                         "COVERAGE=1; the coverage merge at the end of the run writes it.</p>")
        parts.append("<h3>Functional coverage</h3>")
        if cg_detail:
            parts.append(html_table(["Covergroup"] + [f"col{i}" for i in
                                                       range(max(len(c) for _, c in cg_detail))],
                                    [[n] + [p + (f" ({d})" if d else "") for p, d in c]
                                     for n, c in cg_detail]))
        if cg_types:
            if not cg_detail:
                parts.append("<p>Per covergroup interface type (cg_detail.txt gave no "
                             "per-covergroup rows).</p>")
            parts.append(html_table(["Covergroup type", "Average", "Covered"],
                                    [[n] + [p + (f" ({d})" if d else "") for _, p, d in cells]
                                     for n, cells in cg_types]))
        if not cg_detail and not cg_types:
            parts.append("<p>No functional coverage report.</p>")
        args.html_extra.parent.mkdir(parents=True, exist_ok=True)
        args.html_extra.write_text("\n".join(parts) + "\n")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps({
        "timestamp": datetime.datetime.now().strftime("%Y-%m-%d %H:%M"),
        "test_results": results,
        "cov_results": cov_results,
    }, indent=2) + "\n")
    total = sum(r["total"] for r in results)
    passing = sum(r["passing"] for r in results)
    print(f"{len(results)} tests: {passing}/{total} test x simulator results accepted -> {args.out}")


if __name__ == "__main__":
    main()
