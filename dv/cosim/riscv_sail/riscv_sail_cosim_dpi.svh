// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// DPI imports for the RISC-V (non-CHERI) Sail model; see riscv_sail_cosim_dpi.h.

`ifndef RISCV_SAIL_COSIM_DPI_SVH
`define RISCV_SAIL_COSIM_DPI_SVH

import "DPI-C" function void riscv_sail_cosim_configure(bit [31:0] ram_base, bit [31:0] ram_size,
                                                        int pmp_count, int pmp_grain);
import "DPI-C" function void riscv_sail_cosim_init(bit [31:0] boot_addr);
import "DPI-C" function void riscv_sail_cosim_cleanup();
import "DPI-C" function void riscv_sail_cosim_write_mem_byte(bit [31:0] addr, bit [7:0] data);
import "DPI-C" function int  riscv_sail_cosim_take_interrupt(bit [31:0] mip);
import "DPI-C" function int unsigned riscv_sail_cosim_get_mcause();
import "DPI-C" function int unsigned riscv_sail_cosim_get_mtval();
import "DPI-C" function int  riscv_sail_cosim_step(bit [31:0] insn, bit [31:0] pc);
import "DPI-C" function void riscv_sail_cosim_set_mcycle(longint unsigned mcycle);

import "DPI-C" function int unsigned     riscv_sail_cosim_get_pc_wdata();
import "DPI-C" function bit              riscv_sail_cosim_get_trap();
import "DPI-C" function int unsigned     riscv_sail_cosim_get_rd_addr();
import "DPI-C" function int unsigned     riscv_sail_cosim_get_rd_wdata();
import "DPI-C" function int unsigned     riscv_sail_cosim_get_mem_addr();
import "DPI-C" function int unsigned     riscv_sail_cosim_get_mem_rmask();
import "DPI-C" function int unsigned     riscv_sail_cosim_get_mem_wmask();
import "DPI-C" function longint unsigned riscv_sail_cosim_get_mem_rdata();
import "DPI-C" function longint unsigned riscv_sail_cosim_get_mem_wdata();

import "DPI-C" function int    riscv_sail_cosim_get_num_errors();
import "DPI-C" function string riscv_sail_cosim_get_error(int index);
import "DPI-C" function void   riscv_sail_cosim_clear_errors();

`endif  // RISCV_SAIL_COSIM_DPI_SVH
