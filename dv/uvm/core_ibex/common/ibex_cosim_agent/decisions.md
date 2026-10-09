GAP-MS-4 is updated ([spec, GAP-MS-4](ibex_cheriot_verification_spec.md)), retitled "What `formal-cheriot` does not compare". I wrote it from the checker code. It says the flow now compares full capabilities, registers, CSRs and memory accesses (including the tag a store writes), and lists the four limits that remain:
- Tags are compared "at least as strict": the RTL may clear a tag the model keeps.
- The revocation unit is replaced by an abstraction.
- CSR instructions on a list of CSRs are excluded: counters, `cpuctrlsts`, `mie`, PMP, `mshwm` and a few others.
- NMIs and fast interrupts are assumed absent.

For each limit it says which simulation covers it. The gap matrix now lists GAP-MS-4 in the CSR, revocation and NMI rows too.

## Decisions for you

**New since yesterday**

| # | Decision | Options | Recommendation |
|---|---|---|---|
| 1 | GAP-RV-4: the riscv-dv debug ROM corrupts the kernel stack (all 6 `riscv_debug_single_step_test` failures) | (a) patch the ROM: skip a full trap frame, and restore registers on exception instead of a bare `dret` · (b) only raise `timeout_s` to 3600 · (c) both | **(c)**. The three timeouts are slow, not hung, and happen even without stack corruption. |
| 2 | `formal-cheriot-ms-sail` baseline: apply the two one-line port fixes (`misa_value_masked`, mtval stub 0)? | yes / no | **Yes.** Microsoft's own flow had both values, so without them the baseline isn't Microsoft's flow either. You said no to syncing checker edits, but these two fix the port rather than change the checker. |
| 3 | Commit the uncommitted work | now, in logical pieces / after the nyx runs | **Now.** The parent repo and the `ibex` submodule now hold several days of unrelated changes (formal port, coverage fixes, scoreboard, tests, spec). `formal/formal-cheriot-ms-sail` is untracked, so deletions there can't be undone. |

**Waiting on your runs (a decision follows from each result)**

| # | Run | What decides it |
|---|---|---|
| 4 | `pmp_traps` 24861 with `WAVES=1` | Whether the Spike fix for "interrupt, then NMI before the handler's first instruction" is right. If Ibex pre-empts the interrupt with the NMI in the same cycle, the fix needs changing. |
| 5 | `nmi_at_exc` 24865, `assorted_traps` 24857, `mem_error_traps` 24856 with `WAVES=1` | Whether the stale captured request in `ibex_core.sv` is a trace-only bug (apply the fix) or a real controller/trace disagreement (an RTL question). |
| 6 | `riscv_debug_single_step_test` 24855 with `WAVES=1` | The byte `0x0b` that Spike sees and the DUT doesn't: TB memory model, or a possible LSU finding. |
| 7 | `cheriot_illegal_branch_dit` 24855 | If the `IllegalInsnStallMustBeMemStall` assertion fires, the open data-independent-timing branch issue in `rtl_todo.md` becomes a confirmed RTL finding to disposition. |
| 8 | `formal-cheriot-gui` (first 10 minutes) | Confirms the `misa`/mtval fixes. The `Arith_Shift_Addr` and `Ibex_SpecEnUnreach` failures may then need looking at separately. |

**Carried over from [status_4_10_2026.md](status_4_10_2026.md)**

As far as I know these haven't changed, but I haven't re-checked each one:

