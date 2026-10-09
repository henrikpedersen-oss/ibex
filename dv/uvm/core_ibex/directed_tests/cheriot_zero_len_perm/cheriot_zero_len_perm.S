# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_zero_len_perm -- zero-length and zero-permission capabilities
# =============================================================================
# Expected values come from CHERIoT-Sail (dv/cosim/cheriot-sail-model/src):
#   inCapBounds(cap, addr, size) = base <= addr & addr + size <= top
#     (cheri_cap_common.sail:711-715). With size 0 an address equal to top is in
#     bounds, so CSetBounds(c, 0) is permitted at any address in [base, top],
#     including top itself (the end of an object), and keeps the tag
#     (cheri_insts.sail CSetBounds/CSetBoundsExact/CSetBoundsImmediate/
#     CSetBoundsRoundDown: clearTagIf(newCap, not(inBounds)); length 0 is exact,
#     setCapBounds, cheri_cap_common.sail:444-490; round-down gives E = 0, T = B,
#     508-569). Any access of size >= 1 through it fails the bounds check.
#   Data access order (cheri_addr_checks.sail:182-210 ext_data_get_addr; CLC/CSC
#     cheri_insts.sail LoadCapImm/StoreCapImm): tag (0x02), seal (0x03), Permit_Load
#     (0x12), Permit_Store (0x13), [CSC: MC only if the stored value is tagged], bounds
#     (0x01). mtval = regnum << 5 | capcause (cheri_addr_checks.sail:73-94).
#   CAndPerm(c, 0) clears every permission and keeps the tag of an unsealed c
#     (cheri_insts.sail CAndPerm); CGetPerm then reads 0.
#   CJALR checks tag, seal/sentry rules and Permit_Execute (0x11 against cs1), not
#     bounds (cheri_insts.sail:162-216). A jump to a zero-length executable capability
#     therefore succeeds, and the fetch at the target fails: ext_fetch_check_pc
#     inCapBounds(PCC, pc, 2) -> Bounds violation against PCC, mtval 0x401
#     (cheri_addr_checks.sail:112-139); the PCC tag is cleared first, so MEPCC is
#     the target address with tag 0 (148-156, cheri_sys_exceptions.sail:71-81).
#   Representability (setCapAddr/incCapAddr): a zero-length E = 0 capability at b keeps
#     its tag for addresses in [b, b + 512) and loses it below b.
#   CSeal permits only if cs2.base <= cs2.address < cs2.top and cs2 has SE; CUnseal
#     needs inCapBounds(cs2, cs1.otype, 1) and US (cheri_insts.sail CSeal/CUnseal): a
#     zero-length or zero-permission authority always fails (tag 0, no trap); a
#     zero-length capability can itself be sealed and unsealed.
#
# Capabilities (obj is 64-aligned in .data):
#   ca1 Z   = CSetBounds(MTDC @ obj+16, 0)            base = top = obj+16, tagged
#   ca2 ZE  = CSetBounds(P @ obj+32, 0), P = [obj, obj+32): zero length at the end
#   ca3 NP  = CAndPerm(MTDC @ obj, 0)                 perms 0, full bounds, tagged
#   ca4/ca5/ca0 scratch
#
# Checks and failure codes (main returns 0 or the first failing code)
#   1-5    Z: tag 1, CGetLen 0, CGetBase = CGetTop = obj+16, CGetPerm 0x7F
#   6-8    ZE: tag 1, CGetBase = obj+32, CGetLen 0
#   9      CSetBounds(P @ obj+32, 1) has tag 0 (one byte past the end), no trap
#   10-12  NP: tag 1, CGetPerm 0, CGetLen 0xFFFFFFFF
#   13-17  CSetBounds(Z, 0) / CSetBoundsExact(Z, 0) / CSetBoundsImm(Z, 0) /
#          CSetBoundsRoundDown(Z, 0) keep the tag; CSetBounds(Z, 1) clears it
#   18     CSetBounds(CIncAddrImm(Z, 1), 0) clears the tag (address above top)
#   19-22  CIncAddrImm(Z, 1) tag 1, CIncAddrImm(Z, -1) tag 0, CSetAddr(Z, obj+16+511)
#          tag 1, CSetAddr(Z, obj+16+512) tag 0
#   23-24  CSetBounds(NP, 16) keeps tag 1 and perms 0
#   25     CAndPerm(NP, 0xFFF) still perms 0, tag 1 (26)
#   27-28  CSeal(Z, S@9) tag 1 otype 9;  29-30 CUnseal of it tag 1, CGetLen 0
#   31     CSeal(MTDC@obj, CSetBounds(S@9, 0)) tag 0
#   32     CUnseal(CSeal(MTDC@obj, S@9), CSetBounds(S@9, 0)) tag 0
#   33     CSeal(MTDC@obj, CAndPerm(S@9, 0)) tag 0
#   34     CUnseal(CSeal(MTDC@obj, S@9), CAndPerm(S@9, 0)) tag 0
#   35     CSeal(NP, S@9) tag 1 (a permission-less data capability can be sealed)
#   Trapping probes, each: [+0 no trap] [+1 mcause != 28] [+2 mtval] [+3 MEPCC.address]
#   40  lw  0(Z)    0x161      44  lb  0(Z)    0x161      48  sw  0(Z)    0x161
#   52  sb  0(Z)    0x161      56  clc 0(Z)    0x161      60  csc 0(Z)    0x161
#   64  lw  0(ZE)   0x181      68  sw  0(ZE)   0x181
#   72  lw  0(NP)   0x1B2      76  sw  0(NP)   0x1B3      80  clc 0(NP)   0x1B2
#   84  csc 0(NP)   0x1B3
#   88  lw  0(NPZ)  0x1D2  (NPZ = CAndPerm(Z, 0) in ca4: permission before bounds)
#   92  sw  0(NPZ)  0x1D3
#   96  lw  0(CClearTag(Z)) 0x1C2 (tag before bounds)
#   100 cjalr c0, ZX (ZX = CSetBounds(MTCC @ target, 0), ca5): the jump retires and the
#       fetch at the target faults: mtval 0x401, MEPCC.address = target; 104 MEPCC tag 0
#   105 cjalr c0, NPX (NPX = CAndPerm(MTCC @ .Lnpx_target, 0), ca5): 0x11 against ca5,
#       mtval 0x1F1, MEPCC.address = the cjalr
#   110 the stores at 48/52/60/76/84/92 left memory unchanged (marker words)
#   250 unexpected trap;  251 liveness (fewer checks executed than assembled)
#
# Register use: x0-x15 only; s1 check count; t0/t1/t2/s0 integer scratch. No cget*
# result goes into a live capability register (aN and caN are the same register).

