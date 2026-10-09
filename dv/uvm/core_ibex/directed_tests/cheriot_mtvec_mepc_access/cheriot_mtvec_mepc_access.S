# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_mtvec_mepc_access -- legacy mtvec/mepc CSR access in CHERIoT mode
# =============================================================================
# REQ_SCR_07. With cheriot_enable_i asserted, MTCC and MEPCC replace mtvec and
# mepc. Every Zicsr access to mtvec (0x305) or mepc (0x341) -- csrrw, csrrs,
# csrrc and the immediate forms, reads and writes alike -- must raise an illegal
# instruction exception (mcause 2) and leave MTCC and MEPCC unchanged.
#
# Where the expected behaviour comes from, and why it is not CHERIoT-Sail
# ----------------------------------------------------------------------
# The CHERIoT ISA document (cheriot-sail-upstream/archdoc/chap-cheri-riscv.tex,
# just after the SCR table) says: "Attempting to access the legacy RISC-V CSR
# [mtvec/mepc] via the CSR* instructions results in a Reserved Instruction
# exception." ibex does exactly this (ibex_cs_registers.sv, CSR_MTVEC/CSR_MEPC:
# illegal_csr for any access while cheriot_enable_i is On), so on the current
# RTL every check below is expected to PASS.
# CHERIoT-Sail diverges from its own ISA text: zicsr reads call
# get_mtvec() = MTCC.address and get_xret_target() = MEPCC.address (no trap),
# and writes call set_mtvec()/set_xret_target(), which are
# internal_error("unsupported") upstream (cheri_sys_exceptions.sail). The UVM
# cosim copy (dv/cosim/cheriot-sail-model) makes set_mtvec() return its argument
# (write silently dropped) and keeps set_xret_target() as internal_error; its
# Sail assertion is caught by the DPI's longjmp recovery, which skips the step
# and leaves the model's PC where it was.
#
# So under +enable_cheriot_seq=1 (the CHERIoT-Sail oracle) every probe here
# would log UVM_ERRORs on correct RTL: "DUT trapped before pc ..., model did not"
# (check_cheriot_trap_cause; +check_cheriot_cause=0 silences only that one) and
# "model PC ... differs from DUT PC" on the next step. There is no plusarg that
# turns only the CHERIoT-Sail oracle off. The test therefore runs the way
# cheriot_enable_transition does: it boots in RISC-V mode (riscv-tests
# environment), writes the trigger address, and the testbench raises the pin
# (+cheriot_enable_on_write); the CHERIoT-Sail oracle is only initialised for
# +enable_cheriot_seq=1, so it is off, and Spike, which does not model CHERIoT,
# runs relaxed (+disable_cosim=1). The test is self-checking.
#
# Why no value checks: after the switch, MTCC.address is mtvec_q (ibex keeps
# the integer part of MTCC in the mtvec register) and the capability metadata is
# the reset root; nothing here depends on that beyond test 3.
#
# Checks and failure codes
# ------------------------
# Result: CORE_STATUS word = (code << 8), then TEST_PASS (code 0) or TEST_FAIL.
#   1  After the switch, AUIPCC returns a tagged capability (CHERIoT really on)
#   2  PCC has SR (bit 7): the CSR accesses below are not failing for lack of SR
#   3  MTCC is tagged
#   4  control: mscratch write/read works in CHERIoT mode
#   5  control: CSpecialRW reads MTCC back with the vector just installed
#   6  control: CSpecialW MEPCC then CSpecialR MEPCC returns the same address
#   7  mcause = 0 and 8  mip = 0 before the first probe
#   Probe n (n = 1..18) uses codes 10n+1 .. 10n+5:
#     10n+1  the access did not trap
#     10n+2  mcause != 2
#     10n+3  MEPCC.address != the probing instruction
#     10n+4  its rd (s0, preset to 0xDEADBEEF) was written
#     10n+5  MTCC changed (CSetEqualExact against a copy taken before the probe)
#   mtvec: 1 csrr s0   2 csrw t0   3 csrrw s0,t0   4 csrrs s0,t0   5 csrrc s0,t0
#          6 csrrwi s0,4   7 csrrsi s0,4   8 csrrci s0,4   9 csrrsi s0,0 (read)
#   mepc:  10-18, the same nine forms.
#   t0 holds the address of .Lhijack for every probe, so a write that did reach
#   MTCC would send the trap there:
#   190  the trap went to .Lhijack (a mtvec write took effect)
#   191  unexpected trap in a post-probe check
#   192  mip != 0 after the last mret
#   193  unexpected trap during setup
# MEPCC after a write to mepc cannot be checked: the trap itself overwrites it.
#
# Registers after the switch: only x1-x15 (no x16-x31), integer scratch t0, t1,
# t2, s0; ca4/ca5 are the MTCC copies. CHERI instructions are .word-encoded from
# the Sail encdec clauses.

