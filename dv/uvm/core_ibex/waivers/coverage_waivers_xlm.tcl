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

# Not here, but in ibex/dv/coverage/ibex_cover.ccf (kept out of the model at compile time): prim_lfsr,
# prim_prince and the prim_secded_* blocks (verified elsewhere), the code and assertions of the
# functional-coverage interfaces, the push_pull agent's covergroups and the RVFI port toggles. They
# were excluded here, and IMC reports excluding an item that has hits as *E,EREXCE (25 per merge,
# 2026-10-08).

# RVFI (ibex_core.sv `ifdef RVFI): the retirement trace the cosim and TestRIG read -- verification
# instrumentation, not synthesised, so its code is not design coverage. The per-stage pipeline
# (g_rvfi_stages) is a scope of its own and is excluded here, for the main core and the lockstep
# shadow core; the rest of the RVFI block sits directly in ibex_core and stays in the numbers. A path
# this model does not have is logged as IBEX_WAIVER_NOT_APPLIED (merge_combined.log).
ibex_waive exclude -inst "ibex_top/u_ibex_core/g_rvfi_stages*" -metrics code
ibex_waive exclude -inst "ibex_top/gen_lockstep/u_ibex_lockstep/u_shadow_core/g_rvfi_stages*" -metrics code

# hart_id_i and boot_addr_i: hard-wired inputs in a real design (upstream waived them as such), so
# their toggles are not scored -- not here but in ibex/dv/coverage/ibex_cover_toggle_excl, with the
# RVFI ports: core_ibex_tb_top.sv drives their complement while rst_n is low and ibex_mhartid_ones
# sets hart_id_i to all-ones, so they have hits, and an IMC exclusion of them would be *E,EREXCE.
# ram_cfg_icache_tag_i / ram_cfg_icache_data_i are a passthrough set of signals to provide memory
# instance specific data and have no functional impact on the design (core_ibex_tb_top.sv ties both
# to RAM_1P_CFG_REQ_DEFAULT). Upstream's "ram_cfg_i.*" waiver matched nothing here (*E,INVPTH).
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
# No waivers. cp_rf_a_ecc_err, cp_rf_b_ecc_err and rf_ecc_err_cross now sample the lockstep
# shadow core, where the register-file ECC check runs (core_ibex_fcov_if.sv rf_ecc_err_*_shdw);
# riscv_rf_intg_test injects the errors. cp_icache_ecc_err is reachable (ICacheECC=1): the hole is
# core_ibex_icache_intg_test releasing its force before a sampling edge
# (tech-notes/fcov_closure_2026-10-07.md). The waivers removed here named a covergroup "fcov_cg"
# that does not exist (the group is uarch_cg), so they never applied.

# ── Fetch FIFO coverpoints (item 3) ─────────────────────────────────────────
# With ICache=1 (opentitan config), the generate block g_fcov_fetch_fifo in
# core_ibex_fcov_if.sv is not elaborated; g_no_fcov_fetch_fifo drives all five
# probes to 0. The iff guards on these coverpoints therefore never become true.
# These can only be exercised by a separate non-ICache regression configuration,
# which is not in scope for the current opentitan-config coverage target.
# Syntax: IMC -coveritem format is <cg_name>.<item_name> (help exclude).
ibex_waive exclude -type "core_ibex_fcov_if" -coveritem "uarch_cg.cp_fetch_fifo_bypass"
ibex_waive exclude -type "core_ibex_fcov_if" -coveritem "uarch_cg.cp_fetch_fifo_clear_while_full"
ibex_waive exclude -type "core_ibex_fcov_if" -coveritem "uarch_cg.cp_fetch_push_during_pop"
ibex_waive exclude -type "core_ibex_fcov_if" -coveritem "uarch_cg.cp_fetch_unaligned_compressed"
ibex_waive exclude -type "core_ibex_fcov_if" -coveritem "uarch_cg.cp_fetch_unaligned_uncompressed"