| # | Decision | Recommendation there |
|---|---|---|
| 9 | `mshwm` lowered by the second half of a misaligned store | fix the RTL (use the start address) |
| 10 | Integrity NMI later than Ibex documents (codes 66, 72) | raise upstream first |
| 11 | Misaligned store with a PMP fault still writes its other half | accept as design intent, recorded |
| 12 | Legacy `mtvec`/`mepc` access in CHERIoT mode | raise Reserved Instruction, as the arch doc says |
| 13 | `mtval` `cap_idx`: 5 bits or 6 | fix whichever side disagrees with the arch doc |
| 14 | Close the stale GPR-reset item in `rtl_todo.md` | close it |
| 15 | VeriCHERI counterexample spurious? | decide from the next batch run's waveform |
| 16 | VeriCHERI proof caching off | keep off while assumptions change |
| 17 | RISC-V Sail checker in the UVM regression (GAP-SR-4) | turn on after one characterisation regression |

The fastest to settle are 1–3. If you answer them, I'll apply 1 and 2 and prepare the commits for 3.

## Commands to run

1–3 are decided: 1 (a), debug ROM patch applied; 2 no; 3 parent repo committed, `ibex` not yet.

**0. Copy the changes to nyx (laptop):**
```sh
make resync-nyx
```

**On nyx, in the repo.** Delete each test's old directory before rerunning it, or the rerun reports the stale "0 PASSED / binary MISSING".
```sh
cd ~/work/ibex_cheriot_verification
T=ibex/dv/uvm/core_ibex/out/run/tests
```

**Fixes to check (no waves)**
```sh
# fix A (no NMIs in core_ibex_irq_traps_test): should pass
rm -rf $T/riscv_pmp_traps_test.24870 $T/riscv_pmp_traps_test.24886
make uvm-test-xlm TEST=riscv_pmp_traps_test SEED=24870 ITERATIONS=1
make uvm-test-xlm TEST=riscv_pmp_traps_test SEED=24886 ITERATIONS=1

# #7, CHERIoT-Sail stop at cpuctrlsts: pass 2 now runs. The log says "CHERIoT-Sail oracle stopped after N instructions".
#     Assertion IllegalInsnStallMustBeMemStall fires = RTL finding; code 0 = refuted; 3000-range code = wrong trap with DIT on
rm -rf $T/cheriot_illegal_branch_dit.24855
make uvm-test-xlm TEST=cheriot_illegal_branch_dit SEED=24855 ITERATIONS=1

# decision 1 (a), debug ROM patch: 24856 and 24865 should pass; 24858/24859/24863 may still time out (timeout not raised)
rm -rf $T/riscv_debug_single_step_test.{24856,24858,24859,24863,24865}
for s in 24856 24858 24859 24863 24865; do make uvm-test-xlm TEST=riscv_debug_single_step_test SEED=$s ITERATIONS=1; done
```

**#4, #5, #6: waves read, fixes in (`ibex` uncommitted); rerun without waves, all should pass.**
#4 = Spike `take_deferred_irq()` before an NMI; #5 = RVFI `captured_taken` (ibex_core.sv, RVFI only);
#6 = IMEM model fills uninitialised bytes with 0x00 per byte. The irq driver change (`drive_nm`/`drive_maskable`)
can affect every irq test, so these are a first check, not the whole check; the next full regression is that.
```sh
rm -rf $T/riscv_pmp_traps_test.24861 $T/riscv_nmi_at_exc_test.24865 \
       $T/riscv_assorted_traps_interrupts_debug_test.24857 $T/riscv_mem_error_traps_test.24856 \
       $T/riscv_debug_single_step_test.24855
make uvm-test-xlm TEST=riscv_pmp_traps_test SEED=24861 ITERATIONS=1                         # #4
make uvm-test-xlm TEST=riscv_nmi_at_exc_test SEED=24865 ITERATIONS=1                        # #5
make uvm-test-xlm TEST=riscv_assorted_traps_interrupts_debug_test SEED=24857 ITERATIONS=1   # #5
make uvm-test-xlm TEST=riscv_mem_error_traps_test SEED=24856 ITERATIONS=1                   # #5
make uvm-test-xlm TEST=riscv_debug_single_step_test SEED=24855 ITERATIONS=1                 # #6
```

