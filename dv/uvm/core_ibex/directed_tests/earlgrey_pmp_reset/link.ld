/* Copyright lowRISC contributors.
 * Licensed under the Apache License, Version 2.0, see LICENSE for details.
 * SPDX-License-Identifier: Apache-2.0
 *
 * earlgrey_pmp_reset: everything in Earl Grey's DV_ROM PMP region (region 13 at reset: NAPOT
 * 0x0001_0000, 4 KiB, locked RWX), the only region the core can fetch from after reset. The
 * earlgrey-pmprst build boots there (BOOT_ADDR 0x0001_0000, compile_tb.py). The MEMORY region
 * makes the link fail rather than spill out of it.
 */
OUTPUT_ARCH( "riscv" )
ENTRY(_start)

MEMORY
{
  dv_rom (rwx) : ORIGIN = 0x00010000, LENGTH = 0x1000
}

SECTIONS
{
  .text.init : { *(.text.init) } > dv_rom
  .text      : { *(.text) }      > dv_rom
  .data      : { *(.data) }      > dv_rom
  .bss       : { *(.bss) }       > dv_rom
}
