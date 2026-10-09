// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// CHERIoT-Ibex's implementation-defined CSRs, as platform functions of the CHERIoT-Sail model
// (local addition, ibex_cheriot_verification spec GAP-CS-3). See ibex_platform_csrs.c.
//
// The ibex_csr_* functions taking/returning Sail types are externs of the model: the .sail
// sources declare them as `val ibex_csr_... = {c: "ibex_csr_..."}` (riscv_sys_control.sail) and
// the generated C calls them. The ibex_platform_set_* functions are for the bench (DPI bridge).

#pragma once
#include "sail.h"

#ifdef __cplusplus
extern "C" {
#endif

// Model externs (Sail types: csreg/xlenbits = mach_bits, bool, unit).
bool      ibex_csr_defined(mach_bits csr);
mach_bits ibex_csr_read(mach_bits csr);
unit      ibex_csr_write(mach_bits csr, mach_bits value);
bool      ibex_csr_read_without_asr(mach_bits csr);
unit      ibex_csr_reset(unit);
unit      ibex_csr_sync_exception(unit);
unit      ibex_csr_mret(unit);

// Bench inputs, pushed before each step (never read back from the DUT's CSR state).
// idx is the counter number, 3..31 (mhpmcounter<idx>); value is the full 64-bit counter.
void ibex_platform_set_mhpmcounter(unsigned idx, uint64_t value);
// cpuctrlsts.ic_scr_key_valid (bit 8): the instruction cache's scrambling key handshake.
void ibex_platform_set_ic_scr_key_valid(bool valid);
// The mcounteren_writable_i pin (default 1, ibex_configs/TestRIG tie it On).
void ibex_platform_set_mcounteren_writable(bool writable);

#ifdef __cplusplus
}
#endif
