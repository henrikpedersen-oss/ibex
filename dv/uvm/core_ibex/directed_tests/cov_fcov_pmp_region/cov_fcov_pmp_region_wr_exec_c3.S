# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# cov_fcov_pmp_region_wr_exec_c3: pmp_region_cg.pmp_wr_exec_region for every PMP entry but 3,
# which holds the code rule. Variant 3 of five; the sequence, the per-entry locked values and the
# failure codes are in pmp_region_wr_exec.h.

#include "riscv_test.h"
#include "test_macros.h"

#define WR_EXEC_CODE_REGION 3
#include "pmp_region_wr_exec.h"
