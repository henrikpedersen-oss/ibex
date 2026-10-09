# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_scr_legalize -- MTCC/MEPCC legalisation on CSpecialW
# =============================================================================
# REQ_SCR_02, REQ_SCR_03. Expected values come from CHERIoT-Sail CSpecialRW
# (cheri_insts.sail):
#   MTCC (28):  invalid = address[1:0] != 0 | sealed | not(permit_execute);
#               address[1:0] := 0; tag cleared if invalid. Nothing else changes:
#               the otype of a sealed value is kept, the bounds are kept.
#   MEPCC (31): invalid = address[0] != 0 | sealed | not(permit_execute);
#               address[0] := 0; tag cleared if invalid.
# The write never traps (PCC has SR here). cheriot_cjalr_faults covers the
# missing-EX arm; this test covers the misaligned-address and sealed arms, with
# an aligned unsealed control for each SCR, so a core that clears the tag on
# every write fails too. Every operand is checked tagged before it is written:
# an untagged operand would read back untagged whatever the core does.
#
# An untagged MTCC must not live across anything that can trap: the trap would
# install it as PCC and livelock (CHERIoT-Sail ext_fetch_check_pc stops with
# not_implemented when PCC and MTCC are both untagged). Each MTCC probe is
# therefore cspecialw / cspecialr / cspecialw-restore with nothing in between,
# and the checks run afterwards on the copy. MEPCC needs no restore: no mret
# follows, and main returns through cra.
#
# Operands: ca0 = MTCC as installed (vector .Lunexpected, tag 1), ca1 = the
# operand, built from ca0 with CSetAddr (and CSeal), ca2 = the read-back value,
# ca3 = MScratchC @ 1 (sealing authority for otype 1, a forward sentry: CSeal
# permits otypes 1-7 for an executable capability). V = .Lunexpected.
#
# Checks and failure codes (main returns 0 or the first failing code)
#   MTCC, address V + k (k = 1, 2, 3), codes 10k: +0 operand tag 1,
#        +1 read-back tag 0, +2 read-back address V (bits [1:0] cleared)
#   40-42  MTCC control, address V: operand tag 1, read-back tag 1, address V
#   50-54  MTCC sealed (otype 1), address V: operand tag 1, operand CGetType 1,
#          read-back tag 0, read-back CGetType 1 (kept), address V
#   60-62  MEPCC, address V + 1: operand tag 1, read-back tag 0, address V
#   70-74  MEPCC sealed (otype 1), address V: as 50-54
#   80-82  MEPCC control, address V: operand tag 1, read-back tag 1, address V
#   90     MTCC tagged again at the end (every restore worked)
#   250    unexpected trap;  251 liveness (fewer checks executed than assembled)
#
# Register use: x0-x15 only; s1 check count (cheriot_dv.h EXPECT_*); t0/t1/t2
# integer scratch; s0 = V; ca0-ca3 as above. No cget* result goes into a live
# capability register (aN and caN are the same register).

#include "cheriot_dv.h"

    .option norelax

# ca1 := ca0 with address s0 + \off
.macro OPERAND off
    addi      t0, s0, \off
    csetaddr  a1, a0, t0
.endm

# ca1 := CSeal(ca1, ca3): sealed with otype 1
.macro SEAL_OPERAND
    cseal     a1, a1, a3
.endm

# Write ca1 to MTCC, read it back into ca2, restore MTCC from ca0.
.macro PROBE_MTCC
    cspecialw SCR_MTCC, a1
    cspecialr a2, SCR_MTCC
    cspecialw SCR_MTCC, a0
.endm

.macro PROBE_MEPCC
    cspecialw SCR_MEPCC, a1
    cspecialr a2, SCR_MEPCC
.endm

# ca1 tagged (\c_op); ca2 tag \tag (\c_tag) and address V (\c_addr)
.macro EXPECT_LEGALISED tag, c_op, c_tag, c_addr
    cgettag   t1, a1
    EXPECT_EQI t1, 1, \c_op
    cgettag   t1, a2
    EXPECT_EQI t1, \tag, \c_tag
    cgetaddr  t1, a2
    EXPECT_EQ t1, s0, \c_addr
.endm

    .text
    .globl main
main:
    li        s1, 0
    SET_VEC   .Lunexpected, t0, t1
    cspecialr a0, SCR_MTCC                  # ca0 = MTCC @ V, tagged
    LA_FAR    s0, .Lunexpected, t0          # s0 = V
    cspecialr a3, SCR_MSCRATCHC
    li        t0, 1
    csetaddr  a3, a3, t0                    # ca3 = sealing authority, otype 1

    # ── 10-32: MTCC with address[1:0] != 0 ───────────────────────────────────
    OPERAND   1
    PROBE_MTCC
    EXPECT_LEGALISED 0, 10, 11, 12
    OPERAND   2
    PROBE_MTCC
    EXPECT_LEGALISED 0, 20, 21, 22
    OPERAND   3
    PROBE_MTCC
    EXPECT_LEGALISED 0, 30, 31, 32

    # ── 40-42: MTCC control, aligned and unsealed ────────────────────────────
    OPERAND   0
    PROBE_MTCC
    EXPECT_LEGALISED 1, 40, 41, 42

    # ── 50-54: MTCC sealed ───────────────────────────────────────────────────
    OPERAND   0
    SEAL_OPERAND
    PROBE_MTCC
    EXPECT_LEGALISED 0, 50, 52, 54
    cgettype  t1, a1
    EXPECT_EQI t1, 1, 51
    cgettype  t1, a2
    EXPECT_EQI t1, 1, 53

    # ── 60-62: MEPCC with address[0] != 0 ────────────────────────────────────
    OPERAND   1
    PROBE_MEPCC
    EXPECT_LEGALISED 0, 60, 61, 62

    # ── 70-74: MEPCC sealed ──────────────────────────────────────────────────
    OPERAND   0
    SEAL_OPERAND
    PROBE_MEPCC
    EXPECT_LEGALISED 0, 70, 72, 74
    cgettype  t1, a1
    EXPECT_EQI t1, 1, 71
    cgettype  t1, a2
    EXPECT_EQI t1, 1, 73

    # ── 80-82: MEPCC control, aligned and unsealed ───────────────────────────
    OPERAND   0
    PROBE_MEPCC
    EXPECT_LEGALISED 1, 80, 81, 82

    cspecialr a2, SCR_MTCC
    cgettag   t1, a2
    EXPECT_EQI t1, 1, 90

    CHECK_LIVENESS 251
    li        a0, 0
    j         .Lexit

    .balign 4
.Lunexpected:
    li        a0, 250
.Lexit:
    ret
