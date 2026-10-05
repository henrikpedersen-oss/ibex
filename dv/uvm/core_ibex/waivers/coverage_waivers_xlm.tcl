# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Apply one exclusion; if IMC rejects it (pattern matches nothing in this model) say so in the log,
# grep-able as IBEX_WAIVER_NOT_APPLIED, and carry on with the rest of the file instead of stopping.
proc ibex_waive {args} {
  if {[catch {uplevel 1 $args} msg]} {
    puts "IBEX_WAIVER_NOT_APPLIED: $args -- $msg"
  }
}

# Exclude standard primitives that are verified elsewhere
exclude -type "prim_lfsr"
exclude -type "prim_prince"

# The secded primitives are verified in OpenTitan using FPV
exclude -type "prim_secded*"

# Exclude code coverage from aux code used for gathering functional coverage
exclude -type "core_ibex_fcov_if*" -metrics code:statement:fsm:assertion
exclude -type "core_ibex_pmp_fcov_if*" -metrics code:statement:fsm:assertion
ibex_waive exclude -type "core_ibex_trvk_fcov_if*" -metrics code:statement:fsm:assertion

# Vendor push_pull agent covergroups (push_pull_agent_pkg, used here only as the scrambling-key
# device). They measure the agent's handshake, not the DUT, and are never sampled (the monitor's
# sampling is a TODO upstream), so they only add 0-hit bins to the functional total. Packages show
# up as a type in type-based reports and as an instance in instance-based ones, hence both forms.
ibex_waive exclude -type "push_pull_agent_pkg"
ibex_waive exclude -inst "push_pull_agent_pkg"

# RVFI signals not present in real design so not relevant to coverage closure
exclude -type "ibex_top" -toggle "rvfi*"
# hart_id_i and boot_addr_i are intended to be hard-wired inputs that do not
# toggle
exclude -type "ibex_top" -toggle "hart_id_i"
exclude -type "ibex_top" -toggle "boot_addr_i"
# ram_cfg_i is a passthrough set of signals to provide memory instance specific
# data and have no functional impact on the design. This ibex_top has split it
# into ram_cfg_icache_tag_i / ram_cfg_icache_data_i (core_ibex_tb_top.sv ties both
# to RAM_1P_CFG_REQ_DEFAULT); "ram_cfg_i.*" matches nothing here.
ibex_waive exclude -type "ibex_top" -toggle "ram_cfg_i.*"
ibex_waive exclude -type "ibex_top" -toggle "ram_cfg_icache_tag_i*"
ibex_waive exclude -type "ibex_top" -toggle "ram_cfg_icache_data_i*"
# The matching responses are constant by construction, not by the testbench:
# prim_ram_1p (generic) assigns cfg_o = RAM_1P_CFG_RSP_DEFAULT, and ibex_top
# assigns the same constant when ICache=0. No stimulus can toggle them.
ibex_waive exclude -type "ibex_top" -toggle "ram_cfg_icache_tag_o*"
ibex_waive exclude -type "ibex_top" -toggle "ram_cfg_icache_data_o*"

# Inputs core_ibex_tb_top.sv ties to a constant. Only tie-offs are waived here: every
# input the testbench drives (bus, irq, debug_req, fetch_enable_i, cheriot_enable_i,
# mcounteren_writable_i, scramble key/nonce/valid, TRVK revbm handshake) is still scored.
# test_en_i is NOT waived: core_ibex_tb_top.sv drives it (+test_en_pct, default 10% of cycles)
# so the clock gates' test-enable term is exercised.
# scan_rst_ni: tied 1'b1. DFT scan reset; with test_en_i high it is the lockstep shadow
# core's reset (ibex_lockstep.sv), which the TB keeps deasserted.
ibex_waive exclude -type "ibex_top" -toggle "scan_rst_ni"
# trvk_heap_base_addr_i and trvk_revbm_err_i are NOT waived (both were, as tie-offs, until
# 2026-10-01): ibex_revbm_responder now drives them from ibex_revbm_pkg -- the heap base is
# drawn per seed (or +revbm_heap_base), revbm_err from +revbm_err_pct/+revbm_err_list. Bits the
# heap-base draw cannot reach (it is 8-byte aligned, [2:0] always 0 per HeapBaseAligned_A, and
# only a few values are drawn per regression) will show as toggle holes; waive those bits
# individually if they are judged unreachable, not the whole port.
# Not waived either: trvk_revbm_rdata_i / trvk_revbm_rdata_intg_i. Driven by the responder,
# which revokes only with +revbm_mode=random|range: their toggle coverage records whether the
# regression ran the revocation tests (cheriot_revoke_load_barrier*).

