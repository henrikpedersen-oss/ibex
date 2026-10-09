#!/usr/bin/env python3
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""Generate ibex/dv/testplans/core_ibex_testplan.hjson from the UVM bench's own sources.

The core_ibex bench has ~1000 tests (riscv-dv testlist + directed testlists) and ~260 coverpoints,
and both grow; a hand-written testplan would drift at once. So the testplan is generated:

  testpoints   FAMILIES below: each has a hand-written obligation (desc) and a rule selecting its
               tests from the test lists by name, config and source path. The generated file lists
               every selected test. A test that no family selects, or that two select, is an
               error -- adding a test means deciding which obligation it serves.
  covergroups  read from ibex/dv/uvm/core_ibex/fcov/*.sv: every covergroup, with its coverpoints
               and crosses, marking the crosses compiled out unless CHERIOT_FCOV_LARGE_CROSSES.

Run: ibex/dv/testplans/py.sh ibex/dv/testplans/gen_core_ibex_testplan.py   (make testplan-uvm-gen)
Obligations belong in ibex_cheriot_verification_spec.md; the descs here say which runs serve them.
"""

import re
import sys
import textwrap
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]  # ibex/dv/testplans -> repository root
UVM = REPO / "ibex/dv/uvm/core_ibex"
TESTLISTS = [UVM / "riscv_dv_extension/testlist.yaml"] + sorted(
    (UVM / "directed_tests").glob("directed_testlist*.yaml"))
FCOV = [UVM / "fcov/core_ibex_fcov_if.sv", UVM / "fcov/core_ibex_pmp_fcov_if.sv",
        UVM / "fcov/core_ibex_trvk_fcov_if.sv"]
OUT = REPO / "ibex/dv/testplans/core_ibex_testplan.hjson"
# Coverpoint descriptions and requirement links come from the spec's Functional Coverage chapter.
# Optional: without the spec (e.g. ibex on its own) only the hand-written CG_DETAILS remain.
SPEC = REPO / "ibex_cheriot_verification_spec.md"
# Test descriptions that only restate the name (generated riscv-tests/arch-tests/ePMP lists).
BOILERPLATE_DESC = re.compile(r"^riscv test - ")


def rdv(*names):
    """Select riscv-dv testlist tests by exact name."""
    s = set(names)
    return lambda t: t["list"] == "testlist.yaml" and t["name"] in s


def rdv_re(pattern):
    r = re.compile(pattern)
    return lambda t: t["list"] == "testlist.yaml" and r.fullmatch(t["name"]) is not None


def directed(pred):
    return lambda t: t["list"] != "testlist.yaml" and pred(t)


# (name, stage, tags, desc, selector). Order is presentation order.
FAMILIES = [
    # ── riscv-dv random tests (riscv_dv_extension/testlist.yaml) ─────────────────────────────
    ("rdv_random_instructions", "V1", ["riscv-dv"],
     "Random instruction streams in M and U mode, arithmetic-only through full RV32IMC, "
     "compared instruction by instruction against Spike (cosim).",
     rdv("riscv_arithmetic_basic_test", "riscv_machine_mode_rand_test", "riscv_rand_instr_test",
         "riscv_rv32im_instr_test", "riscv_user_mode_rand_test")),
    ("rdv_control_flow", "V2", ["riscv-dv"],
     "Random jumps, jump stress and loops: branch/jump targets, the prefetch buffer and "
     "instruction-side flushes; fetch_enable_i toggled while loads and stores are in flight "
     "(riscv_fetch_en_chk_test).",
     rdv("riscv_rand_jump_test", "riscv_jump_stress_test", "riscv_loop_test",
         "riscv_fetch_en_chk_test")),
    ("rdv_exceptions", "V2", ["riscv-dv"],
     "Illegal instructions, hints, ebreak and invalid CSR accesses trap (or retire) exactly as "
     "the reference model does, and the handler resumes correctly.",
     rdv("riscv_illegal_instr_test", "riscv_hint_instr_test", "riscv_ebreak_test",
         "riscv_invalid_csr_test")),
    ("rdv_debug", "V2", ["riscv-dv"],
     "Debug mode: entry by request, trigger, ebreak and single step; dret; debug CSRs; debug "
     "and interrupts in both orders; debug during WFI and branches.",
     rdv_re(r"riscv_(debug_\w+|dret_test|irq_in_debug_mode_test)")),
    ("rdv_interrupts", "V2", ["riscv-dv"],
     "Single, multiple and nested interrupts, interrupts during WFI and CSR access, traps "
     "mixed with interrupts and debug, and NMIs taken ahead of an excepting instruction in ID "
     "(riscv_nmi_at_exc_test).",
     rdv_re(r"riscv_(single|multiple|nested)_interrupt_test|riscv_interrupt_\w+_test|"
            r"riscv_assorted_traps_interrupts_debug_test|riscv_nmi_at_exc_test")),
    ("rdv_csrs_and_privilege", "V2", ["riscv-dv"],
     "CSR read/write behaviour against the CSR description, and U-mode WFI timeout (mstatus.TW).",
     rdv("riscv_csr_test", "riscv_umode_tw_test")),
    ("rdv_memory", "V2", ["riscv-dv"],
     "Unaligned loads and stores, bus errors on data and instruction fetch, and memory stress; "
     "bus errors with interrupts and debug requests on top, some raised the moment a data-side "
     "error is decided so that they are pending when it arrives (riscv_mem_error_traps_test).",
     rdv("riscv_unaligned_load_store_test", "riscv_mem_error_test", "riscv_mmu_stress_test",
         "riscv_mem_error_traps_test")),
    ("rdv_integrity_countermeasures", "V2S", ["riscv-dv"],
     "Security countermeasures: integrity errors on memory responses, the PC, the register file "
     "(data and address) and the RAMs/icache are detected and raise the right alert.",
     rdv("riscv_mem_intg_error_test", "riscv_pc_intg_test", "riscv_rf_intg_test",
         "riscv_rf_addr_intg_test", "riscv_ram_intg_test", "riscv_icache_intg_test")),
    ("rdv_reset", "V2", ["riscv-dv"],
     "Reset in the middle of execution returns the core to its reset state.",
     rdv("riscv_reset_test")),
    ("rdv_pmp_epmp", "V2", ["riscv-dv"],
     "PMP and ePMP (mseccfg MML/MMWP/RLB): region matching, permissions, locked regions, "
     "out-of-bounds and fully random configurations.",
     rdv_re(r"riscv_(pmp|epmp)_\w+")),
    ("rdv_bitmanip", "V2", ["riscv-dv"],
     "Bit-manipulation instructions for each supported configuration.",
     rdv_re(r"riscv_bitmanip_\w+")),

    # ── Directed tests (directed_tests/directed_testlist*.yaml) ──────────────────────────────
    ("directed_flow_smoke", "V1", ["directed"],
     "The directed-test flow itself: an empty test boots, signals completion and passes the "
     "testbench's end-of-test checks. If this fails, no other directed result means anything.",
     directed(lambda t: t["name"] == "empty")),
    ("riscv_tests_isa", "V1", ["directed"],
     "riscv-tests ISA suites rv32ui, rv32um and rv32mi: each instruction and M-mode behaviour "
     "self-checks and passes.",
     directed(lambda t: "/vendor/riscv-tests/isa/" in t["src"])),
    ("riscv_arch_tests", "V1", ["directed"],
     "RISC-V architectural test suite (I, M, C, B): each test's signature matches the reference.",
     directed(lambda t: t["config"] == "riscv-arch-tests")),
    ("epmp_generated", "V2", ["directed"],
     "Generated ePMP tests (riscv-isa-sim mseccfg gengen): every combination of lock, RLB, MMWP, "
     "MML, mode and permission, for CSR behaviour and for access checks.",
     directed(lambda t: t["config"] == "epmp-tests")),
    ("pmp_directed", "V2", ["directed"],
     "PMP directed tests: overlapping regions (priority of the lowest-numbered match), and "
     "mseccfg RLB and lock interaction -- which pmpcfg writes are accepted after locking; "
     "PMP-fault, bus-error and completing load/stores followed by each instruction category, "
     "with the icache and data-independent timing off and on, a masked pending interrupt, "
     "dcsr.ebreakm, and debug requests, NMIs and fetch-enable drops raised at the fault "
     "(pmp_fault_hazard, core_ibex_stall_events_test), including a non-executable word that "
     "decodes as a load, so the faulting fetch also stalls ID as a memory instruction. TOR "
     "entries whose top is not above their bottom match nothing, for all 16 entries, and a "
     "fetch at the start of a locked TOR entry faults with mtval at that address; an "
     "instruction access fault at pc 0 and an exception taken with the mtvec base at 0 "
     "(cov_expr_pmp_tor). A 32-bit instruction at 0xFFFFFFFE whose second half wraps to address "
     "0 executes, and with address 0 denied faults with mepc 0xFFFFFFFE and mtval 0 "
     "(cov_expr_fetch_wrap). With mseccfg.MML = 1 and RLB = 0, writes of every executable MML "
     "configuration to locked entries are ignored (cov_fcov_pmp_mml_locked_wr).",
     directed(lambda t: t["name"].startswith("pmp_mseccfg_test") or
              t["name"] in ("access_pmp_overlap", "pmp_fault_hazard", "cov_expr_pmp_tor",
                            "cov_expr_fetch_wrap", "cov_fcov_pmp_mml_locked_wr"))),
    ("counters_and_user_mode", "V2", ["directed"],
     "mcounteren gating of U-mode counter access, its lock behaviour, and U-mode execution; "
     "every CSR read and written from M-mode and from U-mode, illegal accesses trapping "
     "(csr_access_sweep). minstret and mhpmcounter10 (compressed instructions retired) count "
     "exactly, stay frozen while their mcountinhibit bits are set and count again once cleared "
     "(cov_expr_counter_inhibit, self-checking: this Spike does not inhibit minstret).",
     directed(lambda t: t["name"] in ("mcounteren_test", "mcounteren_lock_test",
                                      "u_mode_exec_test", "csr_access_sweep",
                                      "cov_expr_counter_inhibit"))),
    ("cheriot_isa_directed", "V2", ["directed", "cheriot"],
     "CHERIoT instructions and capability state, self-checking: capability fields (base, length, "
     "type, permissions, address, high word), CIncAddr/CSetAddr/CSetBounds variants and "
     "rounding, sealing and unsealing, sentries on CJALR, CJALR fault causes, priority and "
     "sentry/register-pair rules, PCC, PCC bounds at instruction fetch (sequential, straddling "
     "32-bit, branch/jump/CJALR/MRET targets), the null capability, capability "
     "readback, CLC/CSC through an authority without MC (tag stripped on load, tagged store "
     "traps, untagged store succeeds), SCRs, and ASR-gated counters; every failing arm of "
     "CSeal/CUnseal and the tag-clearing of modified sealed capabilities; CSR, CSpecialRW and "
     "MRET faults without PCC.SR; the legacy mtvec/mepc CSRs being illegal in CHERIoT mode. "
     "CSetHigh: the CGetHigh/CSetHigh round trip (cheriot_cap_high) and, in cheriot_csethigh, "
     "tagged, untagged, sealed and bounded sources, inexact and exact bounds, cursors that move "
     "the decoded bounds, all six permission formats, the reserved bit and sealed otypes, with "
     "the tag always cleared. AUIPCC and AUICGP on both sides of each representable-window edge "
     "(cheriot_auipcc_auicgp_repr); CSetAddr, CIncAddr and CIncAddrImm at every byte within 10 of "
     "both window edges for E = 0, 3 and 10 (cheriot_repr_window_sweep). CSpecialRW read-only "
     "(cs1 = c0), write-only (cd = c0), "
     "read-write and no-op forms on all four SCRs (cheriot_cspecialrw_c0). Zero-length and "
     "zero-permission capabilities through every instruction class that uses an authority "
     "(cheriot_zero_len_perm). MTCC/MEPCC legalisation of misaligned and sealed values "
     "(cheriot_scr_legalize); CLC bounds against a top of 2^32 (cheriot_clsc_top_edge); the "
     "faulting register's index in mtval for c0 and csp-cs1, and R-type operand indices over "
     "x0/x5/x15 (cheriot_reg_index). c.srli/c.srai with a non-zero shift on a capability "
     "register: shifted address, tag cleared (cheriot_c_shift_imm). CJAL at 2^32 - 2, whose link "
     "wraps to 0 (cheriot_cjal_link_wrap, cosim off: CHERIoT-Sail cannot represent the link): the "
     "link is untagged or keeps exactly the PCC's bounds. AUICGP, CIncAddrImm and CIncAddr on "
     "an untagged sealed E = 0 capability whose base decodes above its address (0xFFFFFF00 "
     "for address 0x10), and CGetBase of the memory root at address 0xFFFFFFFF, against "
     "CHERIoT-Sail (cov_fcov2_cheri_isa).",
     directed(lambda t: t["name"] == "cov_fcov2_cheri_isa" or
              t["name"].startswith("cheriot_") and
              t["name"] not in ("cheriot_enable_transition", "cheriot_bck_nocheck",
                                "cheriot_mshwm", "cheriot_enable_on_off",
                                "cheriot_fatal_err_mtcc", "cheriot_dummy_instr") and
              not t["name"].startswith(("cheriot_rtos_", "cheriot_revoke_", "cheriot_illegal_",
                                        "cheriot_rand_")) and
              not t["name"].endswith("_illegal"))),
    ("cheriot_random_operands", "V2", ["directed", "cheriot"],
     "CHERIoT instructions over randomly built operands, checked instruction by instruction "
     "by the CHERIoT-Sail cosim (rd value and tag; capability metadata through a CGetHigh of "
     "every capability result): a per-seed LFSR builds capabilities from MTDC, MTCC and "
     "MScratchC in every operand class the cheriot_uarch_cg crosses name -- root, E = 24, "
     "E = 1..14, E = 0 and zero-length bounds, cursor below/at the base, inside, near, at and "
     "above the top, all permission encodings, every otype, untagged and raw-encoded -- and "
     "runs the CSetBounds family, CIncAddr/CIncAddrImm/CSetAddr, AUICGP and AUIPCC (every "
     "imm20 class, from E = 0/2/5/24 PCCs), CGet*, CSetHigh, CSEQX, CTestSubset, CSeal, "
     "CUnseal, CRRL, CRAM, CSC, CLC, CJALR (every rd and immediate class, target against the "
     "bounds, sentries, MIE), CJAL from bounded PCCs, and CSpecialRW on every SCR form with "
     "and without PCC.SR. Instructions that fault resume through a CHERIoT trap handler; the "
     "program checks liveness, its trap causes and model-independent invariants (CSetHigh "
     "round trip, monotonic CSetBounds, CAndPerm only removes permissions, CUnseal unseals). "
     "Fills the per-instruction operand crosses while riscv_cheriot_rand_instr_test is "
     "disabled (cheriot_rand_operands). The same program built for loads and stores only "
     "(cheriot_rand_ldst) issues every load/store width and CLC/CSC at -10..10 bytes from the "
     "base or the top of an authority that is valid, untagged or sealed, with the needed "
     "permission dropped or kept -- below-base cursors through an E = 24 authority, the only "
     "exponent whose representable range includes them -- for the bounds edges and the "
     "fault priority of every access (cheri_access_bounds_cg).",
     directed(lambda t: t["name"].startswith("cheriot_rand_"))),
    ("cheriot_stack_high_water_mark", "V2", ["directed", "cheriot"],
     "Stack high water mark CSRs mshwm/mshwmb (CHERIoT ISA section 'Stack high water mark', "
     "CHERIoT-Sail): reset value, rounding of every write form to 16 bytes, the update on every "
     "store kind whose start address is in [mshwmb, mshwm) and on no other access (loads, "
     "stores outside the window, an empty window, faulting stores, a misaligned store starting "
     "below mshwmb), the update from a PCC without SR, and SR-gated CSR access (capcause 0x18). "
     "The pin-Off half (CSRs absent, illegal instruction) is in cheriot_illegal_rv_mode.",
     directed(lambda t: t["name"] == "cheriot_mshwm")),
    ("cheriot_illegal_instructions", "V2", ["directed", "cheriot"],
     "Illegal instructions with the expected cause, mtval and MEPCC: in CHERIoT mode a sweep of "
     "every reserved encoding class on which CHERIoT-Sail and the RTL agree (mcause 2, mtval 0), "
     "a second sweep of the encodings Sail rejects and the RTL executes (Zcb, draft "
     "bit-manipulation, CSRs absent from the Sail platform; GAP-CS-3, expected to fail until each "
     "disagreement is resolved), one unwaived test per encoding the specification makes illegal "
     "and the RTL accepted (CGetOffset: cheriot_cgetoffset_illegal; every CSR instruction form "
     "on cdbg_ctrl: cheriot_cdbg_ctrl_illegal), and with the pin Off every CHERIoT-only "
     "encoding (opcodes 0x5B and 0x7B, CLC/CSC, the CHERIoT CSRs, compressed capability "
     "loads/stores) with mtval = the instruction bits, against Spike. Random illegal "
     "instructions with the pin Off are rdv_exceptions.",
     directed(lambda t: t["name"].startswith("cheriot_illegal_") or
              t["name"].endswith("_illegal"))),
    ("cheriot_rtos_patterns", "V2", ["directed", "cheriot"],
     "CHERIoT instructions exercised the way the CHERIoT RTOS uses them, with expected values "
     "from the CHERIoT Sail model: capabilities survive CSC/CLC exactly and an integer store "
     "untags only its own granule; CMove copies every field and never sets a tag; CRRL/CRAM "
     "across the exponent boundaries and saturation, and the allocator's CSetBoundsExact "
     "recipe built on them; CGetTop saturates at 2^32 and decodes independently of cursor and "
     "tag; CSetEqualExact detects a difference in any single field; CTestSubset uses the Sail "
     "operand order and compares bounds, permissions and tag.",
     directed(lambda t: t["name"].startswith("cheriot_rtos_"))),
    ("cheriot_temporal_safety", "V2", ["directed", "cheriot"],
     "Temporal safety at the core boundary (REQ_TMP_01): every integer store width "
     "clears the tag of the granule it touches, CSC of an untagged value clears it, stores do not "
     "disturb neighbouring granules, and dereferencing a scrubbed (untagged) pointer raises a "
     "CHERI tag violation reported against the right register and PC. The CLC load barrier "
     "returns tag 0 for a capability whose base lies in a revoked granule (bit select, unaligned "
     "base, first/last bitmap word), never revokes outside the heap window, exempts SE/US/U0 "
     "capabilities, and treats a bitmap bus or integrity error as revoked (alone or both on one "
     "response) and raises "
     "alert_major_bus. ibex_revbm_responder serves the bitmap from +revbm_* plusargs and the "
     "CHERIoT-Sail cosim is given the same bitmap, so every revoked CLC is checked by the model.",
     directed(lambda t: t["name"].startswith("cheriot_revoke_"))),
    ("cheriot_enable_transition", "V2", ["directed", "cheriot"],
     "cheriot_enable_i 0->1 while running (#827, REQ_BCK_05): RISC-V mode works with the pin Off, "
     "the testbench raises the pin when the program writes the trigger address "
     "(+cheriot_enable_on_write), and CHERIoT mode is then active -- auipc decodes as CAUIPCC and "
     "returns a tagged capability, while the auipc executed before the switch left no tag. "
     "Self-checking, cosim off: neither Spike nor CHERIoT-Sail models a pin that changes mid-run. "
     "The formal side (formal_testplan.hjson cheriot_enable_transition) covers invalid encodings "
     "and tag creation while Off.",
     directed(lambda t: t["name"] == "cheriot_enable_transition")),
    ("cheriot_enable_on_off", "V2", ["directed", "cheriot"],
     "cheriot_enable_i 0->1 and then 1->0 while running (REQ_BCK_06). The 1->0 change breaks the "
     "pin contract of REQ_BCK_05; the core must then raise alert_major_internal_o rather than "
     "switch the capability checks off silently. After a CSC/CLC round trip in CHERIoT mode the "
     "testbench slows the d-side grants and lowers the pin while a CSC waits for its first grant "
     "(LSU CTX_WAIT_GNT1 -> IDLE, otherwise never taken), and requires the alert within 100 "
     "cycles (+cheriot_disable_on_write). Cosim off: neither model has the pin.",
     directed(lambda t: t["name"] == "cheriot_enable_on_off")),
    ("zcmp_push_pop_mv", "V2", ["directed"],
     "Every Zcmp instruction in RISC-V mode: cm.push/cm.pop/cm.popret/cm.popretz over all rlist "
     "values (ra .. ra,s0-s11) and all spimm values, cm.mvsa01/cm.mva01s over all sreg pairs, the "
     "reserved rlist 0-3 and mv forms (illegal instruction), and back-to-back sequences. Checks "
     "sp, every saved/loaded slot and register, and that nothing else changed. Self-checking, cosim "
     "off: Spike cannot pair Zcmp's multi-register accesses (GAP-RV-6).",
     directed(lambda t: t["name"] == "zcmp_push_pop_mv")),
    ("counter_high_half_write", "V2", ["directed"],
     "Writes to the high halves of mcycle, minstret and mhpmcounter3-12 (mcycleh, minstreth, "
     "mhpmcounterNh): mcycleh/minstreth read back, the low half is unchanged, both counters carry "
     "into the high half; the 32-bit event counters read 0 in their high half. Checked against "
     "Spike.",
     directed(lambda t: t["name"] == "counter_high_half_write")),
    ("cheriot_fatal_err_mtcc", "V2", ["directed", "cheriot"],
     "A trap taken with MTCC untagged sets the sticky cheriot_fatal_err: alert_major_internal_o "
     "rises within 4 cycles of the trap and stays high; no alert before it, no minor or bus alert "
     "(core_ibex_cheriot_fatal_err_test). The spec leaves this trap undefined (REQ_PER_03); the "
     "alert is checked as RTL design intent.",
     directed(lambda t: t["name"] == "cheriot_fatal_err_mtcc")),
    ("cheriot_enable_off", "V2", ["directed", "cheriot"],
     "cheriot_enable_i held Off on the CHERIoT-capable build (REQ_BCK_02, Off half): integer "
     "loads and stores through base registers that carry no capability -- which in CHERIoT mode "
     "would each be a tag violation -- complete normally, checked against Spike; CHERI "
     "instructions and CLC are illegal instructions, showing the pin really is Off.",
     directed(lambda t: t["name"] == "cheriot_bck_nocheck")),
    ("juliet_baremetal", "V2", ["directed", "cheriot"],
     "Juliet CWE cases on bare metal: each memory-safety weakness is stopped by the expected "
     "CHERI check (bounds, tag, permission, representability).",
     directed(lambda t: t["name"].startswith("juliet_"))),
    ("whitebox_uarch", "V2", ["directed", "cheriot"],
     "White-box microarchitecture scenarios: fetch FIFO full/single, prefetch on branch, "
     "instruction stalls, CLC/CSC in the pipeline, sentry CJALR, trap/mret, misaligned LSU "
     "accesses and counter inhibit.",
     directed(lambda t: t["name"].startswith("wb_"))),
    ("debug_directed", "V2", ["directed"],
     "Debug mode beyond the riscv-dv debug tests: ebreak in debug mode re-enters without "
     "updating dpc/dcsr; ecall, mret to U, a U-mode CSR access and dret at U inside one debug "
     "session (UNSPECIFIED in the Debug Spec; expected values from the RTL, see the test header) "
     "(debug_mret_umode); fetches, loads and stores in the Debug Module range in debug mode with "
     "the PMP allowing and denying the range, addresses outside it still PMP-checked, and the "
     "range denied outside debug mode (debug_dm_pmp, REQ_DBG_05). The trigger CSRs tselect, "
     "tdata1 and tdata2 read in debug mode, which riscv-dv's debug ROM never does "
     "(cov_fcov_debug_tdata_read). A single step with the timer interrupt pending and enabled "
     "runs exactly one instruction and re-enters debug mode (cause 4; Ibex hardwires "
     "dcsr.stepie to 0), and the interrupt is taken after the next dret with mepc = that dpc "
     "(cov_expr_step_irq, REQ_DBG_02). In CHERIoT mode: a trap through an MTCC at address 0, "
     "DEPCC := NULL read back untagged, and an ecall in debug mode going to the debug exception "
     "address with mcause and MEPCC unchanged (cov_expr_cheriot_dbg).",
     directed(lambda t: t["name"] in ("debug_mret_umode", "debug_dm_pmp",
                                      "cov_fcov_debug_tdata_read", "cov_expr_step_irq",
                                      "cov_expr_cheriot_dbg"))),
    ("cheriot_cpuctrl_hardening", "V2", ["directed", "cheriot"],
     "Data-independent timing and dummy instruction insertion with cheriot_enable_i asserted: "
     "CHERI work gives the same results and takes no trap (doc/03_reference/security.rst). "
     "Depends on the RTL accepting cpuctrlsts in CHERIoT mode (GAP-CS-3).",
     directed(lambda t: t["name"] == "cheriot_dummy_instr")),
    ("port_toggle", "V2", ["directed"],
     "The configuration inputs hart_id_i and boot_addr_i: mhartid reads hart_id_i (0 and "
     "all-ones) and cannot be written; mtvec holds the boot address when the core boots. The "
     "testbench drives both ports' complement while rst_n is low, so their toggle coverage "
     "measures the ports (boot_addr_i[7:0] waived: 256-byte aligned).",
     directed(lambda t: t["name"] in ("ibex_mhartid", "ibex_mhartid_ones", "ibex_boot_addr"))),
    ("rv32_decode_corners", "V2", ["directed"],
     "Decode corners the random tests do not reach: packu and packh results (draft 0.93 Zbp); "
     "reserved OP-IMM encodings (unary group rs2 = 15, srli/srai with shamt[5] = 1) raise an "
     "illegal-instruction exception with mtval = the instruction and leave rd unwritten; every "
     "mhpmcounter low half is writable and the unavailable ones read 0. rori and bexti with "
     "shamt[5] = 1 likewise, without stalling ID as a multi-cycle ALU operation "
     "(cov_expr_rv_misc).",
     directed(lambda t: t["name"] in ("ibex_decode_holes", "cov_expr_rv_misc"))),
    ("trap_timing_hazards", "V2", ["directed", "cheriot"],
     "Debug requests, NMIs and fetch-enable drops placed in an exact cycle of the instruction "
     "behind a data access rather than at random: the bench acts on the access's grant "
     "(+gnt_trig_lo/hi) and the program chooses the data-side response delay per section "
     "(+mem_mode_on_write), with a masked timer interrupt pending. RISC-V mode "
     "(cov_fcov2_rv_hazard): a debug request rising in the single ID cycle of a Mul or Load; "
     "ebreak, ecall and a fetch error unstalling with a debug request pending; ebreak, an "
     "illegal and a CSR-illegal instruction behind a faulting access at every response "
     "timing, interrupt and debug combination; an NMI pending while ebreak, wfi, a fetch "
     "error or a dcsr read waits behind a faulting access, taken right after its flush; and "
     "IF empty and idle behind c.ebreak, c.unimp and a CSR-illegal instruction for each "
     "writeback state. CHERIoT mode (cov_fcov2_cheri_hazard): a CHERI instruction "
     "independent of, or reading, a load's result, behind an access that completes or gets a "
     "bus error, at each response timing, with and without the interrupt and a debug request. "
     "Self-checking (trap, NMI and debug-entry counts, causes, NMI mepc); the bench fails the "
     "test if a configured trigger never fires. Spike cosim on in RISC-V mode; cosim off in "
     "CHERIoT mode (CHERIoT-Sail has no debug mode and no bus errors).",
     directed(lambda t: t["name"] in ("cov_fcov2_rv_hazard", "cov_fcov2_cheri_hazard"))),
    ("integrity_directed", "V2S", ["directed"],
     "Bus integrity errors injected by address (+dside_intg_err_lo/hi, +iside_intg_err_lo/hi): "
     "a load with bad integrity raises the internal NMI (mcause 0xFFFFFFE0, mtval its address, "
     "rd unwritten); a second one raised inside the NMI handler stays pending while nmi_mode "
     "blocks it and is taken right after the handler's mret; the instructions after the first "
     "load each execute once. Zcmp encodings fetched with bad integrity raise an instruction "
     "access fault and change nothing. A bus alert per integrity error and no other alert "
     "(core_ibex_cheriot_mem_err_test). Self-checking (cov_expr_intg_err).",
     directed(lambda t: t["name"] == "cov_expr_intg_err")),
    ("debug_module", "V2", ["directed", "cheriot"],
     "The real RISC-V debug module (vendor/pulp_riscv_dbg dm_top with the CHERIoT patches) "
     "behind the core's instruction and data buses, driven over its DMI port: dmstatus, "
     "hartinfo and abstractcs reset values; halt, cross-checked against the core's debug mode; "
     "dcsr and dpc; GPR reads and writes by abstract command, with s0 and a0, which every "
     "command borrows, restored; the program buffer; a mailbox write; resume. RISC-V mode "
     "(dm_basic): a 64-bit access is refused (cmderr 2) and a read of an unimplemented CSR "
     "reports the debug-mode exception (cmderr 3). CHERIoT mode (dm_basic_cheriot): 64-bit "
     "capability register reads match the program's own stored images, DEPCC is read through "
     "the SCR path, a 64-bit write puts an untagged capability in a4, x16 faults (cmderr 3), "
     "and s0/a0 keep their tags (REQ_DBG_05). Needs the DM=1 testbench build, which ties the "
     "core's debug addresses to the DM ROM and takes debug_req_i from dm_top; skipped by "
     "all_directed without it. Self-checking, cosim off (+cosim_off=1: no model has the debug "
     "module's ROM).",
     directed(lambda t: t["name"] in ("dm_basic", "dm_basic_cheriot"))),
]


# One-line summary per testpoint: the first line of its desc, as in the lowRISC templates.
TITLES = {
    "rdv_random_instructions": "Random instruction streams checked against Spike",
    "rdv_control_flow": "Random jumps, branches and loops",
    "rdv_exceptions": "Illegal instructions, hints, ebreak and invalid CSRs",
    "rdv_debug": "Debug mode entry, exit and interaction with interrupts",
    "rdv_interrupts": "Interrupt handling",
    "rdv_csrs_and_privilege": "CSR behaviour and U-mode WFI timeout",
    "rdv_memory": "Unaligned accesses, bus errors and memory stress",
    "rdv_integrity_countermeasures": "Integrity-error countermeasures",
    "rdv_reset": "Reset during execution",
    "rdv_pmp_epmp": "Random PMP and ePMP configurations",
    "rdv_bitmanip": "Bit-manipulation instructions",
    "directed_flow_smoke": "Directed-test flow smoke test",
    "riscv_tests_isa": "riscv-tests ISA suites",
    "riscv_arch_tests": "RISC-V architectural test suite",
    "epmp_generated": "Generated ePMP CSR and access tests",
    "pmp_directed": "Directed PMP: overlap, mseccfg lock, TOR edges and faults behind accesses",
    "counters_and_user_mode": "Counter enable and inhibit, and U-mode execution",
    "cheriot_isa_directed": "Directed CHERIoT instruction tests",
    "cheriot_random_operands": "CHERIoT instructions over random operands, checked by the cosim",
    "cheriot_stack_high_water_mark": "CHERIoT stack high water mark CSRs",
    "cheriot_illegal_instructions": "Illegal instructions in CHERIoT and RISC-V mode",
    "cheriot_rtos_patterns": "CHERIoT RTOS-pattern capability tests",
    "cheriot_temporal_safety": "CHERIoT temporal safety: store revocation and stale-pointer faults",
    "cheriot_enable_transition": "cheriot_enable_i 0 to 1 while running",
    "cheriot_enable_on_off": "cheriot_enable_i 1 to 0 during a capability store raises a major alert",
    "zcmp_push_pop_mv": "Zcmp push/pop/move: every rlist, stack adjustment and register pair",
    "counter_high_half_write": "Writes to the upper half of the 64-bit counters",
    "cheriot_fatal_err_mtcc": "A trap through an untagged MTCC raises a sticky major alert",
    "cheriot_enable_off": "Loads and stores unchecked while cheriot_enable_i is Off",
    "juliet_baremetal": "Juliet CWE memory-safety cases on bare metal",
    "whitebox_uarch": "White-box microarchitecture scenarios",
    "debug_directed": "Directed debug-mode tests: privilege changes, the Debug Module range, "
                      "trigger CSRs and single step",
    "cheriot_cpuctrl_hardening": "Dummy instructions and data-independent timing in CHERIoT mode",
    "port_toggle": "ibex_top port toggle coverage for hart_id_i and boot_addr_i",
    "rv32_decode_corners": "packu/packh, reserved OP-IMM encodings and HPM counter writes",
    "trap_timing_hazards": "Debug requests, NMIs and fetch drops timed to a data access's grant",
    "integrity_directed": "Directed bus integrity errors: internal NMI and fetch faults",
    "debug_module": "The real debug module driven over DMI, RISC-V and CHERIoT mode",
}

# One-line summary per covergroup.
CG_TITLES = {
    "uarch_cg": "Ibex microarchitecture: instruction categories, stalls, hazards and pipeline state",
    "cheriot_uarch_cg": "CHERIoT instructions, capability operands and their results",
    "cheriot_cfi_detail_cg": "CHERIoT control-flow integrity detail",
    "cheriot_obi_backpressure_cg": "CHERIoT memory accesses under bus back-pressure",
    "cheri_spatial_gap_cg": "Accesses just outside a capability's bounds",
    "cheri_interrupt_cheri_cg": "Interrupts taken during CHERIoT instructions",
    "pmp_region_cg": "PMP per-region configuration and access outcome",
    "pmp_top_cg": "PMP/ePMP global state: mseccfg, privilege and access type",
    "cheri_access_bounds_cg": "Data accesses within 10 bytes of capability bounds",
    "cheri_representability_cg": "Address changes within 10 bytes of the representable window",
    "cheri_mshwm_cg": "Stack high water mark CSR access, legalisation and store updates",
    "cheri_zero_len_perm_cg": "Zero-length and zero-permission capability operands",
    "cheri_illegal_insn_cg": "Illegal instructions by encoding class, CHERIoT mode and pin Off",
    "trvk_cg": "Load-barrier revocation check (ibex_trvk)",
}


# Hand-written description per covergroup: what it samples, what each coverpoint and cross is
# for. Paragraphs are strings, bullet lists are lists. Placed before the generated list of
# coverpoint names, so the name list stays complete even if this text lags behind the source.
CG_DETAILS = {
    "cheri_access_bounds_cg": [
        "Every CHERIoT-mode data access, sampled once in its first execute cycle from the signals "
        "the core's bounds check uses (base32, top33, the access address and size): plain loads "
        "and stores through a capability, and CLC/CSC, which are always 8 bytes. Debug mode and "
        "the unchecked second half of a misaligned access are not sampled.",
        ["cp_acc_type: 8 access types, load/store x byte/half/word/cap",
         "cp_acc_base_dist: access start minus base, one bin per byte from -10 to +10",
         "cp_acc_top_dist: access end minus top, one bin per byte from -10 to +10; using the end "
         "covers accesses that straddle top (a word at top-2 lands at +2)",
         "cp_acc_perm_ok: whether the access has the permission it needs, Load or Store",
         "cp_acc_auth: whether the authorising capability is untagged, sealed or valid",
         "cp_acc_bounds: whether the access starts below base, lies inside, or ends above top",
         "acc_base_edge_cross (168 bins): access type x distance from base",
         "acc_top_edge_cross (168 bins): access type x distance from top",
         "acc_fault_priority_cross (144 bins): access type x authority x permission x bounds"],
        "The priority cross covers accesses where several checks fail at once: which cause the "
        "core reports then is where a core and its model most often disagree, and the cosim "
        "compares the trap cause. Unreachable bins (for example a CLC/CSC address that is not "
        "8-byte aligned) are ignored, each with its reason.",
    ],
    "cheri_representability_cg": [
        "CSetAddr, CIncAddr, CIncAddrImm, AUIPCC and AUICGP on a tagged capability, sampled in "
        "the execute cycle: the new address (result_data_o) against the input capability -- "
        "rf_fullcap_a (cs1, or c3 for AUICGP) or PCC (pcc_cap_i) for AUIPCC. The window edges are "
        "the RTL's rule in ibex_cheriot_pkg::cheriot_set_address: the address is representable in "
        "[base, base + 2^(9+E)), or anywhere when E = 24. The older cheriot_uarch_cg crosses "
        "cheriot_cauipcc_cross and cheriot_cauicgp_cross also cross both instructions with the "
        "below/above-window cases (cp_cheri_cd_pcc_repr_cases, cp_cheri_cd_cs1_repr_cases).",
        ["cp_rep_op: CSetAddr, CIncAddr, CIncAddrImm, AUIPCC or AUICGP",
         "cp_rep_eclass: exponent class, E = 0, 1-7, 8-14 or 24 (whole address space)",
         "cp_rep_lo_dist: new address minus base, one bin per byte from -10 to +10",
         "cp_rep_hi_dist: new address minus the window's top, one bin per byte from -10 to +10; "
         "not sampled at E = 24, which has no upper edge",
         "cp_rep_lo_edge, cp_rep_hi_edge: the tag outcome exactly at each edge, both outcomes "
         "binned (below/base, last/past x cleared/kept)",
         "cp_rep_sealed_out: the outcome for a sealed input, which must always lose its tag",
         "rep_lo_edge_cross (84 bins): exponent class x lower-edge distance",
         "rep_hi_edge_cross (63 bins): exponent class x upper-edge distance, E = 24 ignored",
         "rep_op_eclass_cross (20 bins): instruction x exponent class",
         "cp_rep_outside, rep_op_outside_cross: every instruction with its new address inside "
         "and outside the window -- the representability-failure case",
         "cp_rep_edge_hit, rep_op_edge_cross: every instruction exactly at each edge (-1, -2, base; "
         "-1, -2, one past the top); AUIPCC's odd distances are ignored, since its PC is 2-aligned, "
         "the offset a multiple of 2048 and a PCC window above 2048 bytes needs an 8-aligned base",
         "cp_rep_auipcc_edge: AUIPCC's tag outcome at the even edge distances",
         "cp_rep_auicgp_sealed_out: AUICGP through a sealed c3 (must clear the tag)"],
        "There are deliberately no illegal_bins. The window formula is the RTL's implementation, "
        "while CHERIoT-Sail defines representability as the bounds decoding the same with the new "
        "address; illegal bins built on the RTL's formula would miss exactly a disagreement "
        "between the two. The group records which edges were reached; whether each outcome is "
        "right is the cosim's and TestRIG's call against Sail, so a below_kept or past_kept hit "
        "is checked there.",
    ],
}


CG_DETAILS["cheri_mshwm_cg"] = [
    "mshwm (0xBC1) and mshwmb (0xBC2), CHERIoT ISA section 'Stack high water mark' and "
    "CHERIoT-Sail (legalize_mshwm, ext_check_phys_mem_write, ext_check_CSR).",
    ["hwm_access_cross: CSR x read/write x PCC.SR in CHERIoT mode (without SR: capcause 0x18)",
     "cp_hwm_pin_off: the CSRs read and written with cheriot_enable_i Off (illegal instruction)",
     "cp_hwm_legalise: writes with bits [3:0] zero and nonzero, per CSR",
     "cp_hwm_store_pos x cp_hwm_store_kind / cp_hwm_store_err / cp_hwm_store_set: each store "
     "kind below, inside and above the window and with an empty window; faulting stores; "
     "whether the core updated mshwm",
     "cp_hwm_split: the second half of a misaligned store, which the ISA does not count"],
]
CG_DETAILS["cheri_zero_len_perm_cg"] = [
    "Tagged operands with length 0 (top = base) or permissions 0, by the instruction class that "
    "uses them, and CSetBounds* with length 0 at an address inside the bounds, at the top (the "
    "end of an object, still in bounds) and outside.",
]
CG_DETAILS["cheri_illegal_insn_cg"] = [
    "Illegal-instruction exceptions by encoding class (CHERI opcode, LOAD, STORE, JALR/BRANCH, "
    "MISC-MEM, SYSTEM, CSR, OP/OP-IMM, other opcodes, 16-bit, x16-x31), separately in CHERIoT "
    "mode and with the pin Off; in CHERIoT mode mtval must be 0 (illegal_bins), as "
    "CHERIoT-Sail's handle_illegal gives with the C platform's settings.",
]


def read_testlist(path):
    """Minimal parser for the testlist YAML: '- test: NAME' entries with config/test_srcs and a
    folded description. Only these fields are read, so no YAML library is needed."""
    tests, cur, in_desc = [], None, False
    for line in path.read_text().splitlines():
        m = re.match(r"^- test:\s*(\S+)", line)
        if m:
            cur = {"name": m.group(1), "list": path.name, "config": "", "src": "", "desc": ""}
            tests.append(cur)
            in_desc = False
            continue
        if cur is None:
            continue
        m = re.match(r"^\s+(config|test_srcs):\s*(\S+)", line)
        if m:
            cur["config" if m.group(1) == "config" else "src"] = m.group(2)
            in_desc = False
        elif re.match(r"^\s+(description|desc):\s*>", line):
            in_desc = True
        elif in_desc and re.match(r"^\s{4,}\S", line):
            cur["desc"] += (" " if cur["desc"] else "") + line.strip()
        elif re.match(r"^\s+\w+:", line):
            in_desc = False
    return tests


def read_covergroups(path):
    """Covergroups with their coverpoints/crosses; items inside `ifdef CHERIOT_FCOV_LARGE_CROSSES
    are marked as compiled out by default."""
    cgs, cg, stack, pending = [], None, [], None
    for line in path.read_text().splitlines():
        if re.match(r"^\s*//", line):
            continue
        # 'name :' with 'coverpoint'/'cross' on the next line
        if cg and pending:
            m = re.match(r"^\s*(coverpoint|cross)\b", line)
            if m:
                off = ("ifdef", "CHERIOT_FCOV_LARGE_CROSSES") in stack
                cg["items"].append((pending, m.group(1), off))
            pending = None
        # lowRISC dv_fcov_macros.svh: `DV_FCOV_EXPR_SEEN(NAME_, ...) is 'cp_NAME_: coverpoint ...'
        m = re.match(r"^\s*`DV_FCOV_EXPR_SEEN\(\s*(\w+)\s*,", line)
        if cg and m:
            off = ("ifdef", "CHERIOT_FCOV_LARGE_CROSSES") in stack
            cg["items"].append((f"cp_{m.group(1)}", "coverpoint", off))
            continue
        m = re.match(r"^\s*(\w+)\s*:\s*$", line)
        if cg and m:
            pending = m.group(1)
            continue
        m = re.match(r"^\s*`(ifdef|ifndef|else|endif)\b\s*(\w*)", line)
        if m:
            kw, arg = m.groups()
            if kw in ("ifdef", "ifndef"):
                stack.append((kw, arg))
            elif kw == "else" and stack:
                k, a = stack[-1]
                stack[-1] = ("ifndef" if k == "ifdef" else "ifdef", a)
            elif kw == "endif" and stack:
                stack.pop()
            continue
        m = re.match(r"^\s*covergroup\s+(\w+)", line)
        if m:
            cg = {"name": m.group(1), "items": []}
            cgs.append(cg)
            continue
        if cg and re.match(r"^\s*endgroup", line):
            cg = None
            continue
        m = re.match(r"^\s*(\w+)\s*:\s*(coverpoint|cross)\b", line)
        if cg and m:
            off = ("ifdef", "CHERIOT_FCOV_LARGE_CROSSES") in stack
            cg["items"].append((m.group(1), m.group(2), off))
    return cgs


