# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: ibex_boot_addr -- mtvec holds the boot address when the core boots
# =============================================================================
# Expected behaviour (not taken from the RTL):
#   - doc/03_reference/exception_interrupts.rst: "The base address of the vector table is
#     initialized to the boot address (must be aligned to 256 bytes ...) when the core is
#     booting"; the core starts fetching at {boot_addr_i[31:8], 8'h80}.
#   - doc/03_reference/cs_registers.rst: mtvec.MODE is vectored (1).
#   In RISC-V mode (this config: cheriot_enable_i Off) mtvec reads {BOOT_ADDR[31:8], 8'h01}
#   before software writes it.
#
# The reset PC itself is checked by every test: the cosim's first retired PC must match
# Spike's start_pc. This test checks the second use of boot_addr_i, the mtvec init, which is
# also what would catch the testbench driving boot_addr_i's reset-time complement too long
# (core_ibex_tb_top.sv). It cannot use RVTEST_CODE_BEGIN: that writes mtvec before user code.
#
# Failure: the testbench sees TEST_FAIL; TESTNUM (gp) holds the code of the failing check.
#   1      mtvec != {BOOT_ADDR[31:8], 8'h01} at _start
#   0x100  a trap before the check (lands at BASE+0 through the boot mtvec)

#include "riscv_test.h"
#include "test_macros.h"

# link.ld places .text.init at 0x80000000; compile_tb.py builds the TB with BOOT_ADDR=8000_0000.
#define BOOT_ADDR      0x80000000
#define MTVEC_AT_BOOT  ((BOOT_ADDR & 0xFFFFFF00) | 0x1)

  .section .text.init
  .globl _start
  # Vectored mtvec at boot: exceptions enter at BASE+0 (interrupts are disabled at reset).
  j     fail_trap
  .org 0x80
_start:
  li    TESTNUM, 1
  csrr  a0, mtvec
  li    t1, MTVEC_AT_BOOT
  bne   a0, t1, fail
  j     pass

fail_trap:
  ori   TESTNUM, TESTNUM, 0x100
fail:
  RVTEST_FAIL
pass:
  RVTEST_PASS

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
