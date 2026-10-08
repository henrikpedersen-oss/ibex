#!/usr/bin/env python3
"""Convert one or more 32-bit RISC-V ELF files to a merged Verilog vmem file.

Usage:
    elf_to_vmem.py [--base-addr BASE] [--size SIZE] elf1 [elf2 ...] > out.vmem

Outputs a $readmemh-compatible vmem with 32-bit word addresses (@addr) relative
to BASE_ADDR. Only PT_LOAD segments whose physical address falls within
[BASE_ADDR, BASE_ADDR + SIZE) are included. Multiple ELFs are merged into a
single image (later ELFs overwrite earlier ones for overlapping addresses).

Defaults:
    --base-addr 0x100000   (Sonata main SRAM)
    --size      0x20000    (128 KiB)
"""

import argparse
import struct
import sys

ELF_MAGIC = b'\x7fELF'
PT_LOAD = 1


def parse_elf_segments(path):
    """Return list of (paddr, data) for all PT_LOAD segments with filesz > 0."""
    with open(path, 'rb') as f:
        raw = f.read()

    if len(raw) < 4 or raw[:4] != ELF_MAGIC:
        raise ValueError(f'{path}: not an ELF file')
    if raw[4] != 1:
        raise ValueError(f'{path}: only 32-bit ELF supported (EI_CLASS={raw[4]})')

    # 32-bit ELF header fields
    e_phoff,    = struct.unpack_from('<I', raw, 0x1c)
    e_phentsize,= struct.unpack_from('<H', raw, 0x2a)
    e_phnum,    = struct.unpack_from('<H', raw, 0x2c)

    segments = []
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        p_type,   = struct.unpack_from('<I', raw, off + 0x00)
        p_offset, = struct.unpack_from('<I', raw, off + 0x04)
        p_paddr,  = struct.unpack_from('<I', raw, off + 0x0c)
        p_filesz, = struct.unpack_from('<I', raw, off + 0x10)
        p_memsz,  = struct.unpack_from('<I', raw, off + 0x14)
        if p_type != PT_LOAD or p_filesz == 0:
            continue
        data = bytearray(raw[p_offset:p_offset + p_filesz])
        # Zero-pad BSS region
        if p_memsz > p_filesz:
            data.extend(b'\x00' * (p_memsz - p_filesz))
        segments.append((p_paddr, bytes(data)))
    return segments


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('elf_files', nargs='+', metavar='ELF')
    parser.add_argument('--base-addr', type=lambda x: int(x, 0), default=0x100000,
                        metavar='ADDR', help='Memory region base address (default: 0x100000)')
    parser.add_argument('--size', type=lambda x: int(x, 0), default=0x20000,
                        metavar='SIZE', help='Memory region size in bytes (default: 0x20000)')
    parser.add_argument('--fill', action='store_true',
                        help='Emit every word in the region, not just the loaded segments. '
                             'The Sonata SRAM/HyperRAM models are behavioural arrays: anything '
                             '$readmemh does not write stays X, and a read of unwritten memory '
                             'returns X rather than the arbitrary-but-defined value real RAM '
                             'gives. That X reaches the TL-UL response FIFOs and trips '
                             'prim_fifo_sync DataKnown_A from ~987500 ps, and eventually an '
                             'X instruction fetch. Filling the window costs a larger vmem and '
                             'nothing else.')
    args = parser.parse_args()

    base = args.base_addr
    size = args.size
    mem  = bytearray(size)
    # Tracks which bytes an ELF segment actually covers.
    #
    # A zero word *inside* a loaded segment is real data and must be emitted; a zero
    # word outside every segment is unused memory and can be skipped. The emitter used
    # to drop every zero word regardless, and $readmemh leaves anything it does not
    # write as X, not 0. sim_boot_stub begins with 0x80 bytes of zeros, so the vmem
    # started at @00000020, the reset vector at 0x00100000 was never written, and the
    # core fetched X:  "Illegal instruction (hart 0) at PC 0x00100000: 0xxxxxxxxx".
    covered = bytearray(size)

    for elf_path in args.elf_files:
        try:
            segments = parse_elf_segments(elf_path)
        except Exception as e:
            print(f'WARNING: {e}', file=sys.stderr)
            continue
        for paddr, data in segments:
            if paddr >= base + size or paddr + len(data) <= base:
                continue  # entirely outside window
            start = max(paddr, base) - base
            end   = min(paddr + len(data), base + size) - base
            src_off = start - (paddr - base)
            mem[start:end] = data[src_off:src_off + (end - start)]
            covered[start:end] = b'\x01' * (end - start)

    # Emit vmem: 32-bit word-addressed. Skip only words that no segment covers, so
    # zeros within a segment are still written and never left as X.
    need_addr = True
    for word_idx in range(size // 4):
        chunk = mem[word_idx * 4:(word_idx + 1) * 4]
        if not args.fill and not any(covered[word_idx * 4:(word_idx + 1) * 4]):
            need_addr = True
            continue
        if need_addr:
            print(f'@{word_idx:08x}')
            need_addr = False
        val, = struct.unpack_from('<I', chunk)
        print(f'{val:08x}')


if __name__ == '__main__':
    main()
