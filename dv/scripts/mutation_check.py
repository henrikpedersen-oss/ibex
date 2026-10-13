#!/usr/bin/env python3
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""Mutation check for the Sonata test suites: does breaking a hardware check make a test fail?

Each mutation (ibex/dv/cheriot-rtos-test-suites/tb/cheriot_rtos_tb.sv, +sonata_mutate=<name>)
forces one check off. For each, RUNS lists the runs that exercise it and the tests that must then
report FAIL. A test that still passes with the check broken is not testing that check.

  --list-runs   print "<mutation>|<make arguments>" per run, in build order, for the Makefile
  --check       read <results>/<mutation>/ and report, per expectation:
                  CAUGHT   the test reported FAIL
                  MISSED   the test reported PASS with the check broken
                  NO LOG   the run left no UART log (it did not run, or died before the UART)
                  CRASHED  the log never reports the test: the run failed before reaching it,
                           so the suite noticed, but not through this test
                and INACTIVE if the run's simulator summary lacks "MUTATION <name> active".
                Exits non-zero on any MISSED or INACTIVE.
"""

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sonata_results import parse_log  # noqa: E402  (same verdict parsing as the report)

# Every run is in the one build (the CHERIoT memory subsystem; build tag "cheriot_mem"). The Sonata
# flow's default and REVOCATION=1 builds are gone, so their runs moved here: the CHERI-C mutations
# and the revocation_test barrier mutations now run with the memory subsystem in.
# (mutation, make arguments, [(test, build) that must FAIL]). REBUILD=1 on the first run only; the
# mutation itself is a plusarg and needs no rebuild.
RUNS = [
    ("bounds_off", "sonata-cheri-c-xlm REBUILD=1", [("cheri_c_array", "cheriot_mem")]),
    ("ldst_perm_off", "sonata-cheri-c-xlm", [("cheri_c_input", "cheriot_mem"),
                                             ("cheri_c_output", "cheriot_mem")]),
    ("exec_off", "sonata-cheri-c-xlm", [("cheri_c_badcall", "cheriot_mem")]),
    ("datastore_tag", "sonata-cheri-c-xlm", [("cheri_c_union", "cheriot_mem")]),
    ("barrier_none", "sonata-revocation-xlm", [("revocation_barrier_phase2", "cheriot_mem")]),
    ("barrier_all", "sonata-revocation-xlm", [("revocation_barrier_phase1", "cheriot_mem"),
                                              ("revocation_barrier_phase3", "cheriot_mem")]),
    ("tbre_no_inval", "sonata-revocation-xlm", [("revocation_sweep", "cheriot_mem"),
                                                ("bus_master_tbre_invalidate_only",
                                                 "cheriot_mem")]),
    ("bounds_off", "sonata-juliet-xlm", [("juliet_cwe121_bof", "cheriot_mem"),
                                         ("juliet_cwe122_heap_bof", "cheriot_mem"),
                                         ("juliet_cwe190_int_overflow", "cheriot_mem")]),
    ("barrier_none", "sonata-rtos-tests-xlm", [("rtos_test_allocator", "cheriot_mem")]),
]

# Make target -> the SONATA_RESULT name it saves its log under (Makefile).
RESULT_NAME = {
    "sonata-cheri-c-xlm": "cheri-c",
    "sonata-juliet-xlm": "juliet",
    "sonata-revocation-xlm": "revocation",
    "sonata-rtos-tests-xlm": "rtos-tests",
}


def check(results):
    ok = True
    for mutation, args, expects in RUNS:
        target = args.split()[0]
        builds = {b for _, b in expects}
        for build in sorted(builds):
            stem = results / mutation / f"{RESULT_NAME[target]}.{build}"
            log, sim = Path(f"{stem}.uart.log"), Path(f"{stem}.sim.txt")
            head = f"{mutation:14s} make {args}"
            if not log.exists():
                print(f"NO LOG    {head}: {log} missing")
                ok = False
                continue
            active = sim.exists() and re.search(rf"MUTATION {re.escape(mutation)} active",
                                                sim.read_text(errors="replace"))
            if not active:
                print(f"INACTIVE  {head}: no 'MUTATION {mutation} active' in {sim} -- the "
                      f"result says nothing about the mutation")
                ok = False
                continue
            verdicts = {}
            for test, passed in parse_log(log):
                verdicts[test] = verdicts.get(test, True) and passed
            for test, b in expects:
                if b != build:
                    continue
                if test not in verdicts:
                    print(f"CRASHED   {head}: {test} never reported -- the run failed before it")
                elif verdicts[test]:
                    print(f"MISSED    {head}: {test} PASSED with the check broken")
                    ok = False
                else:
                    print(f"CAUGHT    {head}: {test} FAILED")
            collateral = sorted(t for t, p in verdicts.items()
                                if not p and (t, build) not in expects)
            if collateral:
                print(f"          also failed: {', '.join(collateral)}")
    return ok


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--list-runs", action="store_true")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--results", type=Path,
                    default=Path("ibex/dv/cheriot-rtos-test-suites/xlm_rtos_out/results/mutations"))
    args = ap.parse_args()
    if args.list_runs:
        for mutation, make_args, _ in RUNS:
            print(f"{mutation}|{make_args}")
    if args.check:
        sys.exit(0 if check(args.results) else 1)


if __name__ == "__main__":
    main()