# Layout of the lowRISC testplan templates: ibex/dv/uvm/icache/data/ibex_icache_testplan.hjson and
# dvsim's util/dvsim/examples/testplanner/foo_testplan.hjson -- licence header, unquoted keys, one
# block per testpoint separated by a blank line, desc as a '''...''' block whose first line is a
# one-line summary, then stage and tests; covergroups as name + desc blocks.
DESC_INDENT = " " * 12
WIDTH = 100


def read_spec_coverage(path):
    """Coverpoint/cross text from the spec's Functional Coverage chapter.

    Table rows whose first cell names items (| `cp_a`, `cp_b` | description | requirements |) give
    those items their description and requirement IDs. An item the chapter names only in prose
    maps to the heading of the section that first names it. Returns (rows, prose)."""
    if not path.exists():
        print(f"note: {path.name} not found; coverpoints get no spec descriptions", file=sys.stderr)
        return {}, {}
    lines = path.read_text().splitlines()
    start = next((i for i, l in enumerate(lines) if l.startswith("## Functional Coverage")), None)
    if start is None:
        return {}, {}
    end = next((i for i, l in enumerate(lines) if i > start and l.startswith("## ")), len(lines))
    def split_row(line):
        return [c.strip().replace("\\|", "|")
                for c in re.split(r"(?<!\\)\|", line.strip().strip("|"))]

    rows, prose, section = {}, {}, "Functional Coverage"
    req_col = None  # the current table's Requirement(s) column, from its header row
    for line in lines[start:end]:
        if line.startswith("#"):
            section = line.lstrip("#").strip()
        elif line.startswith("|") and not line.startswith("| `"):
            header = split_row(line)
            if not all(re.fullmatch(r":?-+:?", c) for c in header):
                req_col = next((i for i, c in enumerate(header) if c.startswith("Requirement")),
                               None)
        elif line.startswith("| `"):
            cells = split_row(line)
            text = cells[1] if len(cells) > 1 else ""
            reqs = cells[req_col] if req_col is not None and req_col < len(cells) else ""
            for name in re.findall(r"`(\w+)`", cells[0]):
                rows.setdefault(name, (text, reqs))
        else:
            for name in re.findall(r"`(\w+)`", line):
                prose.setdefault(name, section)
    return rows, prose