# ── TRVK and CHERIoT cross waivers: none ────────────────────────────────────
# trvk_revoked_source_cross: the bins where the verdict and its sources disagree are illegal_bins
# in core_ibex_trvk_fcov_if.sv (the equation in ibex_trvk.sv makes them impossible, and a hit is a
# defect). The -coverbin waivers that stood here never applied: IMC reported NOMATCH for every one.
#
# cheriot_ccleartag_cross, cheriot_cmove_cross, cheriot_csethigh_src_cross: their "untagged +
# sealed" bin was waived as structurally unreachable. It is reachable (CClearTag of a sealed
# capability gives one) and all three crosses read 4/4 in the 2026-10-08 regression. The waivers
# named a covergroup fcov_cg that does not exist, so they never applied either.
#
# cheriot_cs1cd_tag_cross is not waived here: a tagged CGet* result is an illegal_bins in
# core_ibex_fcov_if.sv (REQ_TAG_06).

# ── Code blocks reachable only from a state reset never produces, or dead (21 per core) ──
# Left after the Jasper UNR pass (2026-10-08 review): Jasper reached each of them, but it starts
# from an arbitrary state (unr::config_reset), not from reset. Each is waived with its reason.
#
# IMC names a block by an index that moves whenever its module's source changes, so these do not
# hard-code indices. ibex_waive_blocks reads the loaded model's block report for the main core's
# instance and excludes, by type (main and lockstep shadow core), the blocks on \line that have
# 0 hits and whose kind matches \kind. It excludes nothing, and logs IBEX_WAIVER_NOT_APPLIED, unless
# exactly \count blocks match: after an RTL change the waiver stops applying instead of excluding
# some other block.
# \excl_insts: exclude in these instances instead of by type. For a block in a generate scope,
# whose type IMC reports as <module>.<scope>_T (e.g. ibex_controller.g_wb_exceptions_T): block
# indices are per type, so the main core's index is also the lockstep shadow core's.
proc ibex_waive_blocks {inst type line count kind reason {excl_insts {}}} {
  set tmp "/tmp/ibex_waive_blocks_[pid].txt"
  if {[catch {report -detail -metrics block -inst $inst -all -out $tmp -overwrite} msg]} {
    puts "IBEX_WAIVER_NOT_APPLIED: blocks $type:$line -- report failed: $msg"
    return
  }
  set ids {}
  set in_type 0
  set fh [open $tmp r]
  while {[gets $fh row] >= 0} {
    if {[regexp {^Type name:\s*(\S+)} $row -> t]} {
      set in_type [expr {$t eq $type}]
    } elseif {$in_type &&
              [regexp {^\s*(\S+)\s+(\d+)\s+\d+\s+(\d+)\s+(.*)$} $row -> hits blk ln rest] &&
              $hits eq "0" && $ln == $line && [string match "*$kind*" $rest]} {
      lappend ids $blk
    }
  }
  close $fh
  file delete $tmp
  if {[llength $ids] != $count} {
    puts "IBEX_WAIVER_NOT_APPLIED: blocks $type:$line ($kind) -- [llength $ids] uncovered block(s)\
          {$ids}, expected $count"
    return
  }
  # eval, not {*}: IMC's Tcl is 8.4, which reads {*}$ids as "extra characters after close-brace"
  # (formal_cov/unr/imc_unr_vrefine.log, 2026-10-09) and aborts the rest of this file.
  if {[llength $excl_insts] == 0} {
    eval [list ibex_waive exclude -type $type -block] $ids [list -comment $reason]
  } else {
    foreach i $excl_insts {
      eval [list ibex_waive exclude -inst $i -block] $ids [list -comment $reason]
    }
  }
}

