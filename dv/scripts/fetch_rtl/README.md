# Third-party RTL fetched at build time

Three sources of third-party RTL are not committed. Each build fetches them into its own output
directory with [`../fetch_rtl.sh`](../fetch_rtl.sh) `<source> <dir>`. The script holds the pinned
commits and the paths. It does a sparse git fetch of the pinned commit (only the listed paths,
checked by git against the commit hash) and applies the local patches in `patches/<source>/`. A
stamp in `<dir>` records the source, commit, paths and patches, so a later build with the same
ones reuses the fetch, and any change re-fetches from scratch. The first build of an output
directory needs network access to github.com (anonymous HTTPS, no `gh`).

| Source | Upstream | Used by | Named in the file lists as |
|---|---|---|---|
| `opentitan-cheriot` | lowRISC/opentitan `5df8c6e6` (PR #31515, merged 2026-10-07, stacked on #31470) | `dv/cheriot-mem-ss`, the CHERIoT RTOS test SoC | `${OT_CHERIOT_DIR}` |
| `sonata-system` | lowRISC/sonata-system `cdc024df` | the CHERIoT RTOS test SoC | `${SONATA_DIR}` |
| `pulp_riscv_dbg` | SamuelRiedel/opentitan `ce6c22fb` (branch `rv-dm-cheriot`), `hw/vendor/pulp_riscv_dbg` | the UVM testbench's `DM=1` build, the RTOS test SoC | `${PULP_RISCV_DBG_DIR}` (`<dir>/hw/vendor/pulp_riscv_dbg`) |

Where each build fetches them:

| Build | Directory |
|---|---|
| `dv/cheriot-mem-ss` Xcelium build / mutation build | `xlm_out/rtl/`, `xlm_mutation_out/rtl/` |
| `dv/cheriot-mem-ss` lint, `make filelist` | `lint_out/rtl/` |
| CHERIoT RTOS test SoC build / lint | `xlm_rtos_out/rtl/`, `lint_out/rtl/` |
| UVM testbench, `DM=1` | `out/build/rtl/` (`scripts/compile_tb.py`) |

To move a pin, change `SHA` in `fetch_rtl.sh`; the next build re-fetches. A patch that no longer
applies stops the fetch: rework it against the new upstream rather than drop it.

`cheriot_rtl.f` is the file list of the memory subsystem (`dv/cheriot-mem-ss` builds with it): the
subsystem as `${OT_CHERIOT_DIR}`, built against ibex's own `vendor/lowrisc_ip` prim and
`vendor/pulp_common_cells`.

## opentitan-cheriot

The CHERIoT memory subsystem from OpenTitan (`hw/ip/cheriot`), including the background revocation
engine (TBRE; TRBE in [lowRISC/opentitan#31470](https://github.com/lowRISC/opentitan/pull/31470),
which introduced it) and capability stores to the NVM from
[#31515](https://github.com/lowRISC/opentitan/pull/31515), plus the OpenTitan RTL it needs that
`ibex/vendor` does not provide.

| Patch | Why |
|---|---|
| `0001-build-with-older-prim-and-tlul.patch` | Drops parameter overrides and ports that older `prim` and TL-UL lack: `NeverClears` on `prim_fifo_sync`, `SkewCycles`, `ReturnBlankResp`, and the `reinit_i(1'b0)` connections of the register top's `prim_subreg` (absent from both Sonata's and `ibex/vendor`'s); gives the tag filter a local `get_rsp_intg` for Sonata's `tlul_pkg`. Behaviour is unchanged on both library sets; only the `NeverClears_A` assertion is lost. `NeverClears` on `prim_fifo_sync_cnt` (`cheriot.sv`, `cheriot_tbre_mover.sv`) is kept: both library sets in use (`ibex/vendor/lowrisc_ip` with OpenTitan's or Sonata's TL-UL) have it. |
| `0002-nvmcapstores-parameter.patch` | Makes the tag filter's `NvmCapStores` a parameter of `cheriot` (default `1'b1`, upstream behaviour), so the RTOS test SoC, which maps writable code RAM as the NVM region, can set it to 0. |

| Path | What it is |
|---|---|
| `hw/ip/cheriot/rtl/cheriot.sv` | Subsystem top: tag filter, RMW filter, access checkers, meta SRAM arbiter, TBRE, CSRs, alert |
| `hw/ip/cheriot/rtl/cheriot_tag_filter.sv` | Forks each core data access into data, tag lookup and metadata FIFO; clears tags on non-capability stores |
| `hw/ip/cheriot/rtl/cheriot_wtrc.sv` | On the core's tag filter's host port: a capability store to the NVM becomes a read, compared with the store; the tag is set only if both words match, otherwise d_error |
| `hw/ip/cheriot/rtl/cheriot_rmw_filter.sv` | Read-modify-write of the bit-granular tag words in the meta SRAM |
| `hw/ip/cheriot/rtl/cheriot_tbre.sv` | Revocation engine: `cheriot_tbre_mover` → own TRVK filter → own tag filter (tag-only writes) |
| `hw/ip/cheriot/rtl/cheriot_tbre_mover.sv` | Sweeps `TBRE_NUM_CAPS` capabilities from `TBRE_BASE_ADDR` (main SRAM or NVM), two words each, as capability loads, up to two in flight; does not clear a capability the core writes after its lower word was read (snooped core writes) |
| `hw/ip/cheriot/rtl/cheriot_trvk_core.sv`, `cheriot_trvk_tlul.sv` | TRVK load barrier used by the TBRE: a tagged, non-sealing capability whose base has its revocation bit set loses its tag |
| `hw/ip/cheriot/rtl/cheriot_socket_m1.sv` | TL-UL M:1 socket carrying the tag and bit-select sideband (core and TBRE onto the one RMW filter) |
| `hw/ip/cheriot/rtl/cheriot_access_check.sv` | Per-requester meta SRAM region check; everything is refused unless `cheriot_ena_i` is strictly `MuBi4True` |
| `hw/ip/cheriot/rtl/cheriot_reg_pkg.sv`, `cheriot_regs_reg_top.sv` | Generated CSRs: `INTR_STATE`/`INTR_ENABLE`/`INTR_TEST` (`tbre_done`), `ALERT_TEST`, `TBRE_REGWEN`, `TBRE_BASE_ADDR`, `TBRE_NUM_CAPS`, `TBRE_START`, `TBRE_STATUS`, `TBRE_EPOCH` |
| `hw/ip/cheriot/doc/theory_of_operation.md`, `registers.md`, `programmers_guide.md` | Design description (meta SRAM map, WTRC, snoop window, error-handling table), registers, how software drives the engine |
| `hw/ip/cheriot/dv/` | OpenTitan's block-level DV environment (a CSR-only smoke env at this commit) |
| `hw/ip/tlul/` | TL-UL package, sockets and adapters (all of `rtl/`; the RACL, `lc_gate` and JTAG files are not needed) |
| `hw/top_earlgrey/rtl/top_pkg.sv` | `TL_AW`, `TL_DW` and the other TL-UL widths |
| `hw/vendor/pulp_common_cells/rtl/stream_fork_dynamic.sv` | The only common cell `ibex/vendor/pulp_common_cells` lacks (same upstream revision) |
| `hw/top_earlgrey/ip_autogen/rv_core_ibex/rtl/rv_core_ibex.sv` | **Reference only.** How `ibex_top`'s data port, `data_tag_o/i` and `trvk_revbm_*` port become TL-UL towards the subsystem |
| `hw/ip/rv_core_ibex/rtl/rv_core_ibex_cheriot_switch.sv` | **Reference only.** The write-once CHERIoT mode switch that drives `cheriot_ena` |

Nothing from `prim` is fetched: the subsystem builds against `ibex/vendor/lowrisc_ip`. At the pinned
commit every `prim` it uses is byte-identical to OpenTitan's, except `prim_arbiter_ppc` (`IdxW`
differs only for `N=1`; the sockets use `M=2`) and `prim_ram_1p_scr` (named only in a comment).
A build contains one `tlul_pkg`: in the RTOS test SoC the subsystem uses Sonata's TL-UL (patch 0001
makes that possible); `hw/ip/tlul` here is for standalone builds (`dv/cheriot-mem-ss`). The only
non-style lint warnings are `UNOPTFLAT` combinational-loop notices, which OpenTitan waives in
`hw/ip/cheriot/lint/cheriot.vlt`.

## sonata-system

The Sonata IP the RTOS test SoC builds on: UART, rv_plic, rv_timer, rev_ctl, the SRAM model, the
address-map packages, Sonata's CHERIoT TL-UL and top_pkg, and the uartdpi DPI model. The patches and
why each is needed are in `dv/cheriot-rtos-test-suite/README.md` (Sources).

## pulp_riscv_dbg

The RISC-V debug module: pulp-platform/riscv-dbg `2bc55e1e` with OpenTitan's patches 0001-0004 and
Samuel Riedel's CHERIoT patches 0005-0011 already applied in that tree (copies under
`hw/vendor/patches/pulp_riscv_dbg/`, for reference only: do not apply them again). Fetched:
`src/`, `debug_rom/`, `sva/`, the licences, README, `Bender.yml` and OpenTitan's FuseSoC core
(`hw/vendor/pulp_riscv_dbg.core`). Not fetched: `tb/`, `ci/`, `doc/`.
