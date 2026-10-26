// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// soc_cosim DPI for Spike (SOC_COSIM_SPIKE), on top of Ibex's co-simulation DPI (dv/cosim).
//
// soc_cosim_load_elf: every loadable segment of a 32-bit RISC-V ELF into the co-simulator's memory
//   at its load address. Spike fetches its instructions from this memory, so it runs the same
//   images the SoC's memories hold. Returns the number of bytes written, or -1 on an error.
//
// The handover to CHERIoT-Sail at the CHERIoT lock (soc_cosim_cfg SocStartRiscv) takes its state
// from Spike, never from the chip:
//   soc_cosim_get_gpr / get_pc / get_csr: Spike's registers, PC and CSRs;
//   soc_cosim_copy_mem_to_cheriot_sail: Spike's memory over [base, base + size) into CHERIoT-Sail's
//     (the images and every store made in RISC-V mode). Only non-zero bytes: CHERIoT-Sail has just
//     been initialised and its memory is zero. Returns the number of bytes copied.

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <vector>

#include "cosim.h"
#include "soc_cosim_elf.h"
#include "spike_cosim.h"

// CHERIoT-Sail co-simulation (dv/cosim/cheriot_sail).
extern "C" void cheriot_sail_cosim_write_mem_byte(const uint32_t *addr, const uint32_t *data);

namespace {

SpikeCosim *spike(void *cosim_handle) {
  return dynamic_cast<SpikeCosim *>(static_cast<Cosim *>(cosim_handle));
}

}  // namespace

extern "C" int soc_cosim_load_elf(void *cosim_handle, const char *path) {
  auto cosim = static_cast<Cosim *>(cosim_handle);
  return soc_cosim::for_each_segment(path, "soc_cosim_load_elf",
                                     [cosim](uint32_t paddr, const uint8_t *data, uint32_t size) {
                                       return cosim->backdoor_write_mem(paddr, size, data);
                                     });
}

extern "C" uint32_t soc_cosim_get_gpr(void *cosim_handle, int idx) {
  return spike(cosim_handle)->get_gpr(idx);
}

extern "C" uint32_t soc_cosim_get_pc(void *cosim_handle) { return spike(cosim_handle)->get_pc(); }

extern "C" uint32_t soc_cosim_get_csr(void *cosim_handle, int csr_num) {
  return spike(cosim_handle)->get_csr(csr_num);
}

extern "C" int soc_cosim_copy_mem_to_cheriot_sail(void *cosim_handle, uint32_t base,
                                                  uint32_t size) {
  auto cosim = static_cast<Cosim *>(cosim_handle);
  const uint32_t kChunk = 4096;
  std::vector<uint8_t> buf(kChunk);
  int copied = 0;
  for (uint64_t off = 0; off < size; off += kChunk) {
    uint32_t n = uint32_t(std::min<uint64_t>(kChunk, size - off));
    uint32_t addr = uint32_t(base + off);
    if (!cosim->backdoor_read_mem(addr, n, buf.data())) {
      std::fprintf(stderr, "soc_cosim_copy_mem_to_cheriot_sail: no Spike memory at 0x%08x\n", addr);
      return -1;
    }
    for (uint32_t i = 0; i < n; ++i) {
      if (buf[i] == 0) continue;
      uint32_t a = addr + i, d = buf[i];
      cheriot_sail_cosim_write_mem_byte(&a, &d);
      ++copied;
    }
  }
  return copied;
}