# ibex_compressed_decoder, Zcmp micro-op FSM: Xcelium gives a multi-label case item one block copy
# per label, nesting included. In the popretz/popret/pop arm (5'b11010, 5'b11100, 5'b11110) the
# copies whose outer label does not match the inner state are unreachable; the matching copies
# are covered. The FSM defaults (682, 773, 804, 832) are states cm_state_q never holds.
set _cdec ibex_top/u_ibex_core/if_stage_i/compressed_decoder_i
set _zcmp "Zcmp: per-label copy of a multi-label case item, or FSM default (unreachable state)"
foreach {line count} {682 1  757 2  761 4  765 1  767 3  773 3  804 1  832 1} {
  ibex_waive_blocks $_cdec ibex_compressed_decoder $line $count "" $_zcmp
}
# ibex_controller: the CHERIoT ID-stage exception. cheriot_ex_err_raw is 1'b0 in every assignment
# in ibex_cheriot_ex.sv (default, CLC, CSC, CJALR/CJAL) and cheriot_ex_err_info_o is 12'h0 ("no
# ex stage cheriot error currently"): CJALR/CJAL faults moved to cheriot_wb_err_raw and CLC/CSC
# faults to the LSU. Dead code; an RTL clean-up candidate (tech-notes/rtl_todo.md).
set _ctrl ibex_top/u_ibex_core/id_stage_i/controller_i
set _dead "dead: cheriot_ex_err is constant 0 (ibex_cheriot_ex.sv drives cheriot_ex_err_raw = 0 only)"
# Line 328 is in the g_wb_exceptions generate scope (WritebackStage = 1), a type of its own.
ibex_waive_blocks $_ctrl/g_wb_exceptions ibex_controller.g_wb_exceptions_T 328 1 "true part" \
  $_dead [list $_ctrl/g_wb_exceptions \
    ibex_top/gen_lockstep/u_ibex_lockstep/u_shadow_core/id_stage_i/controller_i/g_wb_exceptions]
ibex_waive_blocks $_ctrl ibex_controller 928 1 "" $_dead
ibex_waive_blocks $_ctrl ibex_controller 929 1 "true part" $_dead
# ebreak_into_debug: the 1'b0 arm is for a privilege level other than M or U. priv_lvl_q is
# only loaded from M, mstatus.mpp or dcsr.prv, and writes legalise both to M or U
# (ibex_cs_registers.sv mstatus_d.mpp / dcsr_d.prv); this core has no S or H mode.
ibex_waive_blocks $_ctrl ibex_controller 483 1 "" "priv_mode_i is only ever M or U"
# ibex_load_store_unit: the 2'b11 copy of '2'b10,2'b11:'. The decoder only issues data types
# 2'b00, 2'b01 and 2'b10, and data_type_q is loaded from lsu_type_i.
ibex_waive_blocks ibex_top/u_ibex_core/load_store_unit_i ibex_load_store_unit 377 1 "" \
  "data_type_q 2'b11 is never issued (decoder: word 00, half 01, byte 10)"
# No waiver for ibex_icache.sv:1303 (OUT_OF_RESET, scramble key request): it was waived as
# unreachable from reset (ibex_top resets scramble_key_valid_q to 1), but the 2026-10-09
# regression hit it, so that reasoning does not hold and the block stays scored.
unset _cdec _zcmp _ctrl _dead

# ── Expression rows that cannot occur in the verified configuration ─────────────────────────────
# Left after the Jasper UNR pass and the regression of 2026-10-09
# (formal_cov/unr/uncovered_after_exclude.txt). Rows that can occur have directed tests in
# directed_tests/directed_testlist_cov_expr.yaml instead; rows still open are listed there.
#
# Xcelium scores an expression per operand row ("is each input shown to control the result").
# IMC names a row <expr>.<sub>.<row> (e.g. 6.1.3), indices that move whenever the module's source
# changes, so, as for the blocks above, nothing here hard-codes an index. ibex_waive_expr reads the
# loaded model's expression report for \inst, finds the expression of type \type on one of the
# source lines \lines (a list: a condition spanning lines is reported on one of them) whose text is
# \text (whitespace-normalised; a trailing "..." makes it a prefix), and in it the rows given in
# \rows, then excludes those rows by type (main and lockstep shadow core), or in
# \excl_insts for a generate-scope type (<module>.<scope>_T, see ibex_waive_blocks). A row is given
# as the report prints it after the hit column, e.g. "0 | 1 1 1" (rval | inputs), "1 -", "lhs !=
# rhs"; or, for an always_comb event-or row ("e" in one column), as event:<term>, the term whose
# event alone would trigger the block. Nothing is excluded, and IBEX_WAIVER_NOT_APPLIED is logged,
# unless exactly one expression matches and every row is found exactly once with 0 hits: a
# waived row that has hits means its reason is wrong, and the waiver must not hide that.
proc ibex_norm {s} {
  return [string trim [regsub -all {\s+} $s " "]]
}

