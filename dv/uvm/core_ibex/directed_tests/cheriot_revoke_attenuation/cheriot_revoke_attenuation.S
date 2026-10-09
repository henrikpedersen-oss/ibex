# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_revoke_attenuation — load-global attenuation of a REVOKED load
# =============================================================================
# Order of operations in CHERIoT-Sail LoadCapImm (cheri_insts.sail): the
# LG/LM attenuation is applied "if cr.tag" using the tag read from MEMORY, and
# only afterwards is the revocation bit consulted and the tag cleared. So a
# revoked capability loaded through an authority without LG comes back with
# tag 0 AND GL/LG cleared.
#
# The RTL does it the other way round: TRVK clears the tag before the core
# sees the metadata word, and cheriot_mem_to_cap() gates the attenuation on
# cap.valid (ibex_cheriot_pkg.sv cheriot_mask_loaded_cperms(.., cap.valid, ..)),
# so the revoked capability keeps GL/LG. Static reading of the RTL therefore
# predicts that test 6 FAILS. The result is untagged either way, so this is not
# an escalation of authority -- but CGetPerm makes it architecturally visible.
# The CLC itself matches CHERIoT-Sail (the cosim compares cd_wtag and cd_addr,
# not the metadata); the CHERIoT-Sail oracle reports the difference one
# instruction later, as an rd_wdata mismatch on the CGetPerm of test 6
# (sail=0x7c rtl=0x7f). Kept out of cheriot_revoke_load_barrier so that
# test's verdict stays about the barrier itself.
#
# Plusargs: +revbm_mode=range +revbm_heap_base=80000000
#           +revbm_revoke_base=80018000 +revbm_revoke_size=8
#
#   Test 1  CGetPerm(ca1) = 0x7D: MTDC with LG (bit 1) cleared. Precondition.
#   Test 2  live cap (base 0x80018040, perms 0x7F) via ca1: tag 1.
#   Test 3  ...perms 0x7C (GL and LG cleared by the no-LG authority). Control:
#           the attenuation itself works on a tagged load.
#   Test 4  revoked cap (base 0x80018000) via ca1: tag 0. The barrier works.
#   Test 5  revoked cap via ca0 (full authority): perms 0x7F. Control: nothing
#           to attenuate, so the revoked load alone does not change perms.
#   Test 6  revoked cap via ca1: perms 0x7C, as CHERIoT-Sail computes.
#           Predicted to fail on the current RTL with 0x7F (see above).
#   Test 7  Any trap.
#
# Registers: ca0 = full authority (MTDC, cursor at the slot), ca1 = no-LG
# authority, ca2 = stored cap, ca4 = loaded. Scratch t0-t2. No x16-x31.
# Encodings (all from cheriot_perm_lc_sc / cheriot_revoke_load_barrier):
#   cspecialr ca0, mtdc 0x03D0055B   csetaddr ca0, ca0, t0 0x2055055B
#   candperm ca1, ca0, t0 0x1A5505DB cgetperm t1, ca1 0xFE05835B
#   cspecialr ca2, mtdc 0x03D0065B   csetaddr ca2, ca2, t0 0x2056065B
#   csetbounds ca2, ca2, t0 0x1056065B
#   csc ca2, 0(ca0) 0x00C53023       clc ca4, 0(ca0) 0x00053703
#   clc ca4, 0(ca1) 0x0005B703       cgettag t1, ca4 0xFE47035B
#   cgetperm t1, ca4 0xFE07035B

.macro SET_TRAP_VECTOR label
    la      t0, \label
    .word   0x03C0035B              # cspecialr c6, mtcc
    .word   0x2053035B              # csetaddr  c6, c6, t0
    .word   0x03C3005B              # cspecialw mtcc, c6
.endm

.macro MKCAP base
    .word   0x03D0065B              # cspecialr  ca2, mtdc
    li      t0, \base
    .word   0x2056065B              # csetaddr   ca2, ca2, t0
    li      t0, 8
    .word   0x1056065B              # csetbounds ca2, ca2, t0
    .word   0x00C53023              # csc        ca2, 0(ca0)
.endm

    .text
    .globl main

.balign 4
.Lvec_unexpected:
    j       .Lfail_test7

main:
    SET_TRAP_VECTOR .Lvec_unexpected

    la      t0, cap_slots
    .word   0x03D0055B              # cspecialr ca0, mtdc
    .word   0x2055055B              # csetaddr  ca0, ca0, t0
    li      t0, 0x7D                # all but LG
    .word   0x1A5505DB              # candperm  ca1, ca0, t0
    .word   0xFE05835B              # cgetperm  t1, ca1
    li      t2, 0x7D
    bne     t1, t2, .Lfail_test1

    MKCAP   0x80018040              # live
    .word   0x0005B703              # clc      ca4, 0(ca1)
    .word   0xFE47035B              # cgettag  t1, ca4
    li      t2, 1
    bne     t1, t2, .Lfail_test2
    .word   0xFE07035B              # cgetperm t1, ca4
    li      t2, 0x7C
    bne     t1, t2, .Lfail_test3

    MKCAP   0x80018000              # revoked
    .word   0x0005B703              # clc      ca4, 0(ca1)
    .word   0xFE47035B              # cgettag  t1, ca4
    bnez    t1, .Lfail_test4
    .word   0x00053703              # clc      ca4, 0(ca0)
    .word   0xFE07035B              # cgetperm t1, ca4
    li      t2, 0x7F
    bne     t1, t2, .Lfail_test5
    .word   0x0005B703              # clc      ca4, 0(ca1)
    .word   0xFE07035B              # cgetperm t1, ca4
    li      t2, 0x7C
    bne     t1, t2, .Lfail_test6

    li      a0, 0
    ret

.Lfail_test1: li a0, 1; ret
.Lfail_test2: li a0, 2; ret
.Lfail_test3: li a0, 3; ret
.Lfail_test4: li a0, 4; ret
.Lfail_test5: li a0, 5; ret
.Lfail_test6: li a0, 6; ret
.Lfail_test7: li a0, 7; ret

    .data
    .balign 8
cap_slots:
    .space  8
