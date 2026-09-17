# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# JasperGold script for VeriCHERI formal verification of CHERIoT-Ibex.
# Checks the representability and monotonicity invariants from RPTU-EIS/VeriCHERI
# without requiring the Sail functional spec (independent of verify-cheriot.tcl).
#
# Run via:  make vericcheri        (batch)
#           make vericcheri-gui    (interactive)

# jg's startup script clears LD_LIBRARY_PATH and only re-adds Linux64/lib,
# leaving out jasper_cloud/lib, which jg_bridge needs for its AWS SDK libs.
# verify.tcl repairs the path for that reason, so do the same here — it is cheap
# and keeps the environment consistent with the sibling scripts.
if {[info exists env(JASPER_INSTALL_DIR)]} {
	set _jgclib "$env(JASPER_INSTALL_DIR)/Linux64/jasper_cloud/lib"
	if {[file isdirectory $_jgclib]} {
		if {[info exists env(LD_LIBRARY_PATH)]} {
			set env(LD_LIBRARY_PATH) "$_jgclib:$env(LD_LIBRARY_PATH)"
		} else {
			set env(LD_LIBRARY_PATH) $_jgclib
		}
	}
}

# Delete counterexample traces from any previous run before this one starts.
# They are only rewritten for properties that fail *this* time, so a property
# that has since been fixed leaves its old trace sitting next to a fresh report,
# reading as current.  That happened: a run at 09:24 sat beside cex_*.vcd files
# from 08:25 for two properties that no longer failed, and the stale traces were
# nearly analysed as if they described the new result.  Clearing them here means
# a trace present after a run always belongs to that run.
foreach _stale [glob -nocomplain cex_*.vcd] {
    file delete -force $_stale
}
file delete -force vericcheri_report.txt

clear -all

# Repairing LD_LIBRARY_PATH above is NOT sufficient on nyx.  It was tried on its
# own and every proof thread still died identically:
#
#   ERROR (EPF117): Unable to start Jasper advanced job dispatch and management process.
#   ProofGrid usable level: 0
#   ERROR (EPF044): Unable to create proof process.
#
# All seven asserts aborted — 0 proven, 0 counterexamples — on threads 4, 6, 10,
# 13, 15, 19 and 20.  So the bridge daemon cannot start on this machine for a
# reason the library path does not explain, and must be disabled outright.  This
# is the same conclusion cheriot_rtlcover.tcl reached, in the same words.
#
# Cost: no parallel job dispatch.  MonoStep previously needed 3600s per property
# while running at 99.95 % ProofGrid utilisation across 10 jobs, so expect it to
# be substantially slower here and possibly not to converge.  ReprBase/ReprStep
# are documented as quick and should be unaffected.  A slow proof beats none.
set_proofgrid_bridge off

# ── Proof cache: deliberately OFF ─────────────────────────────────────────────
# The cache is keyed on the COI signature, which does not appear to account for
# changes to the assume configuration.  When this flow still used a phase split
# that toggled assumes, an entry created with them enabled was served to a run
# that had disabled them:
#
#   INFO (IPF057): 0.0.Cache: The property "VeriCHERI_ReprBase" was proven in 0.00 s
#
# "proven in 0.00 s" is the same symptom that flagged the original vacuity
# problem — the fix ran and its result was then discarded for the stale entry.
#
# The phase split is gone, but the hazard is not: any future change to
# LoadedCapRepr or the other assumes has the same shape.  Correctness beats
# re-run time for a signoff proof, so the cache stays off.  If it is ever
# re-enabled, jgproofs-vericcheri must be deleted whenever an assume changes,
# because JasperGold will not do it for you.
set_prove_cache off

# MonoStep needs more than the 600 s previously set here: on nyx it hit exactly
# that limit ("Stopped processing property VeriCHERI_MonoStep [603.11 s]") while
# still making progress, with ProofGrid at 99.95 % utilisation across 10 jobs
# and 7.2 GB peak RSS.  ReprBase/ReprStep are quick and unaffected by the raise.
set_prove_per_property_time_limit 3600s

# Load ibex RTL (same fusesoc filelist as verify-cheriot.tcl)
analyze -sv12 +define+SYNTHESIS \
    -f_relative_to_file_location \
    build/fusesoc/lowrisc_ibex_ibex_formal_0.1/default-vcs/lowrisc_ibex_ibex_formal_0.1.scr

# Load VeriCHERI top.  -incdir adds VeriCHERI/CHERIoT-invariants/ to the search
# path so the `include "symbolic_*.sv" statements in vericcheri_top.sv resolve.
analyze -sv12 +define+CHERIOT_FORMAL \
    -incdir ../../../VeriCHERI/CHERIoT-invariants \
    check/vericcheri_top.sv

