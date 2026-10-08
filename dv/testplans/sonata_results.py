#!/usr/bin/env python3
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""Turn saved Sonata UART logs into a dvsim sim_results file for sonata_testplan.hjson.

Reads <logs>/<target>.<build>.uart.log, as saved by `make sonata-test-xlm SONATA_RESULT=<target>`,
and writes the {timestamp, test_results: [{name, passing, total}]} file that
ibex/vendor/lowrisc_ip/util/dvsim/testplanner.py -s reads.

Counting, per test: total is the number of builds the testplan requires it in (the tags of every
testpoint that lists it); passing is how many of those builds have a log that reports it passed.
A required build with no log, or a log that never mentions the test, counts as not passing --
an incomplete run cannot read as a pass. A FAIL anywhere in a build's logs outranks a PASS in the
same build.

The cheriot-rtos tests.extra runs (SIM_ONLY_TESTS) print no verdict lines. Each passes only if its
<target>.<build>.sim.txt (the failure-marker grep of run.log that sonata-test-xlm keeps) shows the
run ended on the RTOS exit string and holds no other marker, its UART log reports
"Simulation exit code: 0" (local cheriot-rtos patch 0002) and no other code, and the log contains
the lines the test must print (SIM_ONLY_TESTS).
"""

import argparse
import datetime
import json
import re
import sys
from pathlib import Path

import hjson

# The build tag every log carries (<target>.<build>.uart.log). The CHERIoT RTOS test SoC
# (ibex/dv/cheriot-rtos-test-suites) has one build, with the CHERIoT memory subsystem; the Sonata
# flow's "default" and "revocation" builds are gone, and logs tagged with them are skipped.
BUILDS = ("cheriot_mem",)

# cheriot-rtos/tests/test-runner.cc: run_timed("<display name>", <function>).
RTOS_TESTS = {
    "Debug helpers (C++)": "test_debug_cxx",
    "Debug helpers (C)": "test_debug_c",
    "MMIO": "test_mmio",
    "Unwind cleanup": "test_unwind_cleanup",
    "stdio": "test_stdio",
    "Static sealing": "test_static_sealing",
    "Crash recovery": "test_crash_recovery",
    "Compartment calls": "test_compartment_call",
    "check_pointer": "test_check_pointer",
    "Misc APIs": "test_misc",
    "Stacks exhaustion in the switcher": "test_stack",
    "Thread pool": "test_thread_pool",
    "Global Constructors": "test_global_constructors",
    "Queue": "test_queue",
    "Futex": "test_futex",
    "Locks": "test_locks",
    "List": "test_list",
    "Event groups": "test_eventgroup",
    "Multiwaiter": "test_multiwaiter",
    "Allocator": "test_allocator",
}

# examples/juliet_cwe/juliet_orchestrator.cc reports "CWE-nnn".
JULIET_TESTS = {
    "121": "juliet_cwe121_bof",
    "122": "juliet_cwe122_heap_bof",
    "190": "juliet_cwe190_int_overflow",
    "415": "juliet_cwe415_double_free",
    "416": "juliet_cwe416_uaf",
}

# Targets with no UART verdict lines of their own (cheriot-rtos tests.extra): SONATA_RESULT target
# name (the "<target>" in <target>.<build>.uart.log) -> (testplan name, [(regex, count)]): each
# regex must match exactly count lines of the ANSI-stripped UART log.
SIM_ONLY_TESTS = {
    # top1 writes 1 through the read-write import, top2 reads it through the read-only one.
    "regress-drs": ("regress_drs", [(r"^top2: ref2: 1$", 1)]),
    # Prints nothing; the check is that the thread's exit reaches the scheduler without a panic.
    "regress-tei": ("regress_tei", []),
    # Ten waits, each completed within its timeout (a timeout asserts and exits with code 1).
    "hwrev-irq": ("hwrev_irq", [(r"^top: After wait: for \S+, result true, ", 10)]),
}
# The line uartdpi prints when the firmware sends the RTOS exit string: in a .sim.txt it is the
# clean end of the run, not a failure marker. Without it the run ended some other way.
EXIT_SEEN = "Exiting the simulator because the magic UART string was seen."
EXIT_CODE_LINE = re.compile(r"^Simulation exit code: (?P<code>\d+)$")

ANSI = re.compile(r"\x1b\[[0-9;]*m")
RTOS_LINE = re.compile(r"^Test runner: (?P<name>.+?) (?P<verdict>finished in \d+ cycles|failed)$")
REVOCATION_LINE = re.compile(r"^Revocation barrier: (?P<verdict>PASS|FAIL) (?P<what>phase [123]|sweep)\b")
TRBE_INVAL_LINE = re.compile(r"^Revocation barrier: (?P<verdict>PASS|FAIL) TRBE invalidate-only:")
JULIET_LINE = re.compile(r"^.*?: (?P<verdict>PASS|FAIL): CWE-(?P<cwe>\d+)\b")
CHERI_C_LINE = re.compile(r"^.*?: (?P<verdict>PASS|FAIL): clang_purecap_(?P<test>\w+)\b")


def parse_log(path):
    """Yield (test, passed) for every verdict line in one UART log."""
    for raw in path.read_text(errors="replace").splitlines():
        line = ANSI.sub("", raw).strip()
        m = RTOS_LINE.match(line)
        if m and m["name"] in RTOS_TESTS:
            yield "rtos_" + RTOS_TESTS[m["name"]], m["verdict"] != "failed"
            continue
        m = REVOCATION_LINE.match(line)
        if m:
            what = m["what"].replace(" ", "")
            name = "revocation_sweep" if what == "sweep" else "revocation_barrier_" + what
            yield name, m["verdict"] == "PASS"
            continue
        m = TRBE_INVAL_LINE.match(line)
        if m:
            yield "bus_master_trbe_invalidate_only", m["verdict"] == "PASS"
            continue
        m = JULIET_LINE.match(line)
        if m and m["cwe"] in JULIET_TESTS:
            yield JULIET_TESTS[m["cwe"]], m["verdict"] == "PASS"
            continue
        m = CHERI_C_LINE.match(line)
        if m:
            yield "cheri_c_" + m["test"], m["verdict"] == "PASS"


def sim_only_verdict(log, checks):
    """(passed, reason) for one tests.extra run: its .sim.txt, exit code and required lines."""
    sim_txt = log.with_name(log.name[: -len(".uart.log")] + ".sim.txt")
    if not sim_txt.exists():
        return False, f"no {sim_txt.name}"
    markers = [m for m in sim_txt.read_text(errors="replace").splitlines() if m.strip()]
    others = [m for m in markers if m.strip() != EXIT_SEEN]
    if others:
        return False, f"{sim_txt.name}: {others[0].strip()}"
    if len(markers) == len(others):
        return False, f"{sim_txt.name}: the run did not end on the RTOS exit string"
    lines = [ANSI.sub("", raw).strip() for raw in log.read_text(errors="replace").splitlines()]
    codes = [m["code"] for m in map(EXIT_CODE_LINE.match, lines) if m]
    if codes != ["0"]:
        return False, f"exit code lines {codes or 'none'}, expected exactly one 0"
    for regex, count in checks:
        found = sum(1 for line in lines if re.search(regex, line))
        if found != count:
            return False, f"{found} line(s) matching '{regex}', expected {count}"
    return True, ""


def required_builds(testplan):
    """Map each test in the testplan to the set of builds it must pass in."""
    required = {}
    for tp in testplan.get("testpoints", []):
        builds = {t for t in tp.get("tags", []) if t in BUILDS}
        for test in tp.get("tests", []):
            required.setdefault(test, set()).update(builds)
    return required


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--testplan", required=True, type=Path)
    ap.add_argument("--logs", required=True, type=Path, help="directory of <target>.<build>.uart.log")
    ap.add_argument("--out", required=True, type=Path)
    args = ap.parse_args()

    required = required_builds(hjson.loads(args.testplan.read_text()))

    # verdict[(test, build)] = True / False; False sticks.
    verdict = {}
    logs = sorted(args.logs.glob("*.uart.log"))
    # Say which runs this report covers: a report taken part-way through a regression shows the
    # later runs as NOT RUN, and without this list that looks like a broken report.
    print(f"Logs in {args.logs}: " + (", ".join(p.name for p in logs) if logs else "none"))
    for p in sorted(args.logs.glob(".*.start")):
        print(f"  still running: {p.name[1:-len('.start')]} (started, no log yet)")
    for log in logs:
        parts = log.name[: -len(".uart.log")].rsplit(".", 1)
        if len(parts) != 2 or parts[1] not in BUILDS:
            print(f"warning: skipping {log.name}: expected <target>.<build>.uart.log with build in "
                  f"{BUILDS}", file=sys.stderr)
            continue
        build = parts[1]
        for test, passed in parse_log(log):
            if test not in required:
                print(f"warning: {log.name}: '{test}' is not in the testplan", file=sys.stderr)
                continue
            key = (test, build)
            verdict[key] = verdict.get(key, True) and passed

    # Sim-only targets (no UART verdict lines): sim_only_verdict().
    for log in sorted(args.logs.glob("*.uart.log")):
        parts = log.name[: -len(".uart.log")].rsplit(".", 1)
        if len(parts) != 2 or parts[1] not in BUILDS:
            continue
        target, build = parts
        if target not in SIM_ONLY_TESTS:
            continue
        test_name, checks = SIM_ONLY_TESTS[target]
        if test_name not in required:
            print(f"warning: {log.name}: sim-only test '{test_name}' is not in the testplan",
                  file=sys.stderr)
            continue
        passed, reason = sim_only_verdict(log, checks)
        if not passed:
            print(f"{log.name}: {reason}")
        key = (test_name, build)
        verdict[key] = verdict.get(key, True) and passed

    results = []
    for test in sorted(required):
        builds = required[test]
        passing = sum(1 for b in builds if verdict.get((test, b)) is True)
        results.append({"name": test, "passing": passing, "total": len(builds)})
        missing = sorted(b for b in builds if (test, b) not in verdict)
        failed = sorted(b for b in builds if verdict.get((test, b)) is False)
        if failed:
            print(f"FAIL     {test}: {', '.join(failed)}")
        if missing:
            print(f"NOT RUN  {test}: {', '.join(missing)}")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps({
        "timestamp": datetime.datetime.now().strftime("%Y-%m-%d %H:%M"),
        "test_results": results,
    }, indent=2) + "\n")
    total = sum(r["total"] for r in results)
    passing = sum(r["passing"] for r in results)
    print(f"{len(logs)} log(s), {len(results)} tests: {passing}/{total} test x build results pass "
          f"-> {args.out}")


if __name__ == "__main__":
    main()