def test_details(ts):
    """Per-test descriptions from the test lists, tests sharing one description grouped; tests
    whose description only restates the name are summarised by their test list instead."""
    groups, plain = {}, {}
    for t in sorted(ts, key=lambda t: t["name"]):
        if t["desc"] and not BOILERPLATE_DESC.match(t["desc"]):
            groups.setdefault(t["desc"], []).append(t["name"])
        else:
            plain.setdefault(t["list"], []).append(t["name"])
    details = []
    if groups:
        details.append([f"{', '.join(names)}: {desc}" for desc, names in groups.items()])
    for lst, names in plain.items():
        details.append(f"Generated tests from {lst}; each name encodes its scenario "
                       f"({names[0]} ... {names[-1]}).")
    return details


def coverpoint_details(cg, rows, prose):
    """Each coverpoint/cross with its spec text and requirement IDs; items the hand-written
    CG_DETAILS already describe are left to it. Items with no spec table row are named, so a
    missing description is visible."""
    handwritten = repr(CG_DETAILS.get(cg["name"], ""))
    described, in_prose, missing = {}, {}, []
    for name, _, _ in cg["items"]:
        if re.search(rf"\b{name}\b", handwritten):
            continue
        if name in rows:
            described.setdefault(rows[name], []).append(name)
        elif name in prose:
            in_prose.setdefault(prose[name], []).append(name)
        else:
            missing.append(name)
    details = []
    if described:
        details.append("From the verification spec (Functional Coverage):")
        details.append([f"{', '.join(names)}: {text}" + (f" [{reqs}]" if reqs else "")
                        for (text, reqs), names in described.items()])
    for section, names in in_prose.items():
        details.append(f"Described in the verification spec, section '{section}': "
                       + ", ".join(names) + ".")
    if missing:
        details.append("Not described in the verification spec: " + ", ".join(missing) + ".")
    return details


