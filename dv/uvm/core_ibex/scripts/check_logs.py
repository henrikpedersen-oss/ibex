#!/usr/bin/env python3
"""
Collect all the logfiles for a single test, and check for errors.

Pass/fail criteria is determined by any errors found.
"""

# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

import argparse
import sys
import pathlib3x as pathlib

from test_entry import read_test_dot_seed
from test_run_result import TestRunResult, Failure_Modes

from spike_log_to_trace_csv import process_spike_sim_log  # type: ignore
from ibex_log_to_trace_csv import (process_ibex_sim_log,  # type: ignore
                                   check_ibex_uvm_log)

import logging
logger = logging.getLogger(__name__)


def compare_test_run(trr: TestRunResult) -> TestRunResult:
    """Compare results for a single run of a single test.

    Use any log-processing scripts available to check for errors.
    """

    # If the test is already marked as TIMEOUT before we check the logs, it must
    # have been killed at a process-level in the run_rtl stage.
    # Don't check the logs at all in this case.
    if (trr.failure_mode == Failure_Modes.TIMEOUT):
        trr.passed = False
        return trr

    # Process the Ibex trace to create a .csv
    # The format is suitable for ingestion by riscv-dv coverage collection
    #
    # A missing or empty trace is NOT failed here. Some tests legitimately retire
    # no instructions: riscv_pc_intg_test forces pc_if_o, releases it, and ends
    # at ~5020ns, so the tracer never emits a line and this raised
    #   [FAILED]: Processing the ibex trace failed: Logfile ... not found
    # against a simulation that had printed "--- RISC-V UVM TEST PASSED ---" with
    # UVM_FATAL: 0. That cost two false failures in the 2026-09-23 regression.
    #
    # The UVM log is the authority on whether the test passed, so defer to it:
    # remember the trace problem and only report it if the UVM log does not show
    # a clean pass. A trace that is missing because the test died early will
    # still be caught, because the UVM log will not be clean in that case.
    trace_failure = None
    try:
        logger.debug(f"About to do Log processing: {trr.rtl_trace}")
        process_ibex_sim_log(trr.rtl_trace, trr.dir_test/'rtl_trace.csv')
    except (OSError, RuntimeError) as e:
        trace_failure = e

    # Process the test's UVM log.
    # Report a failure if an issue is seen.
    try:
        logger.debug(f"About to do simulation log processing: {trr.rtl_log}")
        uvm_pass, uvm_log_lines, uvm_failure_mode = check_ibex_uvm_log(trr.rtl_log)
    except IOError as e:
        trr.passed = False
        trr.failure_mode = Failure_Modes.FILE_ERROR
        trr.failure_message = f"[FAILED] Could not open simulation log: {e}\n"
        return trr
    if not uvm_pass:
        # Something was found in the logfile that means we mark this test as failed.
        trr.failure_mode = uvm_failure_mode
        if uvm_failure_mode == Failure_Modes.TIMEOUT:
            # If timeout is detected in the log, it means we ended via the wall-clock
            # timeout within the simulator. This is a graceful timeout, keep coverage etc.
            trr.failure_message = "[FAILURE] Simulation ended gracefully due to timeout " \
                                 f"[{trr.timeout_s}s].\n"
        else:
            # Some other error was detected, UVM_FAILED/fatal etc.
            trr.failure_message = f"\n[FAILED]: error seen in '{trr.rtl_log.name}'\n"
        if uvm_log_lines:
            trr.failure_message += \
                "---------------*LOG-EXTRACT*----------------\n" + \
                "\n".join(uvm_log_lines) + "\n" + \
                "--------------------------------------------\n"
        if trace_failure is not None:
            # The UVM log already failed this test; surface the trace problem
            # too, since a missing trace often accompanies an early death and is
            # a useful clue about how far the test got.
            trr.failure_message += \
                f"[NOTE]: the ibex trace could also not be processed: {trace_failure}\n"
        return trr

    # If we got this far then the test has passed. A trace that could not be
    # processed is reported but does not fail the test -- see the note above.
    if trace_failure is not None:
        logger.info(f"{trr.testdotseed}: simulation passed but the ibex trace could not "
                    f"be processed ({trace_failure}). This is expected for tests "
                    "that retire no instructions; no coverage will be collected "
                    "for this run.")

    trr.passed = True
    return trr


def _main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--dir-metadata',
                        type=pathlib.Path, required=True)
    parser.add_argument('--test-dot-seed',
                        type=read_test_dot_seed, required=True)

    args = parser.parse_args()
    tds = args.test_dot_seed

    trr = TestRunResult.construct_from_metadata_dir(args.dir_metadata, f"{tds[0]}.{tds[1]}")

    trr = compare_test_run(trr)
    trr.export(write_yaml=True)

    # Always return 0 (success), even if the test failed. We've successfully
    # generated a comparison log either way and we don't want to stop Make from
    # gathering them all up for us.
    return 0


if __name__ == '__main__':
    sys.exit(_main())
