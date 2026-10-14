// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Extra sources of a DM build of the UVM testbench (make ... DM=1): the real RISC-V debug module
// (pulp_riscv_dbg, CHERIoT-capable; fetched by scripts/compile_tb.py into the build directory as
// ${PULP_RISCV_DBG_DIR}) and the bus mux that connects it to the core.
// scripts/compile_tb.py adds "+define+IBEX_DM_REAL -f <this file>" after ibex_dv.f, so everything
// here may use ibex_dv.f's packages (prim_mubi_pkg, prim_secded_pkg, prim_fifo_sync), but
// core_ibex_tb_top.sv, which ibex_dv.f compiles first, must not name the dm package.
//
// Not compiled: dmi_jtag*.sv, dmi_cdc.sv, dmi_bscane_tap.sv (no JTAG DTM: the test drives the DMI
// port directly) and sva/ (the DM's own bind assertions).

+incdir+${PULP_RISCV_DBG_DIR}/src
${PULP_RISCV_DBG_DIR}/src/dm_pkg.sv
${PULP_RISCV_DBG_DIR}/debug_rom/debug_rom.sv
${PULP_RISCV_DBG_DIR}/debug_rom/debug_rom_one_scratch.sv
${PULP_RISCV_DBG_DIR}/debug_rom/debug_rom_cheriot.sv
${PULP_RISCV_DBG_DIR}/src/dm_csrs.sv
${PULP_RISCV_DBG_DIR}/src/dm_sba.sv
${PULP_RISCV_DBG_DIR}/src/dm_mem.sv
${PULP_RISCV_DBG_DIR}/src/dm_top.sv
${PRJ_DIR}/dv/uvm/core_ibex/tb/ibex_dm_obi_mux.sv
