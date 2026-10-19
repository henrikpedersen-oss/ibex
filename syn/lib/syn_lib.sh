#!/usr/bin/env bash

# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# The cell library of both synthesis flows, from lib/<name>.cfg (the format is in lib/nangate45.cfg).
#
#   source lib/syn_lib.sh
#   syn_lib_select <name> <corner>      SYN_LIB_* below; fails, with a message, on a missing corner
#   syn_lib_prepare_liberty             writes SYN_LIB_LIBERTY if it is a prepared one (see below)
#   syn_lib_setup_yosys                 syn_setup*.sh: the LR_SYNTH_* variables of the Yosys flow
#   syn_lib_genus_clock_gating <file>   Genus's prim_clock_gating for the library's clock gate
#   syn_lib_run_info                    the library lines of a run's run_info.txt
#
#   lib/syn_lib.sh check <name> <corner>   exit status only (make checks SYN_LIB/SYN_CORNER with it)
#   lib/syn_lib.sh list                    the libraries and their corners
#
# SYN_LIB_LIBERTY is the one liberty file both flows read: the corner's file itself, or, for a
# library with several files per corner (ASAP7) or a dont_use list, lib/generated/<name>_<corner>.lib
# (scripts/prepare_liberty.py; regenerated when older than its inputs, never committed).

SYN_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SYN_LIB_CORNERS="typical slow fast"

# <name> <key>: the value, empty if the key is absent.
syn_lib_cfg () {
    sed -n -E "s/^$2=(.*)$/\1/p" "$SYN_LIB_DIR/$1.cfg" | sed -E 's/[[:space:]]+#.*$//; s/[[:space:]]+$//' | tail -1
}

