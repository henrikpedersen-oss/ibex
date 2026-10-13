// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Ibex's implementation-defined CSRs as platform functions of the RISC-V Sail model (local
// addition, VENDORED_FROM 2026-10-12). See ibex_platform_csrs.c.

#pragma once
#include "sail.h"

#ifdef __cplusplus
extern "C" {
#endif

// Model hooks, called from the hand-patched generated C (see VENDORED_FROM).
bool      ibex_csr_defined(mach_bits csr);
bool      ibex_csr_user_counter_enabled(mach_bits csr);
mach_bits ibex_csr_read(mach_bits csr);
unit      ibex_csr_write(mach_bits csr, mach_bits value);
unit      ibex_csr_reset(unit);
unit      ibex_csr_sync_exception(unit);
unit      ibex_csr_mret(unit);

// Smepmp 1.0 (ibex/doc/03_reference/pmp.rst), hooked into the model's PMP code.
bool    ibex_mseccfg_mml(void);
bool    ibex_mseccfg_rlb(void);
// mseccfg.RLB can only be set while no pmpcfg.L is set: the writeCSR hook passes that in.
void    ibex_mseccfg_set_any_locked(bool any_locked);
// MML truth table for a matching entry; acc: 0 read, 1 write, 2 read-write, 3 execute.
bool    ibex_smepmp_mml_perms(uint64_t cfg, int acc, bool machine);
// M-mode access matching no entry: allowed unless MMWP, or MML and an instruction fetch.
bool    ibex_smepmp_m_unmatched_allowed(bool execute);
// pmpWriteCfg with Smepmp: RLB bypasses the lock; MML keeps RW=01 and refuses new executable
// M-mode-only / locked Shared-Region rules unless RLB.
uint64_t ibex_smepmp_write_cfg(uint64_t old_cfg, uint64_t v, uint64_t grain);

// Bench inputs, pushed before each step. idx is the counter number, 3..31 (mhpmcounter<idx>);
// value is the full 64-bit counter.
void ibex_platform_set_mhpmcounter(unsigned idx, uint64_t value);
// cpuctrlsts.ic_scr_key_valid (bit 8): the instruction cache's scrambling-key handshake.
void ibex_platform_set_ic_scr_key_valid(bool valid);

#ifdef __cplusplus
}
#endif