#include "cheriot_dv.h"

    .option norelax

# One trapping probe: \insn must raise a CHERI exception with \mtval at its own pc.
.macro PROBE code, mtval, insn:vararg
    SET_VEC   .Ltrap\@, t0, t1
.Lfault\@:
    \insn
    li        a0, \code
    j         .Lexit
    .balign 4
.Ltrap\@:
    SET_VEC   .Lunexpected, t0, t1
    csrr      t1, mcause
    EXPECT_EQI t1, 28, (\code + 1)
    csrr      t1, mtval
    EXPECT_EQI t1, \mtval, (\code + 2)
    cspecialr a0, SCR_MEPCC
    cgetaddr  t1, a0
    LA_FAR    t0, .Lfault\@, a0
    EXPECT_EQ t1, t0, (\code + 3)
    RESUME    .Lnext\@, a0, t0
.Lnext\@:
.endm

    .text
    .globl main
main:
    li        s1, 0
    SET_VEC   .Lunexpected, t0, t1
    # marker words at obj (NP's target) and obj+16 (Z's target)
    DCAP_FAR  a4, obj, t0
    li        t1, 0x5A5A0000
    sw        t1, 0(a4)
    sw        t1, 16(a4)
    sw        t1, 20(a4)
    LA_FAR    s0, obj, t0                   # s0 = obj

    # ── Z, ZE, NP ────────────────────────────────────────────────────────────
    DCAP_FAR  a1, obj + 16, t0
    csetbounds a1, a1, zero                 # Z
    cgettag   t0, a1
    EXPECT_EQI t0, 1, 1
    cgetlen   t0, a1
    EXPECT_EQ t0, zero, 2
    addi      t1, s0, 16
    cgetbase  t0, a1
    EXPECT_EQ t0, t1, 3
    cgettop   t0, a1
    EXPECT_EQ t0, t1, 4
    cgetperm  t0, a1
    EXPECT_EQI t0, 0x7F, 5
    DCAP_FAR  a2, obj, t0
    li        t0, 32
    csetboundsexact a2, a2, t0              # P = [obj, obj+32)
    cincaddrimm a2, a2, 32                  # cursor at its top (representable)
    li        t0, 1
    csetbounds a4, a2, t0
    csetbounds a2, a2, zero                 # ZE
    cgettag   t0, a2
    EXPECT_EQI t0, 1, 6
    addi      t1, s0, 32
    cgetbase  t0, a2
    EXPECT_EQ t0, t1, 7
    cgetlen   t0, a2
    EXPECT_EQ t0, zero, 8
    cgettag   t0, a4
    EXPECT_EQ t0, zero, 9
    DCAP_FAR  a3, obj, t0
    candperm  a3, a3, zero                  # NP
    cgettag   t0, a3
    EXPECT_EQI t0, 1, 10
    cgetperm  t0, a3
    EXPECT_EQ t0, zero, 11
    cgetlen   t0, a3
    EXPECT_EQI t0, 0xFFFFFFFF, 12

    # ── bounds and address operations on Z ───────────────────────────────────
    csetbounds a4, a1, zero
    cgettag   t0, a4
    EXPECT_EQI t0, 1, 13
    csetboundsexact a4, a1, zero
    cgettag   t0, a4
    EXPECT_EQI t0, 1, 14
    csetboundsimm a4, a1, 0
    cgettag   t0, a4
    EXPECT_EQI t0, 1, 15
    csetboundsrndn a4, a1, zero
    cgettag   t0, a4
    EXPECT_EQI t0, 1, 16
    li        t1, 1
    csetbounds a4, a1, t1
    cgettag   t0, a4
    EXPECT_EQ t0, zero, 17
    cincaddrimm a4, a1, 1
    csetbounds a4, a4, zero
    cgettag   t0, a4
    EXPECT_EQ t0, zero, 18
    cincaddrimm a4, a1, 1
    cgettag   t0, a4
    EXPECT_EQI t0, 1, 19
    cincaddrimm a4, a1, -1
    cgettag   t0, a4
    EXPECT_EQ t0, zero, 20
    addi      t1, s0, 16 + 511
    csetaddr  a4, a1, t1
    cgettag   t0, a4
    EXPECT_EQI t0, 1, 21
    addi      t1, s0, 16 + 512
    csetaddr  a4, a1, t1
    cgettag   t0, a4
    EXPECT_EQ t0, zero, 22

    # ── operations on NP ─────────────────────────────────────────────────────
    li        t1, 16
    csetbounds a4, a3, t1
    cgettag   t0, a4
    EXPECT_EQI t0, 1, 23
    cgetperm  t0, a4
    EXPECT_EQ t0, zero, 24
    li        t1, 0xFFF
    candperm  a4, a3, t1
    cgetperm  t0, a4
    EXPECT_EQ t0, zero, 25
    cgettag   t0, a4
    EXPECT_EQI t0, 1, 26

    # ── sealing ──────────────────────────────────────────────────────────────
    cspecialr a0, SCR_MSCRATCHC
    li        t0, 9
    csetaddr  a0, a0, t0                    # ca0 = S@9
    cseal     a4, a1, a0
    cgettag   t0, a4
    EXPECT_EQI t0, 1, 27
    cgettype  t0, a4
    EXPECT_EQI t0, 9, 28
    cunseal   a4, a4, a0
    cgettag   t0, a4
    EXPECT_EQI t0, 1, 29
    cgetlen   t0, a4
    EXPECT_EQ t0, zero, 30
    DCAP_FAR  a5, obj, t0                   # ca5 = MTDC @ obj
    csetbounds a4, a0, zero                 # zero-length sealing authority
    cseal     a4, a5, a4
    cgettag   t0, a4
    EXPECT_EQ t0, zero, 31
    cseal     a5, a5, a0                    # ca5 = MTDC@obj sealed, otype 9
    csetbounds a4, a0, zero
    cunseal   a4, a5, a4
    cgettag   t0, a4
    EXPECT_EQ t0, zero, 32
    DCAP_FAR  a5, obj, t0
    candperm  a4, a0, zero                  # permission-less sealing authority
    cseal     a4, a5, a4
    cgettag   t0, a4
    EXPECT_EQ t0, zero, 33
    cseal     a5, a5, a0
    candperm  a4, a0, zero
    cunseal   a4, a5, a4
    cgettag   t0, a4
    EXPECT_EQ t0, zero, 34
    cseal     a4, a3, a0
    cgettag   t0, a4
    EXPECT_EQI t0, 1, 35

    # ── trapping data accesses ───────────────────────────────────────────────
    li        t2, 0x12345678                # store data (integer)
    mv        a5, t2                        # ca5 = untagged store data for csc
    PROBE     40, 0x161, lw t1, 0(a1)
    PROBE     44, 0x161, lb t1, 0(a1)
    PROBE     48, 0x161, sw t2, 0(a1)
    PROBE     52, 0x161, sb t2, 0(a1)
    PROBE     56, 0x161, clc a4, a1, 0
    PROBE     60, 0x161, csc a5, a1, 0
    PROBE     64, 0x181, lw t1, 0(a2)
    PROBE     68, 0x181, sw t2, 0(a2)
    PROBE     72, 0x1B2, lw t1, 0(a3)
    PROBE     76, 0x1B3, sw t2, 0(a3)
    PROBE     80, 0x1B2, clc a4, a3, 0
    PROBE     84, 0x1B3, csc a5, a3, 0
    candperm  a4, a1, zero                  # NPZ: zero length and no permissions
    PROBE     88, 0x1D2, lw t1, 0(a4)
    PROBE     92, 0x1D3, sw t2, 0(a4)
    ccleartag a4, a1
    PROBE     96, 0x1C2, lw t1, 0(a4)

    # ── jumps ────────────────────────────────────────────────────────────────
    LA_FAR    t0, .Lzx_target, t1
    cspecialr a5, SCR_MTCC
    csetaddr  a5, a5, t0
    csetbounds a5, a5, zero                 # ZX: zero-length executable
    SET_VEC   .Ltrap_zx, t0, t1
    jalr      zero, 0(a5)
    li        a0, 100
    j         .Lexit
    .balign 4
