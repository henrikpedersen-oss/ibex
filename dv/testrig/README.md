# TestRIG UVM testbench

This directory holds a UVM testbench that runs [TestRIG](https://github.com/CTSRD-CHERI/TestRIG)
random instruction streams against Ibex. QuickCheckVEngine generates the instructions and sends
them to the core over TCP using Direct Instruction Injection (DII). An in-bench scoreboard
checks every instruction the core retires against a Sail reference model:

| Flavour   | Core mode                  | QuickCheckVEngine architecture | Reference model |
|-----------|----------------------------|--------------------------------|-----------------|
| `cheriot` | `cheriot_enable_i` high    | `rv32emcZifencei_Xcheriot`      | CHERIoT-Sail    |
| `riscv`   | `cheriot_enable_i` low     | `rv32emcZifencei`               | RISC-V Sail     |

The testbench builds on Xcelium and on Verilator. Only Xcelium collects coverage and waves.

## Running it

In the `ibex_cheriot_verification` checkout, run TestRIG from the repository root. These targets
build the Sail libraries, start the simulator and QuickCheckVEngine, keep each run's log and
verdict, and feed the testplan report:

```sh
make testrig-cheriot-xlm            # CHERIoT flavour, Xcelium
make testrig-riscv-xlm              # plain RISC-V flavour, Xcelium
make testrig-cheriot-vlt            # same testbench on Verilator (nix develop .#vlt_shell)
make testrig-fault-injection-xlm    # scoreboard fault injection; every run must fail
make testplan-testrig               # report the kept runs against ibex/dv/testplans/testrig_testplan.hjson
```

A run is complete only when the scoreboard has compared a non-zero number of instructions with
zero mismatches at full size (N = 100 per generator). A pipeclean or smaller run does not count.

The report (`testrig_report/testrig_testplan.html`, also produced by `make testrig-results-nyx`)
states the Sail model every kept run was checked against. Each kept `.result` records the model,
its `VENDORED_FROM` source, the tree state, and a hash of the DPI library the run loaded; runs made
against different models are flagged. After a `COVERAGE=1` run, the report also includes the merged
TestRIG coverage from `xlm_testrig_out/coverage_report/`: code coverage of `ibex_top`, and
functional coverage per covergroup type.

## Running it by hand

The local [Makefile](Makefile) builds and runs one simulator process. You start
QuickCheckVEngine yourself in a second shell:

```sh
make sail-libs                      # once: dv/cosim/{cheriot_sail,riscv_sail} DPI libraries
make build-xlm COV=1
make run-xlm FLAVOUR=cheriot        # waits for a connection on port 6000
make vengine FLAVOUR=cheriot N=100  # in a second shell
```

Options for `run-xlm`:
- `COV=1`: collect coverage.
- `WAVES=1` or `GUI=1`: record waves, or open the Simvision GUI.
- `VERBOSE=1`: high UVM verbosity.
- `PORT=<n>`: listen on a different port.
- `PLUSARGS=...`: pass any further plusargs.

For Verilator, use `build-vlt` and `run-vlt` inside `nix develop .#vlt_shell`.

Plusargs read by the testbench:

| Plusarg | Default | Meaning |
|---|---|---|
| `+dii_port=<n>` | 6000 | TCP port the testbench listens on |
| `+dii_idle_polls=<n>` | 50 | End the run after this many consecutive empty 100 ms polls |
| `+dii_ack_timeout=`, `+dii_retire_timeout=`, `+dii_drain_timeout=` | see `ibex_dii_agent/` | Handshake timeouts |
| `+dii_sb_max_errors=<n>` | 100 | Print only the first n mismatches (all are counted) |
| `+dii_sb_corrupt=<n>` | off | Fault injection: corrupt the RTL side of the n-th retired instruction |
| `+dii_sb_corrupt_field=<f>` | `rd` | Field to corrupt: `rd`, `pc`, `trap` or `mem` |
| `+dii_intg_corrupt=<n>` | off | Fault injection: flip an integrity bit of the n-th load response; a `NoAlertsTriggered` UVM_ERROR must follow |

## Core configuration

The core is built with a configuration from `ibex/ibex_configs.yaml`, read through
`util/ibex_config.py`: `-C <config>` on either build script, or `IBEX_CONFIG`, default `opentitan`
(the configuration the UVM testbench, compliance and the RTOS SoC use). The build records it in
`<out>/.ibex_config`, and the run scripts refuse a build for another configuration.

What the opentitan configuration needs from the bench, all in `tb/core_ibex_testrig_tb_top.sv`:

- ICache = 1: there is no prefetch buffer, so DII is injected in the ICache output stage
  (`DII_SIM` block in `rtl/ibex_icache.sv`) instead of the fetch FIFO. The scrambling-key request
  is answered with a zero key.
- SecureIbex = 1: bus integrity is generated for both response buses; the lockstep shadow core
  gets the DII stream and the MEPC reset alignment one cycle late; a `NoAlertsTriggered`
  UVM_ERROR fails the run on any alert.
- RV32E = 0: x16-x31 are real registers in the riscv flavour (as in RISC-V Sail); CHERIoT mode
  still decodes x0-x15 only. QuickCheckVEngine ignores the `e`/`i` letter and generates x0-x15
  regardless, so only `unstructured` reaches x16-x31.
- PMPEnable = 1: the RISC-V Sail model is configured with the same number of PMP regions.
  CHERIoT Sail has none (its bridge has no PMP setting).

Where the core and the Sail models still disagree on what is legal. Only `unstructured` (and the
random 16-bit words of `caprvcrandom`, which runs by default in the cheriot flavour) reach these:

- Zcb (both modes) and Zcmp (riscv mode only): legal on the core, missing from both models.
- The draft bitmanip encodings in RV32BOTEarlGrey (Zbp, Zbr, Zbt, Zbf, cmix/cmov/fsl/fsr, crc32,
  ...): legal on the core; the models implement only ratified Zba/Zbb/Zbc/Zbs (+ Zbkb/Zbkx).
- CSRs: mhpmcounter3-12(h)/mhpmevent3-12 (MHPMCounterNum = 10), tdata1-3/mcontext/scontext
  (DbgTriggerEn = 1), cpuctrlsts/secureseed (0x7C0/0x7C1) and mseccfg exist on the core and not
  in the models; so do pmpcfg*/pmpaddr* in CHERIoT mode.

## Layout

| Path | Contents |
|---|---|
| `ibex_testrig_dv.f` | File list shared by both simulators |
| `tb/core_ibex_testrig_tb_top.sv` | Top level: `ibex_top`, DII instruction side, data memory with tags, X checks |
| `tb/testrig_vlt_prelude.sv`, `tb/testrig_vlt_uvm_dpi.cc` | Verilator-only UVM glue |
| `env/` | DII interface and the TestRIG UVM environment |
| `ibex_dii_agent/` | Socket sequence, driver, sequencers and the Sail scoreboards |
| `tests/core_ibex_testrig_test.sv` | The single UVM test |
| `dpi/` | TestRIG packet socket (C++ DPI) |
| `testrig_{xlm,vlt}_{build,run}.sh` | Build and run scripts; run them from this directory |
| `waves.tcl`, `testrig_vlt_waiver.vlt` | Wave probes, Verilator waivers (coverage uses the shared `ibex/dv/coverage/ibex_cover.ccf`) |
| `xlm_testrig_out/`, `vlt_testrig_out/` | Build and run outputs, including `results/` and `failures/` (git-ignored) |

The testbench also uses these files, which are shared with the main UVM testbench in
`dv/uvm/core_ibex` and stay there:
- `env/core_ibex_rvfi_if.sv`
- `common/ibex_cosim_agent/ibex_rvfi_pkg.sv`
- the `fcov/` coverage interfaces and bind
- `tb/ibex_revbm_responder.sv`

It also links the Sail DPI bridges in `dv/cosim/cheriot_sail` and `dv/cosim/riscv_sail`.
Nothing in the main UVM testbench depends on this directory.

## Known limitations

- **Interrupts and unstructured streams:** the interrupt and unstructured generators are excluded
  (`-x 'interrupt|unstructured'`). The DII flow has no interrupt model.
- **Revocation:** `ibex_revbm_responder.sv` never reports a granule revoked, so the revoked arm of
  the load filter is not exercised here.
- **Verilator builds:** these contain absolute paths. Build on the machine that runs the testbench;
  don't copy a build from elsewhere.