def desc_block(summary, paragraphs):
    """desc: '''<summary>\n\n<paragraphs, wrapped and indented under the opening quotes>'''"""
    lines = [summary]
    for p in paragraphs:
        lines.append("")
        if isinstance(p, list):  # a bullet list, wrapped with a hanging indent
            for item in p:
                lines += textwrap.wrap(item, WIDTH - len(DESC_INDENT) - 3, initial_indent="- ",
                                       subsequent_indent="  ")
        else:
            lines += textwrap.wrap(p, WIDTH - len(DESC_INDENT) - 3)  # room for the closing '''
    out = "      desc: '''" + lines[0]
    for line in lines[1:]:
        out += "\n" + (DESC_INDENT + line if line else "")
    return out + "'''"


def tests_block(names):
    """tests: ["a", "b", ...] wrapped like the templates' multi-test entries."""
    items = [f'"{n}"' for n in names]
    lines, cur = [], ""
    for it in items:
        cand = f"{cur}, {it}" if cur else it
        if cur and len("      tests: [" + cand) + 1 > WIDTH:  # +1: the "," or "]"
            lines.append(cur + ",")
            cur = it
        else:
            cur = cand
    lines.append(cur)
    pad = " " * len("      tests: [")
    return "      tests: [" + ("\n" + pad).join(lines) + "]"


