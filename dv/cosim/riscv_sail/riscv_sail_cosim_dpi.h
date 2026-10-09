// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#ifndef RISCV_SAIL_COSIM_DPI_H_
#define RISCV_SAIL_COSIM_DPI_H_

#include <stdint.h>

#ifndef SV_PACKED_DATA_NEDTYPES
#define SV_PACKED_DATA_NEDTYPES
typedef uint32_t      svBitVecVal;
typedef unsigned char svBit;
#endif

// The library is built with -fvisibility=hidden; only these are exported.
#define RISCV_SAIL_DPI __attribute__((visibility("default")))

#ifdef __cplusplus
extern "C" {
#endif

// Memory map and PMP configuration applied by the next init. Without a call the TestRIG
// defaults apply: 8 MiB RAM at 0x80000000, no PMP.
RISCV_SAIL_DPI void riscv_sail_cosim_configure(const svBitVecVal *ram_base,
                                               const svBitVecVal *ram_size, int pmp_count,
                                               int pmp_grain);

// (Re)initialise to the core's reset state with empty memory.
RISCV_SAIL_DPI void riscv_sail_cosim_init(const svBitVecVal *boot_addr);
RISCV_SAIL_DPI void riscv_sail_cosim_cleanup(void);

// Load one byte into the model's memory (after init). The UVM cosim mirrors every write it makes
// to Spike's memory: the test binary and the random data returned for uninitialised reads.
RISCV_SAIL_DPI void riscv_sail_cosim_write_mem_byte(const svBitVecVal *addr,
                                                    const svBitVecVal *data);

// The DUT entered an interrupt handler with these pending bits. Returns 0 if the model took an
// interrupt from its own state, -1 otherwise (message queued).
RISCV_SAIL_DPI int riscv_sail_cosim_take_interrupt(const svBitVecVal *mip);

// 1 if the model, in its current state, would take an interrupt were these bits pending: one is
// enabled in mie, and the hart is below M-mode or mstatus.MIE is set. Changes nothing.
RISCV_SAIL_DPI int riscv_sail_cosim_irq_would_take(const svBitVecVal *mip);

// Model CSRs, meaningful after a step that trapped.
RISCV_SAIL_DPI uint32_t riscv_sail_cosim_get_mcause(void);
RISCV_SAIL_DPI uint32_t riscv_sail_cosim_get_mtval(void);

// Step over one retired instruction at pc. Returns 0, or -1 if the model could not step it
// (message queued; see get_error).
RISCV_SAIL_DPI int riscv_sail_cosim_step(const svBitVecVal *insn, const svBitVecVal *pc);

RISCV_SAIL_DPI void riscv_sail_cosim_set_mcycle(uint64_t mcycle);

// Fields of the RVFI execution packet from the last step(). rd and mem getters return 0 when
// the model reported no integer write / memory access.
RISCV_SAIL_DPI uint32_t riscv_sail_cosim_get_pc_wdata(void);
RISCV_SAIL_DPI svBit    riscv_sail_cosim_get_trap(void);
RISCV_SAIL_DPI uint32_t riscv_sail_cosim_get_rd_addr(void);
RISCV_SAIL_DPI uint32_t riscv_sail_cosim_get_rd_wdata(void);
RISCV_SAIL_DPI uint32_t riscv_sail_cosim_get_mem_addr(void);
RISCV_SAIL_DPI uint32_t riscv_sail_cosim_get_mem_rmask(void);
RISCV_SAIL_DPI uint32_t riscv_sail_cosim_get_mem_wmask(void);
RISCV_SAIL_DPI uint64_t riscv_sail_cosim_get_mem_rdata(void);
RISCV_SAIL_DPI uint64_t riscv_sail_cosim_get_mem_wdata(void);

RISCV_SAIL_DPI int         riscv_sail_cosim_get_num_errors(void);
RISCV_SAIL_DPI const char *riscv_sail_cosim_get_error(int index);
RISCV_SAIL_DPI void        riscv_sail_cosim_clear_errors(void);

#ifdef __cplusplus
}
#endif

#endif  // RISCV_SAIL_COSIM_DPI_H_