proc ibex_both_cores {path} {
  return [list ibex_top/u_ibex_core/$path \
               ibex_top/gen_lockstep/u_ibex_lockstep/u_shadow_core/$path]
}

proc ibex_waive_expr {inst type lines text rows reason {excl_insts {}}} {
  set tag "expr $type:[join $lines /]"
  set tmp "/tmp/ibex_waive_expr_[pid].txt"
  if {[catch {report -detail -metrics expression -inst $inst -all -out $tmp -overwrite} msg]} {
    puts "IBEX_WAIVER_NOT_APPLIED: $tag -- report failed: $msg"
    return
  }
  set rpt {}
  set fh [open $tmp r]
  while {[gets $fh l] >= 0} {
    lappend rpt $l
  }
  close $fh
  file delete $tmp

  set want [ibex_norm $text]
  set prefix [string match "*..." $want]
  if {$prefix} {
    set want [string range $want 0 end-3]
  }

  # Matching expressions: {text marker-line rows}, rows = {{index hits cells} ...}.
  set matches {}
  set n [llength $rpt]
  set in_type 0
  for {set i 0} {$i < $n} {incr i} {
    set l [lindex $rpt $i]
    if {[regexp {^Type name:\s*(\S+)} $l -> t]} {
      set in_type [expr {$t eq $type}]
      continue
    }
    if {!$in_type || ![regexp {^index:\s+\S+\s+grade:.*\sline:\s+(\d+)} $l -> eline]} {
      continue
    }
    if {[lsearch -exact $lines $eline] < 0} {
      continue
    }
    set j [expr {$i + 1}]
    while {$j < $n && [string trim [lindex $rpt $j]] eq ""} {
      incr j
    }
    set etext [lindex $rpt $j]
    set norm [ibex_norm $etext]
    if {$prefix} {
      if {[string first $want $norm] != 0} {
        continue
      }
    } elseif {$norm ne $want} {
      continue
    }
    set rowl {}
    for {set k [expr {$j + 2}]} {$k < $n} {incr k} {
      set r [lindex $rpt $k]
      if {[regexp {^(index:|Instance name:|Type name:)} $r]} {
        break
      }
      if {[regexp {^(\d+\.\d+\.\d+)\s+\|\s*(\S+)\s*\|(.*)$} $r -> ridx rhit rest]} {
        lappend rowl [list $ridx $rhit [ibex_norm $rest]]
      }
    }
    lappend matches [list $etext [lindex $rpt [expr {$j + 1}]] $rowl]
  }
  if {[llength $matches] != 1} {
    puts "IBEX_WAIVER_NOT_APPLIED: $tag -- [llength $matches] matching expression(s), expected 1:\
          {$text}"
    return
  }
  set m [lindex $matches 0]
  set etext [lindex $m 0]
  set mline [lindex $m 1]
  set rowl  [lindex $m 2]

  # Terms of the expression: the marker line's <--n--> spans, read off the expression text.
  set terms {}
  foreach span [regexp -all -indices -inline {<-*[0-9]+-*>} $mline] {
    set s [lindex $span 0]
    set e [lindex $span 1]
    lappend terms [string trim [string range $etext $s $e]]
  }

  set ids {}
  foreach spec $rows {
    if {[regexp {^event:(.+)$} $spec -> term]} {
      set col [lsearch -exact $terms $term]
      if {$col < 0} {
        puts "IBEX_WAIVER_NOT_APPLIED: $tag -- no term $term in {$terms}"
        return
      }
      set cells {}
      for {set c 0} {$c < [llength $terms]} {incr c} {
        if {$c == $col} {
          lappend cells e
        } else {
          lappend cells -
        }
      }
      set cells [join $cells " "]
    } else {
      set cells [ibex_norm $spec]
    }
    set found {}
    foreach r $rowl {
      if {[lindex $r 2] eq $cells} {
        lappend found $r
      }
    }
    if {[llength $found] != 1} {
      puts "IBEX_WAIVER_NOT_APPLIED: $tag -- row {$spec} found [llength $found] time(s)"
      return
    }
    set r [lindex $found 0]
    if {[lindex $r 1] ne "0"} {
      puts "IBEX_WAIVER_NOT_APPLIED: $tag -- row [lindex $r 0] {$spec} has [lindex $r 1] hits:\
            the waiver's reason does not hold"
      return
    }
    lappend ids [lindex $r 0]
  }
  # eval, not {*}: IMC's Tcl is 8.4 (see ibex_waive_blocks).
  if {[llength $excl_insts] == 0} {
    eval [list ibex_waive exclude -type $type -expression] $ids [list -comment $reason]
  } else {
    foreach x $excl_insts {
      eval [list ibex_waive exclude -inst $x -expression] $ids [list -comment $reason]
    }
  }
}