# ── ECC error coverpoints ────────────────────────────────────────────────────
# cp_rf_a_ecc_err, cp_rf_b_ecc_err, cp_icache_ecc_err are DV_FCOV_EXPR_SEEN
# coverpoints that fire when ECC errors are injected into the register file
# ports or the I-cache. The opentitan TB configuration does not inject ECC
# faults at the register-file or I-cache level (icache ECC requires a separate
# fault-injection agent not present in this regression). These coverpoints are
# structurally unreachable in the current configuration.
ibex_waive exclude -type "core_ibex_fcov_if" -coveritem "fcov_cg.cp_rf_a_ecc_err"
ibex_waive exclude -type "core_ibex_fcov_if" -coveritem "fcov_cg.cp_rf_b_ecc_err"
ibex_waive exclude -type "core_ibex_fcov_if" -coveritem "fcov_cg.cp_icache_ecc_err"

# ── Fetch FIFO coverpoints (item 3) ─────────────────────────────────────────
# With ICache=1 (opentitan config), the generate block g_fcov_fetch_fifo in
# core_ibex_fcov_if.sv is not elaborated; g_no_fcov_fetch_fifo drives all five
# probes to 0. The iff guards on these coverpoints therefore never become true.
# These can only be exercised by a separate non-ICache regression configuration,
# which is not in scope for the current opentitan-config coverage target.
# Syntax: IMC -coveritem format is <cg_name>.<item_name> (help exclude).
ibex_waive exclude -type "core_ibex_fcov_if" -coveritem "fcov_cg.cp_fetch_fifo_bypass"
ibex_waive exclude -type "core_ibex_fcov_if" -coveritem "fcov_cg.cp_fetch_fifo_clear_while_full"
ibex_waive exclude -type "core_ibex_fcov_if" -coveritem "fcov_cg.cp_fetch_push_during_pop"
ibex_waive exclude -type "core_ibex_fcov_if" -coveritem "fcov_cg.cp_fetch_unaligned_compressed"
ibex_waive exclude -type "core_ibex_fcov_if" -coveritem "fcov_cg.cp_fetch_unaligned_uncompressed"

