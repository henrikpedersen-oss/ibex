The covergroup is in: `cheri_access_bounds_cg` in [core_ibex_fcov_if.sv](ibex/dv/uvm/core_ibex/fcov/core_ibex_fcov_if.sv), and the UVM testplan is regenerated. It hasn't been compiled yet.

**What it samples:** every CHERIoT-mode data access, once, in the first execute cycle, from the same signals the core's bounds check uses (`base32`, `top33`, the access address and size):
- plain loads and stores through a capability;
- CLC and CSC, which are always 8 bytes.

Debug mode and the unchecked second half of a misaligned access are skipped.

**Coverpoints:**
- `cp_acc_type`: 8 access types, load/store × byte/half/word/cap.
- `cp_acc_base_dist`: access start minus base, one bin per byte from −10 to +10.
- `cp_acc_top_dist`: access *end* minus top, one bin per byte from −10 to +10. Using the end covers accesses that straddle top: a word at `top−2` lands at +2.
- `cp_acc_perm_ok`: whether the access has the permission it needs, Load or Store.
- `cp_acc_auth`: whether the authorising capability is untagged, sealed or valid.
- `cp_acc_bounds`: whether the access starts below base, lies inside, or ends above top.

**Crosses:**

| Cross | Bins | Covers |
|---|---|---|
| `acc_base_edge_cross` | 8 × 21 = 168 | access type × distance from base |
| `acc_top_edge_cross` | 168 | access type × distance from top |
| `acc_fault_priority_cross` | 8 × 3 × 2 × 3 = 144 | access type × authority × permission × bounds |

The priority cross covers accesses where several checks fail at once. Which cause the core reports then is where cores and models most often disagree, and the cosim compares the trap cause. In total that's 480 bins, small next to the large crosses we compiled out.

It's finished now: `cheri_representability_cg` is written, next to `cheri_access_bounds_cg`, and the UVM testplan is regenerated with both. Neither group has been compiled yet.

**What it samples:** CSetAddr, CIncAddr and CIncAddrImm on a tagged capability, in the execute cycle.
- The new address is taken from `result_data_o`, the input capability from `rf_fullcap_a`.
- The window edges come from the RTL's own rule in `cheriot_set_address`: the window is `[base, base + 2^(9+E))`, or the whole address space at E = 24.

**Coverpoints:**
- `cp_rep_op`: which of the three instructions.
- `cp_rep_eclass`: the exponent class, E = 0, 1–7, 8–14, or 24 (full).
- `cp_rep_lo_dist`: new address minus base, one bin per byte from −10 to +10.
- `cp_rep_hi_dist`: new address minus the window's top, one bin per byte from −10 to +10. It isn't sampled at E = 24, where there's no upper edge.
- `cp_rep_lo_edge` / `cp_rep_hi_edge`: the tag outcome exactly at each edge, with both outcomes binned (`below_cleared`/`below_kept`, `base_*`, `last_*`, `past_*`).
- `cp_rep_sealed_out`: a sealed input's outcome; it must always lose the tag.

**Crosses:** 84 + 63 + 12 bins.

| Cross | Covers |
|---|---|
| `rep_lo_edge_cross` | exponent class × lower-edge distance |
| `rep_hi_edge_cross` | exponent class × upper-edge distance (E = 24 ignored) |
| `rep_op_eclass_cross` | instruction × exponent class |

**There are deliberately no `illegal_bins`.** The window formula is the RTL's implementation; CHERIoT Sail defines representability differently, as "the bounds decode the same with the new address". If the two ever disagree, illegal bins based on the RTL's formula would miss exactly that case. So the covergroup shows which edges were reached, and the cosim/TestRIG check against Sail says whether the outcome was right. If a coverage run shows a `below_kept` or `past_kept` hit, look at the cosim result for that instruction.

**To see them:** both new groups compile into the next UVM TB build. Sampling needs `+enable_ibex_fcov=1`, and `make cov-cg-detail` then shows their bins. Once that run shows which bins can't be reached (for example unaligned CLC/CSC addresses in the bounds group), those become `ignore_bins`, each with its reason.