def render(testpoints, covergroups):
    out = [
        "// Copyright lowRISC contributors.",
        "// Licensed under the Apache License, Version 2.0, see LICENSE for details.",
        "// SPDX-License-Identifier: Apache-2.0",
        "//",
        "// GENERATED by ibex/dv/testplans/gen_core_ibex_testplan.py from the core_ibex test lists and fcov",
        "// sources -- edit FAMILIES there and rerun `make testplan-uvm-gen`, not this file.",
        "{",
        '  name: "core_ibex"',
        "",
        "  testpoints: [",
    ]
    blocks = []
    for tp in testpoints:
        blocks.append("\n".join([
            "    {",
            f"      name: {tp['name']}",
            desc_block(tp["summary"], tp["details"]),
            f"      stage: {tp['stage']}",
            "      tags: [" + ", ".join(f'"{t}"' for t in tp["tags"]) + "]",
            tests_block(tp["tests"]),
            "    }",
        ]))
    out.append("\n\n".join(blocks))
    out += ["  ]", "", "  covergroups: ["]
    blocks = []
    for cg in covergroups:
        blocks.append("\n".join([
            "    {",
            f"      name: {cg['name']}",
            desc_block(cg["summary"], cg["details"]),
            "    }",
        ]))
    out.append("\n\n".join(blocks))
    out += ["  ]", "}", ""]
    return "\n".join(out)


