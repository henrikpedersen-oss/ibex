#!/usr/bin/env python3
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""Mutation check for the CHERIoT RTOS test suites: does breaking a hardware check make a test fail?

Each mutation (ibex/dv/cheriot-rtos-test-suite/dv/tb/cheriot_rtos_tb.sv, +cheriot_rtos_mutate=<name>)
forces one check off. For each, RUNS lists the runs that exercise it and the tests that must then
report FAIL. A test that still passes with the check broken is not testing that check.

A test that fails on the unmutated design (a finding) has the opposite problem: it must be shown
to be able to pass. CONTROLS lists runs with a fix model instead of a mutation (also selected with
+cheriot_rtos_mutate=<name>), and the tests that must then report PASS.

  --list-runs   print "<mutation>|<make arguments>" per run, in build order, for the Makefile
  --check       read <results>/<mutation>/ and report, per expectation:
                  CAUGHT   the test reported FAIL
                  MISSED   the test reported PASS with the check broken
                  NO LOG   the run left no UART log (it did not run, or died before the UART)
                  CRASHED  the log never reports the test: the run failed before reaching it,
                           so the suite noticed, but not through this test
                and for a control, per expectation:
                  PASSES       the test reported PASS with the fix model
                  STILL FAILS  the test reported FAIL even with the fix model
                and for a monitor mutation:
                  CAUGHT   the testbench monitor's error is in the run's simulator summary
                  MISSED   it is not: the monitor did not fire with the fault injected
                and INACTIVE if the run's simulator summary lacks "MUTATION <name> active".
                DISABLED lists the mutations in DISABLED, which are not run (not a failure).
                Exits non-zero on any MISSED, STILL FAILS, CRASHED control, INACTIVE or NO LOG
                of a monitor mutation.
