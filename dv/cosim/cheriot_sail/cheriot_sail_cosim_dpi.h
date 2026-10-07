// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#ifndef CHERIOT_SAIL_COSIM_DPI_H_
#define CHERIOT_SAIL_COSIM_DPI_H_

#include <stdint.h>

// svBitVecVal = uint32_t, svBit = unsigned char (IEEE 1800 / svdpi.h).
// Defined here so this header can be used without Xcelium headers.
#ifndef SV_PACKED_DATA_NEDTYPES
#define SV_PACKED_DATA_NEDTYPES
typedef uint32_t      svBitVecVal;
typedef unsigned char svBit;
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Initialize the cheriot-sail model. Must be called once before any step().
// boot_addr: reset PC and mtvec (matches CHERIoT-Ibex boot_addr_i).
// bit[31:0] → const svBitVecVal * (Xcelium DPI convention for packed vectors)
void cheriot_sail_cosim_init(const svBitVecVal *boot_addr);
// Set x1-x15 to NULL, CHERIoT-Ibex's reset value (init leaves them root_cap_mem, the RVFI-DII
// start state TestRIG uses). Call after init when the program runs from reset (UVM cosim).
void cheriot_sail_cosim_null_gprs(void);
// RAM size mapped at 0x80000000 by the next init (default 8 MiB, the TestRIG TB's data memory).
void cheriot_sail_cosim_set_ram_size(const svBitVecVal *size);

// Advance the model by one retired instruction and compare CHERI/integer outputs.
//
// insn:          32-bit instruction word (from RTL RVFI rvfi_insn)
// pc:            program counter of this instruction (rvfi_pc_rdata)
// cheri_rf_we:   1 if the instruction wrote a capability register  (bit → svBit)
// cheri_rd:      5-bit destination capability register address     (bit[4:0] → svBitVecVal*)
// cheri_rtag:    tag bit written to the capability register        (bit → svBit)
// rtl_rd_wdata:  32-bit integer register write data (rvfi_rd_wdata)
// rtl_trap:      1 if the RTL took a trap this instruction         (bit → svBit)
//
// Returns 0 on match, -1 if the model disagrees (errors queued via
// cheriot_sail_cosim_get_error).
int cheriot_sail_cosim_step(const svBitVecVal *insn,
                             const svBitVecVal *pc,
                             svBit cheri_rf_we,
                             const svBitVecVal *cheri_rd,
                             svBit cheri_rtag,
                             const svBitVecVal *rtl_rd_wdata,
                             svBit rtl_trap);

// Tear down the model (frees Sail runtime state). Safe to call on cleanup and
// before re-initializing after a reset.
void cheriot_sail_cosim_cleanup(void);

// The DUT entered an interrupt handler: give the model the DUT's pending bits (mip) and let it
// take the interrupt from its own state. Call before stepping the handler's first instruction.
// Returns 0 on success, -1 (with an error recorded) if the model would not take it.
int         cheriot_sail_cosim_take_interrupt(const svBitVecVal *mip);

// Return the Sail model's mtval value after the last step() (valid when that step was a trap).
uint32_t    cheriot_sail_cosim_get_mtval(void);
// Return the Sail model's mcause value after the last step() (valid when that step was a trap).
// Bit 31 = interrupt flag; bits [4:0] = exception / interrupt code.
uint32_t    cheriot_sail_cosim_get_mcause(void);

// Error reporting — same pattern as riscv_cosim_get_error.
int         cheriot_sail_cosim_get_num_errors(void);
const char *cheriot_sail_cosim_get_error(int index);
void        cheriot_sail_cosim_clear_errors(void);

// Backdoor memory initialisation: write one byte into the Sail model's RAM.
// Call after cheriot_sail_cosim_init(), before the first step().
void cheriot_sail_cosim_write_mem_byte(const svBitVecVal *addr,
                                       const svBitVecVal *data);  // SV: bit [7:0]

// Push the RTL's current mcycle counter into the Sail model so that csrr
// mcycle instructions in Sail return the hardware value.  Call once per
// retired instruction, before cheriot_sail_cosim_step(), mirroring how
// riscv_cosim_set_mcycle() feeds the same value into Spike.
void cheriot_sail_cosim_set_mcycle(uint64_t mcycle);

// Fields of the RVFI execution packet produced by the last step(). The rd and
// mem getters return 0 when the model reported no integer write / memory access.
uint32_t cheriot_sail_cosim_get_pc_wdata(void);
svBit    cheriot_sail_cosim_get_trap(void);
uint32_t cheriot_sail_cosim_get_rd_addr(void);
uint32_t cheriot_sail_cosim_get_rd_wdata(void);
uint32_t cheriot_sail_cosim_get_cd_addr(void);
uint64_t cheriot_sail_cosim_get_cd_wdata(void);
svBit    cheriot_sail_cosim_get_cd_wtag(void);
svBit    cheriot_sail_cosim_get_mem_present(void);
uint32_t cheriot_sail_cosim_get_mem_addr(void);
uint32_t cheriot_sail_cosim_get_mem_rmask(void);
uint32_t cheriot_sail_cosim_get_mem_wmask(void);
uint64_t cheriot_sail_cosim_get_mem_rdata(void);
uint64_t cheriot_sail_cosim_get_mem_wdata(void);

#ifdef __cplusplus
}
#endif

#endif  // CHERIOT_SAIL_COSIM_DPI_H_
