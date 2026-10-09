// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include <svdpi.h>

#include <cassert>

#include "cosim.h"
#include "spike_cosim.h"

extern "C" {
void *spike_cosim_init(const char *isa_string, svBitVecVal *start_pc,
                       svBitVecVal *start_mtvec, const char *log_file_path_cstr,
                       svBitVecVal *pmp_num_regions,
                       svBitVecVal *pmp_granularity,
                       svBitVecVal *mhpm_counter_num, svBit secure_ibex,
                       svBit icache, svBitVecVal *dm_start_addr,
                       svBitVecVal *dm_end_addr) {
  assert(isa_string);

  std::string log_file_path;

  if (log_file_path_cstr) {
    log_file_path = log_file_path_cstr;
  }

  SpikeCosim *cosim = new SpikeCosim(
      isa_string, start_pc[0], start_mtvec[0], log_file_path, secure_ibex,
      icache, pmp_num_regions[0], pmp_granularity[0], mhpm_counter_num[0],
      dm_start_addr[0], dm_end_addr[0]);
  // Add a memory device that covers the entire address space.
  // This will only be sparsely populated (Spike's mem_t allocates pages on
  // demand), so the full 4 GiB costs nothing.
  //
  // This was 0xFFFF0000, which is 64 KiB SHORT of the 4 GiB the comment claims:
  // it left 0xFFFF0000-0xFFFFFFFF unmapped in Spike while the UVM mem_model
  // answers every address. riscv-dv emits `li rX,-1` followed by a memory access
  // through it, so any access at 0xFFFFFFFF/0xFFFFFFFE -- including the wrapped
  // second half of a misaligned access -- completed in the DUT but raised
  // trap_load_access_fault in the ISS. That surfaced as three unrelated-looking
  // cosim mismatches ("load at address fffffffc ... data 0 was expected",
  // "Synchronous trap was expected ... but the DUT didn't report one", and
  // "Register write data mismatch ... expected: ffffffff" from a later
  // csrrs mtval), which were one bug, not three.
  cosim->add_memory(0x00000000, 0x100000000ULL);
  return static_cast<Cosim *>(cosim);
}

void spike_cosim_release(void *cosim_handle) {
  auto cosim = static_cast<Cosim *>(cosim_handle);

  delete cosim;
}
}