**To compile it:** the next UVM build picks it up; sampling needs `+enable_ibex_fcov=1`, as for the other groups. Then `make cov-cg-detail` shows the new group's bins.

Here's how I'd go about it, ordered by what moves the numbers most for the least work. One caveat first: there's currently no full-regression coverage database to measure against. `coverage_combined/` on nyx holds only the 7-test UVM run, and the kept `regression_merged/` is gone. So step 0 is a baseline.

**0. Get a real baseline.** On nyx:
```sh
make uvm-regr-xlm COVERAGE=1
make compliance-xlm COVERAGE=1 && make compliance-cheriot-xlm COVERAGE=1
make cov-merge && make cov-cg-detail
```
Compliance now builds the same `opentitan` core, so its coverage merges cleanly with UVM. TestRIG stays separate, as we found today.

**1. Clean up the denominators.** This makes the numbers honest rather than adding stimulus.
- **Toggle (around 37%):** most of it is ports tied to constants in this configuration: boot address, hart ID, RAM config, scramble key and debug inputs. Waive those in `coverage_waivers_xlm.tcl`, or restrict toggle to the interfaces we care about.
- **Unreachable code:** the UNR flow (`superlint/unr.tcl`, JasperGold) proves which blocks and branches can't be reached in this configuration. Excluding them removes noise from block, branch and FSM.
- **Covergroup totals:** the per-bin percentage (4% when we last had a regression) is swamped by a few huge crosses. The 15 largest are already compiled out. For the rest, mark impossible bins `illegal_bins` or `ignore_bins`, and judge progress by each covergroup's average rather than one total.

**2. Close the gaps the testbench can't currently reach.** Each is a missing stimulus capability, not a missing test.
- **The TRVK "revoked" verdict:** `ibex_revbm_responder` never revokes, so `cp_trvk_revoked` and the revoked arm of every load-barrier path stay at 0. Let the responder revoke a random or configured subset of granules, with a model of which are revoked, so the scoreboard can check the stripped tags.
- **Bus and PMP errors in CHERIoT mode:** the LSU's error states are reachable only with error injection on split and misaligned accesses. TestRIG's memory never errors; that accounts for its 13/31 LSU FSM states.
- **Interrupts and debug in CHERIoT mode:** the existing riscv-dv debug and interrupt tests run with `cheriot_enable_i` low. Running them with it high covers the controller FSM, the MEPCC/DEPCC paths and the CHERIoT interrupt covergroups. The TestRIG DII agent also has no interrupt model, which is why its interrupt generator is NOT RUN.

**3. More and better stimulus.**
- **Today's new directed tests:** `cheriot_fetch_bounds`, `cheriot_cjalr_faults`, `cheriot_seal_fail`, `cheriot_scr_faults`, `cheriot_perm_lc_sc` and `cheriot_bck_nocheck` target the exception-cause, CJALR and bounds coverpoints directly. They haven't been run yet, so put them in the regression first.
- **Random CHERIoT streams in riscv-dv:** raise the CHERIoT share in `ibex_cheriot_instr_sequence`, and seed it with valid, bounded and sealed capabilities, so CHERI operations act on meaningful operands rather than mostly untagged ones.
- **TestRIG:** MUL/DIV is now generated. Adding the `unstructured` generator exercises the illegal-encoding paths, and longer tests (`-L`) and more tests (`N`) give deeper sequences.

**4. Make closure systematic.**
- **Rank tests:** IMC `rank` shows which tests actually add coverage. Drop seeds that add nothing and spend the budget on the ones that do.
- **Track by requirement:** every covergroup is tied to testpoints in the generated UVM testplan, so the report can show coverage per requirement. Then you can see "REQ_TMP_01 is at 0" instead of an overall 73%.

The highest-value starting points, in my view, are revoke injection in the bus responder and running interrupts and debug in CHERIoT mode. Both open whole areas that are at 0 today. Do you want me to start with those?

Here's my second opinion. The headline numbers don't measure the verification: they come from a narrow sample, and about half the denominator is a duplicate core. The structural holes underneath are real, though.

