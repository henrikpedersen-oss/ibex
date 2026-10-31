#!/usr/bin/env python3
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""Turn saved CHERIoT RTOS test SoC UART logs into a dvsim sim_results file for cheriot-rtos_testplan.hjson.

Reads <logs>/<target>.<build>.uart.log, as saved by `make cheriot-rtos-test-xlm CHERIOT_RTOS_RESULT=<target>`,
and writes the {timestamp, test_results: [{name, passing, total}]} file that
ibex/vendor/lowrisc_ip/util/dvsim/testplanner.py -s reads.

Counting, per test: total is the number of builds the testplan requires it in (the tags of every
testpoint that lists it); passing is how many of those builds have a log that reports it passed.
A required build with no log, or a log that never mentions the test, counts as not passing --
an incomplete run cannot read as a pass. A FAIL anywhere in a build's logs outranks a PASS in the
same build.

The cheriot-rtos tests.extra runs (SIM_ONLY_TESTS) print no verdict lines. Each passes only if its
<target>.<build>.sim.txt (the failure-marker grep of run.log that cheriot-rtos-test-xlm keeps) shows the
run ended on the RTOS exit string and holds no other marker, its UART log reports
"Simulation exit code: 0" (local cheriot-rtos patch 0002) and no other code, and the log contains
the lines the test must print (SIM_ONLY_TESTS).
The perf_test runs perf-<config>-lat<n> (boot_performance) pass only if the .sim.txt is as clean,
the log has "All tests finished" and no FAIL line, and both workloads' PERF lines are within the
15M-cycle boot budget.
"""

import argparse
import datetime
import json
import re
import sys
from pathlib import Path

import hjson
import yaml

# The build tag every log carries (<target>.<build>.uart.log). The CHERIoT RTOS test SoC
# (ibex/dv/cheriot-rtos-test-suite) has one build, with the CHERIoT memory subsystem; the Sonata
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
    "121": "rtos_juliet_cwe121_bof",
    "122": "rtos_juliet_cwe122_heap_bof",
    "190": "rtos_juliet_cwe190_int_overflow",
    "415": "rtos_juliet_cwe415_double_free",
    "416": "rtos_juliet_cwe416_uaf",
}

# Targets with no UART verdict lines of their own (cheriot-rtos tests.extra): CHERIOT_RTOS_RESULT target
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

# firmware/perf_test runs (make cheriot-rtos-perf-xlm), kept as perf-<config>-lat<n>: testplan
# perf_<config, '-' as '_'>_lat<n>. Budget: Earl Grey 2's boot, 100 ms at 150 MHz (perf_report.py).
PERF_TARGET = re.compile(r"^perf-(?P<cfg>.+)-lat(?P<lat>\d+)$")
PERF_LINE = re.compile(r": PERF (?P<wl>\S+) cycles (?P<cyc>\d+)\b")
PERF_FAIL = re.compile(r": (FAIL\b|Test\(s\) Failed)")
PERF_WORKLOADS = ("hash_feed_core", "hash_feed_dma")
PERF_BUDGET_CYCLES = 15_000_000

ANSI = re.compile(r"\x1b\[[0-9;]*m")
UART_FAILURE = re.compile(
    r"Invariant failure|One or more tests failed|Test runner: .* failed|: FAIL[: ]|Test\(s\) Failed")
RTOS_LINE = re.compile(r"^Test runner: (?P<name>.+?) (?P<verdict>finished in \d+ cycles|failed)$")
REVOCATION_LINE = re.compile(r"^Revocation barrier: (?P<verdict>PASS|FAIL) (?P<what>phase [123]|sweep|random|base|preempt|race|progress)\b")
# "PASS race" and "PASS progress" are the sweep_race and sweep_progress tests; the others keep their word.
REVOCATION_TESTS = {"race": "revocation_sweep_race", "progress": "revocation_sweep_progress"}
# TRBE: the engine's name in firmware built before the upstream rename
TBRE_INVAL_LINE = re.compile(
    r"^Revocation barrier: (?P<verdict>PASS|FAIL) T(?:BR|RB)E invalidate-only:")
# firmware/dbg_host_test (make cheriot-rtos-dbg-host-xlm): "Debug host: PASS|FAIL tag clear|locked: ..."
DBG_HOST_LINE = re.compile(r"^Debug host: (?P<verdict>PASS|FAIL) (?P<what>tag clear|locked)\b")
DBG_HOST_TESTS = {
    "tag clear": "bus_master_dbg_host_tag_clear",
    "locked": "bus_master_dbg_host_locked",
}
JULIET_LINE = re.compile(r"^.*?: (?P<verdict>PASS|FAIL): CWE-(?P<cwe>\d+)\b")
CHERI_C_LINE = re.compile(r"^.*?: (?P<verdict>PASS|FAIL): clang_purecap_(?P<test>\w+)\b")
EXPECTED_FAILURES = (Path(__file__).resolve().parent.parent /
                     "cheriot-rtos-test-suite/data/expected_failures.yaml")


def expected_failure_verdict(entry, log):
    """True only when one saved log has exactly its declared failure and required passes."""
    lines = [ANSI.sub("", raw).strip() for raw in log.read_text(errors="replace").splitlines()]
    observed = [line for line in lines if re.search(entry["failure"], line)]
    if len(observed) != 1:
        return False, f"expected one {entry['id']} failure, found {len(observed)}"
    for pattern in entry["required_passes"]:
        found = sum(1 for line in lines if re.search(pattern, line))
        if found != 1:
            return False, f"required one /{pattern}/ PASS, found {found}"
    allowed = set(observed + ["Debug host: Test(s) Failed"])
    unexpected = [line for line in lines if UART_FAILURE.search(line) and line not in allowed]
    if unexpected:
        return False, f"unexpected failure: {unexpected[0]}"
    return True, entry["reason"]


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
            name = ("revocation_barrier_" + what if what.startswith("phase")
                    else REVOCATION_TESTS.get(what, "revocation_" + what))
            yield name, m["verdict"] == "PASS"
            continue
        m = TBRE_INVAL_LINE.match(line)
        if m:
            yield "bus_master_tbre_invalidate_only", m["verdict"] == "PASS"
            continue
        m = DBG_HOST_LINE.match(line)
        if m:
            yield DBG_HOST_TESTS[m["what"]], m["verdict"] == "PASS"
            continue
        m = JULIET_LINE.match(line)
        if m and m["cwe"] in JULIET_TESTS:
            yield JULIET_TESTS[m["cwe"]], m["verdict"] == "PASS"
            continue
        m = CHERI_C_LINE.match(line)
        if m:
            yield "cheri_c_" + m["test"], m["verdict"] == "PASS"


def sim_txt_problem(log):
    """Why the run's .sim.txt is not a clean end on the RTOS exit string, or None."""
    sim_txt = log.with_name(log.name[: -len(".uart.log")] + ".sim.txt")
    if not sim_txt.exists():
        return f"no {sim_txt.name}"
    markers = [m for m in sim_txt.read_text(errors="replace").splitlines() if m.strip()]
    others = [m for m in markers if m.strip() != EXIT_SEEN]
    if others:
        return f"{sim_txt.name}: {others[0].strip()}"
    if len(markers) == len(others):
        return f"{sim_txt.name}: the run did not end on the RTOS exit string"
    return None