#include "riscv_test.h"

#define TRIGGER_ADDR 0x80200000   // must match +cheriot_enable_on_write in the testlist

# Absolute address of \sym. After the switch the AUIPC encoding is AUIPCC, which
# shifts imm20 by 11, not 12, so GNU `la` (AUIPC + ADDI, %pcrel_hi for << 12) is
# only right within about +-2 KiB of the pc; the vectors at the end of the file
# are ~3.4 KiB away. LUI + ADDI do not depend on the pc. Every address taken
# after the switch goes through this.
.macro LA_ABS rd, sym
    lui     \rd, %hi(\sym)
    addi    \rd, \rd, %lo(\sym)
.endm

.macro SET_TRAP_VECTOR label
    LA_ABS  t0, \label
    .word   0x03C0035B              # cspecialr c6, mtcc
    .word   0x2053035B              # csetaddr c6, c6, t0
    .word   0x03C3005B              # cspecialw mtcc, c6
.endm

.macro RESUME label
    LA_ABS  t0, \label
    .word   0x03C0035B              # cspecialr c6, mtcc
    .word   0x2053035B              # csetaddr c6, c6, t0
    .word   0x03F3005B              # cspecialw mepcc, c6
    mret
.endm

# One probe: its own MTCC vector, an MTCC snapshot in ca5, the access, and the
# post-trap checks. Codes 10*id + 1..5.
.macro PROBE id, insn:vararg
    j       .Lset_\id
    .balign 4
.Lvec_\id:
    j       .Ltrap_\id
.Lset_\id:
    SET_TRAP_VECTOR .Lvec_\id
    .word   0x03C007DB              # cspecialr ca5, mtcc
    LA_ABS  t0, .Lhijack
    li      s0, 0xDEADBEEF
.Lfault_\id:
    \insn
    li      t2, 10*\id + 1
    j       .Lsig
.Ltrap_\id:
    .word   0x03C0075B              # cspecialr ca4, mtcc  first: compare MTCC before anything rewrites it
    .word   0x42F7035B              # csetequalexact t1, ca4, ca5
    li      t2, 1
    beq     t1, t2, 1f
    li      t2, 10*\id + 5
    j       .Lsig
1:
    SET_TRAP_VECTOR .Lvec_post
    csrr    t1, mcause
    li      t2, 2
    beq     t1, t2, 2f
    li      t2, 10*\id + 2
    j       .Lsig
2:
    .word   0x03F0035B              # cspecialr ct1, mepcc
    .word   0xFEF3035B              # cgetaddr t1, ct1
    LA_ABS  t2, .Lfault_\id
    beq     t1, t2, 3f
    li      t2, 10*\id + 3
    j       .Lsig
3:
    li      t2, 0xDEADBEEF
    beq     s0, t2, 4f
    li      t2, 10*\id + 4
    j       .Lsig
4:
    RESUME  .Lnext_\id
.Lnext_\id:
.endm

# norelax before RVTEST_CODE_BEGIN, not after: a relaxable .align in the
# header leaves an R_RISCV_ALIGN the linker shrinks by 2 bytes, which shifts
# every later .balign 4 (assembled without relaxation) to 2 mod 4. The MTCC
# vectors then fail legalisation (address[1:0] != 0 clears the tag).
    .option norelax