# Blackbox multiplier/divider units — irrelevant to capability monotonicity
# and contribute significant state space that slows MonoStep induction.
elaborate -top vericcheri_top -disable_auto_bbox \
    -bbox_m BUFGCE \
    -bbox_m ibex_multdiv_slow \
    -bbox_m ibex_multdiv_fast

clock clk_i
reset ~rst_ni

assume -name CheriotEnabled {cheriot_enable_i == IbexMuBiOn}

# After reset the writeback stage holds no valid (tagged) capability — its
# fields are don't-care in hardware.  Without this, the formal engine can
# assign an arbitrary exp to cheriot_rf_wcap_q and produce a spurious ReprBase CEX.
assume -name WbCapNotValidAtReset \
    {$rose(rst_ni) |-> !ibex_top_i.u_ibex_core.wb_stage_i.g_writeback_stage.cheriot_rf_wcap_q.valid}

# Dead while the bridge is off — JasperGold answers these with
#   WARNING (WBR001): Jasper advanced job dispatch and management feature is
#   disabled. All related settings will be ignored.
# Kept, commented, because they are the settings to restore if the bridge is
# ever fixed on this machine; MonoStep was tuned against exactly these values.
# set_proofgrid_max_local_jobs 10
# set_proofgrid_per_engine_max_local_jobs 8

# ── Single-pass proof ─────────────────────────────────────────────────────────
# There is no longer a phase split.  It existed because WbReprAssume and
# RegfileReprAssume assumed wb_repr() and regfile_repr() at every cycle — the
# same predicates ReprBase and ReprStep assert — making two of their four
# conjuncts vacuous.  Disabling those assumes for phase 1 and re-enabling them
# for phase 2 did not fix it: ReprBase then proved genuinely, but ReprStep
# produced a counterexample at 7 cycles, and phase 2's justification ("phase 1
# has just proved them") was void whenever phase 1 failed.
#
# Both assumes are replaced in vericcheri_top.sv by LoadedCapRepr, which
# constrains capabilities arriving from memory rather than the property being
# proved.  Being an environment constraint it is sound at all cycles, so all
# three properties can be proved in one pass and each has to do real work.
#
# ── Engine selection ──────────────────────────────────────────────────────────
# Hp alone is a *bounded* engine.  It closed ReprBase and ReprStep_Pcc with an
# Infinite bound, but on the harder inductive steps it can only report "no
# counterexample to depth N" -- the last run reached bounds 10/16/26/15 without
# converging.  Proving those needs an unbounded method, so N (interpolation) is
# added here.
#
# This is an experiment: N normally dispatches through ProofGrid, which is
# disabled above because its bridge cannot start on nyx (EPF117).  Whether N can
# run in-process the way Hp does is untested.  Hp is listed first so that if N
# cannot start we should still get the bounded results we already had, rather
# than losing everything -- confirm that in the log before reading the outcome.
prove -bg -engine_mode {Hp N} -property {vericcheri_top.VeriCHERI_ReprBase}
prove -bg -engine_mode {Hp N} -property {vericcheri_top.VeriCHERI_ReprStep}
prove -bg -engine_mode {Hp N} -property {vericcheri_top.VeriCHERI_MonoStep}

# Diagnostic split of ReprStep — same antecedent, one conjunct each.  Their
# conjunction is equivalent to ReprStep, so this adds no assumption; it only
# tells us *which* piece of architectural state breaks the invariant.  It has
# already earned its keep: it localised the writeback-mux counterexample to
# regfile_repr() immediately.  No longer cheap now that the spurious
# counterexamples are gone -- these run to the time limit -- but the split costs
# nothing extra, since each sub-property would have to be proved anyway.
prove -bg -engine_mode {Hp N} -property {vericcheri_top.VeriCHERI_ReprStep_Regfile}
prove -bg -engine_mode {Hp N} -property {vericcheri_top.VeriCHERI_ReprStep_Wb}
prove -bg -engine_mode {Hp N} -property {vericcheri_top.VeriCHERI_ReprStep_Scrs}
prove -bg -engine_mode {Hp N} -property {vericcheri_top.VeriCHERI_ReprStep_Pcc}