**1. The sample is narrow.** `coverage_combined` (09:31 today) contains one UVM database, built from **70 runs of 7 directed tests**: the aliasing-fix batch, 10 seeds each. No regression, compliance or Sonata data is in it. So 73.3% block and 4.7% covergroup describe those 7 tests. Several of the low numbers are simply things those tests never do:
- `ex_block` FSM 1/15: they contain no MUL/DIV;
- PMP expression 5% (15/290): they never use PMP;
- the controller and interrupts: they take no interrupts.

A full regression will move all of these a lot.

**2. Half of `ibex_top` is a copy of the core.** With `SecureIbex=1`, the lockstep shadow core (`gen_lockstep`, 8,361 blocks) is almost as big as the main core (`u_ibex_core`, 8,050), and between them they're about 93% of `ibex_top`'s 17,743 blocks. The shadow core runs the same instructions, so it adds no information but doubles the denominator and drags its own uncovered branches into the headline. I'd make **`u_ibex_core`** the headline and report the lockstep separately, or exclude everything in it except the comparison logic.

**3. Things that inflate the denominators:**
- **Toggle 38.9%:** `ibex_top`'s toggle is measured on ports, and many are tied to constants in this bench. Inside the core it's 47.8%. Waive the tied ports.
- **`push_pull_agent_pkg`:** a covergroup from a vendor agent (0/3) is counted in the functional total. Exclude it.
- **The covergroup total (5.97% of 10,879 bins)** is dominated by a few large crosses. The per-covergroup **average is 20.1%**, a fairer measure. Prune the impossible bins and report averages.

**4. Holes no regression will fill, which need testbench work:**
- **Revocation:** `ibex_trvk` toggle is **0% (0/80)** and its covergroup 9.4% (6/64). The whole revocation-bitmap interface never changes, because `ibex_revbm_responder` always answers "not revoked" with zero data. This is the clearest gap in the bench. The fix is revoke injection in the responder.
- **Memory ECC error checks:** `g_mem_ecc_asserts` covers 0 of its 2 assertions, because nothing ever injects an integrity error.
- **LSU error states:** the load-store unit FSM reaches 5 of 31 states. The rest are mostly the split, misaligned and error paths, so they need error injection on those accesses.
- **Interrupts and debug in CHERIoT mode:** none of the bench's interrupt or debug tests run with `cheriot_enable_i` high, so the controller's paths for them are never exercised in CHERIoT mode.

**5. TestRIG already reaches more functional coverage than these tests:** 30% covergroup coverage against 6%, from random streams alone. That supports putting effort into random CHERIoT stimulus, in riscv-dv and TestRIG, over more directed tests.

**Revised order from my earlier plan:**
1. Baseline: run the full regression and compliance with coverage, then `make cov-merge`.
2. Fix the scope: report `u_ibex_core` as the headline, separate the lockstep core, drop the vendor covergroup and tied ports, and report covergroup averages.
3. Revoke injection in the bus responder.
4. Error injection: ECC errors, and bus errors on split and misaligned accesses.
5. Interrupts and debug in CHERIoT mode.

Steps 2–4 are code I can write now. Step 1 needs the regression run on nyx. Which do you want first?

Yes, clean first. The UVM coverage merge collects **every** coverage database it finds under the output directory (`merge_cov.py` globs `**/*.ucd`), not only tonight's. Today's leftovers would be merged into the regression numbers:
- the 70 directed-test runs;
- `cheriot_pcc`;
- the Juliet runs.

`make cov-clean` removes:
- the UVM per-test databases and their merge outputs (`out/run/coverage`, `out/run/tests/*/coverage`);
- `coverage_combined/`;
- the RTOS SoC's coverage database.

It leaves TestRIG's coverage alone. That's fine, because TestRIG is merged and reported separately, and its older runs are still valid RTL coverage.

Tonight, on nyx:
```sh
./resync_nyx                       # from the laptop first: today's RTL/TB/flow fixes
make cov-clean
make uvm-regr-xlm COVERAGE=1
make compliance-xlm COVERAGE=1 && make compliance-cheriot-xlm COVERAGE=1
make cov-merge && make cov-cg-detail
```
Then tomorrow, from the laptop: `make results-nyx`.

