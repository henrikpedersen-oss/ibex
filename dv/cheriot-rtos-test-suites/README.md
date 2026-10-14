# CHERIoT RTOS test SoC

This directory holds a minimal SoC and Xcelium testbench for running CHERIoT RTOS firmware built
for [Sonata](https://github.com/lowRISC/sonata-system) (boards `sonata-1.1` and
`sonata-simulator`) on this repository's `ibex_top`. It runs the upstream CHERIoT RTOS test suite
and the suites in [`firmware/`](firmware) (Juliet CWE, CHERI-C, the revocation and debug host tests). The UART output is the
test oracle: every suite reports its checks on UART0, and the testbench captures UART0 with
`uartdpi`.

The SoC has the core, the OpenTitan CHERIoT memory subsystem
([lowRISC/opentitan#31515](https://github.com/lowRISC/opentitan/pull/31515), stacked on #31470),
two memories, the four peripherals the firmware uses and the RISC-V debug module, on Sonata's memory map:

| Address | Size | Device | RTL |
|---|---|---|---|
| `0x0010_0000` | 128 KiB | SRAM, dual-ported (data + fetch). Boot vector at `+0x80` | Sonata `sram.sv` |
| `0x3000_0000` | 2 KiB | Revocation bitmap window: the memory subsystem's meta SRAM | opentitan-cheriot `cheriot` |
| `0x4000_0000` | 1 MiB | Code RAM, dual-ported: a plain SRAM model in Sonata's HyperRAM window | Sonata `sram.sv` |
| `0x8000_a000` | 4 KiB | `rev_ctl`, the RTOS hardware-revoker interface, driving the subsystem's TBRE | Sonata `rev_ctl` |
| `0x8004_0000` | 64 KiB | `rv_timer` (CLINT: `mtime`, `mtimecmp`) | Sonata `rv_timer.sv` |
| `0x8010_0000` | 4 KiB | UART0 | OpenTitan `uart`, as vendored by Sonata |
| `0x8800_0000` | 128 MiB | `rv_plic`. Sources: 1 = revoker, 8 = UART0 (Sonata's numbering) | Sonata `rv_plic` |
| `0xB000_0000` | 4 KiB | Debug module memory (debug ROM at `+0x800`), data and instruction side. Its system bus access is a bus host; see [Debug module](#debug-module) | `pulp_riscv_dbg` `dm_top` (fetched; see [Sources](#sources)) |
| anything else | | Default responder: logs the access; reads return 0, writes are dropped | `rtl/cheriot_rtos_default_rsp.sv` |

The address decode uses Sonata's own `tl_main_pkg` and `tl_ifetch_pkg` constants, so the map
cannot drift from the board file the firmware is built for. Instruction fetch reaches only the two
memories and the debug module. A fetch from any other address gets a TL-UL error, and the testbench logs it.

The core and memory subsystem are integrated as in Sonata's `sonata_system.sv` with
`UseNewIbexCore = 1` and `UseCheriotMemSubsys = 1`, with the same core parameters (the
`opentitan` configuration the UVM testbench builds), the same bus adapters, memory-integrity
encoding and subsystem parameters. The integration glue (`cheriot_mem_subsys.sv`,
`cheriot_rev_ctl_tbre.sv`, `cheriot_rev_ctl_trbe.sv` there) began as an uncommitted addition to a
sonata-system checkout; the copies
in `rtl/` are this flow's own, ported to #31515. The Sonata RTL the SoC uses is fetched at build
time (see [Sources](#sources)).

## What the firmware needs

The CHERIoT RTOS linker records every MMIO region a firmware image imports in its audit report
(`<firmware>.json`, entries of kind `MMIO`). For the RTOS test suite, Juliet, CHERI-C,
`revocation_test_fw`, `dbg_host_test_fw` and `tests.extra/hardware_revoker_IRQs`, the imports are the same
(the debug module is not imported: the testbench drives it, not the firmware):

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
1 and 2, the HyperRAM controller, Sonata's own tag stores and revocation-bitmap RAM, the legacy
`ibexc` core and the `REVOCATION_CONNECT` bitmap stub. The debug module is kept, without its JTAG
TAP, for the debug host tests (see [Debug module](#debug-module)). Also gone
are the Sonata flow's two other builds. The "default" build had Sonata's tag stores and a barrier
tied to "nothing revoked". The `REVOCATION=1` build had the barrier on a plain bitmap RAM and no
sweep engine. The CHERIoT memory subsystem is always present here.

For firmware that needs those peripherals, use the full Sonata SoC
([lowRISC/sonata-system](https://github.com/lowRISC/sonata-system)).

## Running it

In the `ibex_cheriot_verification` checkout, run the suites from the repository root. These
targets build the firmware, build and run the simulation, keep each run's UART log and verdict, and
feed the testplan report:

```sh
make sonata-xlm                     # the nix-built CHERIoT RTOS test suite
make sonata-rtos-tests-xlm          # the same suite, built from the cheriot-rtos submodule
make sonata-revocation-xlm          # load barrier, both directions, plus one TBRE sweep
make sonata-dbg-host-xlm            # debug module system bus access: tag clear, locked
make sonata-juliet-xlm              # Juliet CWE compartment enforcement
make sonata-cheri-c-xlm             # Cambridge CHERI-C suite
make sonata-test-xlm ELF=<path>     # any firmware image
make sonata-regression-xlm          # every run ibex/dv/cheriot-rtos-test-suites/sonata_testplan.hjson needs
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
| `+dbg_host_drv=0` | 1 | Do not serve the firmware's debug host requests (both debug host tests must then FAIL) |

## Outputs

Everything goes to `xlm_rtos_out/`, which git ignores:

| Path | Contents |
|---|---|
| `build.log`, `run.log` | Elaboration and simulation logs. `run.log` has the heartbeat, `[tbre_monitor]` and `[cheriot_rtos_default_rsp]` lines |
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
notice. `ibex/dv/scripts/mutation_check.py` holds the table of mutations, runs and tests that must report
FAIL, and grades each result:

| Mutation | Forces | Must fail |
|---|---|---|
| `bounds_off` | Load/store bounds checks (main and lockstep shadow core) | `cheri_c_array`; Juliet CWE-121/122 |
| `ldst_perm_off` | Load/store permission checks | `cheri_c_input`, `cheri_c_output` |
| `exec_off` | Execute permission on capability jumps | `cheri_c_noexec_call` |
| `datastore_tag` | Data stores set the tag instead of clearing it | `cheri_c_union` |
| `barrier_none` | Load barrier never revokes | revocation phase 2; `rtos_test_allocator` |
| `barrier_all` | Load barrier revokes revocation_test's barrier object whatever its shadow bit | revocation phases 1 and 3 |
| `tbre_no_inval` | The TBRE sweeps but never invalidates | `revocation_sweep` |
| `dbg_lock_open` | The debug-access gate on the debug module's system bus access is stuck open | `bus_master_dbg_host_locked` |

The CHERI-C and Juliet fault tests pass only on their expected CHERI exception cause
(`firmware/common/expected_fault.hh`), so a broken check that lets an access through and faults
later reports FAIL. Some tests cannot see a mutation and are not listed for it: `cheri_c_badcall`
faults on the tag before the execute check, Juliet CWE-190 on the tag (an unrepresentable cursor)
before the bounds check, and `bus_master_tbre_invalidate_only` passes when the TBRE writes nothing.
`barrier_all` is limited to one object because the barrier looks up every capability based in the
SRAM, the whole revocable window: revoking them all stops the RTOS from booting.

The forces are in `tb/cheriot_rtos_tb.sv`. They use paths under
`u_soc.u_top_tracing.u_ibex_top`, `u_soc.u_cheriot_mem_subsys` and `u_soc.u_dbg_sba_gate`. Run the unmutated
`make sonata-regression-xlm` as the control.

`mutation_check.py` also runs one fix model, the opposite of a mutation, for a test that fails on
the design: `sba_tag_clear_model` clears, from the testbench, the meta-SRAM tag of every debug
host write to the SRAM, and `bus_master_dbg_host_tag_clear` must then PASS (reported as `PASSES` /
`STILL FAILS`). It shows that the test can pass, and so that its failure on the design is the
design's.

## Debug module

```
 testbench (tb/cheriot_rtos_dbg_host.sv)
   |  DMI (dm::dmi_req_t / dmi_resp_t)            dbg_en_i (lc_hw_debug_en model)
   v                                                 |
 dm_top (pulp_riscv_dbg)             --debug_req--> AND --> ibex_top debug_req_i
   |  slave port (debug memory)      ^ master port (SBA)
   |                                 |
 tlul_adapter_reg <- tlul_socket_m1 <- data xbar dbg_dev (0xB000_0000)
   (en_ifetch: dbg_en_i)             <- ifetch xbar dbg_dev
                                    tlul_adapter_host (capability bit 0)
                                     |
                                    cheriot_rtos_dbg_gate (dbg_en_i)
                                     |
                                    xbar dbg_host --> SRAM port A (with the core and the TBRE)
                                                  --> code RAM port A (with the core)
                                                  --> anything else: TL-UL error
```

The debug module is `pulp_riscv_dbg`'s `dm_top` (fetched), connected as in Sonata's
`sonata_system.sv`: its memory in Sonata's `dbg_dev` window (`0xB000_0000`, 4 KiB, which was free
here: it went to the default responder) on both crossbars, through one `tlul_socket_m1` and a
`tlul_adapter_reg`; `debug_req` to the core; its system bus access (SBA) as the crossbar's
`dbg_host`, which reaches the SRAM and the code RAM. The core's `DmHaltAddr` and `DmExceptionAddr`
are the vendored debug module's (`dm::HaltAddress` = `+0x800`, `dm::ExceptionAddress` = `+0x810`;
they were `+0x800` / `+0x808` before, Sonata's older layout), and `DmBaseAddr` / `DmAddrMask` are
the window. `cheriot_enable_i` follows the core's CHERIoT pin, in `prim_mubi` encoding.

SBA is a crossbar host of its own, as in Sonata and OpenTitan: its writes do not pass the CHERIoT
memory subsystem's tag filter and do not clear tags. OpenTitan states this in
`opentitan-cheriot/hw/ip/cheriot/doc/theory_of_operation.md` ("System Bus Access") and requires
debug accesses in CHERIoT mode to go through Ibex. The CHERIoT ISA (v1.0, 7.7) lets only a CSC of a
tagged capability set a tag, so `bus_master_dbg_host_tag_clear` fails on this design: an SBA write
over a tagged capability leaves a forged capability. Sonata without the memory subsystem does not
have the problem: its SRAM keeps the tag beside the data and the debug host writes it as 0.

**Debug access enable.** OpenTitan gates `rv_dm` with the life-cycle signal `lc_hw_debug_en`:
SBA through a `tlul_lc_gate`, `debug_req`, and instruction fetch from the debug memory; the JTAG
DMI is gated separately by the pinmux strap (`pinmux_hw_debug_en`). Here the SoC input `dbg_en_i`
models `lc_hw_debug_en`, with `lc_tx_t`'s encoding (On = `4'b0101` = `ibex_pkg::IbexMuBiOn`): only a
strict On opens SBA (`rtl/cheriot_rtos_dbg_gate.sv`, the same states as `tlul_lc_gate`: drain,
then answer every request with a TL-UL error, so the debug module reports `sberror` = 2),
`debug_req` and the debug memory's instruction fetch. The DMI itself is not gated: the testbench
is the debug transport, and keeping the DMI open is what lets the test reach the bus-side gate,
the last line of defence. The testbench holds `dbg_en_i` Off except while it serves a request
that needs it.

**Inert by default.** With the DMI idle the debug module stays inactive (`dmactive` = 0), nothing
requests debug, and SBA issues no access. The testbench drives the DMI only when the firmware
asks: `firmware/dbg_host_test` prints `DBGHOST REQ <op> <slot> <value> <flag>` on UART0,
`tb/cheriot_rtos_tb.sv` decodes the line, and `tb/cheriot_rtos_dbg_host.sv` does the SBA write of
`<value>` to `<slot>` (op 1 with debug access enabled, op 2 disabled), reads it back, and writes
`<flag>` over SBA when done. The firmware then reloads `<slot>` with a capability load and prints
`Debug host: PASS|FAIL tag clear|locked: ...`, which `sonata_results.py` maps to
`bus_master_dbg_host_tag_clear` and `bus_master_dbg_host_locked`.
`dbg_access_monitor` in the testbench fails the run on any SBA request that reaches the crossbar
while debug access is disabled.

The SRAM's crossbar socket now has three hosts (core, TBRE, debug host) and the code RAM's two
(core, debug host). The core and the TBRE keep host indices 0 and 1, so with the debug host idle
the arbitration and the timing of every other firmware run are unchanged.

## Coverage

With `-c`, the build instruments `ibex_top` and `cheriot_mem_subsys` and nothing else
(`cheriot_rtos_cover.ccf` with `-covdut cheriot_rtos_soc`). It collects
statement/block/branch/expression/FSM coverage below each, and toggle coverage on their ports.
The pre-verified prims are black-boxed as in `dv/tools/xcelium/cover.ccf`. The core has the same
parameters as the UVM testbench's `opentitan` configuration. The run merges its database into
`xlm_rtos_out/coverage_merged`, which `run_all_tests.sh` adds to the combined merge.

The functional covergroups are bound from outside the RTL (`fcov/cheriot_mem_subsys_fcov_bind.sv`),
and they sample with `+enable_ibex_fcov=1`:
- the memory subsystem: tag filter, RMW filter, TBRE mover, access checks, subsystem top level
- the rev_ctl shim
- the TRVK covergroup on the core's load barrier and on the TBRE's own filter

## Layout

| Path | Contents |
|---|---|
| `rtl/cheriot_rtos_soc.sv` | The SoC |
| `rtl/cheriot_rtos_xbar.sv` | Data and instruction crossbars on Sonata's map |
| `rtl/cheriot_rtos_default_rsp.sv` | Responder for unmapped data addresses |
| `rtl/cheriot_rtos_dbg_gate.sv` | Debug-access gate on the debug module's system bus access (OpenTitan rv_dm's `tlul_lc_gate`) |
| `rtl/cheriot_mem_subsys.sv`, `rtl/cheriot_rev_ctl_tbre.sv` | Sonata's memory-subsystem glue (derived; ported to #31515) |
| `tb/cheriot_rtos_tb.sv` | Clock, reset, uartdpi, memory load, timeout, heartbeat, mutations, TBRE and debug access monitors |
| `tb/cheriot_rtos_dbg_host.sv` | The debug module's DMI host and debug access enable, serving `firmware/dbg_host_test` |
| `fcov/` | Memory-subsystem covergroups and their binds |
| `firmware/` | The revocation, debug host, Juliet CWE and CHERI-C firmware (xmake) and the boot stub |
| `patches/cheriot-rtos/` | Local cheriot-rtos change the root Makefile applies (the test-runner filter) |
| `patches/cheri-c-tests/` | Local cheri-c-tests change the CHERI-C build needs (kept for reference) |
| `patches/archive/` | The retired Sonata filelist of the CHERIoT memory subsystem (`opentitan-cheriot/cheriot_rtl_sonata.f`) |
| `cheriot_rtos_dv.f` | File list, shared by Xcelium and Verilator lint |
| `cheriot_rtos_xlm_{build,run}.sh`, `elf_to_vmem.py` | Build and run scripts |
| `cheriot_rtos_cover.ccf` | Coverage configuration |

## Sources

| What | From |
|---|---|
| The core, every `prim` / `prim_generic` / `dv_utils` file | this ibex repository (`rtl/`, `vendor/lowrisc_ip`): the same copies the UVM testbench builds the core with |
| The RISC-V debug module | `pulp_riscv_dbg`: OpenTitan's, with the CHERIoT changes (Samuel Riedel's branch `rv-dm-cheriot`), as the UVM testbench's `DM=1` build compiles it |
| The CHERIoT memory subsystem | `opentitan-cheriot`: lowRISC/opentitan `hw/ip/cheriot` and its TL-UL |
| TL-UL, `top_pkg`, UART, `rv_timer`, `rv_plic`, `rev_ctl`, the SRAM model, `uartdpi`, the address-map packages | `sonata-system`: lowRISC/sonata-system |

The last three are not committed. Each build fetches them into its output directory
(`xlm_rtos_out/rtl/`; `lint_out/rtl/` for `make lint`) with `ibex/dv/scripts/fetch_rtl.sh`, which
pins their commits and applies the local patches in `ibex/dv/scripts/fetch_rtl/patches/`; a later
build with the same pins reuses the fetch. The first build needs network access to github.com.

One `tlul_pkg` is compiled: Sonata's, which carries the CHERIoT capability bit in `a_user`/`d_user`
and whose host and SRAM adapters have the `wdata_cap`/`rdata_cap` ports the SoC and the SRAM model
connect (OpenTitan's has neither). The Sonata patches, applied in order
(`fetch_rtl/patches/sonata-system/`):

| Patch | Why |
|---|---|
| `0001-tl_main_pkg-cheriot-trbe-host.patch` | The sonata-system checkout's local `TlCheriotTrbe` host (the engine's name before upstream renamed it TBRE). Unused here (only `ADDR_*` constants are); kept so the file is the one the flow was validated with |
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
| `firmware/dbg_host_test/` | `dbg_host_test_fw` |
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
- **Debug module: no JTAG, no non-debug reset, no halt test.** The DMI is a port the testbench
  drives; `ndmreset` is not routed. Halting the core (`debug_req`, the debug ROM) is wired as in
  Sonata but no test here uses it: the UVM testbench's `DM=1` tests (`dm_basic`,
  `dm_basic_cheriot`) cover the core side.
- **Not standalone.** The flow needs the `ibex_cheriot_verification` superproject for
  `opentitan-cheriot/`, and its firmware for the `cheriot-rtos` and `cheri-c-tests` submodules and
  the flake's CHERIoT toolchain. A plain ibex checkout cannot build it.
- **Older Sonata IP on newer prims.** The vendored Sonata TL-UL, UART, PLIC and `rev_ctl` were
  written against the older prim Sonata vendors; here they build against `ibex/vendor/lowrisc_ip`
  (lint-clean; the only port change is `prim_ram_2p`'s `cfg_o`, Sonata patch 0003). The
  register block's `prim_subreg` `reinit_i` connections, which neither prim set has, are dropped by
  the opentitan-cheriot patch 0001.
- **The code RAM is the subsystem's NVM.** The core's tag filter treats the NVM as read-only: a
  capability store (`csc`) to `0x4000_0000` is a read and compare, answered with a bus error unless
  the code RAM already holds the capability's 64 bits, and never writes it.
- **Unmapped accesses complete silently for the firmware.** They are only visible in `run.log`, and
  `run_all_tests.sh` reports how many there were. Use `+default_rsp_error=1` to turn them into
  faults.
- **Coverage merge.** The coverage top is `cheriot_rtos_soc`. The UVM testbench's is `ibex_top`.
  The combined merge unions `ibex_top` across the two hierarchies, as it did for the Sonata flow.
