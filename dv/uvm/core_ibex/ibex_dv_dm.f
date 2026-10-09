// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Extra sources of a DM build of the UVM testbench (make ... DM=1): the real RISC-V debug module
// (vendor/pulp_riscv_dbg, CHERIoT-capable) and the bus mux that connects it to the core.
// scripts/compile_tb.py adds "+define+IBEX_DM_REAL -f <this file>" after ibex_dv.f, so everything
// here may use ibex_dv.f's packages (prim_mubi_pkg, prim_secded_pkg, prim_fifo_sync), but
// core_ibex_tb_top.sv, which ibex_dv.f compiles first, must not name the dm package.
//
// Not compiled: dmi_jtag*.sv, dmi_cdc.sv, dmi_bscane_tap.sv (no JTAG DTM: the test drives the DMI
// port directly) and sva/ (the DM's own bind assertions).

+incdir+${PRJ_DIR}/vendor/pulp_riscv_dbg/src
${PRJ_DIR}/vendor/pulp_riscv_dbg/src/dm_pkg.sv
${PRJ_DIR}/vendor/pulp_riscv_dbg/debug_rom/debug_rom.sv
${PRJ_DIR}/vendor/pulp_riscv_dbg/debug_rom/debug_rom_one_scratch.sv
${PRJ_DIR}/vendor/pulp_riscv_dbg/debug_rom/debug_rom_cheriot.sv
${PRJ_DIR}/vendor/pulp_riscv_dbg/src/dm_csrs.sv
${PRJ_DIR}/vendor/pulp_riscv_dbg/src/dm_sba.sv
${PRJ_DIR}/vendor/pulp_riscv_dbg/src/dm_mem.sv
${PRJ_DIR}/vendor/pulp_riscv_dbg/src/dm_top.sv
${PRJ_DIR}/dv/uvm/core_ibex/tb/ibex_dm_obi_mux.sv