RVTEST_RV32M
RVTEST_CODE_BEGIN

    # ── RISC-V mode, pin Off: any trap here ends the test by timeout ─────────
    la      t0, trap_fail
    csrw    mtvec, t0

    li      t0, TRIGGER_ADDR
    sw      zero, 0(t0)
    # The bench raises the pin cheriot_enable_delay (6) cycles after the write.
    .rept 30
    nop
    .endr

    # ── CHERIoT mode ─────────────────────────────────────────────────────────
    .word   0x00000517              # auipcc ca0, 0
    .word   0xFE45035B              # cgettag t1, ca0
    li      t2, 1
    bne     t1, t2, .Lfail_1
    .word   0xFE05035B              # cgetperm t1, ca0
    andi    t1, t1, 0x80
    beqz    t1, .Lfail_2
    .word   0x03C005DB              # cspecialr ca1, mtcc
    .word   0xFE45835B              # cgettag t1, ca1
    li      t2, 1
    bne     t1, t2, .Lfail_3

    SET_TRAP_VECTOR .Lvec_setup
    li      t2, 0x5A5A5A5A
    csrw    mscratch, t2
    csrr    t1, mscratch
    bne     t1, t2, .Lfail_4
    .word   0x03C005DB              # cspecialr ca1, mtcc
    .word   0xFEF5835B              # cgetaddr t1, ca1
    LA_ABS  t2, .Lvec_setup
    bne     t1, t2, .Lfail_5
    LA_ABS  t0, .Lvec_setup
    .word   0x205585DB              # csetaddr ca1, ca1, t0
    .word   0x03F5805B              # cspecialw mepcc, ca1
    .word   0x03F0065B              # cspecialr ca2, mepcc
    .word   0xFEF6035B              # cgetaddr t1, ca2
    bne     t1, t0, .Lfail_6
    csrr    t1, mcause
    bnez    t1, .Lfail_7
    csrr    t1, mip
    bnez    t1, .Lfail_8

    # ── Probes 1-9: mtvec (0x305) ────────────────────────────────────────────
    PROBE 1,  csrr   s0, mtvec
    PROBE 2,  csrw   mtvec, t0
    PROBE 3,  csrrw  s0, mtvec, t0
    PROBE 4,  csrrs  s0, mtvec, t0
    PROBE 5,  csrrc  s0, mtvec, t0
    PROBE 6,  csrrwi s0, mtvec, 4
    PROBE 7,  csrrsi s0, mtvec, 4
    PROBE 8,  csrrci s0, mtvec, 4
    PROBE 9,  csrrsi s0, mtvec, 0
    # ── Probes 10-18: mepc (0x341) ───────────────────────────────────────────
    PROBE 10, csrr   s0, mepc
    PROBE 11, csrw   mepc, t0
    PROBE 12, csrrw  s0, mepc, t0
    PROBE 13, csrrs  s0, mepc, t0
    PROBE 14, csrrc  s0, mepc, t0
    PROBE 15, csrrwi s0, mepc, 4
    PROBE 16, csrrsi s0, mepc, 4
    PROBE 17, csrrci s0, mepc, 4
    PROBE 18, csrrsi s0, mepc, 0

    csrr    t1, mip
    bnez    t1, .Lfail_192
    li      t2, 0
    j       .Lsig

.Lfail_1:   li t2, 1;   j .Lsig
.Lfail_2:   li t2, 2;   j .Lsig
.Lfail_3:   li t2, 3;   j .Lsig
.Lfail_4:   li t2, 4;   j .Lsig
.Lfail_5:   li t2, 5;   j .Lsig
.Lfail_6:   li t2, 6;   j .Lsig
.Lfail_7:   li t2, 7;   j .Lsig
.Lfail_8:   li t2, 8;   j .Lsig
.Lfail_192: li t2, 192; j .Lsig

.balign 4
.Lhijack:   li t2, 190; j .Lsig
.balign 4
.Lvec_post: li t2, 191; j .Lsig
.balign 4
.Lvec_setup: li t2, 193; j .Lsig

# Result write, through an MTDC-derived capability (a plain sw through an
# integer base would fault in CHERIoT mode). t2 = code, 0 = pass.
.Lsig:
    li      a1, SIGNATURE_ADDR      # 0x8ffffff8 = cfg.signature_addr - 4
    slli    t0, t2, 8               # (code << 8) | CORE_STATUS
    sltu    t1, zero, t2            # TEST_FAIL if code != 0
    slli    t1, t1, 8
    ori     t1, t1, TEST_RESULT
    .word   0x03D0055B              # cspecialr ca0, mtdc
    .word   0x20B5055B              # csetaddr ca0, ca0, a1
    fence   iorw, iorw
    sw      t0, 0(a0)
    sw      t1, 0(a0)
1:  j       1b

# Reached only by a trap before the switch (mtvec, pin Off): cspecialr is illegal
# there, so this cannot report; the test ends by timeout, which is a failure.
    .balign 256
trap_fail:
    j       trap_fail

RVTEST_CODE_END

    .data
RVTEST_DATA_BEGIN
RVTEST_DATA_END
