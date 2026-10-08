# CHERIoT RTOS test SoC

This directory holds a minimal SoC and Xcelium testbench for running CHERIoT RTOS firmware built
for [Sonata](https://github.com/lowRISC/sonata-system) (boards `sonata-1.1` and
`sonata-simulator`) on this repository's `ibex_top`. It runs the upstream CHERIoT RTOS test suite
and the suites in [`firmware/`](firmware) (Juliet CWE, CHERI-C, the revocation test). The UART output is the
test oracle: every suite reports its checks on UART0, and the testbench captures UART0 with
`uartdpi`.

The SoC has the core, the OpenTitan CHERIoT memory subsystem
([lowRISC/opentitan#31515](https://github.com/lowRISC/opentitan/pull/31515), stacked on #31470),
two memories and the four peripherals the firmware uses, on Sonata's memory map:

| Address | Size | Device | RTL |
|---|---|---|---|
| `0x0010_0000` | 128 KiB | SRAM, dual-ported (data + fetch). Boot vector at `+0x80` | Sonata `sram.sv` |
| `0x3000_0000` | 2 KiB | Revocation bitmap window: the memory subsystem's meta SRAM | opentitan-cheriot `cheriot` |
| `0x4000_0000` | 1 MiB | Code RAM, dual-ported: a plain SRAM model in Sonata's HyperRAM window | Sonata `sram.sv` |
| `0x8000_a000` | 4 KiB | `rev_ctl`, the RTOS hardware-revoker interface, driving the subsystem's TRBE | Sonata `rev_ctl` |
| `0x8004_0000` | 64 KiB | `rv_timer` (CLINT: `mtime`, `mtimecmp`) | Sonata `rv_timer.sv` |
| `0x8010_0000` | 4 KiB | UART0 | OpenTitan `uart`, as vendored by Sonata |
| `0x8800_0000` | 128 MiB | `rv_plic`. Sources: 1 = revoker, 8 = UART0 (Sonata's numbering) | Sonata `rv_plic` |
| anything else | | Default responder: logs the access; reads return 0, writes are dropped | `rtl/cheriot_rtos_default_rsp.sv` |

The address decode uses Sonata's own `tl_main_pkg` and `tl_ifetch_pkg` constants, so the map
cannot drift from the board file the firmware is built for. Instruction fetch reaches only the two
memories. A fetch from any other address gets a TL-UL error, and the testbench logs it.

The core and memory subsystem are integrated as in Sonata's `sonata_system.sv` with
`UseNewIbexCore = 1` and `UseCheriotMemSubsys = 1`, with the same core parameters (the
`opentitan` configuration the UVM testbench builds), the same bus adapters, memory-integrity
encoding and subsystem parameters. The integration glue (`cheriot_mem_subsys.sv`,
`cheriot_rev_ctl_trbe.sv`) began as an uncommitted addition to a sonata-system checkout; the copies
in `rtl/` are this flow's own, ported to #31515. The Sonata RTL the SoC uses is vendored under
`vendor/` (see [Sources](#sources)).

## What the firmware needs

The CHERIoT RTOS linker records every MMIO region a firmware image imports in its audit report
(`<firmware>.json`, entries of kind `MMIO`). For the RTOS test suite, Juliet, CHERI-C,
`revocation_test_fw` and `tests.extra/hardware_revoker_IRQs`, the imports are the same:

| Import | Device |
|---|---|
| `0x3000_0000 +0x800` | `shadow`: the revocation bitmap (the loader zeroes it at boot) |
| `0x8000_a000 +0x1000` | `revoker`: rev_ctl |
| `0x8004_0000 +0x10000` | `clint`: the timer |
| `0x8010_0000 +0x34` | `uart` |
| `0x8800_0000 +0x400000` | `plic` |

The only other imports are heap regions inside SRAM. Nothing else in the board file is imported.
Sonata's `examples/heartbleed` (sonata-software) is the exception: it uses the board GPIO (joystick)
and the LCD (SPI and PWM), which this SoC does not have, and it is not built here. See
[Known limitations](#known-limitations).

## What was removed, and why

Everything in `sonata_system` that no firmware above uses: GPIO, pinmux, I2C, SPI (including the
LCD and Ethernet controllers), USB device, PWM, XADC, the RGB LED controller, `system_info`, UARTs
1 and 2, the HyperRAM controller, the debug module and its bus host, Sonata's own tag stores and
revocation-bitmap RAM, the legacy `ibexc` core and the `REVOCATION_CONNECT` bitmap stub. Also gone
are the Sonata flow's two other builds. The "default" build had Sonata's tag stores and a barrier
tied to "nothing revoked". The `REVOCATION=1` build had the barrier on a plain bitmap RAM and no
sweep engine. The CHERIoT memory subsystem is always present here.

For firmware that needs those peripherals, or for the debug host, use the full Sonata SoC
([lowRISC/sonata-system](https://github.com/lowRISC/sonata-system)).

## Running it

In the `ibex_cheriot_verification` checkout, run the suites from the repository root. These
targets build the firmware, build and run the simulation, keep each run's UART log and verdict, and
feed the testplan report:

```sh
make sonata-xlm                     # the nix-built CHERIoT RTOS test suite
make sonata-rtos-tests-xlm          # the same suite, built from the cheriot-rtos submodule
make sonata-revocation-xlm          # load barrier, both directions, plus one TRBE sweep
make sonata-juliet-xlm              # Juliet CWE compartment enforcement
make sonata-cheri-c-xlm             # Cambridge CHERI-C suite
make sonata-test-xlm ELF=<path>     # any firmware image
make sonata-regression-xlm          # every run ibex/dv/testplans/sonata_testplan.hjson needs
make testplan-sonata                # report the kept runs against the testplan (no simulation)
make sonata-mutation-check-xlm      # break one hardware check per run (see below)
make rtos-firmware                  # build every firmware image above, without simulating
```

`REBUILD=1` forces re-elaboration. Without it, a cached build (`xlm_rtos_out/.elab_ok`) is reused
even after an RTL change. `COVERAGE=0` builds without coverage (the root default is on).

A run passes only if all of the following hold:
- the UART log is not empty
- `run.log` has no timeout, assertion failure or `*E`/`*F`
- the UART log has no failure line
- for suites that report one, the UART log says `All tests finished`

Unmapped accesses do not fail a run. `run_all_tests.sh` prints how many there were.

## Running it by hand

The local [Makefile](Makefile) builds and runs one simulator process, with `xrun` on the `PATH`
(for example inside `nix develop .#eda_shell` in the superproject). It does not build firmware or
judge the result:

```sh
make build COV=1
make run ELF=<firmware ELF>                        # boot stub: firmware/sim_boot_stub/sim_boot_stub
make run ELF=<firmware> BOOT=<sim_boot_stub> GUI=1
make run ELF=<firmware> MUTATE=barrier_none MAX_CYCLES=40000000
make run ELF=<firmware> PLUSARGS="+default_rsp_error=1 +ibex_tracer_enable=1"
make lint                                          # Verilator lint, inside nix develop .#vlt_shell
make clean
```

The scripts can also be called directly: `./cheriot_rtos_xlm_build.sh [-c] [-o <outdir>]` and
`./cheriot_rtos_xlm_run.sh [-c] [-g] [-o <outdir>] [-- <plusargs>]`. The run script reads
`SONATA_TEST_ELF`, `SONATA_BOOT_STUB`, `UART_LOG`, `SONATA_MAX_CYCLES` and `SONATA_MUTATE` from the
environment. These are the names `run_all_tests.sh` sets.

The run script turns the boot stub and the firmware into two vmem images with `elf_to_vmem.py`:
the SRAM gets the boot stub and any SRAM-resident segments, and the code RAM gets the segments at
`0x4000_0000`. The testbench loads both at time 0, and it fails at once if the boot vector is
empty.

Plusargs read by the testbench:

| Plusarg | Default | Meaning |
|---|---|---|
| `+sram_vmem=<file>` | required | SRAM image |
| `+code_vmem=<file>` | none | Code RAM image |
| `+UARTDPI_LOG_uart0=<file>` | `uart0.log` | UART0 log |
| `+max_cycles=<n>` | 4.8e9 | Cycle timeout. Prints `[cheriot_rtos_tb] TIMEOUT` |
| `+sonata_mutate=<name>` | off | Break one hardware check (below) |
| `+default_rsp_error=1` | off | Unmapped data accesses get a TL-UL error, which the core raises as an access fault |
| `+enable_ibex_fcov=1` | off | Sample the functional covergroups |
| `+ibex_tracer_enable=1` | 0 (run script) | Instruction trace |

## Outputs

Everything goes to `xlm_rtos_out/`, which git ignores:

| Path | Contents |
|---|---|
| `build.log`, `run.log` | Elaboration and simulation logs. `run.log` has the heartbeat, `[trbe_monitor]` and `[cheriot_rtos_default_rsp]` lines |
| `uart0.log` | UART0 of the last run |
| `sram.vmem`, `code.vmem` | Memory images of the last run |
| `xcelium.d/`, `.elab_ok`, `.coverage_enabled` | Snapshot and its stamps |
| `cov_work/`, `coverage_merged/` | Coverage database of the last run, and its merge |
| `results/<target>.cheriot_mem.uart.log` | UART logs kept by the root `SONATA_RESULT` targets, read by `make testplan-sonata` |
| `results/mutations/<mutation>/` | The mutation check's logs |

`make clean` removes all of it, including `results/`.

## Mutation check

`+sonata_mutate=<name>` forces one hardware check off at run time, so one build serves every
mutation. `make sonata-mutation-check-xlm` runs each mutation against the suites that should
notice. `ibex/dv/testplans/mutation_check.py` holds the table of mutations, runs and tests that must report
FAIL, and grades each result:

| Mutation | Forces | Must fail |
|---|---|---|
| `bounds_off` | Load/store bounds checks (main and lockstep shadow core) | `cheri_c_array`; Juliet CWE-121/122/190 |
| `ldst_perm_off` | Load/store permission checks | `cheri_c_input`, `cheri_c_output` |
| `exec_off` | Execute permission on capability jumps | `cheri_c_badcall` |
| `datastore_tag` | Data stores set the tag instead of clearing it | `cheri_c_union` |
| `barrier_none` / `barrier_all` | Load barrier never / always revokes | revocation phase 2 / phases 1 and 3; `rtos_test_allocator` |
| `trbe_no_inval` | The TRBE sweeps but never invalidates | `revocation_sweep` |

The forces are in `tb/cheriot_rtos_tb.sv`. They use paths under
`u_soc.u_top_tracing.u_ibex_top` and `u_soc.u_cheriot_mem_subsys`. Run the unmutated
`make sonata-regression-xlm` as the control.

## Coverage

With `-c`, the build instruments `ibex_top` and `cheriot_mem_subsys` and nothing else
(`cheriot_rtos_cover.ccf` with `-covdut cheriot_rtos_soc`). It collects
statement/block/branch/expression/FSM coverage below each, and toggle coverage on their ports.
The pre-verified prims are black-boxed as in `dv/tools/xcelium/cover.ccf`. The core has the same
parameters as the UVM testbench's `opentitan` configuration. The run merges its database into
`xlm_rtos_out/coverage_merged`, which `run_all_tests.sh` adds to the combined merge.

The functional covergroups are bound from outside the RTL (`fcov/cheriot_mem_subsys_fcov_bind.sv`),
and they sample with `+enable_ibex_fcov=1`:
- the memory subsystem: tag filter, RMW filter, TRBE mover, access checks, subsystem top level
- the rev_ctl shim
- the TRVK covergroup on the core's load barrier and on the TRBE's own filter

## Layout

| Path | Contents |
|---|---|
| `rtl/cheriot_rtos_soc.sv` | The SoC |
| `rtl/cheriot_rtos_xbar.sv` | Data and instruction crossbars on Sonata's map |
| `rtl/cheriot_rtos_default_rsp.sv` | Responder for unmapped data addresses |
| `rtl/cheriot_mem_subsys.sv`, `rtl/cheriot_rev_ctl_trbe.sv` | Sonata's memory-subsystem glue (derived; ported to #31515) |
| `tb/cheriot_rtos_tb.sv` | Clock, reset, uartdpi, memory load, timeout, heartbeat, mutations, TRBE monitor |
| `fcov/` | Memory-subsystem covergroups and their binds |
| `firmware/` | The revocation, Juliet CWE and CHERI-C firmware (xmake) and the boot stub |
| `vendor/` | The Sonata RTL the SoC uses, pinned: `fetch.sh`, `VENDORED_FROM`, local `patches/` |
| `patches/cheriot-rtos/` | Local cheriot-rtos change the root Makefile applies (the test-runner filter) |
| `patches/cheri-c-tests/` | Local cheri-c-tests change the CHERI-C build needs (kept for reference) |
| `patches/archive/` | Uncommitted changes saved from the removed sonata-system and sonata-software checkouts |
| `cheriot_rtos_dv.f` | File list, shared by Xcelium and Verilator lint |
| `cheriot_rtos_xlm_{build,run}.sh`, `elf_to_vmem.py` | Build and run scripts |
| `cheriot_rtos_cover.ccf` | Coverage configuration |

## Sources

| What | From |
|---|---|
| The core, every `prim` / `prim_generic` / `dv_utils` file | this ibex repository (`rtl/`, `vendor/lowrisc_ip`): the same copies the UVM testbench builds the core with |
| The CHERIoT memory subsystem | the superproject's `opentitan-cheriot/` (override with `OT_CHERIOT_DIR`) |
| TL-UL, `top_pkg`, UART, `rv_timer`, `rv_plic`, `rev_ctl`, the SRAM model, `uartdpi`, the address-map packages | `vendor/sonata-system/`: lowRISC/sonata-system at the commit in `vendor/VENDORED_FROM`, fetched by `vendor/fetch.sh` |

One `tlul_pkg` is compiled: Sonata's, which carries the CHERIoT capability bit in `a_user`/`d_user`
and whose host and SRAM adapters have the `wdata_cap`/`rdata_cap` ports the SoC and the SRAM model
connect (OpenTitan's has neither). `vendor/fetch.sh` re-fetches the files and re-applies
`vendor/patches/` in order:

| Patch | Why |
|---|---|
| `0001-tl_main_pkg-cheriot-trbe-host.patch` | The sonata-system checkout's local `TlCheriotTrbe` host. Unused here (only `ADDR_*` constants are); kept so the file is the one the flow was validated with |
| `0002-uartdpi-quiet-pty-write-errors.patch` | The checkout's local uartdpi change: no stderr line per failed PTY write when logging to a file |
| `0003-sram-prim_ram_2p-cfg_o.patch` | `ibex/vendor/lowrisc_ip`'s `prim_ram_2p` splits the RAM configuration into `cfg_i` and `cfg_o`; `cfg_o` is left open. The generic RAM model is otherwise line-for-line Sonata's |

## Firmware

[`firmware/`](firmware) holds the images that are not part of cheriot-rtos, moved from
sonata-software/examples (sonata-software 5734522 plus its uncommitted fixes) and built against the
pinned `cheriot-rtos` submodule beside this bench (`cheriot-rtos/`, a submodule of ibex), with the CHERIoT toolchain of the superproject's
`nix develop .#cheriot_sw_shell` (llvm-cheriot 17.0.0, xmake 2.9.1, as in sonata-software):

| Path | xmake target |
|---|---|
| `firmware/revocation_test/` | `revocation_test_fw` |
| `firmware/juliet_cwe/` | `juliet_cwe_tests` |
| `firmware/cheri_c_tests/` | `cheri_c_tests` (includes the `cheri-c-tests` submodule beside this bench; needs `patches/cheri-c-tests/0001` in its working tree) |
| `firmware/sim_boot_stub/` | the boot stub (`make`), from sonata-system `sw/cheri/sim_boot_stub` |

The upstream test suite and `tests.extra` are built from the `cheriot-rtos` submodule itself. The
root Makefile applies `patches/cheriot-rtos/` to its working tree first: 0001 is the
`CHERIOT_TEST_MASK`/`CHERIOT_TEST_ONLY` filter in `tests/test-runner.cc`; 0002 makes Sonata's
`platform_simulation_exit()` print `Simulation exit code: <n>` before the exit string, which is
otherwise the same for a scheduler panic as for a clean exit. The `tests.extra` programs print no
verdict of their own, so they are built for board `sonata-simulator` (SIMULATION: the run ends when
the only thread returns) and graded on that line. `make sonata-xlm` runs
the nix-built suite instead: the superproject flake's `cheriot-rtos-test-suite` (cheriot-rtos
e34c07ef, board `sonata-prerelease`, built as sonata-system's flake built it).

## Known limitations

- **Heartbleed is not supported.** The demonstrator (sonata-software `examples/heartbleed`) waits
  for joystick input on the board GPIO, which is not here, and is not built here. The testplan's
  `heartbleed_blocked` needs the firmware moved into `firmware/`, a GPIO model and a joystick
  driver.
- **No debug module.** The testplan's `bus_master_dbg_host_tag_clear` and
  `bus_master_dbg_host_locked` need the debug host, so they cannot run on this SoC.
- **Not standalone.** The flow needs the `ibex_cheriot_verification` superproject for
  `opentitan-cheriot/`, and its firmware for the `cheriot-rtos` and `cheri-c-tests` submodules and
  the flake's CHERIoT toolchain. A plain ibex checkout cannot build it.
- **Older Sonata IP on newer prims.** The vendored Sonata TL-UL, UART, PLIC and `rev_ctl` were
  written against the older prim Sonata vendors; here they build against `ibex/vendor/lowrisc_ip`
  (lint-clean; the only port change is `prim_ram_2p`'s `cfg_o`, `vendor/patches/0003`). The
  register block's `prim_subreg` `reinit_i` connections, which neither prim set has, are dropped by
  `opentitan-cheriot/patches/0001`.
- **The code RAM is the subsystem's NVM.** The core's tag filter treats the NVM as read-only: a
  capability store (`csc`) to `0x4000_0000` is a read and compare, answered with a bus error unless
  the code RAM already holds the capability's 64 bits, and never writes it.
- **Unmapped accesses complete silently for the firmware.** They are only visible in `run.log`, and
  `run_all_tests.sh` reports how many there were. Use `+default_rsp_error=1` to turn them into
  faults.
- **Coverage merge.** The coverage top is `cheriot_rtos_soc`. The UVM testbench's is `ibex_top`.
  The combined merge unions `ibex_top` across the two hierarchies, as it did for the Sonata flow.
