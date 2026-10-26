// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// CHERIoT-Sail co-simulation: a SoC's revocation, for CHERIoT-Sail's load barrier
// (cheri_mem.sail mem_read_cap_revoked).
//
// cheriot_sail_cosim_set_revocation(heap_base, heap_size, bits_base): the revocable heap
//   [heap_base, heap_base + heap_size) and its bitmap at bits_base (one bit per 8-byte granule, as
//   the TRVK reads it). The defaults are the core bench's (heap from the RAM base, bitmap at
//   0x83000000), which it feeds itself (ibex_cosim_scoreboard cheriot_sail_load_revbm). A SoC
//   whose software writes the bitmap with ordinary stores (the CHERIoT RTOS test SoC, Earl Grey 2)
//   needs only the layout: CHERIoT-Sail executes those stores into its own memory.
//   Call after cheriot_sail_cosim_init().
//
// cheriot_sail_cosim_clear_tag(addr): the tag of the capability at addr cleared, as a revocation
//   engine (the TBRE) does in the SoC's memory behind the core: an input event from another bus
//   master, as a DMA write would be.

#include <cstdint>

// gmp.h first, in C++ context, as cheriot_sail_cosim_dpi.cc does: sail.h requests it again inside
// extern "C", where its C++ stream operators would not compile.
#include <gmp.h>

extern "C" {
#include "sail.h"
#include "rts.h"  // write_tag_bool: the model's tag memory
#include "riscv_platform_impl.h"
}

extern "C" void cheriot_sail_cosim_set_revocation(uint32_t heap_base, uint32_t heap_size,
                                                  uint32_t bits_base) {
  rv_revocation_heap_base = heap_base;
  rv_revocation_heap_size = heap_size;
  rv_revocation_bits_base = bits_base;
}

extern "C" void cheriot_sail_cosim_clear_tag(uint32_t addr) {
  // The model keys its tag memory by capability index (cheri_mem_metadata.sail addr_to_tag_addr:
  // the top 29 bits of the address), not by byte address.
  write_tag_bool(uint64_t(addr >> 3), false);
}

// Debug: one byte of CHERIoT-Sail's memory (the soc_cosim checking stack's +soc_cosim_peek).
extern "C" uint32_t cheriot_sail_cosim_read_mem_byte(uint32_t addr) {
  return uint32_t(read_mem(uint64_t(addr)) & 0xffu);
}
