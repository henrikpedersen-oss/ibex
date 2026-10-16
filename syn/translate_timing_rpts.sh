#!/usr/bin/env bash

# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# The translation looks each timing-path cell up in the flattened top module. With the hierarchy
# kept (LR_SYNTH_FLATTEN=0) the cells sit in submodules and are not found, so the raw reports stay.
if [ "${LR_SYNTH_FLATTEN:-1}" = 0 ]; then
  echo "translate_timing_rpts: hierarchical netlist, timing reports left untranslated"
  exit 0
fi

./python/build_translated_names.py ibex_top ./"$LR_SYNTH_OUT_DIR"/generated ./"$LR_SYNTH_OUT_DIR"/reports/timing/*.csv.rpt

for file in ./"$LR_SYNTH_OUT_DIR"/reports/timing/*.csv.rpt; do
  ./python/translate_timing_csv.py "$file" ./"$LR_SYNTH_OUT_DIR"/generated
done

