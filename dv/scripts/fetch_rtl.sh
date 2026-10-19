#!/usr/bin/env bash
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Fetch third-party RTL that is not committed here into a build's output directory, pinned to one
# upstream commit, and apply the local patches in fetch_rtl/patches/<source>/.
#
#   fetch_rtl.sh <source> <dir>
#
# Sources:
#   opentitan-cheriot  lowRISC/opentitan: the CHERIoT memory subsystem (hw/ip/cheriot_mem_sys: tag filter, RMW
#                      filter, TRVK filter, revocation engine TBRE) and the TL-UL RTL, top_pkg and
#                      pulp cell it needs. Used by ibex/dv/cheriot-mem-ss and the CHERIoT RTOS test
#                      SoC, through fetch_rtl/cheriot_rtl.f ($OT_CHERIOT_DIR = <dir>).
#   sonata-system      lowRISC/sonata-system: the Sonata IP of the CHERIoT RTOS test SoC (UART,
#                      rv_plic, rv_timer, rev_ctl, the SRAM model, the address-map packages, Sonata's
#                      CHERIoT TL-UL and top_pkg, uartdpi). $SONATA_DIR = <dir>.
#   pulp_riscv_dbg     The RISC-V debug module with the CHERIoT changes (Samuel Riedel's OpenTitan
#                      branch rv-dm-cheriot: pulp-platform/riscv-dbg 2bc55e1e with OpenTitan's patches
#                      0001-0004 and the CHERIoT patches 0005-0011 already applied). Used by the UVM
#                      DM build (DM=1) and the RTOS test SoC. $PULP_RISCV_DBG_DIR =
#                      <dir>/hw/vendor/pulp_riscv_dbg.
#
# <dir> is a sparse git checkout of the pinned commit, holding only the listed paths, with the
# local patches applied; files keep their upstream paths. A stamp file records the source, commit
# and patches: a later call with the same ones returns at once, any change re-fetches from scratch.
# Needs git and network access to github.com (anonymous HTTPS); git checks the content against
# the pinned commit. To move a pin, change SHA below and re-run a build; a patch that no longer
# applies stops the fetch, so rework it against the new upstream rather than drop it.
set -euo pipefail