set _core ibex_top/u_ibex_core

# ---- Event-or rows (set_expr_coverable_operators -event_or): an always_comb's implicit
# sensitivity list scored per term; row "e" for term T means "the block ran because of an event on
# T alone". A term that is constant in this configuration, or that the block itself writes, can
# never be that event. These rows carry no design intent.
#
# Written by the block itself (it changes only because the block ran):
ibex_waive_expr $_core/id_stage_i/decoder_i ibex_decoder 230 "instr\[6:0\] or opcode or ..." \
  [list event:opcode] "event-or: opcode is assigned in this always_comb (opcode_e'(instr\[6:0\]))"
ibex_waive_expr $_core/id_stage_i/decoder_i ibex_decoder 880 \
  "instr_alu\[6:0\] or opcode_alu or ..." [list event:opcode_alu] \
  "event-or: opcode_alu is assigned in this always_comb (opcode_e'(instr_alu\[6:0\]))"
ibex_waive_expr $_core/ex_block_i/alu_i ibex_alu 253 "shift_left or operand_a_rev or ..." \
  [list event:shift_result_rev] "event-or: shift_result_rev is assigned in this always_comb"
ibex_waive_expr $_core/if_stage_i/compressed_decoder_i ibex_compressed_decoder 213 \
  "instr_i or cm_rlist_q or ..." [list event:cm_rlist_d event:cm_sp_offset_d] \
  "event-or: cm_rlist_d and cm_sp_offset_d are assigned in this always_comb"
ibex_waive_expr $_core/g_cheriot_ex/u_ibex_cheriot_ex ibex_cheriot_ex 614 \
  "cheriot_setaddr_sel_i or pcc_cap_i or ..." [list event:tfcap1] \
  "event-or: tfcap1 is assigned in this always_comb (set_address_comb)"
ibex_waive_expr $_core/cs_registers_i/gen_scr ibex_cs_registers.gen_scr_T 2065 \
  "csr_save_cause_i or mtvec_cap or ..." [list event:tr_cap event:tf_cap] \
  "event-or: tr_cap and tf_cap are assigned in this always_comb" \
  [ibex_both_cores cs_registers_i/gen_scr]
# Constant in this configuration:
ibex_waive_expr $_core/if_stage_i/gen_icache/icache_i ibex_icache 507 \
  "tag_match_ic1 or ic_data_rdata_i or data_tweak_lw_ic1" [list event:data_tweak_lw_ic1] \
  "event-or: ICacheTweakInfection = 0 (core_ibex_tb_top.sv), so gen_no_tweak_infection ties\
   data_tweak_lw_ic1 to 0"

