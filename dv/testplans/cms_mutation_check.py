#!/usr/bin/env python3
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""Mutation check for the CHERIoT memory subsystem bench: does a real RTL bug make its tests fail?

Each mutation (ibex/dv/cheriot-mem-subsys/tb/cms_tb.sv, +cms_mutate=<name>) forces one internal
signal of the unmodified subsystem to what a plausible design error would drive. For each, RUNS
lists the runs of cms_regress.list (result names) that must then FAIL. A test that still passes
with the bug in is not testing that obligation. The +cms_sb_corrupt runs show the checker can
fail; these show the stimulus reaches real bugs and the checker sees them.

  --list-runs   print "<mutation>|<test>|<name>|<seed>|<plusargs>" per run, for cms_mutation.sh
  --check       read <results>/<mutation>/<name>.<seed>.log and report, per expectation:
                  CAUGHT    the bench's verdict is FAIL (CMS_RESULT status=FAIL); the first
                            CMS_ERROR is shown
                  MISSED    the bench passed it (an RTL assertion that fired is shown, but does
                            not count: the bench's own checks did not see the bug)
                  NO LOG    the run left no log (it did not run)
                  CRASHED   the log has no CMS_RESULT line: the simulator stopped before the bench
                            reached a verdict, so the run noticed, but not through this test
                  INACTIVE  the log lacks "MUTATION <name> active": the forced value never
                            differed from the RTL's, so the result says nothing about the bug
                Exits non-zero on any MISSED, NO LOG or INACTIVE, and on a mutation that none of
                its tests CAUGHT (all CRASHED): every mutation must be caught by at least one of
                its tests, and every test listed for it must catch it.
"""

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cheriot_mem_subsys_results import RESULT, TOOL_ERR  # noqa: E402  (the report's parsing)

BENCH = Path(__file__).resolve().parent.parent / "cheriot-mem-subsys"

# Mutations run at this seed; the expectations below were chosen from what each test drives at any
# seed, not from a run.
SEED = 1

# (mutation, RTL it replaces (opentitan-cheriot/hw/ip/cheriot/rtl/), bug it models,
#  [cms_regress.list result names that must FAIL with it])
RUNS = [
    # ─── Tag store ───────────────────────────────────────────────────────────────────────────────
    ("partial_write_keeps_tag", "cheriot_tag_filter.sv:215 require_lookup",
     "a sub-word or PutPartialData store is not looked up, so it leaves the granule's tag set",
     ["cms_tag_clear_subword", "cms_rmw_same_word", "cms_random"]),
    ("datastore_sets_tag", "cheriot_tag_filter.sv:328 tag_m_o",
     "a full-word data store (tag sideband 0) writes tag 1",
     ["cms_smoke", "cms_tag_clear_subword", "cms_tag_store_load", "cms_random"]),
    ("capstore_drops_tag", "cheriot_tag_filter.sv:328 tag_m_o",
     "the upper word of a capability store writes tag 0, so every stored capability is untagged",
     ["cms_smoke", "cms_tag_store_load", "cms_cap_load_hint", "cms_trbe_sweep"]),
    # ─── Revocation bitmap lookup ────────────────────────────────────────────────────────────────
    ("trvk_wrong_bit", "cheriot_trvk_core.sv:275 revbm_bit_select",
     "the engine's bitmap lookup reads the next granule's revocation bit",
     ["cms_trbe_base_decode", "cms_trbe_sweep"]),
    # ─── Revocation engine ───────────────────────────────────────────────────────────────────────
    ("trbe_skip_last", "cheriot.sv:544 trbe_num_words",
     "a sweep of more than one capability stops one capability early",
     ["cms_trbe_sweep", "cms_trbe_base_decode", "cms_trbe_epoch"]),
    ("trbe_no_inval", "cheriot_trbe_mover.sv:323 write_a_valid",
     "the engine reads and looks up every capability but never clears a revoked one's tag",
     ["cms_trbe_sweep", "cms_trbe_base_decode", "cms_rmw_core_trbe_same_word",
      "cms_trbe_snoop_window"]),
    ("trbe_epoch_stuck", "cheriot.sv:599 trbe_epoch_en",
     "TRBE_EPOCH never counts a sweep",
     ["cms_trbe_epoch", "cms_trbe_csr", "cms_random"]),
    # Timing-dependent: the bench sees it only when a busy poll or the interrupt lands between the
    # last read and the last clear of a sweep whose last capability is revoked (a few per test).
    ("trbe_done_early", "cheriot_trbe_mover.sv:498 busy_o",
     "busy, and with it trbe_done and the interrupt, drops when the last word is read, before the "
     "clears are answered",
     ["cms_trbe_sweep", "cms_trbe_intr"]),
    # ─── Core store racing a sweep ───────────────────────────────────────────────────────────────
    ("snoop_off", "cheriot.sv:426 trbe_snoop_valid",
     "the engine does not watch core writes: a clear overwrites the tag of a capability the core "
     "stored after the engine read it",
     ["cms_trbe_store_race", "cms_trbe_snoop_window"]),
    # ─── Errors and alert ────────────────────────────────────────────────────────────────────────
    ("meta_intg_unreported", "cheriot_rmw_filter.sv:354,366 rsp_intg_error_o, data_intg_error_o",
     "integrity errors on meta SRAM responses are not reported (no fatal_fault, no sweep_err)",
     ["cms_err_meta_intg"]),
    ("data_err_dropped", "cheriot_tag_filter.sv:392 tl_d_o",
     "the core's tag filter drops d_error from the data path (cored_tl_h) on its way to the core",
     ["cms_err_data_path", "cms_nvm_cap_store", "cms_tag_store_load"]),
    ("alert_dropped", "cheriot.sv:703 alert_req_i",
     "no fatal error raises fatal_fault (ALERT_TEST still does)",
     ["cms_err_tag_path", "cms_err_csr_intg", "cms_err_trbe_read", "cms_nvm_cap_store"]),
    # ─── Mode gating ─────────────────────────────────────────────────────────────────────────────
    ("mode_loose_mubi", "cheriot_access_check.sv:61-72 allow_forward (corerevbm_tl)",
     "the core's bitmap window treats every cheriot_ena_i but MuBi4False as CHERIoT mode",
     ["cms_mode_gating"]),
]


def read_list(path):
    """cms_regress.list: name -> (test, plusargs)."""
    runs = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        name, test, _seeds, *plusargs = line.split()
        runs[name] = (test, " ".join(plusargs))
    return runs


def selected(only):
    runs = [r for r in RUNS if not only or r[0] == only]
    if not runs:
        sys.exit(f"cms_mutation_check: no mutation '{only}'")
    return runs


def list_runs(only):
    regress = read_list(BENCH / "cms_regress.list")
    for mutation, _rtl, _bug, names in selected(only):
        for name in names:
            if name not in regress:
                sys.exit(f"cms_mutation_check: '{name}' ({mutation}) is not in cms_regress.list")
            test, plusargs = regress[name]
            print(f"{mutation}|{test}|{name}|{SEED}|{plusargs}")


def check(results, only):
    ok = True
    for mutation, _rtl, bug, names in selected(only):
        caught = 0
        print(f"{mutation}: {bug}")
        for name in names:
            log = results / mutation / f"{name}.{SEED}.log"
            head = f"  {name} seed {SEED}"
            if not log.exists():
                print(f"NO LOG    {head}: {log} missing")
                ok = False
                continue
            text = log.read_text(errors="replace")
            if not re.search(rf"^MUTATION {re.escape(mutation)} active\b", text, re.M):
                print(f"INACTIVE  {head}: no 'MUTATION {mutation} active' -- the result says "
                      f"nothing about the mutation")
                ok = False
                continue
            m = None
            for m in RESULT.finditer(text):
                pass
            tool = TOOL_ERR.search(text)
            tool_line = ""
            if tool:
                end = text.find("\n", tool.start())
                tool_line = text[text.rfind("\n", 0, tool.start()) + 1:
                                 end if end >= 0 else len(text)].strip()[:110]
            if m is None:
                why = f" ({tool_line})" if tool else ""
                print(f"CRASHED   {head}: no CMS_RESULT line{why}")
                continue
            if m.group(3) == "PASS":
                why = f"; only an RTL assertion fired: {tool_line}" if tool else ""
                print(f"MISSED    {head}: PASSED with the bug in{why}")
                ok = False
                continue
            caught += 1
            first = re.search(r"^CMS_ERROR.*$", text, re.M)
            print(f"CAUGHT    {head}: FAIL, {m.group(4)} error(s)"
                  + (f"; first: {first.group(0)[:110]}" if first else ""))
        if caught == 0:
            print(f"  -> {mutation} caught by none of its tests")
            ok = False
    return ok


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--list-runs", action="store_true")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--only", metavar="MUTATION", help="one mutation only")
    ap.add_argument("--results", type=Path, default=BENCH / "xlm_mutation_out" / "results")
    args = ap.parse_args()
    if args.list_runs:
        list_runs(args.only)
    if args.check:
        sys.exit(0 if check(args.results, args.only) else 1)


if __name__ == "__main__":
    main()
