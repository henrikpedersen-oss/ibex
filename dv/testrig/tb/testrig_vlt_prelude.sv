// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Used only by the TestRIG build in testrig_vlt_build.sh: compilation-unit imports for the
// vendored lowRISC interfaces. clk_rst_if.sv skips its own uvm_pkg / common_ifs_pkg imports
// under `ifndef VERILATOR (it assumes Verilator never compiles UVM), so provide them in $unit.
import uvm_pkg::*;
import common_ifs_pkg::*;
