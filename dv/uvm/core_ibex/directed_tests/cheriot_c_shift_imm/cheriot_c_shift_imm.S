# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_c_shift_imm -- c.srli / c.srai with a non-zero shift in CHERIoT mode
# =============================================================================
# RTL block no regression test reached (Jasper UNR found it reachable, 2026-10-08):
# ibex_compressed_decoder.sv, c.srli/c.srai with cheriot_enable_i On, the shamt != 0 arm of
# the rd select (rd = rs1'; shamt == 0 is a HINT expanded with rd = x0).
#
# Expected behaviour (not taken from the RTL):
#   - RISC-V C: c.srli/c.srai rd' = rd' >>(logical/arithmetic) shamt.
#   - CHERIoT-Sail: an integer instruction writes rd with X(rd) = v, an untagged value, so a
#     capability shifted in place loses its tag and holds the shifted address.
#
# ca0 is loaded from MTCC (tagged; crt_cheriot.S installs trap_entry there). The C tests link
# at 0x100000, so that address is positive and c.srai on it equals c.srli: test 6 shifts a
# negative integer to tell the two apart. Integer results go to t0/t1/s0, never a0 (aN and caN
# are the same register).
#
#   1  CGetTag(ca0) = 1 before the shift (rules out an already-untagged source)
#   2  c.srli a0, 4 on the capability: a0 = address >> 4
#   3  ... and CGetTag(ca0) = 0
#   4  c.srai a0, 4 on the capability: a0 = address >> 4 (positive address)
#   5  ... and CGetTag(ca0) = 0
#   6  c.srai a0, 4 on 0x80001230: a0 = 0xF8000123
# Returns 0 on success, else the failing test number.
#
# Encodings:
#   cspecialr ca0, mtcc = .word 0x03C0055B   cgettag t0, ca0 = .word 0xFE4502DB
#   cgetaddr s0, ca0    = .word 0xFEF5045B   (all as in cheriot_ccleartag.S)
#   c.srli a0, 4 = .hword 0x8111             c.srai a0, 4 = .hword 0x8511
# =============================================================================

.globl main
main:
    .word   0x03C0055B              # cspecialr ca0, mtcc
    .word   0xFE4502DB              # cgettag t0, ca0
    li      t1, 1
    bne     t0, t1, .Lfail1
    .word   0xFEF5045B              # cgetaddr s0, ca0

    .hword  0x8111                  # c.srli a0, 4
    srli    t1, s0, 4
    bne     a0, t1, .Lfail2
    .word   0xFE4502DB              # cgettag t0, ca0
    bnez    t0, .Lfail3

    .word   0x03C0055B              # cspecialr ca0, mtcc
    .hword  0x8511                  # c.srai a0, 4
    srai    t1, s0, 4
    bne     a0, t1, .Lfail4
    .word   0xFE4502DB              # cgettag t0, ca0
    bnez    t0, .Lfail5

    li      a0, 0x80001230
    .hword  0x8511                  # c.srai a0, 4
    li      t1, 0xF8000123
    bne     a0, t1, .Lfail6

    li      a0, 0
    ret

.Lfail1: li a0, 1; ret
.Lfail2: li a0, 2; ret
.Lfail3: li a0, 3; ret
.Lfail4: li a0, 4; ret
.Lfail5: li a0, 5; ret
.Lfail6: li a0, 6; ret