usage() { sed -n '/^#   fetch_rtl.sh/,/^# Needs git/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2; }
[[ $# -eq 2 ]] || usage
SOURCE=$1
DEST=$2
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PATHS=()
case "${SOURCE}" in
  opentitan-cheriot)
    # lowRISC/opentitan b578b9d8 "[cheriot,rtl] Pipeline TBRE read responses", 2026-10-17: the
    # newest commit on the subsystem. Since the previous pin (5df8c6e6, PR #31515, 2026-10-07)
    # upstream renamed hw/ip/cheriot to hw/ip/cheriot_mem_sys (1ed24ec6, 2026-10-08: module
    # cheriot_mem_sys, package cheriot_mem_sys_reg_pkg); b578b9d8 is the one RTL change besides.
    URL=https://github.com/lowRISC/opentitan.git
    SHA=b578b9d81991abd27e9586d54805811cd1691d39
    PATHS=(
      /hw/ip/cheriot_mem_sys/ '!/hw/ip/cheriot_mem_sys/**/*.svg'
      /hw/ip/tlul/rtl/ '/hw/ip/tlul/*.core'
      /hw/top_earlgrey/rtl/top_pkg.sv
      # The one pulp common cell ibex/vendor lacks (stream_fork and stream_join_dynamic are the
      # same upstream revision in both).
      /hw/vendor/pulp_common_cells/rtl/stream_fork_dynamic.sv /hw/vendor/pulp_common_cells/LICENSE
      # Reference only, not compiled: how ibex_top's data, tag and TRVK bitmap ports reach the
      # subsystem over TL-UL, and OpenTitan's CHERIoT mode switch.
      /hw/top_earlgrey/ip_autogen/rv_core_ibex/rtl/rv_core_ibex.sv
      /hw/ip/rv_core_ibex/rtl/rv_core_ibex_cheriot_switch.sv
      /LICENSE
    )
    ;;
  sonata-system)
    URL=https://github.com/lowRISC/sonata-system.git
    SHA=cdc024df0d244cf22c5f5cfcf5783383dc4e0368
    # Sonata's TL-UL rather than OpenTitan's: its tlul_pkg carries the CHERIoT capability bit in
    # a_user/d_user, and tlul_adapter_host / tlul_adapter_sram have the wdata_cap/rdata_cap ports the
    # SoC (cheriot_mem_subsys.sv, cheriot_rev_ctl_tbre.sv) and the SRAM model connect. A build has one
    # tlul_pkg, so opentitan-cheriot is patched to build against this one (its patch 0001). prim,
    # prim_generic and dv_utils come from ibex's own vendor/lowrisc_ip.
    PATHS=(
      /LICENSE
      /vendor/lowrisc_ip/ip/top_pkg/rtl/top_pkg.sv
      /vendor/lowrisc_ip/ip/tlul/rtl/tlul_pkg.sv
      /vendor/lowrisc_ip/ip/tlul/rtl/tlul_data_integ_enc.sv
      /vendor/lowrisc_ip/ip/tlul/rtl/tlul_data_integ_dec.sv
      /vendor/lowrisc_ip/ip/tlul/rtl/tlul_cmd_intg_gen.sv
      /vendor/lowrisc_ip/ip/tlul/rtl/tlul_cmd_intg_chk.sv
      /vendor/lowrisc_ip/ip/tlul/rtl/tlul_rsp_intg_gen.sv
      /vendor/lowrisc_ip/ip/tlul/rtl/tlul_rsp_intg_chk.sv
      /vendor/lowrisc_ip/ip/tlul/rtl/tlul_fifo_sync.sv
      /vendor/lowrisc_ip/ip/tlul/rtl/tlul_err.sv
      /vendor/lowrisc_ip/ip/tlul/rtl/tlul_err_resp.sv
      /vendor/lowrisc_ip/ip/tlul/rtl/tlul_socket_1n.sv
      /vendor/lowrisc_ip/ip/tlul/rtl/tlul_socket_m1.sv
      /vendor/lowrisc_ip/ip/tlul/rtl/tlul_adapter_reg.sv
      /vendor/lowrisc_ip/ip/tlul/rtl/tlul_adapter_host.sv
      /vendor/lowrisc_ip/ip/tlul/rtl/tlul_adapter_sram.sv
      /vendor/lowrisc_ip/ip/tlul/rtl/tlul_sram_byte.sv
      # UART0, and the testbench's UART0 sink (DPI)
      /vendor/lowrisc_ip/ip/uart/rtl/uart_reg_pkg.sv
      /vendor/lowrisc_ip/ip/uart/rtl/uart_reg_top.sv
      /vendor/lowrisc_ip/ip/uart/rtl/uart_rx.sv
      /vendor/lowrisc_ip/ip/uart/rtl/uart_tx.sv
      /vendor/lowrisc_ip/ip/uart/rtl/uart_core.sv
      /vendor/lowrisc_ip/ip/uart/rtl/uart.sv
      /vendor/lowrisc_ip/dv/dpi/uartdpi/uartdpi.sv
      /vendor/lowrisc_ip/dv/dpi/uartdpi/uartdpi.c
      /vendor/lowrisc_ip/dv/dpi/uartdpi/uartdpi.h
      # Hardware revoker interface the RTOS drives (cheriot_rev_ctl_tbre.sv sits behind it)
      /rtl/ip/rev_ctl/rtl/rev_ctl_reg_pkg.sv
      /rtl/ip/rev_ctl/rtl/rev_ctl_reg_top.sv
      /rtl/ip/rev_ctl/rtl/rev_ctl.sv
      # PLIC
      /rtl/system/autogen/rv_plic/rtl/rv_plic_gateway.sv
      /rtl/system/autogen/rv_plic/rtl/rv_plic_target.sv
      /rtl/system/autogen/rv_plic/rtl/rv_plic_reg_pkg.sv
      /rtl/system/autogen/rv_plic/rtl/rv_plic_reg_top.sv
      /rtl/system/autogen/rv_plic/rtl/rv_plic.sv
      # SRAM model (data + tag RAM) and timer
      /rtl/system/sram.sv
      /rtl/system/rv_timer.sv
      # Address map: ADDR_SPACE_* / ADDR_MASK_* only (the crossbar is cheriot_rtos_xbar.sv)
      /rtl/bus/tl_main_pkg.sv
      /rtl/bus/tl_ifetch_pkg.sv
    )
    ;;
  pulp_riscv_dbg)
    URL=https://github.com/SamuelRiedel/opentitan.git
    SHA=ce6c22fbfe06846d2625c30713d435cccc6109c2
    # Not taken: tb/, ci/, doc/. hw/vendor/patches/pulp_riscv_dbg/: the patches already applied in
    # that tree, for reference only (do not apply them again).
    PATHS=(
      /hw/vendor/pulp_riscv_dbg/src/ /hw/vendor/pulp_riscv_dbg/debug_rom/ /hw/vendor/pulp_riscv_dbg/sva/
      /hw/vendor/patches/pulp_riscv_dbg/ /hw/vendor/pulp_riscv_dbg/LICENSE
      /hw/vendor/pulp_riscv_dbg/LICENSE.SiFive /hw/vendor/pulp_riscv_dbg/README.md
      /hw/vendor/pulp_riscv_dbg/Bender.yml /hw/vendor/pulp_riscv_dbg.core
    )
    ;;
  *)
    echo "fetch_rtl.sh: unknown source '${SOURCE}' (opentitan-cheriot, sonata-system, pulp_riscv_dbg)" >&2
    exit 2 ;;