syn_lib_names () {
    local f n=()
    for f in "$SYN_LIB_DIR"/*.cfg; do n+=("$(basename "$f" .cfg)"); done
    echo "${n[*]}"
}

syn_lib_corners () {
    local c out=()
    for c in $SYN_LIB_CORNERS; do [ -n "$(syn_lib_cfg "$1" "$c")" ] && out+=("$c"); done
    echo "${out[*]}"
}

syn_lib_select () {
    local name=$1 corner=$2 rel f files=()
    if [ -z "$name" ] || [ ! -f "$SYN_LIB_DIR/$name.cfg" ]; then
        echo "No cell library '$name': the libraries are $(syn_lib_names) (ibex/syn/lib/*.cfg)" >&2
        return 1
    fi
    rel=
    [[ " $SYN_LIB_CORNERS " == *" $corner "* ]] && rel=$(syn_lib_cfg "$name" "$corner")
    if [ -z "$rel" ]; then
        echo "Cell library $name has no '$corner' corner: it has $(syn_lib_corners "$name")" >&2
        return 1
    fi
    for f in $rel; do
        if [ ! -f "$SYN_LIB_DIR/$f" ]; then
            echo "Cell library $name, $corner corner: no such file ibex/syn/lib/$f" >&2
            return 1
        fi
        files+=("$SYN_LIB_DIR/$f")
    done

    export SYN_LIB_NAME=$name SYN_LIB_CORNER=$corner SYN_LIB_FILES="${files[*]}"
    SYN_LIB_TITLE=$(syn_lib_cfg "$name" title)
    SYN_LIB_TIME_UNIT_PS=$(syn_lib_cfg "$name" time_unit_ps)
    SYN_LIB_DRIVING_CELL=$(syn_lib_cfg "$name" driving_cell)
    SYN_LIB_OUTPUT_LOAD=$(syn_lib_cfg "$name" output_load)
    SYN_LIB_ABC_OUTPUT_LOAD=$(syn_lib_cfg "$name" abc_output_load)
    SYN_LIB_GE_CELL=$(syn_lib_cfg "$name" ge_cell)
    SYN_LIB_GE_AREA=$(syn_lib_cfg "$name" ge_area)
    SYN_LIB_ICG=$(syn_lib_cfg "$name" icg)
    SYN_LIB_LATCH_P=$(syn_lib_cfg "$name" latch_p)
    SYN_LIB_LATCH_N=$(syn_lib_cfg "$name" latch_n)
    SYN_LIB_DONT_USE=$(syn_lib_cfg "$name" dont_use)
    export SYN_LIB_TITLE SYN_LIB_TIME_UNIT_PS SYN_LIB_DRIVING_CELL SYN_LIB_OUTPUT_LOAD \
           SYN_LIB_ABC_OUTPUT_LOAD SYN_LIB_GE_CELL SYN_LIB_GE_AREA SYN_LIB_ICG SYN_LIB_LATCH_P \
           SYN_LIB_LATCH_N SYN_LIB_DONT_USE

    if [ ${#files[@]} -eq 1 ] && [ -z "$SYN_LIB_DONT_USE" ]; then
        SYN_LIB_LIBERTY=${files[0]}
    else
        SYN_LIB_LIBERTY=$SYN_LIB_DIR/generated/${name}_${corner}.lib
    fi
    # Output directory names carry the library, except NanGate45's (those of the runs before).
    SYN_LIB_SUFFIX=
    [ "$name" = nangate45 ] || SYN_LIB_SUFFIX=_$name
    export SYN_LIB_LIBERTY SYN_LIB_SUFFIX
}

syn_lib_prepare_liberty () {
    local out=$SYN_LIB_LIBERTY py=$SYN_LIB_DIR/../scripts/prepare_liberty.py f stale=0 merge=()
    [ "$out" = "$SYN_LIB_FILES" ] && return 0
    if [ -f "$out" ]; then
        for f in $SYN_LIB_FILES "$SYN_LIB_DIR/$SYN_LIB_NAME.cfg" "$py"; do
            [ "$f" -nt "$out" ] && stale=1
        done
    else
        stale=1
    fi
    [ $stale -eq 0 ] && return 0
    mkdir -p "$SYN_LIB_DIR/generated"
    [ -f "$SYN_LIB_DIR/generated/.gitignore" ] || echo '*' > "$SYN_LIB_DIR/generated/.gitignore"
    set -- $SYN_LIB_FILES
    [ $# -gt 1 ] && merge=(--name "${SYN_LIB_NAME//-/_}_${SYN_LIB_CORNER}")
    python3 "$py" -o "$out" "${merge[@]}" --dont-use "$SYN_LIB_DONT_USE" "$@"
}

# <E polarity P|N> <cell enable data output [PIN=value ...]>
syn_lib_latch_module () {
    local pol=$1 ties="" t
    set -- $2
    [ $# -ge 4 ] || return 0
    local cell=$1 en=$2 d=$3 q=$4
    shift 4
    for t in "$@"; do ties+=", .${t%%=*}(${t#*=})"; done
    printf 'module $_DLATCH_%s_ (input E, input D, output Q);\n%s _TECHMAP_REPLACE_ (.%s(E), .%s(D), .%s(Q)%s);\nendmodule\n\n' \
        "$pol" "$cell" "$en" "$d" "$q" "$ties"
}

# The Yosys flow's library files: NanGate45's own (lib/nangate45.cfg's yosys_*), else written into
# $LR_SYNTH_OUT_DIR/lib/ (not generated/, whose *.v the flow reads as the design). A variable already
# in the environment is kept.
syn_lib_yosys_files () {
    local d=$LR_SYNTH_OUT_DIR/lib top=${LR_SYNTH_TOP_MODULE:-ibex_top} f
    f=$(syn_lib_cfg "$SYN_LIB_NAME" yosys_latch_map)
    if [ -z "$f" ]; then
        mkdir -p "$d"
        f=$d/latch_map.v
        {
            echo "// Generated by lib/syn_lib.sh from lib/$SYN_LIB_NAME.cfg: latch primitives to $SYN_LIB_TITLE cells."
            echo
            syn_lib_latch_module P "$SYN_LIB_LATCH_P"
            syn_lib_latch_module N "$SYN_LIB_LATCH_N"
        } > "$f"
    fi
    export LR_SYNTH_LATCH_MAP=${LR_SYNTH_LATCH_MAP:-$f}

    f=$(syn_lib_cfg "$SYN_LIB_NAME" yosys_sdc)
    if [ -z "$f" ]; then
        mkdir -p "$d"
        f=$d/$top.$SYN_LIB_NAME.sdc
        printf '# Generated by lib/syn_lib.sh from lib/%s.cfg.\n\nset_driving_cell [all_inputs] -lib_cell %s\nset_load %s [all_outputs]\n' \
            "$SYN_LIB_NAME" "$SYN_LIB_DRIVING_CELL" "$SYN_LIB_OUTPUT_LOAD" > "$f"
        export LR_SYNTH_SDC_FILE_OUT=${LR_SYNTH_SDC_FILE_OUT:-$LR_SYNTH_OUT_DIR/generated/$top.$SYN_LIB_NAME.out.sdc}
    fi
    export LR_SYNTH_SDC_FILE_IN=${LR_SYNTH_SDC_FILE_IN:-$f}

    f=$(syn_lib_cfg "$SYN_LIB_NAME" yosys_abc_sdc)
    if [ -z "$f" ]; then
        mkdir -p "$d"
        f=$d/${top}_abc.$SYN_LIB_NAME.sdc
        printf '# Generated by lib/syn_lib.sh from lib/%s.cfg (ABC: the load in fF).\n\nset_driving_cell %s\nset_load %s [all_outputs]\n' \
            "$SYN_LIB_NAME" "$SYN_LIB_DRIVING_CELL" "$SYN_LIB_ABC_OUTPUT_LOAD" > "$f"
    fi
    export LR_SYNTH_ABC_SDC_FILE_IN=${LR_SYNTH_ABC_SDC_FILE_IN:-$f}
}

# Library and corner for the Yosys flow: LR_SYNTH_LIB (default nangate45) at LR_SYNTH_CORNER (default
# typical). With neither set, an LR_SYNTH_CELL_LIBRARY_PATH from the environment (the nix syn_shell's
# NanGate45 typical) is kept, as upstream. Needs LR_SYNTH_OUT_DIR.
syn_lib_setup_yosys () {
    local keep=0
    [ -z "${LR_SYNTH_LIB:-}" ] && [ -z "${LR_SYNTH_CORNER:-}" ] && [ -n "${LR_SYNTH_CELL_LIBRARY_PATH:-}" ] && keep=1
    export LR_SYNTH_LIB=${LR_SYNTH_LIB:-nangate45}
    syn_lib_select "$LR_SYNTH_LIB" "${LR_SYNTH_CORNER:-typical}" || return 1
    if [ $keep -eq 0 ]; then
        export LR_SYNTH_CORNER=${LR_SYNTH_CORNER:-typical}
        syn_lib_prepare_liberty || return 1
        export LR_SYNTH_CELL_LIBRARY_PATH=$SYN_LIB_LIBERTY
    fi
    export LR_SYNTH_CELL_LIBRARY_NAME=${LR_SYNTH_CELL_LIBRARY_NAME:-nangate}
    [ "$LR_SYNTH_LIB" = nangate45 ] || LR_SYNTH_CELL_LIBRARY_NAME=$LR_SYNTH_LIB
    export LR_SYNTH_TIME_UNIT_PS=$SYN_LIB_TIME_UNIT_PS
    syn_lib_yosys_files
    echo "Cell library $LR_SYNTH_LIB (${LR_SYNTH_CORNER:-} corner): $LR_SYNTH_CELL_LIBRARY_PATH"
}

syn_lib_genus_clock_gating () {
    set -- $SYN_LIB_ICG "$1"
    [ $# -eq 6 ] || { echo "lib/$SYN_LIB_NAME.cfg: icg needs a cell and four pins" >&2; return 1; }
    cat > "$6" <<EOF
// Generated by lib/syn_lib.sh from lib/$SYN_LIB_NAME.cfg: $SYN_LIB_TITLE's integrated clock gate,
// as genus/prim_clock_gating.v is NanGate45's.

module prim_clock_gating (
  input  clk_i,
  input  en_i,
  input  test_en_i,
  output clk_o
);

  $1 u_icg (
    .$2(clk_i),
    .$3(en_i),
    .$4(test_en_i),
    .$5(clk_o)
  );

endmodule
EOF
}

syn_lib_run_info () {
    echo "lib=$SYN_LIB_NAME"
    echo "ge_cell=$SYN_LIB_GE_CELL"
    echo "ge_area=$SYN_LIB_GE_AREA"
    echo "time_unit_ps=$SYN_LIB_TIME_UNIT_PS"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    case "${1:-}" in
        check)
            syn_lib_select "${2:-}" "${3:-}" ;;
        list)
            for n in $(syn_lib_names); do
                printf '%-12s %-28s %s\n' "$n" "$(syn_lib_cfg "$n" title)" "$(syn_lib_corners "$n")"
            done ;;
        *)
            echo "usage: $0 check <library> <corner> | list" >&2
            exit 2 ;;
    esac
fi