def perf_verdict(log):
    """(passed, reason) for one perf_test run (boot_performance testpoint)."""
    problem = sim_txt_problem(log)
    if problem:
        return False, problem
    lines = [ANSI.sub("", raw).strip() for raw in log.read_text(errors="replace").splitlines()]
    failed = [line for line in lines if PERF_FAIL.search(line)]
    if failed:
        return False, failed[0]
    if not any(line.endswith(": All tests finished") for line in lines):
        return False, "no 'All tests finished'"
    cycles = {}
    for line in lines:
        m = PERF_LINE.search(line)
        if m:
            cycles[m["wl"]] = int(m["cyc"])
    for wl in PERF_WORKLOADS:
        if wl not in cycles:
            return False, f"no PERF line for {wl}"
        if cycles[wl] > PERF_BUDGET_CYCLES:
            return False, f"{wl}: {cycles[wl]} cycles, over the {PERF_BUDGET_CYCLES} budget"
    return True, ""


def sim_only_verdict(log, checks):
    """(passed, reason) for one tests.extra run: its .sim.txt, exit code and required lines."""
    problem = sim_txt_problem(log)
    if problem:
        return False, problem
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
    expected_failures = yaml.safe_load(EXPECTED_FAILURES.read_text()) or []

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

    # A declared must-fail test is accepted only when its exact failure is present.  This is done
    # after ordinary parsing so an unexpected pass cannot quietly become a report PASS.
    logs_by_target_build = {}
    for log in logs:
        parts = log.name[: -len(".uart.log")].rsplit(".", 1)
        if len(parts) == 2 and parts[1] in BUILDS:
            logs_by_target_build[(parts[0], parts[1])] = log
    for entry in expected_failures:
        for field in ("id", "target", "test", "tracker", "reason", "failure",
                      "required_passes"):
            if not entry.get(field):
                raise RuntimeError(f"{EXPECTED_FAILURES}: entry has no {field}: {entry}")
        if entry["test"] not in required:
            raise RuntimeError(f"{EXPECTED_FAILURES}: expected-failure test {entry['test']!r} "
                               "is absent from the testplan")
        for build in required.get(entry["test"], set()):
            log = logs_by_target_build.get((entry["target"], build))
            if log is None:
                continue
            passed, reason = expected_failure_verdict(entry, log)
            verdict[(entry["test"], build)] = passed
            label = "PASS (must fail)" if passed else "FAIL (must fail mismatch)"
            print(f"{label} {entry['test']}: {entry['id']} -- {reason}")

    # Sim-only targets (no UART verdict lines): sim_only_verdict().
    for log in sorted(args.logs.glob("*.uart.log")):
        parts = log.name[: -len(".uart.log")].rsplit(".", 1)
        if len(parts) != 2 or parts[1] not in BUILDS:
            continue
        target, build = parts
        mp = PERF_TARGET.match(target)
        if mp:
            test_name = f"perf_{mp['cfg'].replace('-', '_')}_lat{mp['lat']}"
            verdict_fn = perf_verdict
        elif target in SIM_ONLY_TESTS:
            test_name, checks = SIM_ONLY_TESTS[target]
            verdict_fn = lambda log, checks=checks: sim_only_verdict(log, checks)
        else:
            continue
        if test_name not in required:
            print(f"warning: {log.name}: sim-only test '{test_name}' is not in the testplan",
                  file=sys.stderr)
            continue
        passed, reason = verdict_fn(log)
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
