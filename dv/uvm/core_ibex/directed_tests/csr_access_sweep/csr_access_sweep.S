# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Reads and writes every CSR that uarch_cg's cp_csr_read_only / cp_csr_write count (csr_num_e
# minus IGNORED_CSRS in fcov/core_ibex_csr_categories.svh), from M-mode and from U-mode, so that
# csr_read_only_priv_cross and csr_write_priv_cross see every (CSR, privilege) pair. Those
# coverpoints count illegal accesses too, so the sweep does not need any access to succeed.
#
# - M-mode: read each CSR, then write back the value just read. No CSR changes value (mtvec,
#   mstatus, PMP and mseccfg included); writes to read-only CSRs (counters, IDs) and accesses to
#   debug-only CSRs trap as illegal and the handler skips the instruction.
# - U-mode: read and write each CSR, once with mcounteren = 0 and once with all bits set.
#   Everything except an enabled counter read traps; the handler skips it. Nothing is written.
#
# MSHWM (0xBC1) and MSHWMB (0xBC2) are CHERIoT CSRs, illegal in RISC-V mode (ibex_cs_registers.sv)
# and unknown to Spike. They are swept from U-mode only, where both sides trap whether or not the
# CSR exists (machine-level address), so the cosim agrees; the M-mode accesses are left to the
# CHERIoT tests. CDBG_CTRL (0xBC4) is left out: the RTL no longer implements it.

#include "riscv_test.h"
#include "test_macros.h"
#include "custom_macros.h"

# The 108 CSRs (numeric addresses, as csr_num_e).
#define CSR_LIST \
  0xF11, 0xF12, 0xF13, 0xF14, 0xF15, \
  0x300, 0x301, 0x304, 0x305, 0x310, 0x30A, \
  0x340, 0x341, 0x342, 0x343, 0x344, \
  0x3A0, 0x3A1, 0x3A2, 0x3A3, \
  0x3B0, 0x3B1, 0x3B2, 0x3B3, 0x3B4, 0x3B5, 0x3B6, 0x3B7, \
  0x3B8, 0x3B9, 0x3BA, 0x3BB, 0x3BC, 0x3BD, 0x3BE, 0x3BF, \
  0x747, 0x7A0, 0x7A1, 0x7A2, 0x7B0, 0x7B1, 0x7B2, 0x7B3, \
  0x7C0, 0x7C1, \
  0xC00, 0xC02, 0xC03, 0xC04, 0xC05, 0xC06, 0xC07, 0xC08, 0xC09, 0xC0A, 0xC0B, 0xC0C, \
  0xC0D, 0xC0E, 0xC0F, 0xC10, 0xC11, 0xC12, 0xC13, 0xC14, 0xC15, 0xC16, 0xC17, 0xC18, \
  0xC19, 0xC1A, 0xC1B, 0xC1C, 0xC1D, 0xC1E, 0xC1F, \
  0xC80, 0xC82, 0xC83, 0xC84, 0xC85, 0xC86, 0xC87, 0xC88, 0xC89, 0xC8A, 0xC8B, 0xC8C, \
  0xC8D, 0xC8E, 0xC8F, 0xC90, 0xC91, 0xC92, 0xC93, 0xC94, 0xC95, 0xC96, 0xC97, 0xC98, \
  0xC99, 0xC9A, 0xC9B, 0xC9C, 0xC9D, 0xC9E, 0xC9F

# Swept from U-mode only (MSHWM, MSHWMB; see above).
#define CSR_LIST_U_ONLY 0xBC1, 0xBC2

# M-mode: read, then write back what was read (csrr = csrrs rd, csr, x0: a read-only access;
# csrw = csrrw x0, csr, rs: a write).
.macro SWEEP_M
  .irp csr, CSR_LIST
    csrr  t0, \csr
    csrw  \csr, t0
  .endr
.endm

# U-mode: read, then write. Writes from U-mode are always illegal for these CSRs.
.macro SWEEP_U
  .irp csr, CSR_LIST, CSR_LIST_U_ONLY
    csrr  t0, \csr
    csrw  \csr, t0
  .endr
.endm

RVTEST_RV32M
RVTEST_CODE_BEGIN

  la    t0, mtvec_handler
  csrw  mtvec, t0

  # ---- M-mode sweep ----
  SWEEP_M

  # ---- U-mode sweeps ----
  csrwi mcounteren, 0
  la    s5, after_u0
  SWITCH_TO_U_MODE_LABEL(u_sweep_0)
.balign 4
u_sweep_0:
  SWEEP_U
  ecall
after_u0:

  li    t0, 0xFFFFFFFF
  csrw  mcounteren, t0
  la    s5, after_u1
  SWITCH_TO_U_MODE_LABEL(u_sweep_1)
.balign 4
u_sweep_1:
  SWEEP_U
  ecall
after_u1:

  csrwi mcounteren, 0
  j     pass

  TEST_PASSFAIL

# Illegal instruction (mcause 2): skip the 4-byte CSR instruction and return to the mode it came
# from (mret restores the privilege the trap saved in mstatus.MPP). ecall from U-mode (mcause 8):
# a sweep is done; return to M-mode at s5. Anything else fails. Uses t5/t6 only.
.balign 256
mtvec_handler:
  csrr  t5, mcause
  li    t6, 2
  beq   t5, t6, skip_insn
  li    t6, 8
  beq   t5, t6, u_done
  j     fail
skip_insn:
  csrr  t5, mepc
  addi  t5, t5, 4
  csrw  mepc, t5
  mret
u_done:
  csrw  mepc, s5
  li    t6, MSTATUS_MPP
  csrs  mstatus, t6
  mret

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
