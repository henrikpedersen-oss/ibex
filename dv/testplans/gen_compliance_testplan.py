#!/usr/bin/env python3
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""Generate ibex/dv/testplans/compliance_testplan.hjson from the pinned riscv-compliance suite.

The test list is the suite's own: one test per reference signature in
riscv-compliance/riscv-test-suite/<isa>/references/, for the five ISAs
ibex/dv/riscv_compliance/run_all_xlm.sh runs. Test names are <isa>_<TEST>. Every test is required
in both configurations the flow runs: cheriot_enable_i low (make compliance-xlm) and high
(make compliance-cheriot-xlm). Written in the lowRISC testplan template layout (shared with
gen_core_ibex_testplan.py). Run: make testplan-compliance-gen.

EXPECTED_FAIL is the one list of expected failures; ibex/dv/testplans/compliance_results.py imports it.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_core_ibex_testplan import desc_block, tests_block  # noqa: E402  (template writer)

REPO = Path(__file__).resolve().parents[3]  # ibex/dv/testplans -> repository root
SUITE = REPO / "riscv-compliance/riscv-test-suite"
OUT = REPO / "ibex/dv/testplans/compliance_testplan.hjson"
ISAS = ["rv32i", "rv32im", "rv32imc", "rv32Zicsr", "rv32Zifencei"]
TAGS = ["enable_low", "enable_high"]

# test -> (configurations in which it is expected to fail, reason). A listed test that fails there
# counts as expected; one that passes is reported XPASS, so the list is corrected by evidence rather
# than kept by habit. Per configuration because the RTL differs: mtvec.BASE is 4-byte aligned only
# with cheriot_enable_i On (ibex_if_stage.sv exc_pc, ibex_cs_registers.sv); with it Off it is
# truncated to 256 bytes as in upstream ibex, so I-ECALL-01 / I-EBREAK-01 fail there only.
BOTH = ("enable_low", "enable_high")
EXPECTED_FAIL = {
    "rv32i_I-MISALIGN_JMP-01": (BOTH,
        "misa is read-only, so C cannot be disabled and a 2-byte-aligned jump target is legal; "
        "the test expects an instruction-address-misaligned exception"),
    "rv32i_I-MISALIGN_LDST-01": (BOTH,
        "misaligned loads and stores are handled in hardware; the test expects an "
        "address-misaligned exception"),
}

# Tests left out of the testplan altogether (not run as evidence of anything), with the reason. Both
# fail in both configurations for a reason outside what they test: their environment installs the
# trap handler with `csrw mtvec`. With CHERIoT off mtvec.BASE is truncated to a 256-byte boundary
# (upstream ibex, lowrisc/ibex#100); with CHERIoT on the legacy mtvec CSR is not the trap vector
# (MTCC is, and the legacy write is ignored: tech-notes/rtl_todo.md, legacy mtvec/mepc). Excluded on
# 2026-10-04 at Henrik's request; trap entry is covered by the UVM tests instead.
EXCLUDED = {
    "rv32i_I-ECALL-01": "trap handler installed with csrw mtvec: 256-byte mtvec truncation (CHERIoT "
                        "off), legacy mtvec not the trap vector (CHERIoT on)",
    "rv32i_I-EBREAK-01": "as I-ECALL-01",
}

TITLES = {
    "rv32i": "RV32I base integer instructions",
    "rv32im": "M extension: multiply and divide",
    "rv32imc": "C extension: compressed instructions",
    "rv32Zicsr": "Zicsr: CSR access instructions",
    "rv32Zifencei": "Zifencei: instruction-fetch fence",
}


def main():
    testpoints = []
    total = 0
    for isa in ISAS:
        refs = sorted(p.name[: -len(".reference_output")]
                      for p in (SUITE / isa / "references").glob("*.reference_output"))
        if not refs:
            sys.exit(f"no references for {isa} in {SUITE / isa} -- is riscv-compliance checked out?")
        tests = [f"{isa}_{t}" for t in refs if f"{isa}_{t}" not in EXCLUDED]
        total += len(tests)
        details = [
            f"The {len(tests)} riscv-compliance {isa} tests (riscv-test-suite/{isa}), run on the "
            "Xcelium compliance testbench with cheriot_enable_i low and high. Each test's "
            "signature must match the suite's reference output exactly; a missing signature is a "
            "failure. The enable-high run checks that plain RISC-V code behaves the same with "
            "CHERIoT enabled."]
        xfail = [f"{t.split('_', 1)[1]} ({', '.join(EXPECTED_FAIL[t][0])}): {EXPECTED_FAIL[t][1]}"
                 for t in tests if t in EXPECTED_FAIL]
        if xfail:
            details += ["Expected failures (counted as expected while they fail, reported XPASS "
                        "if they pass):", xfail]
        excl = [f"{t.split('_', 1)[1]}: {r}" for t, r in EXCLUDED.items() if t.startswith(isa + "_")]
        if excl:
            details += ["Not in this testplan:", excl]
        testpoints.append((isa, TITLES[isa], details, tests))

    out = [
        "// Copyright lowRISC contributors.",
        "// Licensed under the Apache License, Version 2.0, see LICENSE for details.",
        "// SPDX-License-Identifier: Apache-2.0",
        "//",
        "// GENERATED by ibex/dv/testplans/gen_compliance_testplan.py from the pinned riscv-compliance suite",
        "// -- rerun `make testplan-compliance-gen`, do not edit by hand.",
        "{",
        '  name: "compliance"',
        "",
        "  testpoints: [",
    ]
    blocks = []
    for isa, title, details, tests in testpoints:
        blocks.append("\n".join([
            "    {",
            f"      name: {isa}",
            desc_block(title, details),
            "      stage: V1",
            "      tags: [" + ", ".join(f'"{t}"' for t in TAGS) + "]",
            tests_block(tests),
            "    }",
        ]))
    out += ["\n\n".join(blocks), "  ]", "}", ""]
    OUT.write_text("\n".join(out))
    print(f"{OUT.relative_to(REPO)}: {len(testpoints)} testpoints, {total} tests x {len(TAGS)} "
          f"configurations, {len(EXPECTED_FAIL)} expected failures, {len(EXCLUDED)} excluded")


if __name__ == "__main__":
    main()
