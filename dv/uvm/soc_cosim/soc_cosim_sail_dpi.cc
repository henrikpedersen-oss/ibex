// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// soc_cosim DPI for CHERIoT-Sail (SOC_COSIM_SAIL).
//
// soc_cosim_load_elf_cheriot_sail: copy every loadable segment of a 32-bit RISC-V ELF into
// CHERIoT-Sail's memory at its load address (p_paddr: the LMA, so initialised data lands where the
// image keeps it and the start-up code copies it, as in the SoC's memories). For a SoC whose core
// is CHERIoT from reset (soc_cosim_cfg SocStartCheriot). Returns the number of bytes written, or
// -1 on an error (reported on stderr).

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <iterator>
#include <vector>

#include "soc_cosim_elf.h"

// CHERIoT-Sail co-simulation (dv/cosim/cheriot_sail).
extern "C" void cheriot_sail_cosim_write_mem_byte(const uint32_t *addr, const uint32_t *data);

extern "C" int soc_cosim_load_elf_cheriot_sail(const char *path) {
  return soc_cosim::for_each_segment(
      path, "soc_cosim_load_elf_cheriot_sail",
      [](uint32_t paddr, const uint8_t *data, uint32_t size) {
        for (uint32_t i = 0; i < size; ++i) {
          uint32_t a = paddr + i, d = data[i];
          cheriot_sail_cosim_write_mem_byte(&a, &d);
        }
        return true;
      });
}