**Single step that executes nothing (waves).** With the debug ROM patch, 24856 now gets to 272 ms: after the dret at
272411714 ns the DUT re-enters debug at 272412174 ns without executing c.sw at dpc 0x800025b0; Spike executes it.
`WAVES_FROM` starts the probe just before the window (a full-run probe for 272 ms is far too big) and
`TIMEOUT_S` lifts the per-test wall-clock limit for this run.
Window 272411000-272413000 ns: debug_req_i, debug_single_step_i, controller do_single_step_q/d,
enter_debug_mode_prio_q, ctrl_fsm_cs, debug_mode_q, instr_valid_i, pc_if/pc_id, data_req_o, dpc/dcsr.cause written.
cause=step, dpc=0x800025b0, no data_req, debug_req_i low = RTL finding; debug_req_i high = stimulus/monitor.
Same symptom as the open riscv_debug_basic_test 2895 item (re-entry to debug right after dret).
```sh
rm -rf $T/riscv_debug_single_step_test.24856
make uvm-test-xlm TEST=riscv_debug_single_step_test SEED=24856 ITERATIONS=1 WAVES=1 WAVES_FROM=272400000 TIMEOUT_S=7200
```

**New tests (FSM + block coverage), one at a time, each must pass at SEED=1.** Coverage stays on (the default).
```sh
rm -rf $T/{cheriot_enable_on_off,zcmp_push_pop_mv,counter_high_half_write,cheriot_cdbg_ctrl,cheriot_fatal_err_mtcc}.1
# REQ_BCK_06: pin 0->1, CSC, pin 1->0 in CTX_WAIT_GNT1; alert_major_internal_o within 100 cycles.
#   A fail with "REQ_BCK_06: ..." is the RTL finding in tech-notes/rtl_todo.md, not a bench bug.
make uvm-test-xlm TEST=cheriot_enable_on_off SEED=1 ITERATIONS=1
make uvm-test-xlm TEST=zcmp_push_pop_mv SEED=1 ITERATIONS=1          # 213 cases, 1697 checks, Spike
make uvm-test-xlm TEST=counter_high_half_write SEED=1 ITERATIONS=1   # mcycleh/minstreth/mhpmcounterNh, Spike
make uvm-test-xlm TEST=cheriot_cdbg_ctrl SEED=1 ITERATIONS=1         # GAP-CS-3 characterisation
make uvm-test-xlm TEST=cheriot_fatal_err_mtcc SEED=1 ITERATIONS=1    # bench verdict: core_ibex_cheriot_fatal_err_test
```

**UNR exclusions (block coverage: removes unreachable code from the denominator).** Needs the full
regression database; nothing else running. formal-cov-unr prints the number of block properties it
extracted and stops if it is 0.
```sh
make formal-cov-unr
make formal-cov-vrefine
```

**Coverage report** (uses the 23:02 `merged` database until the next full regression; expect a WARNING saying so).
The RVFI exclusion lands in the headline `cov_combined.txt`; the .vRefine from the step above only in the
secondary `cov_combined_unr.txt` (the headline stays unrefined until the .vRefine has been reviewed).
```sh
make cov-merge
```

**Then a full regression** (`make uvm-regr-xlm`), which is the real check of the irq stimulus change and the
place the new tests' coverage lands in the merged database.

**#8, formal-cheriot.** The 9:56 run already has the misa/mtval fixes: only `Top_Addr` and `Arith_Shift_Addr` (26 cycles) left.
Open the `Top_Addr` trace and add `wbexc_decompressed_instr`, `wbexc_illegal`, `` `WB.rf_we_wb_o ``, `` `WB.rf_waddr_wb_o ``,
`wbexc_post_wX_en`, `wbexc_post_wX_addr`. For the next run (has the STOP file):
```sh
make formal-cheriot-gui
touch formal/formal-cheriot/STOP     # later, to stop the proofs but keep the session; then click stop once
```

**Results back to the laptop**
```sh
make uvm-results-nyx                  # laptop
```