# ── TRVK cross bins — structurally or logically unreachable ─────────────────
#
# trvk_revoked_source_cross (cross of revoked × bitmap × err × intg):
#   revbm_revoked = rdata[bit_select] || revbm_err_i || |intg_error (trvk.sv:363).
#   (a) not_revoked with any source=1: contradicts revbm_revoked==0 — impossible.
#   (b) revoked with all sources=0: contradicts revbm_revoked==1 — impossible.
#   (c) revoked with multiple simultaneous sources: theoretically possible but
#       the TB injects one fault type at a time so unreachable in this regression.
#
# trvk_sealing_cross (cross of revoked × sealing_cap):
#   revbm_req_required requires !is_sealing_cap (trvk.sv:349). Sealing caps skip
#   the bitmap entirely; assertion RevbmRspOnlyWhenOutstanding_A (trvk.sv:413)
#   prevents unsolicited responses. So revbm_rvalid_i is only high when a
#   non-sealing cap is at the FIFO head, making sealing=1 cross bins impossible.
#   Note: cp_trvk_sealing_cap (individual CP) IS 100% covered by
#   cheriot_revoke_load_barrier tests 21-30; the cross just cannot be sampled.
#
# trvk_revoked_outstanding_cross (cross of revoked × outstanding):
#   The same assertion (rvalid_i |-> outstanding_q) guarantees outstanding_q==1
#   whenever rvalid_i is asserted. cp_trvk_revoked samples on rvalid_i, so
#   outstanding=0 bins can never be hit.
#
# Syntax: IMC -coverbin format is <cg_name>.<cross_name>.<bin_name> where
# cross bin names use the _X_ separator between per-CP bin names (help exclude).
ibex_waive exclude -type "core_ibex_trvk_fcov_if" -coverbin "trvk_cg.trvk_sealing_cross.not_revoked_X_auto[1]"
ibex_waive exclude -type "core_ibex_trvk_fcov_if" -coverbin "trvk_cg.trvk_sealing_cross.revoked_X_auto[1]"
ibex_waive exclude -type "core_ibex_trvk_fcov_if" -coverbin "trvk_cg.trvk_revoked_outstanding_cross.not_revoked_X_auto[0]"
ibex_waive exclude -type "core_ibex_trvk_fcov_if" -coverbin "trvk_cg.trvk_revoked_outstanding_cross.revoked_X_auto[0]"
ibex_waive exclude -type "core_ibex_trvk_fcov_if" -coverbin "trvk_cg.trvk_revoked_source_cross.not_revoked_X_auto[0]_X_auto[0]_X_auto[1]"
ibex_waive exclude -type "core_ibex_trvk_fcov_if" -coverbin "trvk_cg.trvk_revoked_source_cross.not_revoked_X_auto[0]_X_auto[1]_X_auto[0]"
ibex_waive exclude -type "core_ibex_trvk_fcov_if" -coverbin "trvk_cg.trvk_revoked_source_cross.not_revoked_X_auto[0]_X_auto[1]_X_auto[1]"
ibex_waive exclude -type "core_ibex_trvk_fcov_if" -coverbin "trvk_cg.trvk_revoked_source_cross.not_revoked_X_auto[1]_X_auto[0]_X_auto[0]"
ibex_waive exclude -type "core_ibex_trvk_fcov_if" -coverbin "trvk_cg.trvk_revoked_source_cross.not_revoked_X_auto[1]_X_auto[0]_X_auto[1]"
ibex_waive exclude -type "core_ibex_trvk_fcov_if" -coverbin "trvk_cg.trvk_revoked_source_cross.not_revoked_X_auto[1]_X_auto[1]_X_auto[0]"
ibex_waive exclude -type "core_ibex_trvk_fcov_if" -coverbin "trvk_cg.trvk_revoked_source_cross.not_revoked_X_auto[1]_X_auto[1]_X_auto[1]"
ibex_waive exclude -type "core_ibex_trvk_fcov_if" -coverbin "trvk_cg.trvk_revoked_source_cross.revoked_X_auto[0]_X_auto[0]_X_auto[0]"
ibex_waive exclude -type "core_ibex_trvk_fcov_if" -coverbin "trvk_cg.trvk_revoked_source_cross.revoked_X_auto[0]_X_auto[1]_X_auto[1]"
ibex_waive exclude -type "core_ibex_trvk_fcov_if" -coverbin "trvk_cg.trvk_revoked_source_cross.revoked_X_auto[1]_X_auto[0]_X_auto[1]"
ibex_waive exclude -type "core_ibex_trvk_fcov_if" -coverbin "trvk_cg.trvk_revoked_source_cross.revoked_X_auto[1]_X_auto[1]_X_auto[0]"
ibex_waive exclude -type "core_ibex_trvk_fcov_if" -coverbin "trvk_cg.trvk_revoked_source_cross.revoked_X_auto[1]_X_auto[1]_X_auto[1]"

set waiver_dir [file dirname [file normalize [info script]]]

# The two .vRefine files are item-level refinements recorded in 2022 against upstream ibex's
# coverage model (modelCheckSum 1554954276 in their headers), not reviewed for this design. dvsim's
# own report keeps loading them. The repo-level coverage merge (run_all_tests.sh) sets
# ::ibex_cov_skip_refinements so its numbers only carry the reasoned, rule-based waivers above.
if {[info exists ::ibex_cov_skip_refinements] && $::ibex_cov_skip_refinements} {
  puts "IBEX_WAIVERS: rule-based waivers applied; aux_code.vRefine/unr.vRefine not loaded"
} else {
# Waivers for code related to memory loading and obtaining scramble keys used by
# the testbench environment
load -refinement "$waiver_dir/aux_code.vRefine"
# Waivers for unreachable code, created manually (via the IMC GUI)
load -refinement "$waiver_dir/unr.vRefine"
}
