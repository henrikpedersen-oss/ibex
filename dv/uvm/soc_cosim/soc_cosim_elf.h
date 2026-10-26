// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// The loadable segments of a 32-bit little-endian RISC-V ELF, for the soc_cosim DPI loaders.

#ifndef SOC_COSIM_ELF_H_
#define SOC_COSIM_ELF_H_

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <iterator>
#include <vector>

namespace soc_cosim {

template <typename T>
inline bool read_at(const std::vector<uint8_t> &elf, size_t off, T *out) {
  if (off + sizeof(T) > elf.size()) return false;
  std::memcpy(out, elf.data() + off, sizeof(T));
  return true;
}

// Calls put(paddr, data, size) for every PT_LOAD segment with file contents, at its load address.
// Returns the bytes given to put, or -1 on an error (reported on stderr as "<who>: ...").
template <typename Put>
inline int for_each_segment(const char *path, const char *who, Put put) {
  std::ifstream f(path, std::ios::binary);
  if (!f) {
    std::fprintf(stderr, "%s: cannot open %s\n", who, path);
    return -1;
  }
  std::vector<uint8_t> elf((std::istreambuf_iterator<char>(f)), {});
  // e_ident: 0x7f 'E' 'L' 'F', EI_CLASS = 1 (32-bit), EI_DATA = 1 (little-endian).
  if (elf.size() < 52 || std::memcmp(elf.data(), "\x7f" "ELF", 4) != 0 || elf[4] != 1 ||
      elf[5] != 1) {
    std::fprintf(stderr, "%s: %s is not a 32-bit little-endian ELF\n", who, path);
    return -1;
  }
  uint32_t phoff;
  uint16_t phentsize, phnum;
  read_at(elf, 28, &phoff);
  read_at(elf, 42, &phentsize);
  read_at(elf, 44, &phnum);
  int total = 0;
  for (uint16_t i = 0; i < phnum; ++i) {
    size_t ph = phoff + size_t(i) * phentsize;
    uint32_t type, offset, paddr, filesz;
    if (!read_at(elf, ph + 0, &type) || !read_at(elf, ph + 4, &offset) ||
        !read_at(elf, ph + 12, &paddr) || !read_at(elf, ph + 16, &filesz)) {
      std::fprintf(stderr, "%s: %s: truncated program header\n", who, path);
      return -1;
    }
    const uint32_t kPtLoad = 1;
    if (type != kPtLoad || filesz == 0) continue;
    if (size_t(offset) + filesz > elf.size()) {
      std::fprintf(stderr, "%s: %s: segment %u past the end of the file\n", who, path, i);
      return -1;
    }
    if (!put(paddr, elf.data() + offset, filesz)) {
      std::fprintf(stderr, "%s: %s: no memory at 0x%08x\n", who, path, paddr);
      return -1;
    }
    total += filesz;
  }
  return total;
}

}  // namespace soc_cosim

#endif  // SOC_COSIM_ELF_H_