"""

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cheriot_rtos_results import parse_log  # noqa: E402  (same verdict parsing as the report)

# Every run is in the one build (the CHERIoT memory subsystem; build tag "cheriot_mem"). The Sonata
# flow's default and REVOCATION=1 builds are gone, so their runs moved here: the CHERI-C mutations
# and the revocation_test barrier mutations now run with the memory subsystem in.
# (mutation, make arguments, [(test, build) that must FAIL]). REBUILD=1 on the first run only; the
# mutation itself is a plusarg and needs no rebuild.
#
# The CHERI-C and Juliet fault tests pass only on their expected capcause (firmware/common/
# expected_fault.hh), so a broken check that lets the access through and faults later is a FAIL.
RUNS = [
    ("bounds_off", "cheriot-rtos-cheri-c-xlm REBUILD=1", [("cheri_c_array", "cheriot_mem")]),
    ("ldst_perm_off", "cheriot-rtos-cheri-c-xlm", [("cheri_c_input", "cheriot_mem"),
                                             ("cheri_c_output", "cheriot_mem")]),
    # Not cheri_c_badcall: its call is through an untagged pointer, which CJALR rejects on the tag
    # before it checks Permit_Execute, in the mutated design as in the unmutated one.
    ("exec_off", "cheriot-rtos-cheri-c-xlm", [("cheri_c_noexec_call", "cheriot_mem")]),
    ("datastore_tag", "cheriot-rtos-cheri-c-xlm", [("cheri_c_union", "cheriot_mem")]),
    ("barrier_none", "cheriot-rtos-revocation-xlm", [("revocation_barrier_phase2", "cheriot_mem"),
                                               ("revocation_random", "cheriot_mem"),
                                               ("revocation_base", "cheriot_mem"),
                                               ("revocation_preempt", "cheriot_mem"),
                                               ("revocation_sweep_race", "cheriot_mem")]),
    # Not bus_master_tbre_invalidate_only: it checks that the sweep writes nothing but tag
    # clears, which a TBRE that writes nothing at all satisfies. revocation_sweep checks that the
    # revoked capability was cleared.
    ("tbre_no_inval", "cheriot-rtos-revocation-xlm", [("revocation_sweep", "cheriot_mem"),
                                                ("revocation_random", "cheriot_mem"),
                                                ("revocation_sweep_race", "cheriot_mem")]),
    # Not juliet_cwe190_int_overflow: its wrapped cursor is unrepresentable, so the tag is
    # cleared and the store faults on the tag before it reaches the bounds check.
    ("bounds_off", "cheriot-rtos-juliet-xlm", [("juliet_cwe121_bof", "cheriot_mem"),
                                         ("juliet_cwe122_heap_bof", "cheriot_mem")]),
    ("barrier_none", "cheriot-rtos-suite-tests-xlm", [("rtos_test_allocator", "cheriot_mem")]),
    # The debug-access gate on the debug module's system bus access stuck open.
    ("dbg_lock_open", "cheriot-rtos-dbg-host-xlm", [("bus_master_dbg_host_locked", "cheriot_mem")]),
]

# Fix models: (name, make arguments, [(test, build) that must PASS]). bus_master_dbg_host_tag_clear
# fails on the design (SBA bypasses the memory subsystem's tag filter); with the testbench clearing
# the tag of every SBA write to the SRAM it must pass, or the test cannot tell the two apart.
CONTROLS = [
    ("sba_tag_clear_model", "cheriot-rtos-dbg-host-xlm",
     [("bus_master_dbg_host_tag_clear", "cheriot_mem")]),
]

# Monitor mutations: (mutation, make arguments, regex the run's simulator summary must match).
# They inject a fault the firmware cannot see, only a testbench monitor can: the memory
# subsystem's fatal errors and the rev_ctl shim's sticky error are wired to nothing in the SoC
# (tb/cheriot_rtos_tb.sv tbre_monitor). The summary keeps the monitors' error lines (Makefile,
# cheriot-rtos-test-xlm).
MONITORS = [
    ("tbre_read_err", "cheriot-rtos-revocation-xlm", r"\[tbre_monitor\] \d+: rev_ctl shim: sweep failed"),
    ("tbre_fatal", "cheriot-rtos-revocation-xlm", r"\[tbre_monitor\] \d+: fatal errors 0+ -> [01]*1"),
]

# Mutations that are not run, with the reason; --check lists each as DISABLED (not a failure) so
# the missing check stays visible. Put one back in RUNS once its mutation works.
DISABLED = [
    # Meant to revoke only revocation_test's barrier object (an unrestricted force strips every
    # SRAM capability and the RTOS cannot boot; see the testbench), but the restricted force stops
    # the boot too: the core traps at 0x00100000 about 1760 cycles in, before any UART output, in
    # every run so far (2026-10-10, 10-11, 10-14), so phase 1 and 3 never report. Cause not found.
    ("barrier_all", "cheriot-rtos-revocation-xlm", [("revocation_barrier_phase1", "cheriot_mem"),
                                              ("revocation_barrier_phase3", "cheriot_mem")],
     "the restricted force still stops the RTOS boot (trap loop at 0x00100000); cause not found"),
]

# Make target -> the CHERIOT_RTOS_RESULT name it saves its log under (Makefile).
RESULT_NAME = {
    "cheriot-rtos-cheri-c-xlm": "cheri-c",
    "cheriot-rtos-juliet-xlm": "juliet",
    "cheriot-rtos-revocation-xlm": "revocation",
    "cheriot-rtos-suite-tests-xlm": "rtos-tests",
    "cheriot-rtos-dbg-host-xlm": "dbg-host",
}


def check(results):
    ok = True
    runs = [(m, a, e, False) for m, a, e in RUNS] + [(m, a, e, True) for m, a, e in CONTROLS]
    for mutation, args, expects, control in runs:
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
                if control:
                    if test not in verdicts:
                        print(f"CRASHED   {head}: {test} never reported -- the run failed before it")
                        ok = False
                    elif verdicts[test]:
                        print(f"PASSES    {head}: {test} PASSED with the fix model")
                    else:
                        print(f"STILL FAILS {head}: {test} FAILED even with the fix model")
                        ok = False
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
    for mutation, args, pattern in MONITORS:
        stem = results / mutation / f"{RESULT_NAME[args.split()[0]]}.cheriot_mem"
        sim = Path(f"{stem}.sim.txt")
        head = f"{mutation:14s} make {args}"
        if not sim.exists():
            print(f"NO LOG    {head}: {sim} missing")
            ok = False
            continue
        text = sim.read_text(errors="replace")
        if not re.search(rf"MUTATION {re.escape(mutation)} active", text):
            print(f"INACTIVE  {head}: no 'MUTATION {mutation} active' in {sim} -- the "
                  f"result says nothing about the mutation")
            ok = False
        elif re.search(pattern, text):
            print(f"CAUGHT    {head}: monitor error /{pattern}/")
        else:
            print(f"MISSED    {head}: no monitor error /{pattern}/ in {sim}")
            ok = False
    for mutation, args, expects, why in DISABLED:
        tests = ", ".join(t for t, _ in expects)
        print(f"DISABLED  {mutation:14s} make {args}: not run ({why}); {tests} unchecked")
    return ok


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--list-runs", action="store_true")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--results", type=Path,
                    default=Path("ibex/dv/cheriot-rtos-test-suite/xlm_rtos_out/results/mutations"))
    args = ap.parse_args()
    if args.list_runs:
        for mutation, make_args, _ in RUNS + CONTROLS + MONITORS:
            print(f"{mutation}|{make_args}")
    if args.check:
        sys.exit(0 if check(args.results) else 1)


if __name__ == "__main__":
    main()