# ---- ibex_decoder: ~illegal_c_insn_i in the JAL, AUIPC, AUICGP and CSC arms (CHERIoT on).
# illegal_c_insn_i = 1 needs an expanded instruction the compressed decoder flags illegal. Its
# illegal cases expand to OPCODE_CHERI (c.incaddr4cspn imm 0, c.incaddr16csp imm 0), OP_IMM, LUI,
# LOAD (c.lwsp/c.clcsp rd 0), JALR (c.jr rs1 0), STORE funct3 010 (Zcmp push with rlist <= 3), or
# pass the 16 raw bits on (instr[1:0] != 2'b11, not a 32-bit opcode). Never JAL (c.jal/c.j are
# never illegal), AUIPC or AUICGP (no compressed form), nor STORE funct3 011 (c.csc/c.cscsp are
# never illegal).
set _dec $_core/id_stage_i/decoder_i
set _cinsn "no compressed instruction flagged illegal expands to this opcode\
  (ibex_compressed_decoder.sv)"
foreach l {{279 280} {439 440} {835 836}} {
  ibex_waive_expr $_dec ibex_decoder $l \
    "((BaseIsa == BaseIsaRV32IorCHERIoT) & (cheriot_enable_i == IbexMuBiOn))\
     & (~ illegal_c_insn_i)" [list "0 | 1 1 1"] $_cinsn
}
foreach l {368 369 370} {
  ibex_waive_expr $_dec ibex_decoder $l "~ illegal_c_insn_i" [list "1"] $_cinsn
}

# ---- ibex_controller ----
set _ctrl $_core/id_stage_i/controller_i
# ebreak_into_debug: the U test runs only when priv_mode_i != M, and priv_lvl_q is only ever M or
# U (no S/H mode; ibex_cs_registers.sv legalises mstatus.mpp and dcsr.prv). Same reason as the
# block waiver on line 483.
ibex_waive_expr $_ctrl ibex_controller 482 "(priv_mode_i == PRIV_LVL_U)" [list "lhs != rhs"] \
  "priv_mode_i is only ever M or U"
# SLEEP exit with only debug_single_step_i set: with dcsr.step set every instruction outside debug
# mode is the stepped one, so a WFI in ID sets do_single_step_d and enter_debug_mode_prio_q, and
# FLUSH goes to DBG_TAKEN_IF instead of WAIT_SLEEP. SLEEP is never entered while stepping.
ibex_waive_expr $_ctrl ibex_controller 615 \
  "(((irq_nm || irq_pending_i) || debug_req_i) || debug_mode_q) || debug_single_step_i" \
  [list "0 0 0 0 1"] "a stepped WFI enters debug mode from FLUSH, never SLEEP"
# Illegal-instruction mtval in RISC-V mode: an uncompressed instruction has instr[1:0] = 2'b11,
# so instr_i is never 0 when instr_is_compressed_i is 0.
ibex_waive_expr $_ctrl ibex_controller 867 \
  "((BaseIsa == BaseIsaRV32IorCHERIoT) & (cheriot_enable_i == IbexMuBiOn)) ? 32'h00000000 :\
   (instr_is_compressed_i ? {16'b0000000000000000,instr_compressed_i} : instr_i)" \
  [list "0 | 1 0 0 - 0"] "an uncompressed instruction is never 0 (instr\[1:0\] = 2'b11)"
# cheriot_ex_err is constant 0 (see the block waivers on lines 328/928/929 above).
ibex_waive_expr $_ctrl ibex_controller 929 "cheriot_enable_i == IbexMuBiOn" [list "lhs == rhs"] \
  "dead: inside cheriot_ex_err_prio, and cheriot_ex_err is constant 0"