.Lzx_target:
    li        a0, 100                       # must not execute: outside PCC bounds
    j         .Lexit
    .balign 4
.Ltrap_zx:
    SET_VEC   .Lunexpected, t0, t1
    csrr      t1, mcause
    EXPECT_EQI t1, 28, 101
    csrr      t1, mtval
    EXPECT_EQI t1, 0x401, 102
    cspecialr a0, SCR_MEPCC
    cgetaddr  t1, a0
    LA_FAR    t0, .Lzx_target, a4
    EXPECT_EQ t1, t0, 103
    cgettag   t1, a0
    EXPECT_EQ t1, zero, 104
    RESUME    .Lafter_zx, a0, t0
.Lafter_zx:
    LA_FAR    t0, .Lnpx_target, t1
    cspecialr a5, SCR_MTCC
    csetaddr  a5, a5, t0
    candperm  a5, a5, zero                  # NPX: tagged, unsealed, no EX
    PROBE     105, 0x1F1, jalr zero, 0(a5)
    j         .Lafter_npx
    .balign 4
.Lnpx_target:
    li        a0, 105                       # must not execute: NPX has no EX
    j         .Lexit
.Lafter_npx:

    # ── 110: no faulting store wrote memory ──────────────────────────────────
    DCAP_FAR  a4, obj, t0
    lw        t0, 0(a4)
    lw        t1, 16(a4)
    xor       t0, t0, t1
    lw        t1, 20(a4)
    li        t2, 0x5A5A0000
    xor       t1, t1, t2
    or        t0, t0, t1
    lw        t1, 16(a4)
    xor       t1, t1, t2
    or        t0, t0, t1
    EXPECT_EQ t0, zero, 110

    CHECK_LIVENESS 251
    li        a0, 0
    j         .Lexit

    .balign 4
.Lunexpected:
    li        a0, 250
.Lexit:
    ret

    .data
    .balign 64
obj:
    .space  64
