#!/usr/bin/env bash

# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

if [ $# -eq 1 ]; then
  export LR_SYNTH_OUT_DIR=$1
elif [ -n "${LR_SYNTH_OUT_DIR:-}" ]; then
  export LR_SYNTH_OUT_DIR
elif [ $# -eq 0 ]; then
  # The library is in the name unless it is NanGate45 (the names of the runs before the choice).
  lib_suffix=
  [ "${LR_SYNTH_LIB:-nangate45}" = nangate45 ] || lib_suffix=_$LR_SYNTH_LIB
  export LR_SYNTH_OUT_DIR_PREFIX="syn_out/ibex${LR_SYNTH_IBEX_CONFIG:+_$LR_SYNTH_IBEX_CONFIG}${lib_suffix}"
  LR_SYNTH_OUT_DIR=$(date +"${LR_SYNTH_OUT_DIR_PREFIX}_%d_%m_%Y_%H_%M_%S")
  export LR_SYNTH_OUT_DIR
else
  echo "Usage $0 [synth_out_dir]"
  exit 1
fi

export LR_SYNTH_TIMING_RUN=1
export LR_SYNTH_FLATTEN=${LR_SYNTH_FLATTEN:-1}

# Cell library: LR_SYNTH_LIB (default nangate45; lib/<name>.cfg, lib/README.md) at LR_SYNTH_CORNER
# (typical, the default, slow or fast, as the library has them). With neither set, an
# LR_SYNTH_CELL_LIBRARY_PATH from the environment still wins (upstream behaviour).
source lib/syn_lib.sh
syn_lib_setup_yosys || exit 1

# When using `nix develop .#syn_shell`, the following are set automatically by
# the shell hook (via nix/syn.nix):
#   LR_SYNTH_CELL_LIBRARY_PATH  (path to NangateOpenCellLibrary_typical.lib)
#   LR_SYNTH_CELL_LIBRARY_NAME  (nangate)
# For non-Nix environments, uncomment and set these manually:
# export LR_SYNTH_CELL_LIBRARY_PATH=/path/to/NangateOpenCellLibrary_typical.lib
# export LR_SYNTH_CELL_LIBRARY_NAME=nangate