Notes on tonight's run:
- **New tests:** the regression (`TEST=all,all_directed`) picks up every directed test list, so today's new tests are included: the fetch-bounds, CJALR, seal, SCR, permission and enable-off tests, plus the rewritten Juliet and RTOS tests. Many of them have never run, so expect some failures among them. That's the point of running them.
- **Testbench rebuild:** the testbench was last built with VCS, so this run rebuilds it for Xcelium automatically ("variable SIMULATOR has changed value"). Don't leave `SIMULATOR=vcs` set in that shell.
- **Compliance:** it now builds the `opentitan` configuration, so tonight is also its first run with the new parameters.

The scope fixes I proposed (making `u_ibex_core` the headline, separating the lockstep core, dropping the vendor covergroup and tied ports) can all be applied when the report is generated, so they don't need to be in before the regression. I can write them while it runs.

Here's my second opinion. The headline numbers don't measure the verification: they come from a narrow sample, and about half the denominator is a duplicate core. The structural holes underneath are real, though.

**1. The sample is narrow.** `coverage_combined` (09:31 today) contains one UVM database, built from **70 runs of 7 directed tests**: the aliasing-fix batch, 10 seeds each. No regression, compliance or Sonata data is in it. So 73.3% block and 4.7% covergroup describe those 7 tests. Several of the low numbers are simply things those tests never do:
- `ex_block` FSM 1/15: they contain no MUL/DIV;
- PMP expression 5% (15/290): they never use PMP;
- the controller and interrupts: they take no interrupts.

A full regression will move all of these a lot.

**2. Half of `ibex_top` is a copy of the core.** With `SecureIbex=1`, the lockstep shadow core (`gen_lockstep`, 8,361 blocks) is almost as big as the main core (`u_ibex_core`, 8,050), and between them they're about 93% of `ibex_top`'s 17,743 blocks. The shadow core runs the same instructions, so it adds no information but doubles the denominator and drags its own uncovered branches into the headline. I'd make **`u_ibex_core`** the headline and report the lockstep separately, or exclude everything in it except the comparison logic.

**3. Things that inflate the denominators:**
- **Toggle 38.9%:** `ibex_top`'s toggle is measured on ports, and many are tied to constants in this bench. Inside the core it's 47.8%. Waive the tied ports.
- **`push_pull_agent_pkg`:** a covergroup from a vendor agent (0/3) is counted in the functional total. Exclude it.
- **The covergroup total (5.97% of 10,879 bins)** is dominated by a few large crosses. The per-covergroup **average is 20.1%**, a fairer measure. Prune the impossible bins and report averages.

**4. Holes no regression will fill, which need testbench work:**
- **Revocation:** `ibex_trvk` toggle is **0% (0/80)** and its covergroup 9.4% (6/64). The whole revocation-bitmap interface never changes, because `ibex_revbm_responder` always answers "not revoked" with zero data. This is the clearest gap in the bench. The fix is revoke injection in the responder.
- **Memory ECC error checks:** `g_mem_ecc_asserts` covers 0 of its 2 assertions, because nothing ever injects an integrity error.
- **LSU error states:** the load-store unit FSM reaches 5 of 31 states. The rest are mostly the split, misaligned and error paths, so they need error injection on those accesses.
- **Interrupts and debug in CHERIoT mode:** none of the bench's interrupt or debug tests run with `cheriot_enable_i` high, so the controller's paths for them are never exercised in CHERIoT mode.

**5. TestRIG already reaches more functional coverage than these tests:** 30% covergroup coverage against 6%, from random streams alone. That supports putting effort into random CHERIoT stimulus, in riscv-dv and TestRIG, over more directed tests.

**Revised order from my earlier plan:**
1. Baseline: run the full regression and compliance with coverage, then `make cov-merge`.
2. Fix the scope: report `u_ibex_core` as the headline, separate the lockstep core, drop the vendor covergroup and tied ports, and report covergroup averages.
3. Revoke injection in the bus responder.
4. Error injection: ECC errors, and bus errors on split and misaligned accesses.
5. Interrupts and debug in CHERIoT mode.

Steps 2–4 are code I can write now. Step 1 needs the regression run on nyx. Which do you want first?