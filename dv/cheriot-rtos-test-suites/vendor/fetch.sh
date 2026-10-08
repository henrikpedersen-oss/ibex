#!/usr/bin/env bash
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Fetch the Sonata RTL the CHERIoT RTOS test SoC builds on (UART, rv_plic, rv_timer, rev_ctl, the
# SRAM model, the address-map packages, Sonata's CHERIoT TL-UL and top_pkg, and the uartdpi DPI
# model), pinned to one lowRISC/sonata-system commit, then apply the local patches in patches/.
#
#   ./fetch.sh [<sonata-system-sha>]
#
# Files land under sonata-system/ here with their sonata-system paths. Existing files are
# overwritten; files no longer in FILES below are not deleted (check `git status` after a
# re-fetch). Needs `gh`, or SONATA_SYSTEM_GIT=<a local sonata-system clone> to read the files with
# `git show` instead.
#
# Why Sonata's TL-UL and not opentitan-cheriot/hw/ip/tlul: Sonata's tlul_pkg carries the CHERIoT
# capability bit in a_user/d_user, and its tlul_adapter_host / tlul_adapter_sram have the
# wdata_cap/rdata_cap ports the SoC (cheriot_mem_subsys.sv, cheriot_rev_ctl_trbe.sv) and the SRAM
# model (sram.sv) connect. OpenTitan's has neither. A build has one tlul_pkg, so the OpenTitan
# CHERIoT subsystem builds against this one (opentitan-cheriot/patches/0001).
#
# Not vendored: prim, prim_generic and dv_utils come from this ibex repository's own
# vendor/lowrisc_ip, the same copies the core is built with everywhere else.
set -euo pipefail

SHA="${1:-cdc024df0d244cf22c5f5cfcf5783383dc4e0368}"
REPO="lowRISC/sonata-system"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${HERE}/sonata-system"

FILES=(
  LICENSE
  # Sonata's CHERIoT TL-UL (capability bit in a_user/d_user) and its top_pkg widths
  vendor/lowrisc_ip/ip/top_pkg/rtl/top_pkg.sv
  vendor/lowrisc_ip/ip/tlul/rtl/tlul_pkg.sv
  vendor/lowrisc_ip/ip/tlul/rtl/tlul_data_integ_enc.sv
  vendor/lowrisc_ip/ip/tlul/rtl/tlul_data_integ_dec.sv
  vendor/lowrisc_ip/ip/tlul/rtl/tlul_cmd_intg_gen.sv
  vendor/lowrisc_ip/ip/tlul/rtl/tlul_cmd_intg_chk.sv
  vendor/lowrisc_ip/ip/tlul/rtl/tlul_rsp_intg_gen.sv
  vendor/lowrisc_ip/ip/tlul/rtl/tlul_rsp_intg_chk.sv
  vendor/lowrisc_ip/ip/tlul/rtl/tlul_fifo_sync.sv
  vendor/lowrisc_ip/ip/tlul/rtl/tlul_err.sv
  vendor/lowrisc_ip/ip/tlul/rtl/tlul_err_resp.sv
  vendor/lowrisc_ip/ip/tlul/rtl/tlul_socket_1n.sv
  vendor/lowrisc_ip/ip/tlul/rtl/tlul_socket_m1.sv
  vendor/lowrisc_ip/ip/tlul/rtl/tlul_adapter_reg.sv
  vendor/lowrisc_ip/ip/tlul/rtl/tlul_adapter_host.sv
  vendor/lowrisc_ip/ip/tlul/rtl/tlul_adapter_sram.sv
  vendor/lowrisc_ip/ip/tlul/rtl/tlul_sram_byte.sv
  # UART0
  vendor/lowrisc_ip/ip/uart/rtl/uart_reg_pkg.sv
  vendor/lowrisc_ip/ip/uart/rtl/uart_reg_top.sv
  vendor/lowrisc_ip/ip/uart/rtl/uart_rx.sv
  vendor/lowrisc_ip/ip/uart/rtl/uart_tx.sv
  vendor/lowrisc_ip/ip/uart/rtl/uart_core.sv
  vendor/lowrisc_ip/ip/uart/rtl/uart.sv
  # The testbench's UART0 sink (DPI)
  vendor/lowrisc_ip/dv/dpi/uartdpi/uartdpi.sv
  vendor/lowrisc_ip/dv/dpi/uartdpi/uartdpi.c
  vendor/lowrisc_ip/dv/dpi/uartdpi/uartdpi.h
  # Hardware revoker interface the RTOS drives (cheriot_rev_ctl_trbe.sv sits behind it)
  rtl/ip/rev_ctl/rtl/rev_ctl_reg_pkg.sv
  rtl/ip/rev_ctl/rtl/rev_ctl_reg_top.sv
  rtl/ip/rev_ctl/rtl/rev_ctl.sv
  # PLIC
  rtl/system/autogen/rv_plic/rtl/rv_plic_gateway.sv
  rtl/system/autogen/rv_plic/rtl/rv_plic_target.sv
  rtl/system/autogen/rv_plic/rtl/rv_plic_reg_pkg.sv
  rtl/system/autogen/rv_plic/rtl/rv_plic_reg_top.sv
  rtl/system/autogen/rv_plic/rtl/rv_plic.sv
  # SRAM model (data + tag RAM) and timer
  rtl/system/sram.sv
  rtl/system/rv_timer.sv
  # Address map: ADDR_SPACE_* / ADDR_MASK_* only (the crossbar is cheriot_rtos_xbar.sv)
  rtl/bus/tl_main_pkg.sv
  rtl/bus/tl_ifetch_pkg.sv
)

fetch_one() {
  local f="$1"
  if [[ -n "${SONATA_SYSTEM_GIT:-}" ]]; then
    git -C "${SONATA_SYSTEM_GIT}" show "${SHA}:${f}"
  else
    gh api "repos/${REPO}/contents/${f}?ref=${SHA}" -H "Accept: application/vnd.github.raw"
  fi
}

for f in "${FILES[@]}"; do
  mkdir -p "${DEST}/$(dirname "${f}")"
  fetch_one "${f}" > "${DEST}/${f}"
done

{
  echo "${REPO} ${SHA} (fetched $(date -u +%Y-%m-%d) by fetch.sh; ${#FILES[@]} files under sonata-system/)"
  echo "Files:"
  printf '  %s\n' "${FILES[@]}"
} > "${HERE}/VENDORED_FROM"
echo "Fetched ${#FILES[@]} files from ${REPO}@${SHA}"

# Local patches, in order (as OpenTitan's util/vendor.py does). A patch that no longer applies after
# a re-fetch stops the script: rework it against the new upstream rather than dropping it.
for p in "${HERE}"/patches/*.patch; do
  [[ -e "${p}" ]] || continue
  patch -p1 -d "${DEST}" --no-backup-if-mismatch < "${p}"
  echo "Applied patches/$(basename "${p}")" | tee -a "${HERE}/VENDORED_FROM"
done
