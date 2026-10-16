#!/usr/bin/env bash

# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Synthesis setup for ibex_top with BaseIsa=BaseIsaRV32IorCHERIoT.
# Source this instead of syn_setup.sh when running syn_yosys.sh for a CHERIoT build.
# Usage: ln -s syn_setup_cheriot.sh syn_setup.sh  (or copy and adjust as needed)

if [ $# -eq 1 ]; then
  export LR_SYNTH_OUT_DIR=$1
elif [ $# -eq 0 ]; then
  export LR_SYNTH_OUT_DIR_PREFIX="syn_out/ibex_cheriot"
  LR_SYNTH_OUT_DIR=$(date +"${LR_SYNTH_OUT_DIR_PREFIX}_%d_%m_%Y_%H_%M_%S")
  export LR_SYNTH_OUT_DIR
else
  echo "Usage $0 [synth_out_dir]"
  exit 1
fi

export LR_SYNTH_TIMING_RUN=1
export LR_SYNTH_FLATTEN=1

# Select the CHERIoT base ISA and matching IO-constraint config file.
export LR_SYNTH_IBEX_BASE_ISA=1
export LR_SYNTH_CONFIG_FILE=ibex_top_cheriot_lr_synth_conf.tcl

# LR_SYNTH_CELL_LIBRARY_PATH / LR_SYNTH_CELL_LIBRARY_NAME are set automatically
# by the nix develop .#syn_shell hook (nix/syn.nix: NangateOpenCellLibrary_typical.lib).
