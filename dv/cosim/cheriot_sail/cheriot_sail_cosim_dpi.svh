// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// DPI imports for the cheriot-sail cosim oracle.
// Include this file in any SV module that calls into the Sail model.

`ifndef CHERIOT_SAIL_COSIM_DPI_SVH
`define CHERIOT_SAIL_COSIM_DPI_SVH

// Initialize (or re-initialize after reset) the Sail model.
// boot_addr: reset PC and mtvec (match CHERIoT-Ibex boot_addr_i).
import "DPI-C" function void cheriot_sail_cosim_init(bit [31:0] boot_addr);
// Set x1-x15 to NULL, CHERIoT-Ibex's reset value; init leaves them root_cap_mem (the RVFI-DII
// start state TestRIG uses). Call after init when the program runs from reset (UVM cosim).
import "DPI-C" function void cheriot_sail_cosim_null_gprs();
// RAM size mapped at 0x80000000 by the next init (default 8 MiB, the TestRIG TB's data memory).
import "DPI-C" function void cheriot_sail_cosim_set_ram_size(bit [31:0] size);

// Tear down the model and release Sail runtime state.
import "DPI-C" function void cheriot_sail_cosim_cleanup();

// Advance the model by one retired CHERIoT instruction and compare outputs.
//
// insn:          32-bit instruction word (RVFI rvfi_insn)
// pc:            instruction PC (rvfi_pc_rdata)
// cheri_rf_we:   1 if instruction wrote a capability register
// cheri_rd:      5-bit destination capability register address
// cheri_rtag:    tag bit written to the capability register by the RTL
// rtl_rd_wdata:  32-bit integer register write data (rvfi_rd_wdata)
// rtl_trap:      1 if the RTL took a trap this instruction
//
// Returns 0 on match, -1 on mismatch (errors queued in the model).
import "DPI-C" function int cheriot_sail_cosim_step(
  bit [31:0] insn,
  bit [31:0] pc,
  bit        cheri_rf_we,
  bit [ 4:0] cheri_rd,
  bit        cheri_rtag,
  bit [31:0] rtl_rd_wdata,
  bit        rtl_trap
);

// The DUT entered an interrupt handler: give the model the DUT's pending bits and let it take
// the interrupt from its own state. Call before stepping the handler's first instruction.
import "DPI-C" function int cheriot_sail_cosim_take_interrupt(bit [31:0] mip);

// Return the Sail model's mtval register after the last step (valid when that step was a trap).
import "DPI-C" function bit [31:0] cheriot_sail_cosim_get_mtval();
// Return the Sail model's mcause register after the last step (valid when that step was a trap).
// Bit 31 = interrupt flag; bits [4:0] = exception / interrupt code.
import "DPI-C" function bit [31:0] cheriot_sail_cosim_get_mcause();

// Error reporting.
import "DPI-C" function int  cheriot_sail_cosim_get_num_errors();
import "DPI-C" function string cheriot_sail_cosim_get_error(int index);
import "DPI-C" function void cheriot_sail_cosim_clear_errors();

// Backdoor memory load: write one byte into the Sail model's RAM.
// Call after cheriot_sail_cosim_init(), before the first step().
import "DPI-C" function void cheriot_sail_cosim_write_mem_byte(
  bit [31:0] addr,
  bit [ 7:0] data
);

// Push the RTL's mcycle counter into the Sail model before each step so that
// csrr mcycle instructions return the hardware value.  The Sail DII model
// does not advance mcycle on its own; without this push both csrr reads
// would return 0 and arithmetic on those values would mismatch the RTL.
import "DPI-C" function void cheriot_sail_cosim_set_mcycle(longint unsigned mcycle);

// Fields of the RVFI execution packet produced by the last step(). The rd and
// mem getters return 0 when the model reported no integer write / memory access.
import "DPI-C" function int unsigned     cheriot_sail_cosim_get_pc_wdata();
import "DPI-C" function bit              cheriot_sail_cosim_get_trap();
import "DPI-C" function int unsigned     cheriot_sail_cosim_get_rd_addr();
import "DPI-C" function int unsigned     cheriot_sail_cosim_get_rd_wdata();
import "DPI-C" function int unsigned     cheriot_sail_cosim_get_cd_addr();
import "DPI-C" function longint unsigned cheriot_sail_cosim_get_cd_wdata();
import "DPI-C" function bit              cheriot_sail_cosim_get_cd_wtag();
import "DPI-C" function bit              cheriot_sail_cosim_get_mem_present();
import "DPI-C" function int unsigned     cheriot_sail_cosim_get_mem_addr();
import "DPI-C" function int unsigned     cheriot_sail_cosim_get_mem_rmask();
import "DPI-C" function int unsigned     cheriot_sail_cosim_get_mem_wmask();
import "DPI-C" function longint unsigned cheriot_sail_cosim_get_mem_rdata();
import "DPI-C" function longint unsigned cheriot_sail_cosim_get_mem_wdata();

`endif  // CHERIOT_SAIL_COSIM_DPI_SVH