# Vacuity checks: the antecedents of both inductive steps need reachability
# covers, or the implications could hold trivially.  They are SVA `cover
# property` in check/vericcheri_top.sv, not `cover` commands here.
#
# They used to be here, and it broke every run.  A TCL-level cover over an
# expression cannot resolve calls to the SystemVerilog functions these
# predicates are built from:
#
#   ERROR (ENL002): Unable to find signal "vericcheri_top.regfile_repr()".
#   ERROR: problem encountered at line 99 in file verify-vericcheri.tcl
#
# A TCL error aborts the script, so `prove -wait` and the results capture below
# never ran, the backgrounded proofs were orphaned, and the run looked like it
# had crashed with no summary — leaving JasperGold at its console printing
# "Use the 'exit' command to exit." until the session died.  Do not move
# anything referencing those predicates back into this file.
#
# They must also be proved explicitly.  `prove -property` only runs the
# properties it is named, so listing just the seven asserts above left every
# cover "unprocessed" — the first real run reported 11 covers, 100 %
# unprocessed.  That silently defeats their entire purpose: an unreachable
# antecedent makes its implication vacuously true and nothing was checking.
prove -bg -engine_mode {Hp N} -property {vericcheri_top.ReprStepAntecedentReachable}
prove -bg -engine_mode {Hp N} -property {vericcheri_top.MonoStepAntecedentReachable}
prove -bg -engine_mode {Hp N} -property {vericcheri_top.LoadedCapRepr_NotVacuous}

prove -wait

# ── Results and counterexample capture ────────────────────────────────────────
# A batch run otherwise leaves nothing behind but log lines, so every failure
# costs a full re-run to inspect.  Write a summary, then dump a VCD per failing
# property.  Everything here is wrapped in catch: a diagnostic that aborts the
# script would throw away the proof results it exists to explain.
if {[catch {report -force -file vericcheri_report.txt -results -summary} err]} {
    puts "WARN: could not write vericcheri_report.txt: $err"
}

if {[catch {set failing [get_property_list -include {type assert status cex}]} err]} {
    puts "WARN: could not enumerate failing properties: $err"
    set failing {}
}

foreach prop $failing {
    set stem [string map {. _ : _ [ _ ] _} $prop]
    if {[catch {
        visualize -violation -property $prop -new_window
        visualize -save -vcd cex_${stem}.vcd
    } err]} {
        puts "WARN: could not dump trace for $prop: $err"
    }
}

# ── Exit status ───────────────────────────────────────────────────────────────
# `exit 0` used to be unconditional here, which made the exit code report only
# "JasperGold ran", not "the properties were proved".  run_all_tests.sh derives
# PASS/FAIL purely from that code, so an aborted proof was reported as
#
#   [PASS] VeriCHERI formal done
#
# with nothing proven at all.  That happened for real when ProofGrid failed to
# start (EPF117/EPF044): every proof aborted, and the run still passed.
#
# Exit non-zero unless every assert actually reached "proven".  The zero-assert
# case is treated as a failure too: if the property list is empty the proof
# never ran, which must never be reported as success.
set vericcheri_rc 1
if {[catch {
    set n_assert  [llength [get_property_list -include {type assert}]]
    set n_proven  [llength [get_property_list -include {type assert status proven}]]
    set n_cex     [llength [get_property_list -include {type assert status cex}]]
    # An unreachable cover means the matching antecedent can never occur, so the
    # implication it guards holds vacuously and proves nothing.  A vacuous pass
    # is worse than a failure because it looks like success, so it fails the run
    # even when every assertion is "proven".
    #
    # LoadedCapRepr_NotVacuous is the documented exception.  data_tag_i is tied
    # to 1'b0 in vericcheri_top.sv, so no tagged capability can ever arrive from
    # memory and LoadedCapRepr is inert by construction.  That is a known scope
    # limitation (capabilities loaded from memory are outside this proof), not a
    # defect, so it is reported and does not fail the run.  It is exactly what
    # the cover exists to surface.  Any *other* unreachable cover is real.
    set _unreach_all [get_property_list -include {type cover status unreachable}]
    set _unreach_bad {}
    set _unreach_expected {}
    foreach _c $_unreach_all {
        if {[string match {*LoadedCapRepr_NotVacuous*} $_c]} {
            lappend _unreach_expected $_c
        } else {
            lappend _unreach_bad $_c
        }
    }
    set n_unreach [llength $_unreach_bad]

    puts "VeriCHERI summary: ${n_proven}/${n_assert} proven, ${n_cex} with counterexample"

    foreach _c $_unreach_expected {
        puts "NOTE: $_c is unreachable, as expected (data_tag_i tied low:"
        puts "NOTE:   capabilities arriving from memory are outside this proof)."
    }

    if {$n_unreach > 0} {
        puts "ERROR: ${n_unreach} cover(s) unreachable — a guarded property is vacuous:"
        foreach _c $_unreach_bad {
            puts "ERROR:   $_c"
        }
    } elseif {$n_assert == 0} {
        puts "ERROR: no assert properties were found — the proof did not run."
    } elseif {$n_proven == $n_assert} {
        puts "VeriCHERI: all ${n_assert} assertions proven."
        set vericcheri_rc 0
    } else {
        puts "ERROR: [expr {$n_assert - $n_proven}] of ${n_assert} assertions not proven."
    }
} err]} {
    puts "ERROR: could not determine proof status: $err"
}

exit $vericcheri_rc
