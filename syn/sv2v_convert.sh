#!/usr/bin/env bash

# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# sv2v conversion of the Ibex RTL and the primitives it uses, one .v per module, shared by
# syn_yosys.sh and eqy/run_eqy.sh so both see the same Verilog.
#
#   ./sv2v_convert.sh <out_dir>     convert (run from ibex/syn)
#   source ./sv2v_convert.sh        only define the source lists below

LR_DEP_PKGS=(
    "../vendor/lowrisc_ip/ip/prim/rtl/prim_count_pkg.sv"
    "../vendor/lowrisc_ip/ip/prim/rtl/prim_cipher_pkg.sv"
    "../vendor/lowrisc_ip/ip/prim/rtl/prim_util_pkg.sv"
)

LR_DEP_SOURCES=(
    "../vendor/lowrisc_ip/ip/prim/rtl/prim_count.sv"
    "../vendor/lowrisc_ip/ip/prim/rtl/prim_fifo_sync.sv"
    "../vendor/lowrisc_ip/ip/prim/rtl/prim_fifo_sync_cnt.sv"
    "../vendor/lowrisc_ip/ip/prim/rtl/prim_secded_inv_39_32_dec.sv"
    "../vendor/lowrisc_ip/ip/prim/rtl/prim_secded_inv_39_32_enc.sv"
    "../vendor/lowrisc_ip/ip/prim/rtl/prim_secded_inv_64_57_dec.sv"
    "../vendor/lowrisc_ip/ip/prim/rtl/prim_secded_inv_64_57_enc.sv"
    "../vendor/pulp_common_cells/rtl/stream_fork.sv"
    "../vendor/pulp_common_cells/rtl/stream_join_dynamic.sv"
    "../vendor/lowrisc_ip/ip/prim/rtl/prim_lfsr.sv"
    "../vendor/lowrisc_ip/ip/prim_generic/rtl/prim_and2.sv"
    "../vendor/lowrisc_ip/ip/prim_generic/rtl/prim_buf.sv"
    "../vendor/lowrisc_ip/ip/prim_generic/rtl/prim_clock_mux2.sv"
    "../vendor/lowrisc_ip/ip/prim_generic/rtl/prim_flop.sv"
)

LR_CORE_PKGS=(
    ../rtl/*_pkg.sv
    "../vendor/lowrisc_ip/ip/prim_generic/rtl/prim_ram_1p_pkg.sv"
    "../vendor/lowrisc_ip/ip/prim/rtl/prim_secded_pkg.sv"
    "../vendor/lowrisc_ip/ip/prim/rtl/prim_util_pkg.sv"
)

LR_CORE_SOURCES=()
for _f in ../rtl/*.sv; do
    case "$_f" in *_pkg.sv) ;; *) LR_CORE_SOURCES+=("$_f") ;; esac
done

LR_INCDIRS=(
    "../vendor/lowrisc_ip/ip/prim/rtl"
    "../vendor/lowrisc_ip/dv/sv/dv_utils"
)

[[ "${BASH_SOURCE[0]}" != "$0" ]] && return 0

set -e
set -o pipefail

out=${1:?usage: $0 <out_dir>}
mkdir -p "$out"

# Make sure auto-generated primitives are resolved to generic primitives where available.
generic_prims () {
    sed -i -e 's/prim_and2/prim_generic_and2/g' -e 's/prim_buf/prim_generic_buf/g' \
        -e 's/prim_clock_mux2/prim_generic_clock_mux2/g' -e 's/prim_flop/prim_generic_flop/g' "$1"
}

for file in "${LR_DEP_SOURCES[@]}"; do
    module=$(basename -s .sv "$file")
    sv2v --define=SYNTHESIS --define=YOSYS "${LR_DEP_PKGS[@]}" -I"${LR_INCDIRS[0]}" \
        "$file" > "$out/$module.v"
    generic_prims "$out/$module.v"
done

for file in "${LR_CORE_SOURCES[@]}"; do
    module=$(basename -s .sv "$file")
    sv2v --define=SYNTHESIS --define=YOSYS "${LR_CORE_PKGS[@]}" "${LR_INCDIRS[@]/#/-I}" \
        "$file" > "$out/$module.v"
    generic_prims "$out/$module.v"
done