ibex_waive_expr $_ctrl/g_wb_exceptions ibex_controller.g_wb_exceptions_T 328 \
  "(cheriot_enable_i == IbexMuBiOn) & cheriot_ex_err_q" [list "1 1"] \
  "dead: cheriot_ex_err_q is constant 0 (ibex_cheriot_ex.sv drives cheriot_ex_err_raw = 0 only)" \
  [ibex_both_cores id_stage_i/controller_i/g_wb_exceptions]

# ---- ibex_id_stage / ibex_multdiv_fast: writeback never waits while a MUL/DIV executes.
# rf_we_dec is 1 for every MUL/DIV: the decoder sets rf_we for OP-format MUL/DIV, and mult_en_o /
# div_en_o are cleared by illegal_insn_o, which includes illegal_reg_16 -- the only thing that
# clears rf_we_o without clearing them.
ibex_waive_expr $_core/id_stage_i ibex_id_stage 945 "rf_we_dec & ex_valid_i" [list "0 -"] \
  "rf_we_dec is 1 whenever multdiv_en_dec is 1"
# MULTI_CYCLE `multicycle_done & ready_wb_i` with ready_wb_i = 0. ~ready_wb_i is exactly
# outstanding_memory_access (ibex_wb_stage.sv wb_done / outstanding_*_wb_o). id_fsm_q only takes
# MULTI_CYCLE under instr_executing, which requires ~outstanding_memory_access, and writeback
# takes no instruction until the one in ID/EX completes, so ready_wb_i stays 1 in MULTI_CYCLE.
# (For a load/store multicycle_done is ~stall_mem, 0 while an access is outstanding.) A killed
# multi-cycle instruction leaves id_fsm_q at MULTI_CYCLE only until the next instruction
# executes; its killers (wb_exception, fetch error, decode exception) leave nothing outstanding.
ibex_waive_expr $_core/id_stage_i ibex_id_stage 948 "multicycle_done & ready_wb_i" [list "1 0"] \
  "writeback has no outstanding access while ID/EX is in MULTI_CYCLE"
# multdiv_ready_id_i = ready_wb_i, which is 0 only while writeback waits for a load/store
# response (outstanding_memory_access). A MUL/DIV is enabled only with instr_executing, which
# requires no outstanding access, and writeback takes no new instruction until the MUL/DIV in
# ID/EX completes; the MULH and MD_FINISH states exist only while it is enabled.
ibex_waive_expr $_core/ex_block_i/gen_multdiv_fast/multdiv_i ibex_multdiv_fast 518 \
  "~ multdiv_ready_id_i" [list "0"] "writeback is ready while a division executes"
ibex_waive_expr $_core/ex_block_i/gen_multdiv_fast/multdiv_i/gen_mult_single_cycle \
  ibex_multdiv_fast.gen_mult_single_cycle_T 235 "~ multdiv_ready_id_i" [list "0"] \
  "writeback is ready while a MULH executes" \
  [ibex_both_cores ex_block_i/gen_multdiv_fast/multdiv_i/gen_mult_single_cycle]

# ---- ibex_compressed_decoder: Zcmp stack adjustment. cm_sp_addi is only called in
# CmPushDecrSp and CmPopIncrSp, which the FSM enters from CmIdle only for rlist >= 4 (rlist <= 3
# is reserved: illegal_instr_o, the FSM stays in CmIdle), and cm_stack_adj_base is 16..64 for
# rlist 4..15, so imm is never 0.
ibex_waive_expr $_core/if_stage_i/compressed_decoder_i ibex_compressed_decoder 120 \
  "decr ? -signed'(imm) : signed'(imm)" [list "0 | 0 - 0" "0 | 1 0 -"] \
  "Zcmp stack adjustment is never 0 (rlist >= 4: 16..112)"