def main():
    tests = [t for tl in TESTLISTS for t in read_testlist(tl)]
    selected = {name: [] for name, *_ in FAMILIES}
    errors = []
    for t in tests:
        fams = [name for name, _, _, _, sel in FAMILIES if sel(t)]
        if not fams:
            errors.append(f"{t['list']}: {t['name']} is in no testpoint family")
        elif len(fams) > 1:
            errors.append(f"{t['list']}: {t['name']} is in several families: {fams}")
        else:
            selected[fams[0]].append(t)
    if errors:
        print("\n".join(errors), file=sys.stderr)
        sys.exit(f"{len(errors)} test(s) not assigned exactly once -- extend FAMILIES")

    testpoints = []
    for name, stage, tags, desc, _ in FAMILIES:
        ts = selected[name]
        if not ts:
            sys.exit(f"family {name} selects no tests -- stale rule?")
        details = [desc] + test_details(ts)
        testpoints.append({"name": name, "summary": TITLES[name], "details": details,
                           "stage": stage, "tags": tags,
                           "tests": sorted({t["name"] for t in ts})})

    covergroups = []
    n_items = 0
    spec_rows, spec_prose = read_spec_coverage(SPEC)
    for path in FCOV:
        for cg in read_covergroups(path):
            n_items += len(cg["items"])
            on = [n for n, k, o in cg["items"] if not o]
            off = [n for n, k, o in cg["items"] if o]
            details = list(CG_DETAILS.get(cg["name"], []))
            details += coverpoint_details(cg, spec_rows, spec_prose)
            details += [f"Source: fcov/{path.name}. {len(cg['items'])} coverpoints and crosses, "
                        f"sampled in the main core only (the lockstep shadow core is excluded).",
                       "Built by default: " + ", ".join(on) + "."]
            if off:
                details.append("Compiled out unless CHERIOT_FCOV_LARGE_CROSSES is defined "
                               "(make ... FCOV_LARGE_CROSSES=1): " + ", ".join(off) + ".")
            covergroups.append({"name": cg["name"],
                                "summary": CG_TITLES.get(cg["name"], cg["name"]),
                                "details": details})
        missing = [c["name"] for c in covergroups if c["name"] not in CG_TITLES]
        if missing:
            sys.exit(f"no CG_TITLES entry for {missing} -- add one")

    OUT.write_text(render(testpoints, covergroups))
    print(f"{OUT.relative_to(REPO)}: {len(testpoints)} testpoints, {len(tests)} tests, "
          f"{len(covergroups)} covergroups, {n_items} coverpoints/crosses")


if __name__ == "__main__":
    main()