esac

PATCH_DIR="${HERE}/fetch_rtl/patches/${SOURCE}"
PATCHES=()
for p in "${PATCH_DIR}"/*.patch; do [[ -e "${p}" ]] && PATCHES+=("${p}"); done

# What this fetch is: the source, commit, paths, and the content of every patch.
STAMP_WANT="$(
  printf 'source=%s\nurl=%s\nsha=%s\n' "${SOURCE}" "${URL}" "${SHA}"
  printf 'path=%s\n' "${PATHS[@]}"
  for p in "${PATCHES[@]+"${PATCHES[@]}"}"; do
    printf 'patch=%s %s\n' "$(basename "${p}")" "$(sha256sum < "${p}" | cut -d' ' -f1)"
  done
)"
STAMP="${DEST}/.fetch_rtl"
if [[ -f "${STAMP}" && "$(cat "${STAMP}")" == "${STAMP_WANT}" ]]; then
  exit 0
fi

echo "[fetch_rtl] ${SOURCE}: ${URL} ${SHA:0:12} -> ${DEST}"
rm -rf "${DEST}"
mkdir -p "${DEST}"
git -C "${DEST}" init -q
git -C "${DEST}" remote add origin "${URL}"
git -C "${DEST}" sparse-checkout set --no-cone "${PATHS[@]}"
# Only the pinned commit, and only the blobs the sparse paths need.
if ! git -C "${DEST}" fetch -q --depth 1 --filter=blob:none origin "${SHA}"; then
  echo "[fetch_rtl] ERROR: cannot fetch ${SHA} from ${URL} (network, or the commit is gone)" >&2
  rm -rf "${DEST}"
  exit 1
fi
git -C "${DEST}" -c advice.detachedHead=false checkout -q FETCH_HEAD
for p in "${PATCHES[@]+"${PATCHES[@]}"}"; do
  if ! git -C "${DEST}" apply --whitespace=nowarn "${p}"; then
    echo "[fetch_rtl] ERROR: ${p} does not apply to ${SOURCE} ${SHA}" >&2
    rm -rf "${DEST}"
    exit 1
  fi
done
printf '%s\n' "${STAMP_WANT}" > "${STAMP}"
echo "[fetch_rtl] ${SOURCE}: $(find "${DEST}" -type f -not -path "*/.git/*" -not -name .fetch_rtl | wc -l) files," \
     "${#PATCHES[@]} local patch(es) applied"