# ---- ibex_icache: fill buffer one-hot muxes. fill_ext_arb and fill_ram_arb are one-hot by the
# age matrix (a buffer is allocated with every busy buffer marked older in fill_older_q, so the
# requesting buffers are totally ordered and exactly the oldest wins). Only one loop iteration ORs
# into the accumulator, which is therefore always 0 when an iteration adds to it.
set _ic $_core/if_stage_i/gen_icache/icache_i
set _onehot "one-hot arbitration (age matrix): the accumulator is 0 when the selected buffer ORs in"
ibex_waive_expr $_ic ibex_icache 994 \
  "fill_ext_req_addr | {fill_addr_q\[i\]\[(ADDR_W - 1):IC_LINE_W\],fill_ext_off\[i\]}" \
  [list "1 -"] $_onehot
ibex_waive_expr $_ic ibex_icache 1006 "fill_ram_req_addr | fill_addr_q\[i\]" [list "1 -"] $_onehot
ibex_waive_expr $_ic ibex_icache 1007 "fill_ram_req_way | fill_way_q\[i\]" [list "1 -"] $_onehot
ibex_waive_expr $_ic ibex_icache 1008 "fill_ram_req_data | fill_data_q\[i\]" [list "1 -"] $_onehot

# ---- ibex_cs_registers ----
# mtvec initialisation value 0 with CHERIoT on: needs boot_addr_i[31:8] = 0 at BOOT_SET. The bench
# drives boot_addr_i = BootAddr = 0x80000000 whenever rst_n is high (core_ibex_tb_top.sv; its
# complement 0x7FFFFF00 only during reset, when csr_mtvec_init_i is 0): a constant tie-off.
ibex_waive_expr $_core/cs_registers_i ibex_cs_registers 738 \
  "csr_mtvec_init_i ? {boot_addr_i\[31:8\], 6'b000000, 1'b0, (~ ((BaseIsa ==\
   BaseIsaRV32IorCHERIoT) & (cheriot_enable_i == IbexMuBiOn)))} : {csr_wdata_int\[31:8\],\
   6'b000000, 1'b0, (~ ((BaseIsa == BaseIsaRV32IorCHERIoT) & (cheriot_enable_i ==\
   IbexMuBiOn)))}" \
  [list "0 | 1 0 -"] "boot_addr_i is the bench constant 0x80000000 out of reset"
# DRET outside debug mode: csr_restore_dret_i is raised only in FLUSH for a dret without exc_req_q,
# and a dret outside debug mode is illegal_dret_insn, which is exc_req_q. So debug_mode_i is 1
# whenever csr_restore_dret_i is.
set _dret "csr_restore_dret_i only with debug_mode_i: a dret outside debug mode is an illegal\
  instruction"
ibex_waive_expr $_core/cs_registers_i/gen_scr ibex_cs_registers.gen_scr_T 2073 \
  "csr_restore_dret_i & debug_mode_i" [list "1 0"] $_dret [ibex_both_cores cs_registers_i/gen_scr]
ibex_waive_expr $_core/cs_registers_i/gen_scr ibex_cs_registers.gen_scr_T 2084 \
  "(csr_save_cause_i | csr_restore_mret_i) | (csr_restore_dret_i & debug_mode_i)" \
  [list "0 | 0 0 1 0"] $_dret [ibex_both_cores cs_registers_i/gen_scr]

# ---- ibex_core RVFI (verification instrumentation, `ifdef RVFI) ----
# Stage-0 update `(instr_valid_id_d & instr_new_id_d) | rvfi_irq_valid` with an instruction held
# in ID: rvfi_irq_valid is set only for the cycle after IRQ_TAKEN with handle_irq and ID empty.
# IRQ_TAKEN raises pc_set, so nothing enters ID at that edge and instr_valid_id_q is 0 in the next
# cycle, where instr_valid_id_d is therefore instr_new_id_d (ibex_if_stage.sv).
ibex_waive_expr $_core ibex_core 2073 \
  "(if_stage_i.instr_valid_id_d & if_stage_i.instr_new_id_d) | rvfi_irq_valid" [list "1 | 1 0 1"] \
  "rvfi_irq_valid follows IRQ_TAKEN (pc_set): ID is empty, instr_valid_id_d = instr_new_id_d"

unset _core _dec _cinsn _ctrl _ic _onehot _dret

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
