# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# Test: cheriot_rand_operands -- self-randomising CHERIoT operand stimulus
# =============================================================================
# Fills the per-instruction operand crosses of cheriot_uarch_cg (fcov/core_ibex_fcov_if.sv),
# which the regression leaves almost empty: riscv-dv's riscv_cheriot_rand_instr_test is
# disabled (riscv_dv_extension/testlist.yaml), and the directed tests each hit a handful of
# bins. This program runs in CHERIoT mode from reset (+enable_cheriot_seq=1) with the
# CHERIoT-Sail cosim comparing every retired instruction (rd value and tag), so the program
# itself only has to (a) build operands of every class the crosses name, (b) survive the
# instructions that legally trap, and (c) prove it executed what it planned. Capability
# metadata (GAP-CS-6: the cosim compares rd value + tag only) is exposed to the comparison by
# a CGetHigh of every capability result.
#
# Randomness: an xorshift32 in tp, seeded from DV_SEED, which compile_test.py passes as
# -DDV_SEED=<UVM seed> (one program per seed); NOPS operations per run (default 600).
# -DNO_RAW_HIGH drops the raw CSetHigh-encoded operands from gen_cap, to tell a divergence
# on arbitrary untagged encodings from one on reachable capabilities.
# -DFAR_WINDOWS (test cheriot_rand_operands_far, run with +far_code_windows=1) adds the
# cjalr_det cases that land at the ends of the address space (see cjalr_det below).
#
# Each operation (main_loop) picks one of the groups below (weights out of 256) and builds
# fresh operands from the roots -- MTDC (memory), MTCC (execute), MScratchC (sealing) -- with
# CSetAddr/CSetBounds[Exact]/CAndPerm/CSeal/CClearTag/CSetHigh (gen_cap). Operand classes:
# root / E=24 bounded / E=1..14 / E=0 / zero length; base near 0, near 2^32 or anywhere;
# cursor at base, inside, top-1..top-7, at top, above top, below base, anywhere; random
# permission masks over all three roots (all 64 compressed encodings); sealed with every
# otype (executable 1-7, data 9-15); untagged; raw CSetHigh.
#   36 setbounds  CSetBounds x4 (req_len 0..8, = len, > len, = top-addr, +1, 9..1032, any),
#                 CSetBoundsExact, CSetBoundsRoundDown, CSetBoundsImm x7
#                 -> cheriot_csetbounds_cross1, cp_cheri_setbounds_cases
#   22 addr       CIncAddr (rs2 0, +, 0x80000000, -, -1), CIncAddrImm (0, 1, 2047, -2048,
#                 -2047, -2, -1), CSetAddr x2, AUICGP from c3 (7 imm20 classes)
#                 -> cheriot_cincaddr/_cincaddrimm/_csetaddr/_cauicgp_cross
#   16 cget       all 8 CGet* on a source whose address has 0..32 zero bits
#                 -> cheriot_cget_field_cross (CGetOffset excluded, see below)
#   14 csethigh   8 x CSetHigh with random rs2 -> cheriot_csethigh_cross0, cp_cheri_cd_cperms
#   22 seq        CSEQX / CTestSubset over 6 ordered pairs of 3 capabilities with explicit
#                 tag x otype, half of them E = 0 with raw T/B mantissas 0 / 0x1ff / other
#                 (GEN_TB) -> cheriot_cseqx_cross0/2, cheriot_ctestsubset_cross0/2
#   34 seal       4 x (sealing capability with chosen otype value 0..15/>=16 and position
#                 below/at base/inside/at top/above/zero length -- v = 0 also below the base,
#                 E = 24; SE dropped and untagged in all four combinations, US/GL/sealed random)
#                 against cs1 from MTCC (EX) and from MTDC: CSeal and CUnseal
#                 -> cheriot_cseal_cross0/1, cheriot_cunseal_cross0
#   12 bits       CRRL, CRAM, CSetBoundsRoundDown with rs1 of bit-size 0..32, tagged or not
#                 -> cheriot_crrl/_cram/_csetboundsrndn_cross
#   12 mem        CSC then CLC through an MTDC-derived capability inside `buf` (random
#                 SD/SL/MC/LD/LM/LG/GL, sealed, untagged, cursor in/out of bounds, misaligned),
#                 cs2 with GL random -> cheriot_csc_cross0, cheriot_clc_cross0
#   60 cjalr      2 x CJALR (rd c0/cra/ct1/ca5 x imm 0/2046/-2048/-8/-1) to one of four
#                 landing pads (pc mod 8 = 0/2/4/6) through a capability whose bounds put the
#                 target below/at the base, inside, top-1..7, at or above the top, or in a
#                 root/[0,0x81000000)/[0x80000000,2^32) capability; EX/SR dropped, sealed
#                 1-7/9-15, untagged; mstatus.MIE random
#                 -> cheriot_cjalr_cross0/1, cp_cheri_cjalr_bound
#   10 cjal       CJAL inside a bounded PCC: forward to top-k/at/above the top, backward to
#                 at/inside/below the base; and from E=24 PCCs -> cp_cheri_cjal_bound
#    6 auipcc     AUIPCC with 7 imm20 classes from a root, an E=0, an E=2 and an E=5 PCC
#                 -> cheriot_cauipcc_cross, cp_cheri_pcc_exp
#   12 misc       CAndPerm (random mask), CMove, CClearTag, CSub
# -DONLY_LDST (test cheriot_rand_ldst) replaces the mix above with one group:
#      ldst       LB/LBU/LH/LHU/LW/CLC/SB/SH/SW/CSC at byte distance -10..10 from the base or
#                 the top of the authority, needed permission dropped or kept, authority valid /
#                 untagged / sealed -> cheri_access_bounds_cg (all crosses). Below-base cursors
#                 use an E = 24 authority, the only one whose representable range includes them.
# Once, before the loop, in this order (each block is described where it is defined):
#   scr_sweep, setbounds_det (below);
#   bits_det: CRRL/CRAM/CSetBoundsRoundDown on a tagged rs1 of every bit-size 0..32, and
#     CSetBounds[Imm] on two untagged raw E = 24 sources (base above top, zero length);
#   cjalr_det (gen_cjalr_det.py): CJALR over the tag x EX x bound value x immediate class bins
#     of cheriot_cjalr_cross1 -- every attempt traps, except those whose target is in a landing
#     zone the block writes at 0x80FFFF80 (it counts the instructions run there); with
#     -DFAR_WINDOWS also in zones at 0 and just below 2^32 (+far_code_windows=1);
#   cjalr_ot_det: CJALR over cs1 tag x otype 0..7 x rd x imm x MIE (cheriot_cjalr_cross0);
#   addr_det: the address group on base-0, top-of-memory and wrapped-base cs1 at E = 0 and 1,
#     an untagged sealed E = 4 cs1 at its base, and a raw E = 0 cs1 whose base wraps above it.
# Once, before the loop (setbounds_det): CSetBounds requests 0..9 over fixed sources -- exact
# E = 0 lengths 1..3 at base/base+1/top, sealed and unsealed at base for E = 0/4/24, E = 24 below
# the base and at the top -> the combinations of cheriot_csetbounds_cross1 the random classes
# rarely produce.
# Once, before the loop (scr_sweep): CSpecialRW on SCR 28/29/30/31 and an undefined SCR,
# with cs1 in {c0, ct2, ca5} x cd in {c0, ct1, ca5}, from a PCC with and one without SR
# (90 combinations) -> cheriot_cspecialrw_cross. Values written are the values read, so
# the SCRs never change.
#
# Traps: the instructions that may legally trap (CJALR and its target fetch, CSC, CLC, CJAL
# target fetch, CSpecialRW without SR or of an undefined SCR) are each preceded by setting
# s0 to the address to resume at; bit 0 of s0 also admits mcause 2 (illegal instruction,
# the undefined-SCR cases), bit 1 mcause 4/6 (CLC/CSC through a capability that passes every
# check but alignment: misaligned is checked after tag/seal/perm/bounds, as in CHERIoT-Sail). The handler (MTCC) resumes there through MEPCC = MTCC with that
# cursor and clears s0. Everything else must not trap.
#
# Not stimulated, with the reason (for ignore_bins / UNR review -- see the report):
#   CGetOffset (rs2 = 6): the RTL implements it, CHERIoT-Sail has no such instruction
#     (cheriot_illegal_sweep_sail_only), so executing it is a cosim mismatch by design.
#   CJALR/CJAL targets within 7 bytes of a top at 2^32 or at 0x81000000, or near a top
#     of a [0, T) capability: a jump that is taken would fetch unmapped memory, where the
#     testbench returns c.unimp and the model does not. CJALR uses such targets only with an
#     untagged, EX-less or non-sentry-sealed (otype 6/7) cs1, which faults before the jump;
#     CJAL always jumps, so those cp_cheri_cjal_bound bins are left to a memory-map waiver.
#     For the same reason the default build of cjalr_det leaves out the 63 tagged + EX bins of
#     cheriot_cjalr_cross1 whose target is fetched in bounds within 7 bytes of 0 or of 2^32
#     (cp_cheri_cjalr_bound 0x0a0/0x0c0/0x0e0 bin1-5, 0x0a2 bin1/2/5, 0x0c2/0x0e2 bin1/2/4/5,
#     0x102/0x182 bin1-5, 0x122/0x132/0x142/0x152/0x162 bin1/2/4/5, 0x172 bin1/2/5,
#     0x130/0x150 bin2, 0x170 bin2/4). They are NOT waived: cheriot_rand_operands_far
#     (-DFAR_WINDOWS, +far_code_windows=1, under which CHERIoT-Sail maps [0, 0x1000) and
#     [0x80000000, 2^32)) lands them in zones at 0 and just below 2^32, together with 24 bins
#     the random cjalr group also hits. `gen_cjalr_det.py -v` lists every bin the default
#     build leaves uncovered, each tagged with its reason: "far" (the 87 above), one of the
#     five unreachable groups of the fcov closure review (172 bins), or "random loop".
#
# Checks and failure codes (the cosim checks every value; these check the run itself):
#    2  a trap with s0 = 0, i.e. outside a designated trapping instruction
#    3  a trap with mcause other than 28 (or 2 where admitted); also every "must not fall
#       through" point is an ebreak (mcause 3), so this is the fall-through check for the
#       bounded-PCC blocks, the no-SR CSpecialRW and the CSpecialRW of undefined SCRs
#    4  a CJALR neither jumped nor trapped (it fell through with the landing flag t2 clear)
#    9  debug entry
#   10  liveness: completed operations (s1, counted in op_done) != NOPS
#   11  liveness: cjalr_det attempts completed (s1, before the loop) != CJD_NTRY (plus
#       CJD_NTRY_FAR with -DFAR_WINDOWS)
#   12  no CJALR under test raised its own fault (tag/seal/EX, against cs1: mtval[10] = 0;
#       target-fetch faults are against PCC, mtval[10] = 1, and are counted apart in
#       ST_CJFETCH)
#   13  no CJALR under test landed (they all jump through ca1; nothing else does)
#   14  ONLY_LDST: no access completed      15  ONLY_LDST: no access faulted
#   16  cjalr_det landing: the number of c.addi run at the target != the model's
#   17  cjalr_det landing: returned through ca5 where the fetch must leave PCC's bounds, or
#       trapped where it must return (in the top zone: the c.beqz at 2^32 - 2 not fetched, or
#       its target CJ_TRET outside PCC's bounds)
#   18  cjalr_det: a CJALR attempt trapped with an mtval other than the model's (cs1 << 5 |
#       0x02 untagged / 0x11 no EX; 0x401 for the target fetch)
#   19  CSetBounds/CSetBoundsImm of an untagged cs1 returned a tagged result (bits_det)
#   20  CGetHigh(CSetHigh(c, x)) != x   21  CSetHigh result tagged
#   22  CSEQX(c, c) != 1 / CSEQX(CMove(c), c) != 1
#   23  CClearTag result tagged         24  CTestSubset(c, c) != 1
#   25  tagged CSetBounds* result from a tagged cs1 that is not CTestSubset of cs1
#   26  CAndPerm result has a permission not in cs1.perms & rs2
#   27  tagged CUnseal result still sealed
#
# Register use (x0-x15 only): tp = LFSR state, s0 = trap resume address (0 = none
# expected), s1 = completed operations (in cjalr_det: attempts), sp = traps taken, gp = AUICGP
# source (c3), a1/a2/a3 = operands and result, a5 = return capability, t0-t2/a0/a4 scratch.

#include "cheriot_dv.h"

    .option norelax
    .option norvc

#ifndef DV_SEED
#define DV_SEED 1
#endif
#ifndef NOPS
#define NOPS 600
#endif

#define ST_ITER    0
#define ST_LANDED  4
#define ST_CJTRAP  8
#define ST_CJFETCH 12
#define ST_LDOK    16

#define GF_SEAL  1
#define GF_UNTAG 2
#define GF_PERM  4
#define GF_ALL   7
#define GF_MTDC  8
#define GF_MTCC  16
#define GF_MSCR  24

#define PERM_NO_GL 0xFFE
#define PERM_NO_SR 0xF7F
#define PERM_NO_EX 0xEFF
#define PERM_NO_US 0xDFF
#define PERM_NO_SE 0xBFF

# ---- Instructions not in cheriot_dv.h (cheri_insts.sail encdec 1063-1064, 1093) ----------
.macro crrl rd, rs1
    .insn r 0x5b, 0, 0x7f, \rd, \rs1, x8
.endm
.macro cram rd, rs1
    .insn r 0x5b, 0, 0x7f, \rd, \rs1, x9
.endm
.macro csub rd, cs1, cs2
    .insn r 0x5b, 0, 0x14, \rd, \cs1, \cs2
.endm

# ---- Randomness ---------------------------------------------------------------------------
# \rd := next xorshift32 value (tp is the state). \rd must not be tp.
.macro RAND rd
    slli    \rd, tp, 13
    xor     tp, tp, \rd
    srli    \rd, tp, 17
    xor     tp, tp, \rd
    slli    \rd, tp, 5
    xor     tp, tp, \rd
    mv      \rd, tp
.endm
# \rd := uniform in [0, n). \tmp is clobbered, distinct from \rd.
.macro RANDN rd, n, tmp
    RAND    \rd
    li      \tmp, \n
    mulhu   \rd, \rd, \tmp
.endm

# Weighted dispatch on t2 in [0, 256): goto \label if t2 < \lim. Clobbers t1.
.macro PICK lim, label
    li      t1, \lim
    bgeu    t2, t1, .Lpk\@
    j       \label
.Lpk\@:
.endm

# stats[\off] += 1. Clobbers a0, t0.
.macro INC_STAT off
    DCAP_FAR a0, stats, t0
    lw      t0, \off(a0)
    addi    t0, t0, 1
    sw      t0, \off(a0)
.endm

.macro FAIL code
    li      a0, \code
    j       test_end
.endm

# =============================================================================================
    DV_VECTORS unexpected_debug, unexpected_debug
_start:
    SET_VEC   trap_handler, t1, t0
    li        t0, 0x1800                # mstatus.MPP = M
    csrs      mstatus, t0
    li        s0, 0
    li        s1, 0
    li        sp, 0
    li        t0, (DV_SEED) & 0xffffffff
    li        t1, 0x9E3779B9
    mul       tp, t0, t1
    li        t1, 0x2545F491
    xor       tp, tp, t1
    bnez      tp, 1f
    li        tp, 1
1:  j         scr_sweep

    .text
# =============================================================================================
# Trap handler (MTCC). Resumes at s0 & ~3 with a PCC derived from MTCC.
    .balign 4
trap_handler:
    beqz      s0, .Lh_unexpected
    addi      sp, sp, 1
    csrr      t0, mcause
    li        t1, MCAUSE_CHERI
    beq       t0, t1, .Lh_resume
    andi      t1, s0, 2
    beqz      t1, 1f
    li        t1, MCAUSE_LOAD_MISALIGN
    beq       t0, t1, .Lh_resume
    li        t1, MCAUSE_STORE_MISALIGN
    beq       t0, t1, .Lh_resume
1:  andi      t1, s0, 1
    beqz      t1, .Lh_badcause
    li        t1, 2
    bne       t0, t1, .Lh_badcause
.Lh_resume:
    andi      s0, s0, -4
    cspecialr t0, SCR_MTCC
    csetaddr  t0, t0, s0
    cspecialw SCR_MEPCC, t0
    li        s0, 0
    mret
.Lh_unexpected:
    FAIL      2
.Lh_badcause:
    FAIL      3

unexpected_debug:
    FAIL      9

# =============================================================================================
# CSpecialRW sweep: {28, 29, 30, 31, undefined} x cs1 {c0, ct2, ca5} x cd {c0, ct1, ca5},
# with PCC.SR and without.
.macro SR_GOOD scr, rd, rs1
  .ifnc \rs1, x0
    cspecialr \rs1, \scr                # write back what is there: the SCR does not change
  .endif
    cspecialrw \rd, \scr, \rs1
.endm
.macro SR_BAD scr, rd, rs1
    LA_FAR    s0, .Lsb\@, t0
    ori       s0, s0, 1                 # mcause 2 admitted
    cspecialrw \rd, \scr, \rs1
    ebreak                              # an undefined SCR must trap
.Lsb\@:
    nop                                 # resume labels start with a nop (see op_done)
.endm
# Without SR: jump (a4 = MTCC without SR) to the instruction, which must trap; the
# instruction lives in .text subsection 1, out of line.
.macro NOSR scr, rd, rs1, bad
    LA_FAR    t1, .Lnsi\@, t0
    csetaddr  a2, a4, t1
    LA_FAR    s0, .Lnsr\@, t0
    ori       s0, s0, \bad
    jalr      x0, 0(a2)
    ebreak
    .pushsection .text, 1
.Lnsi\@:
    cspecialrw \rd, \scr, \rs1
    ebreak
    .popsection
.Lnsr\@:
    nop
.endm

scr_sweep:
    .irp scr, 28, 29, 30, 31
    .irp rd, x0, t1, a5
    .irp rs1, x0, t2, a5
    SR_GOOD   \scr, \rd, \rs1
    .endr
    .endr
    .endr
    SR_BAD     0, x0, x0
    SR_BAD     1, x0, t2
    SR_BAD     2, x0, a5
    SR_BAD     5, t1, x0
    SR_BAD     8, t1, t2
    SR_BAD    13, t1, a5
    SR_BAD    16, a5, x0
    SR_BAD    20, a5, t2
    SR_BAD    23, a5, a5
    cspecialr a4, SCR_MTCC
    li        t0, PERM_NO_SR
    candperm  a4, a4, t0
    .irp scr, 28, 29, 30, 31
    .irp rd, x0, t1, a5
    .irp rs1, x0, t2, a5
    NOSR      \scr, \rd, \rs1, 0
    .endr
    .endr
    .endr
    NOSR       3, x0, x0, 1
    NOSR       4, x0, t2, 1
    NOSR       6, x0, a5, 1
    NOSR       9, t1, x0, 1
    NOSR      12, t1, t2, 1
    NOSR      17, t1, a5, 1
    NOSR      19, a5, x0, 1
    NOSR      22, a5, t2, 1
    NOSR       0, a5, a5, 1
    j         setbounds_det

# =============================================================================================
main_loop:
    DCAP_FAR  a0, stats, t0
    lw        t0, ST_ITER(a0)
    li        t1, NOPS
    bltu      t0, t1, 1f
    j         all_done
1:  addi      t0, t0, 1
    sw        t0, ST_ITER(a0)
#ifdef ONLY_LDST
    j         op_ldst
#endif
    RAND      t2
    andi      t2, t2, 255
    PICK      36,  op_setbounds
    PICK      58,  op_addr
    PICK      74,  op_cget
    PICK      88,  op_csethigh
    PICK      110, op_seq
    PICK      144, op_seal
    PICK      156, op_bits
    PICK      168, op_mem
    PICK      228, op_cjalr
    PICK      238, op_cjal
    PICK      244, op_auipcc
    j         op_misc

# Every operation ends here, by a jump or a trap resume. The count is the first instruction;
# every other trap-resume label starts with a nop, so a resume that lands one instruction
# late is only visible here, as a liveness failure.
op_done:
    addi      s1, s1, 1
    li        s0, 0
    j         main_loop

all_done:
    csrw      mscratch, sp              # traps taken, for the log
    li        t0, NOPS
    beq       s1, t0, 1f
    FAIL      10
1:  DCAP_FAR  a1, stats, t0
#ifdef ONLY_LDST
    lw        t0, ST_LDOK(a1)           # some accesses completed, and some faulted
    bnez      t0, 2f
    FAIL      14
2:  li        t1, NOPS
    bltu      t0, t1, 3f
    FAIL      15
#else
    lw        t0, ST_CJTRAP(a1)
    bnez      t0, 2f
    FAIL      12
2:  lw        t0, ST_LANDED(a1)
    bnez      t0, 3f
    FAIL      13
#endif
3:  li        a0, 0
test_end:
    SIG_INIT
    TEST_END_A0

# =============================================================================================
# gen_cap: a1 := random capability. a0 = flags (GF_*; bits 4:3 pick the root, 0 = random).
# Clobbers a0, a4, t0, t1, t2 (t0 also as a capability). Called with jal ra.
gen_cap:
    mv        a4, a0
    srli      t1, a4, 3
    andi      t1, t1, 3
    bnez      t1, 1f
    RANDN     t1, 3, t0
    addi      t1, t1, 1
1:  addi      t1, t1, -2
    beqz      t1, 2f
    addi      t1, t1, -1
    beqz      t1, 3f
    cspecialr a1, SCR_MTDC
    j         4f
2:  cspecialr a1, SCR_MTCC
    j         4f
3:  cspecialr a1, SCR_MSCRATCHC
4:  RAND      t1                        # bounds class
    andi      t1, t1, 7
    beqz      t1, .Lg_root
    addi      t1, t1, -1
    beqz      t1, .Lg_e24
    addi      t1, t1, -1
    beqz      t1, .Lg_mid
    addi      t1, t1, -1
    beqz      t1, .Lg_mid
    addi      t1, t1, -4
    beqz      t1, .Lg_zero
    RAND      t0                        # E = 0: length 0..8 (1/4) or 0..511
    andi      t0, t0, 3
    bnez      t0, 5f
    RANDN     t2, 9, t0
    j         .Lg_base
5:  RAND      t2
    andi      t2, t2, 511
    j         .Lg_base
.Lg_zero:
    li        t2, 0
.Lg_base:                               # t2 = length <= 511; pick a base
    RAND      t0
    andi      t1, t0, 3
    srli      t0, t0, 2
    beqz      t1, 6f
    addi      t1, t1, -1
    beqz      t1, 7f
    RAND      t0                        # anywhere, base + len < 2^32
    li        t1, 0xFFFFFC00
    bltu      t0, t1, 8f
    addi      t0, t0, -1024
    j         8f
6:  slli      t0, t0, 20                # near 0
    srli      t0, t0, 20
    j         8f
7:  slli      t0, t0, 20                # near 2^32: [0xFFFFEE00, 0xFFFFFDFF]
    srli      t0, t0, 20
    li        t1, 0xFFFFEE00
    add       t0, t0, t1
8:  csetaddr  a1, a1, t0
    RAND      t0
    andi      t0, t0, 7
    bnez      t0, 1f
    csetboundsexact a1, a1, t2
    j         .Lg_pos
1:  csetbounds a1, a1, t2
    j         .Lg_pos
.Lg_e24:                                # base k << 24, length (1..64) << 24
    RAND      t0
    andi      t0, t0, 0x7f
    slli      t0, t0, 24
    csetaddr  a1, a1, t0
    RAND      t2
    andi      t2, t2, 0x3f
    addi      t2, t2, 1
    slli      t2, t2, 24
    csetbounds a1, a1, t2
    j         .Lg_pos
.Lg_mid:                                # E = 1..14: length [256, 511] << E, base 2^E-aligned
    RANDN     t1, 14, t0
    addi      t1, t1, 1
    RAND      t2
    andi      t2, t2, 255
    ori       t2, t2, 256
    sll       t2, t2, t1
    RAND      t0
    srl       t0, t0, t1
    sll       t0, t0, t1
    slli      t0, t0, 1
    srli      t0, t0, 1
    csetaddr  a1, a1, t0
    csetbounds a1, a1, t2
    j         .Lg_pos
.Lg_root:                               # root bounds, address 0 / ~(0..15) / anywhere
    RAND      t0
    andi      t1, t0, 3
    beqz      t1, 1f
    addi      t1, t1, -1
    beqz      t1, 2f
    RAND      t0
    j         3f
1:  li        t0, 0
    j         3f
2:  srli      t0, t0, 2
    andi      t0, t0, 15
    not       t0, t0
3:  csetaddr  a1, a1, t0
    j         .Lg_mods
.Lg_pos:                                # cursor relative to the bounds actually set
    cgetbase  t1, a1
    cgetlen   t2, a1
    RAND      a0
    andi      t0, a0, 7
    srli      a0, a0, 3
    beqz      t0, .Lp_base
    addi      t0, t0, -1
    beqz      t0, .Lp_in
    addi      t0, t0, -1
    beqz      t0, .Lp_room
    addi      t0, t0, -1
    beqz      t0, .Lp_top
    addi      t0, t0, -1
    beqz      t0, .Lp_above
    addi      t0, t0, -1
    beqz      t0, .Lp_below
    addi      t0, t0, -1
    beqz      t0, .Lp_far
.Lp_in:
    slli      a0, a0, 3
    mulhu     t0, a0, t2
    add       t0, t0, t1
    j         .Lp_set
.Lp_base:
    mv        t0, t1
    j         .Lp_set
.Lp_room:                               # top - 0..7
    andi      t0, a0, 7
    sub       t0, t2, t0
    add       t0, t0, t1
    j         .Lp_set
.Lp_top:
    add       t0, t1, t2
    j         .Lp_set
.Lp_above:                              # top + 1..32
    andi      t0, a0, 31
    addi      t0, t0, 1
    add       t0, t0, t2
    add       t0, t0, t1
    j         .Lp_set
.Lp_below:                              # base - 1..32
    andi      t0, a0, 31
    addi      t0, t0, 1
    sub       t0, t1, t0
    j         .Lp_set
.Lp_far:
    RAND      t0
.Lp_set:
    csetaddr  a1, a1, t0
.Lg_mods:
    andi      t0, a4, GF_PERM
    beqz      t0, 2f
    RAND      t0                        # 1/4: random permission mask
    andi      t1, t0, 3
    bnez      t1, 1f
    srli      t0, t0, 2
    candperm  a1, a1, t0
1:  RAND      t0                        # 1/8: clear GL only
    andi      t0, t0, 7
    bnez      t0, 2f
    li        t0, PERM_NO_GL
    candperm  a1, a1, t0
2:  andi      t0, a4, GF_SEAL
    beqz      t0, 4f
    RAND      t0                        # 1/4: seal, otype 1-7 (EX) or 9-15
    andi      t1, t0, 3
    bnez      t1, 4f
    srli      t0, t0, 2
    li        t1, 7
    remu      t2, t0, t1
    addi      t2, t2, 1
    cgetperm  t1, a1
    andi      t1, t1, 0x100
    bnez      t1, 3f
    addi      t2, t2, 8
3:  cspecialr t0, SCR_MSCRATCHC
    csetaddr  t0, t0, t2
    cseal     a1, a1, t0
4:  andi      t0, a4, GF_UNTAG
    beqz      t0, 6f
    RAND      t0
    andi      t1, t0, 7                 # 1/8: CClearTag
    bnez      t1, 5f
    ccleartag a1, a1
    j         6f
5:
#ifndef NO_RAW_HIGH                     /* -DNO_RAW_HIGH: no raw-encoded operands (triage) */
    andi      t1, t0, 0x78              # 1/16 of the rest: CSetHigh of a random word
    bnez      t1, 6f
    RAND      t0
    csethigh  a1, a1, t0
#endif
6:  ret

# \rd := 0 | 0x1ff | 1..0x1fe, each 1/3. Clobbers t0, t1.
.macro TB_MANT rd
    RANDN     t1, 3, t0
    li        \rd, 0
    beqz      t1, .Ltm\@
    li        \rd, 0x1ff
    addi      t1, t1, -1
    beqz      t1, .Ltm\@
    RANDN     \rd, 510, t0
    addi      \rd, \rd, 1
.Ltm\@:
.endm

# a1 := tagged E = 0 capability from MTDC with mantissas B and T drawn by TB_MANT: base[8:0] = B,
# length (T - B) mod 512 (<= 511, exact), base < 2^31. CSEQX/CTestSubset sample the raw 9-bit
# T and B (cheriot_cseqx_cross2/_ctestsubset_cross2: 0, 0x1ff, other), which gen_cap gives 0 or
# 0x1ff only by chance. Clobbers a0, t0, t1, t2.
.macro GEN_TB
    TB_MANT   t2
    TB_MANT   a0
    sub       a0, a0, t2
    andi      a0, a0, 0x1ff
    RAND      t0
    srli      t0, t0, 10
    slli      t0, t0, 9
    or        t0, t0, t2
    cspecialr a1, SCR_MTDC
    csetaddr  a1, a1, t0
    csetboundsexact a1, a1, a0
.endm

# a1 := capability with an explicitly random tag and otype (0-7; data caps 9-15) and GL.
# \flags: gen_cap flags (root in bits 4:3). \tb = 1: half the time the source is GEN_TB instead
# of gen_cap. Clobbers a0, a4, t0, t1, t2, ra.
.macro GEN_OT flags=GF_PERM, tb=0
  .if \tb
    RAND      t0
    andi      t0, t0, 1
    beqz      t0, .Lot0\@
    GEN_TB
    j         .Lot1\@
.Lot0\@:
  .endif
    li        a0, \flags
    jal       ra, gen_cap
    cgettag   t0, a1
    bnez      t0, .Lot1\@
    cspecialr a1, SCR_MTDC              # the class left it untagged: fall back to a root
.Lot1\@:
    RAND      t0
    andi      t1, t0, 1
    beqz      t1, .Lot2\@
    li        t1, PERM_NO_GL
    candperm  a1, a1, t1
.Lot2\@:
    srli      t0, t0, 1
    andi      t2, t0, 7
    beqz      t2, .Lot3\@
    cgetperm  t1, a1
    andi      t1, t1, 0x100
    bnez      t1, .Lot4\@
    addi      t2, t2, 8
.Lot4\@:
    cspecialr t1, SCR_MSCRATCHC
    csetaddr  t1, t1, t2
    cseal     a1, a1, t1
.Lot3\@:
    srli      t0, t0, 3
    andi      t0, t0, 1
    bnez      t0, .Lot5\@
    ccleartag a1, a1
.Lot5\@:
.endm

# =============================================================================================
# Request-length classes for CSetBounds of a1: a2 := length. Clobbers t0, t1, t2.
.macro RQLEN
    RANDN     t1, 8, t0
    cgetlen   t2, a1
    beqz      t1, .Lrq_l\@
    addi      t1, t1, -1
    beqz      t1, .Lrq_l\@
    addi      t1, t1, -1
    beqz      t1, .Lrq_len\@
    addi      t1, t1, -1
    beqz      t1, .Lrq_gt\@
    addi      t1, t1, -1
    beqz      t1, .Lrq_fit\@
    addi      t1, t1, -1
    beqz      t1, .Lrq_fit1\@
    addi      t1, t1, -1
    beqz      t1, .Lrq_mid\@
    RAND      a2
    j         .Lrq_end\@
.Lrq_l\@:
    RANDN     a2, 9, t0
    j         .Lrq_end\@
.Lrq_len\@:
    mv        a2, t2
    j         .Lrq_end\@
.Lrq_gt\@:
    RAND      t0
    andi      t0, t0, 7
    addi      t0, t0, 1
    add       a2, t2, t0
    j         .Lrq_end\@
.Lrq_fit\@:
    cgettop   a2, a1
    cgetaddr  t0, a1
    sub       a2, a2, t0
    j         .Lrq_end\@
.Lrq_fit1\@:
    cgettop   a2, a1
    cgetaddr  t0, a1
    sub       a2, a2, t0
    addi      a2, a2, 1
    j         .Lrq_end\@
.Lrq_mid\@:
    RAND      a2
    andi      a2, a2, 1023
    addi      a2, a2, 9
.Lrq_end\@:
.endm

# Monotonicity: a tagged result a3 from a tagged a1 is a subset of a1. Clobbers t0.
.macro MONO_CHECK
    cgethigh  t0, a3
    cgettag   t0, a3
    beqz      t0, .Lmc\@
    cgettag   t0, a1
    beqz      t0, .Lmc\@
    ctestsubset t0, a1, a3
    bnez      t0, .Lmc\@
    FAIL      25
.Lmc\@:
.endm

# =============================================================================================
# A positive increment: 1..16, up to 2^23, or [2^30, 2^31). Clobbers t0, t1.
.macro POSINC rd
    RANDN     t1, 3, t0
    RAND      \rd
    beqz      t1, .Lpi_s\@
    addi      t1, t1, -1
    beqz      t1, .Lpi_m\@
    slli      \rd, \rd, 2
    srli      \rd, \rd, 2
    li        t0, 0x40000000
    or        \rd, \rd, t0
    j         .Lpi_e\@
.Lpi_s\@:
    andi      \rd, \rd, 15
    addi      \rd, \rd, 1
    j         .Lpi_e\@
.Lpi_m\@:
    slli      \rd, \rd, 9
    srli      \rd, \rd, 9
    ori       \rd, \rd, 1
.Lpi_e\@:
.endm

# CIncAddr/CIncAddrImm/CSetAddr/AUICGP of a1 over the increment classes of the address crosses.
# Clobbers a2, a3, gp, t0, t1, t2.
.macro ADDR_OPS
    li        a2, 0
    cincaddr  a3, a1, a2
    cgethigh  t0, a3
    POSINC    a2
    cincaddr  a3, a1, a2
    cgethigh  t0, a3
    li        a2, 0x80000000
    cincaddr  a3, a1, a2
    cgethigh  t0, a3
    POSINC    a2
    neg       a2, a2
    cincaddr  a3, a1, a2
    cgethigh  t0, a3
    li        a2, -1
    cincaddr  a3, a1, a2
    cgethigh  t0, a3
    .irp imm, 0, 1, 2047, -2048, -2047, -2, -1
    cincaddrimm a3, a1, \imm
    cgethigh  t0, a3
    .endr
    cgetaddr  a2, a1
    POSINC    t2
    RAND      t1
    andi      t1, t1, 1
    beqz      t1, 1f
    neg       t2, t2
1:  add       a2, a2, t2
    csetaddr  a3, a1, a2
    cgethigh  t0, a3
    RAND      a2
    csetaddr  a3, a1, a2
    cgethigh  t0, a3
    cmove     gp, a1
    .irp imm, 0, 1, 0x7ffff, 0x80000, 0x80001, 0xffffe, 0xfffff
    auicgp    a3, \imm
    cgethigh  t0, a3
    .endr
.endm

# =============================================================================================
# setbounds_det: once, before the loop. CSetBounds over operand combinations the random
# classes produce too rarely (uarch triage of cheriot_csetbounds_cross1): exact small E = 0
# lengths with the request just above the length, sealed sources with the cursor at base, and
# E = 24 sources with the cursor below the base or at the top. Every request 0..9 for each, so
# the req_len bins little[0..8] and `other` are all crossed. CSetBounds never traps.
#   \base/\len build an MTDC-derived capability; \cur is the cursor relative to \base;
#   \seal = 1 seals it with data otype 9 first.
.macro SB_SWEEP base, len, cur, seal
    cspecialr a1, SCR_MTDC
    li        t0, \base
    csetaddr  a1, a1, t0
    li        t2, \len
    csetbounds a1, a1, t2
    li        t0, \base + \cur
    csetaddr  a1, a1, t0
    .if \seal
    cspecialr t0, SCR_MSCRATCHC
    li        t1, 9
    csetaddr  t0, t0, t1
    cseal     a1, a1, t0
    .endif
    .irp req, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9
    li        a2, \req
    csetbounds a3, a1, a2
    MONO_CHECK
    .endr
.endm

setbounds_det:
    # E = 0, length 1..3: cursor at base, base + 1 and top; requests above the length
    .irp len, 1, 2, 3
    .irp cur, 0, 1, \len
    SB_SWEEP  0x80010000, \len, \cur, 0
    .endr
    .endr
    # Cursor at base, unsealed and sealed: E = 0 (length 16), E = 4 (length 0x1000),
    # E = 24 (base 1 << 24, length 1 << 25)
    .irp seal, 0, 1
    SB_SWEEP  0x80020000, 16, 0, \seal
    SB_SWEEP  0x80100000, 0x1000, 0, \seal
    SB_SWEEP  0x01000000, 0x02000000, 0, \seal
    .endr
    # E = 24 (base 2 << 24, length 1 << 24): cursor below the base (inside the representable
    # range, which only E = 24 allows), and at the top, unsealed and sealed
    SB_SWEEP  0x02000000, 0x01000000, -0x100, 0
    .irp seal, 0, 1
    SB_SWEEP  0x02000000, 0x01000000, 0x01000000, \seal
    .endr
    j         bits_det

# =============================================================================================
# bits_det: once, before the loop. CRRL, CRAM and CSetBoundsRoundDown on a tagged rs1 (the MTDC
# root: every address representable) of each bit-size 0..32, as the lowest (1 << (k-1)) and the
# highest ((1 << k) - 1) value of that size -> the tagged half of cheriot_crrl/_cram/
# _csetboundsrndn_cross, which op_bits reaches about twice per value per regression. Length 0
# keeps the CSetBoundsRoundDown result in bounds at any address. Nothing traps.
.macro BITS_ONE val
    cspecialr a1, SCR_MTDC
    li        t0, \val
    csetaddr  a1, a1, t0
    crrl      a3, a1
    cram      a3, a1
    li        a2, 0
    csetboundsrndn a3, a1, a2
    MONO_CHECK
.endm

# Then CSetBounds and CSetBoundsImm (request 1) on an untagged cs1 with raw CSetHigh metadata
# \meta at address \addr, for the cp_cheri_setbounds_cases / _setboundsimm_cases values no
# tagged cs1 gives. The result is derived from cs1, whose tag is clear, so it must be untagged
# too (cheri_insts.sail CSetBounds/CSetBoundsImmediate; failure code 19).
.macro SB_RAW addr, meta
    cspecialr a1, SCR_MTDC
    li        t0, \addr
    csetaddr  a1, a1, t0
    li        t0, \meta
    csethigh  a1, a1, t0
    li        a2, 1
    csetbounds a3, a1, a2
    cgettag   t0, a3
    beqz      t0, .Lsr1\@
    FAIL      19
.Lsr1\@:
    csetboundsimm a3, a1, 1
    cgettag   t0, a3
    beqz      t0, .Lsr2\@
    FAIL      19
.Lsr2\@:
.endm

bits_det:
    BITS_ONE  0
    .irp k, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32
    BITS_ONE  (1 << (\k - 1))
    BITS_ONE  ((1 << (\k - 1)) - 1 + (1 << (\k - 1)))
    .endr
    # Metadata {cperms 0x3F, otype 0, E 15 (= 24), T, B}: base32 = B << 24 mod 2^32,
    # top33 = T << 24.
    # B = 0x120, T = 0x010: base 0x20000000 above top 0x10000000, cursor at the base; the 33-bit
    # length wraps above 2^32, so any request fits -> case 22 (b4 | b2 | b1)
    SB_RAW    0x20000000, 0x7E3C2120
    # B = T = 0x090: zero length at 0x90000000, cursor 0x80000000 below it, request 1 > length 0
    # -> case 1 (b0 only)
    SB_RAW    0x80000000, 0x7E3D2090
    j         cjalr_det

# =============================================================================================
# cjalr_det: once, before the loop. CJALR over the bins of cheriot_cjalr_cross1 (cs1 tag x EX x
# cp_cheri_cjalr_bound x imm12 class) that the random cj_build reaches too rarely (uarch triage
# 2026-10-04, fcov closure 2026-10-07). The cases are generated by gen_cjalr_det.py
# (cjalr_det_cases.inc) from its model of the CHERIoT-Sail semantics, which gives every bound
# value and every expected result below. Each case builds cs1 in ca1 and runs, as far as it can:
#   - without EX, untagged without EX, and untagged: CJALR faults on cs1 itself, mtval = cs1 << 5
#     | 0x11 (PermitExecuteViolation) or | 0x02 (TagViolation);
#   - tagged with EX, target fetch out of bounds: the jump happens and the fetch faults against
#     PCC (mtval 0x401);
#   - tagged with EX, target fetch in bounds: only for targets in the landing zone [CJ_ZLO,
#     CJ_ZHI), which CJ_ZONE_INIT fills with c.addi t2, 1 and closes with cjalr c0, ca5 back to
#     the attempt. PCC is then cs1, so the run stops where the next fetch leaves its bounds; the
#     attempt checks the number of c.addi run (t2) and whether it returned or trapped there.
# Raw CSetHigh metadata (CJH, untagged) gives the decodes no tagged capability has. Nothing else
# is jumped to, so in the default build targets near 0 and 2^32 (which the CHERIoT-Sail model
# does not map) are only ever fetched out of bounds. With -DFAR_WINDOWS (cheriot_rand_operands_far,
# +far_code_windows=1: the model maps [0, 0x1000) and [0x80000000, 2^32); the bench and Spike
# answer every address) the `#ifdef FAR_WINDOWS` section of the .inc adds two zones written by
# CJ_ZONE_FAR_INIT and the cases landing in them: the bottom zone [CJ_BLO, CJ_BHI) = [0, 0x80),
# laid out like the main one, and the top zone [CJ_TLO, CJ_TBR) = [0xFFFFFF80, 0xFFFFFFFE) whose
# last halfword, at CJ_TBR = 2^32 - 2, is `c.beqz a0, CJ_TRET` (a0 = 0 in every attempt) back to
# a `cjalr c0, ca5` at CJ_TRET = 0xFFFFFF78 just below the zone. A branch has no link, so neither
# ibex nor CHERIoT-Sail (whose CJAL/CJALR assert that the link is representable) computes a link
# that wraps past 2^32, and no fetch crosses 2^32: the run either leaves PCC's bounds before
# CJ_TBR, faults fetching CJ_TBR (top33 < 2^32), faults fetching CJ_TRET (small PCC: ret = 0),
# or returns (ret = 1; the link CJ_TRET + 4 is representable, checked by the generator).
# An attempt that does not trap falls into the ebreak after it (handler: code 3); each one that
# completes counts in s1, checked against the generated CJD_NTRY (+ CJD_NTRY_FAR) at the end
# (code 11).
.macro CJD_TRY r, imm, mtval
    LA_FAR    s0, .Lcjd\@, t0
    jalr      x0, \imm(\r)
    ebreak
.Lcjd\@:
    nop
    addi      s1, s1, 1
    csrr      t0, mtval
    li        t1, \mtval
    beq       t0, t1, .Lcjm\@
    FAIL      18
.Lcjm\@:
.endm

# The tagged + EX attempt of a case whose target is in a zone: \n c.addi run, then the jump back
# through ca5 (\ret = 1) or a fetch fault out of PCC's bounds (\ret = 0; the handler clears s0).
# a0 = 0 makes the top zone's `c.beqz a0, CJ_TRET` taken (FAR_WINDOWS).
.macro CJD_LAND imm, n, ret
    LA_FAR    s0, .Lcjl\@, t0
    cspecialr a5, SCR_MTCC
    csetaddr  a5, a5, s0
    li        t2, 0
    li        a0, 0
    jalr      x0, \imm(a1)
    ebreak
.Lcjl\@:
    nop
    addi      s1, s1, 1
    li        t0, \n
    beq       t2, t0, .Lcjn\@
    FAIL      16
.Lcjn\@:
  .if \ret
    bnez      s0, .Lcjk\@
    FAIL      17
  .else
    beqz      s0, .Lcjf\@
    FAIL      17
.Lcjf\@:
    csrr      t0, mtval
    li        t1, 0x401
    beq       t0, t1, .Lcjk\@
    FAIL      18
  .endif
.Lcjk\@:
    li        s0, 0
.endm

# The attempts on one case (ca1 = cs1, tagged if \tag): tagged with EX if \tex (1: the target
# fetch faults; 2: the target is in the zone), then without EX, untagged without EX, untagged.
.macro CJD_VARIANTS imm, tag, tex, n, ret
  .if \tex == 1
    CJD_TRY   a1, \imm, 0x401           # tagged, EX, target outside the bounds
  .elseif \tex == 2
    CJD_LAND  \imm, \n, \ret            # tagged, EX, target in the zone
  .endif
    li        t0, PERM_NO_EX
    candperm  a2, a1, t0
  .if \tag
    CJD_TRY   a2, \imm, 0x191           # tagged, no EX (ca2 = 12)
  .else
    CJD_TRY   a2, \imm, 0x182           # untagged, no EX
  .endif
    ccleartag a2, a2
    CJD_TRY   a2, \imm, 0x182           # untagged, no EX
    ccleartag a2, a1
    CJD_TRY   a2, \imm, 0x182           # untagged, EX
.endm

# Exact capability [\base, \base + \len) from MTCC (E = 0, 3 or 24), cursor \cur (\tag = 0: the
# cursor is not representable, so ca1 is untagged and its bounds decode from \cur).
.macro CJD base, len, cur, imm, tag, tex, n, ret
    cspecialr a1, SCR_MTCC
    li        t0, \base
    csetaddr  a1, a1, t0
    li        t0, \len
    csetboundsexact a1, a1, t0
    li        t0, \cur
    csetaddr  a1, a1, t0
    CJD_VARIANTS \imm, \tag, \tex, \n, \ret
.endm

# The root execute capability (base 0, top 2^32), cursor \cur.
.macro CJDR cur, imm, tex, n, ret
    cspecialr a1, SCR_MTCC
    li        t0, \cur
    csetaddr  a1, a1, t0
    CJD_VARIANTS \imm, 1, \tex, \n, \ret
.endm

# Raw metadata \meta (executable perms) on cursor \cur through CSetHigh: untagged, with EX and
# without.
.macro CJH meta, cur, imm
    cspecialr a1, SCR_MTCC
    li        t0, \cur
    csetaddr  a1, a1, t0
    li        t0, \meta
    csethigh  a1, a1, t0
    CJD_TRY   a1, \imm, 0x162           # untagged, EX (ca1 = 11)
    li        t0, PERM_NO_EX
    candperm  a2, a1, t0
    CJD_TRY   a2, \imm, 0x182           # untagged, no EX
.endm

# Landing zone: c.addi t2, 1 (0x0385) in every halfword of [CJ_ZLO, CJ_ZHI), cjalr c0, ca5
# (0x00078067) at CJ_ZHI and ebreaks after it, stored through MTDC (both the bench memory and the
# model's see the stores) and made fetchable by fence.i. Clobbers a1, t1, t2.
.macro CJ_ZONE_INIT
    cspecialr a1, SCR_MTDC
    li        t1, CJ_ZLO
    csetaddr  a1, a1, t1
    li        t1, 0x03850385
    li        t2, (CJ_ZHI - CJ_ZLO) / 4
.Lzi\@:
    sw        t1, 0(a1)
    cincaddrimm a1, a1, 4
    addi      t2, t2, -1
    bnez      t2, .Lzi\@
    li        t1, 0x00078067
    sw        t1, 0(a1)
    li        t1, 0x00100073
    sw        t1, 4(a1)
    sw        t1, 8(a1)
    sw        t1, 12(a1)
    fence.i
.endm

# FAR_WINDOWS zones (CJ_BLO/CJ_BHI, CJ_TRET/CJ_TLO/CJ_TBR/CJ_TBRW from the .inc; the generator
# checks CJ_TRET + 8 == CJ_TLO and CJ_TBR + 2 == 2^32), stored through MTDC like the main zone:
#   bottom  c.addi t2, 1 in every halfword of [CJ_BLO, CJ_BHI), cjalr c0, ca5 at CJ_BHI and
#           ebreaks after it -- in the model's ROM window [0, 0x1000), which Sail writes like RAM
#           (within_phys_mem);
#   top     cjalr c0, ca5 at CJ_TRET and an ebreak at CJ_TRET + 4 (a guard: only the c.beqz
#           reaches CJ_TRET), c.addi t2, 1 in every halfword of [CJ_TLO, CJ_TBR) and the word
#           CJ_TBRW = {c.beqz a0, CJ_TRET; c.addi t2, 1} at CJ_TBR - 2, so the last halfword
#           below 2^32 is the branch and no store or fetch crosses 2^32.
# Clobbers a1, t1, t2.
.macro CJ_ZONE_FAR_INIT
    cspecialr a1, SCR_MTDC
    li        t1, CJ_BLO
    csetaddr  a1, a1, t1
    li        t1, 0x03850385
    li        t2, (CJ_BHI - CJ_BLO) / 4
.Lzb\@:
    sw        t1, 0(a1)
    cincaddrimm a1, a1, 4
    addi      t2, t2, -1
    bnez      t2, .Lzb\@
    li        t1, 0x00078067
    sw        t1, 0(a1)
    li        t1, 0x00100073
    sw        t1, 4(a1)
    sw        t1, 8(a1)
    sw        t1, 12(a1)
    cspecialr a1, SCR_MTDC
    li        t1, CJ_TRET
    csetaddr  a1, a1, t1
    li        t1, 0x00078067
    sw        t1, 0(a1)
    li        t1, 0x00100073
    sw        t1, 4(a1)
    cincaddrimm a1, a1, 8                 # = CJ_TLO
    li        t1, 0x03850385
    li        t2, (CJ_TBR - 2 - CJ_TLO) / 4
.Lzt\@:
    sw        t1, 0(a1)
    cincaddrimm a1, a1, 4
    addi      t2, t2, -1
    bnez      t2, .Lzt\@
    li        t1, CJ_TBRW
    sw        t1, 0(a1)                   # at CJ_TBR - 2: the last word below 2^32
    fence.i
.endm

cjalr_det:
    li        s1, 0
#include "cheriot_rand_operands/cjalr_det_cases.inc"
#ifdef FAR_WINDOWS
    li        t0, CJD_NTRY + CJD_NTRY_FAR
#else
    li        t0, CJD_NTRY
#endif
    beq       s1, t0, 1f
    FAIL      11
1:  li        s1, 0
    j         cjalr_ot_det

# =============================================================================================
# cjalr_ot_det: once, before the loop. CJALR over cs1 tag x otype 0..7 x rd {c0, cra, ct1, ca5} x
# imm {0, 2046, -2048, -8, -1} x mstatus.MIE -> cheriot_cjalr_cross0, whose untagged and sealed
# corners op_cjalr reaches by chance (uarch triage). cs1 is ca2, never cra, so no attempt is a
# return (cheri_insts.sail CJALR). It is MTCC sealed with otype \k (0: unsealed) and, untagged, has
# its tag cleared after sealing; its cursor is the attempt's resume label. Then:
#   - untagged, or sealed with imm != 0, or sealed with a type the rd does not allow (cd = cra:
#     forward sentries 1-3 only; otherwise the inheriting forward sentry 1 only): CJALR faults
#     (mcause 28) and the handler resumes at the label;
#   - tagged with imm = 0 and an allowed type (unsealed, or a sentry the rd allows): it jumps to
#     the label. Sentries 2 and 3 change MIE, so MIE is set again after every attempt.
# Tagged unsealed with imm != 0 would jump to label + imm: left out (op_cjalr and cjalr_det).
# An attempt that neither traps nor jumps runs into the ebreak (handler: code 3).
.macro COT k, rd, imm, untag, mie
  .if \untag || \k != 0 || \imm == 0
    LA_FAR    s0, .Lcot\@, t0
    cspecialr a2, SCR_MTCC
    csetaddr  a2, a2, s0
  .if \k
    cspecialr t2, SCR_MSCRATCHC
    li        t0, \k
    csetaddr  t2, t2, t0
    cseal     a2, a2, t2
  .endif
  .if \untag
    ccleartag a2, a2
  .endif
    jalr      \rd, \imm(a2)
    ebreak
.Lcot\@:
    nop
  .if \mie
    csrsi     mstatus, 8
  .else
    csrci     mstatus, 8
  .endif
  .endif
.endm

cjalr_ot_det:
    .irp mie, 0, 1
    .irp k, 0, 1, 2, 3, 4, 5, 6, 7
    .irp imm, 0, 2046, -2048, -8, -1
    .irp rd, x0, ra, t1, a5
    COT       \k, \rd, \imm, 0, \mie
    COT       \k, \rd, \imm, 1, \mie
    .endr
    .endr
    .endr
    .endr
    csrci     mstatus, 8
    j         addr_det

# =============================================================================================
# addr_det: once, before the loop. The address-arithmetic group (ADDR_OPS) on the six kinds of
# cs1 gen_cap never builds (uarch triage of the cincaddr/cincaddrimm/cauicgp crosses):
#   A  base 0, length 16 (E = 0), cursor 0: decrements wrap below the base
#   B  base 0, length 0x200 (E = 1), cursor 0: as A at E = 1
#   C  [0xFFFFFE00, 2^32) (E = 1), cursor 0xFFFFFFFF: increments wrap to below the base
#   D  [0x100, 0x300) (E = 1), cursor set to 0xF0: untagged, and the base decodes as 0xFFFFFD00
#   E  [0x80001000, 0x80002000) (E = 4), cursor at the base, sealed and untagged: decrements
#      land below a non-zero base (case1; at base 0 they wrap to case2)
#   F  raw CSetHigh metadata {cperms 0x3F, otype 0, E 0, T 0x010, B 0x1FE} at address 5
#      (AD_RAW): untagged, the base decodes as 0xFFFFFFFE, above the cursor, so even an
#      increment of 0 is case1 (and so is AUICGP 0 from it)
# A and B tagged and untagged, sealed (otype 9) and not; C sealed and not. -> case1/case2 of
# the representability crosses at E = 0 and 1. Nothing traps.
.macro AD_SWEEP base, len, cur, seal, untag
    cspecialr a1, SCR_MTDC
    li        t0, \base
    csetaddr  a1, a1, t0
    li        t0, \len
    csetbounds a1, a1, t0
    li        t0, \base + \cur
    csetaddr  a1, a1, t0
  .if \seal
    cspecialr t0, SCR_MSCRATCHC
    li        t1, 9
    csetaddr  t0, t0, t1
    cseal     a1, a1, t0
  .endif
  .if \untag
    ccleartag a1, a1
  .endif
    ADDR_OPS
.endm

.macro AD_RAW addr, meta
    cspecialr a1, SCR_MTDC
    li        t0, \addr
    csetaddr  a1, a1, t0
    li        t0, \meta
    csethigh  a1, a1, t0
    ADDR_OPS
.endm

addr_det:
    .irp seal, 0, 1
    .irp untag, 0, 1
    AD_SWEEP  0, 16, 0, \seal, \untag
    AD_SWEEP  0, 0x200, 0, \seal, \untag
    .endr
    AD_SWEEP  0xFFFFFE00, 0x200, 0x1FF, \seal, 0
    .endr
    AD_SWEEP  0x100, 0x200, -0x10, 0, 0
    AD_SWEEP  0x80001000, 0x1000, 0, 1, 1
    AD_RAW    5, 0x7E0021FE
    j         main_loop

op_setbounds:
    li        a0, GF_ALL
    jal       ra, gen_cap
    .rept 4
    RQLEN
    csetbounds a3, a1, a2
    MONO_CHECK
    .endr
    RQLEN
    csetboundsexact a3, a1, a2
    MONO_CHECK
    RQLEN
    csetboundsrndn a3, a1, a2
    MONO_CHECK
    .irp imm, 0, 1, 8, 9, 511, -2048, -1
    csetboundsimm a3, a1, \imm
    MONO_CHECK
    .endr
    j         op_done

op_addr:
    li        a0, GF_ALL
    jal       ra, gen_cap
    ADDR_OPS
    j         op_done

# =============================================================================================
op_cget:
    RAND      t0
    andi      t0, t0, 1
    beqz      t0, 1f
    li        a0, GF_ALL
    jal       ra, gen_cap
    j         2f
1:  RANDN     t1, 3, t0                 # a root: every address is representable
    cspecialr a1, SCR_MTDC
    beqz      t1, 2f
    cspecialr a1, SCR_MTCC
    addi      t1, t1, -1
    beqz      t1, 2f
    cspecialr a1, SCR_MSCRATCHC
2:  RANDN     t1, 33, t0                # address with k zero bits, rotated
    li        t0, -1
    sll       t0, t0, t1
    li        t2, 32
    bne       t1, t2, 3f
    li        t0, 0
3:  RAND      t1
    andi      t1, t1, 31
    sll       t2, t0, t1
    neg       t1, t1
    srl       t0, t0, t1
    or        t0, t0, t2
    csetaddr  a1, a1, t0
    RAND      t0
    andi      t0, t0, 1
    beqz      t0, 4f
    ccleartag a1, a1
4:  cgetperm  t0, a1
    cgettype  t0, a1
    cgetbase  t0, a1
    cgetlen   t0, a1
    cgettag   t0, a1
    cgetaddr  t0, a1
    cgethigh  t0, a1
    cgettop   t0, a1
    j         op_done

# =============================================================================================
.macro SETHIGH_ONE
    RAND      a2
    csethigh  a3, a1, a2
    cgethigh  t0, a3
    beq       t0, a2, .Lsh1\@
    FAIL      20
.Lsh1\@:
    cgettag   t0, a3
    beqz      t0, .Lsh2\@
    FAIL      21
.Lsh2\@:
.endm

op_csethigh:
    li        a0, GF_ALL
    jal       ra, gen_cap
    .rept 8
    SETHIGH_ONE
    .endr
    j         op_done

# =============================================================================================
op_seq:
    GEN_OT    GF_PERM, 1
    cmove     a3, a1
    GEN_OT    GF_PERM, 1
    cmove     a2, a1
    GEN_OT    GF_PERM, 1
    RAND      t0
    andi      t1, t0, 3
    bnez      t1, 1f
    cmove     a2, a1                    # equal pair
1:  andi      t1, t0, 0xc
    bnez      t1, 2f
    li        t1, 8
    csetbounds a3, a1, t1               # (possibly) a subset of a1
2:  cseqx     t0, a1, a2
    cseqx     t0, a2, a1
    cseqx     t0, a1, a3
    cseqx     t0, a3, a1
    cseqx     t0, a2, a3
    cseqx     t0, a3, a2
    ctestsubset t0, a1, a2
    ctestsubset t0, a2, a1
    ctestsubset t0, a1, a3
    ctestsubset t0, a3, a1
    ctestsubset t0, a2, a3
    ctestsubset t0, a3, a2
    li        t1, 1
    cseqx     t0, a1, a1
    beq       t0, t1, 3f
    FAIL      22
3:  ctestsubset t0, a2, a2
    beq       t0, t1, 4f
    FAIL      24
4:  j         op_done

# =============================================================================================
# a2 := sealing capability: address v in 0..15 or >= 16, bounds placing v inside / below
# the base (E = 24) / at the base / above / at the top / zero length at v; then US, GL dropped
# and sealed at random; SE dropped if \k bit 0, untagged if \k bit 1 (op_seal runs k = 0..3,
# so every SE x tag combination of cheriot_cseal_cross1 is built each time).
# Clobbers a0, t0, t1, t2.
.macro MK_SEALER k
    RANDN     t0, 17, t1                # t0 = v
    li        t1, 16
    bltu      t0, t1, .Lms_v\@
    RAND      t0
    andi      t0, t0, 0x3ff
    addi      t0, t0, 16
.Lms_v\@:
    RANDN     t1, 6, t2                 # t1 = position class
    bnez      t0, .Lms_nz\@
    # v = 0: below the base (E = 24, the base decodes above 0 and the tag stays: repr_mask == 0
    # in cheriot_set_address), at the base, or zero length; inside/above/at the top need v > 0
    li        t2, 1
    beq       t1, t2, .Lms_below\@
    li        t2, 3
    bltu      t1, t2, .Lms_atb\@
    li        t1, 5
.Lms_nz\@:
    beqz      t1, .Lms_in\@
    addi      t1, t1, -1
    beqz      t1, .Lms_below\@
    addi      t1, t1, -1
    beqz      t1, .Lms_atb\@
    addi      t1, t1, -1
    beqz      t1, .Lms_above\@
    addi      t1, t1, -1
    beqz      t1, .Lms_att\@
    mv        t2, t0                    # zero length at v
    li        a0, 0
    j         .Lms_mk\@
.Lms_in\@:                              # base = v - d, top = v + 1..8
    RAND      t2
    mulhu     t2, t2, t0
    addi      t2, t2, 1
    RAND      a0
    andi      a0, a0, 7
    addi      a0, a0, 1
    add       a0, a0, t2
    sub       t2, t0, t2
    j         .Lms_mk\@
.Lms_below\@:                           # [16 MiB, 32 MiB), E = 24
    li        t2, 0x01000000
    li        a0, 0x01000000
    j         .Lms_mk\@
.Lms_atb\@:
    mv        t2, t0
    RAND      a0
    andi      a0, a0, 7
    addi      a0, a0, 1
    j         .Lms_mk\@
.Lms_above\@:                           # top = v - d, base = top - 0..3 (>= 0)
    RAND      t2
    mulhu     t2, t2, t0
    addi      t2, t2, 1
    sub       a0, t0, t2                # top
    RAND      t1
    andi      t1, t1, 3
    bgeu      a0, t1, .Lms_ab\@
    mv        t1, a0
.Lms_ab\@:
    sub       t2, a0, t1                # base
    mv        a0, t1                    # length
    j         .Lms_mk\@
.Lms_att\@:                             # base = v - d, top = v
    RAND      a0
    mulhu     a0, a0, t0
    addi      a0, a0, 1
    sub       t2, t0, a0
.Lms_mk\@:                              # t2 = base, a0 = length, t0 = v
    cspecialr a2, SCR_MSCRATCHC
    csetaddr  a2, a2, t2
    csetboundsexact a2, a2, a0
    csetaddr  a2, a2, t0
    RAND      t0
  .if (\k) & 1
    li        t1, PERM_NO_SE
    candperm  a2, a2, t1
  .endif
    andi      t1, t0, 0xc
    bnez      t1, .Lms_2\@
    li        t1, PERM_NO_US
    candperm  a2, a2, t1
.Lms_2\@:
    andi      t1, t0, 0x30
    bnez      t1, .Lms_3\@
    li        t1, PERM_NO_GL
    candperm  a2, a2, t1
.Lms_3\@:
    andi      t1, t0, 0x1c0
    bnez      t1, .Lms_4\@
    srli      t1, t0, 12
    andi      t1, t1, 7
    addi      t1, t1, 8                 # 8-15; 8 is not a data otype: tag cleared
    cspecialr t2, SCR_MSCRATCHC
    csetaddr  t2, t2, t1
    cseal     a2, a2, t2
.Lms_4\@:
  .if (\k) & 2
    ccleartag a2, a2
  .endif
.endm

# Clobbers t0.
.macro UNSEAL_CHECK
    cgethigh  t0, a3
    cgettag   t0, a3
    beqz      t0, .Luc\@
    cgettype  t0, a3
    beqz      t0, .Luc\@
    FAIL      27
.Luc\@:
.endm

op_seal:
    GEN_OT    GF_PERM|GF_MTCC           # a5: from the execute root, so cs1 EX is set
    cmove     a5, a1
    GEN_OT    GF_PERM|GF_MTDC           # a1: no EX
    .irp k, 0, 1, 2, 3
    MK_SEALER \k
    cseal     a3, a1, a2
    cgethigh  t0, a3
    cseal     a3, a5, a2
    cgethigh  t0, a3
    cunseal   a3, a1, a2
    UNSEAL_CHECK
    cunseal   a3, a5, a2
    UNSEAL_CHECK
    .endr
    j         op_done

# =============================================================================================
op_bits:
    RANDN     t1, 33, t0                # rs1 of bit-size t1
    RAND      t0
    li        t2, 0x80000000
    or        t0, t0, t2
    li        t2, 32
    sub       t2, t2, t1
    srl       t0, t0, t2
    bnez      t1, 1f
    li        t0, 0
1:  RAND      t1
    andi      t2, t1, 3
    beqz      t2, 2f
    addi      t2, t2, -1
    beqz      t2, 3f
    mv        a1, t0                    # integer: untagged
    j         4f
2:  cspecialr a1, SCR_MTDC              # tagged root
    csetaddr  a1, a1, t0
    j         4f
3:  mv        a5, t0                    # some bounded capability at that address
    li        a0, GF_ALL
    jal       ra, gen_cap
    csetaddr  a1, a1, a5
4:  crrl      a3, a1
    cram      a3, a1
    RAND      t1
    andi      t2, t1, 3
    beqz      t2, 5f
    addi      t2, t2, -1
    beqz      t2, 6f
    addi      t2, t2, -1
    beqz      t2, 7f
    cgetaddr  a2, a1
    j         8f
5:  andi      a2, t1, 0x3c0
    srli      a2, a2, 6
    j         8f
6:  srli      a2, t1, 20
    j         8f
7:  RAND      a2
8:  csetboundsrndn a3, a1, a2
    MONO_CHECK
    j         op_done

# =============================================================================================
op_mem:
    DCAP_FAR  a1, buf, t0               # [buf + 8k, + 8..256)
    RANDN     t1, 96, t0
    slli      t1, t1, 3
    cincaddr  a1, a1, t1
    RANDN     t1, 32, t0
    addi      t1, t1, 1
    slli      t1, t1, 3
    csetboundsexact a1, a1, t1
    RANDN     t2, 8, t0                 # cursor class
    beqz      t2, 3f
    addi      t2, t2, -1
    beqz      t2, 3f
    addi      t2, t2, -1
    beqz      t2, 3f
    addi      t2, t2, -1
    beqz      t2, 3f
    addi      t2, t2, -1
    beqz      t2, 2f
    addi      t2, t2, -1
    beqz      t2, 1f
    addi      t2, t2, -1
    beqz      t2, 4f
    RAND      t0                        # misaligned inside
    andi      t0, t0, 7
    ori       t0, t0, 1
    j         5f
1:  mv        t0, t1                    # at top: out of bounds
    j         5f
2:  addi      t0, t1, -8                # last slot
    j         5f
3:  srli      t1, t1, 3                 # an aligned slot inside
    RAND      t0
    mulhu     t0, t0, t1
    slli      t0, t0, 3
    j         5f
4:  li        t0, -8                    # below the base
5:  cincaddr  a1, a1, t0
    RAND      t0                        # random subset of GL LG SD LM SL LD MC
    andi      t1, t0, 1
    beqz      t1, 6f
    srli      t1, t0, 1
    andi      t1, t1, 0x7f
    ori       t1, t1, -128              # keep bits 7-11
    candperm  a1, a1, t1
6:  andi      t1, t0, 0x300             # 1/4: sealed (data otype 9-15)
    bnez      t1, 7f
    srli      t1, t0, 10
    andi      t1, t1, 7
    li        t2, 7
    bne       t1, t2, 8f
    li        t1, 0
8:  addi      t1, t1, 9
    cspecialr t2, SCR_MSCRATCHC
    csetaddr  t2, t2, t1
    cseal     a1, a1, t2
7:  srli      t1, t0, 13                # 1/4: untagged
    andi      t1, t1, 3
    bnez      t1, 9f
    ccleartag a1, a1
9:  cmove     a3, a1
    li        a0, GF_ALL
    jal       ra, gen_cap               # cs2
    RAND      t0
    andi      t0, t0, 1
    beqz      t0, 1f
    li        t0, PERM_NO_GL
    candperm  a1, a1, t0
1:  cmove     a2, a1
    cmove     a1, a3
    LA_FAR    s0, .Lmem_ld, t0
    ori       s0, s0, 2
    csc       a2, a1, 0
.Lmem_ld:
    nop
    LA_FAR    s0, op_done, t0
    ori       s0, s0, 2
    clc       a3, a1, 0
    cgethigh  t0, a3
    j         op_done

# =============================================================================================
# Loads and stores at the bounds edges (cheri_access_bounds_cg): one of LB LBU LH LHU LW CLC SB
# SH SW CSC, naturally aligned, through an MTDC-derived authority whose base or top is chosen
# around the access: cursor - base = d, or cursor + size - top = d, with d in [-10, 10].
#   - top edge, and base edge with d >= 0: an exact [base, base + L), L in [24, 256), around an
#     address in `buf` (so an in-bounds access is a real access the cosim checks; L >= 24 keeps
#     the other edge out of the window).
#   - base edge with d < 0: [0x81000000, 0x82000000), E = 24. A cursor below the base is
#     representable only when the representable range [b, b + 2^(e+9)) wraps the whole address
#     space, i.e. E = 24 (ISA chap-cheri-riscv.tex:569-575); with E = 0 CIncAddr would clear the
#     tag and no tagged authority would ever be below its base. The access faults before the
#     bus, so the unmapped address is never accessed.
# Then the permission the access needs is dropped or kept (LD dropped / SD dropped / neither),
# and the authority is left valid, untagged, or sealed (data otype 9-15), 1/3 each. Only the
# access may trap (s0 = op_done); one that does not trap is counted in ST_LDOK.
op_ldst:
    RANDN     t2, 10, t0                # kind, in ldst_lg2 order
    DCAP_FAR  a0, ldst_lg2, t0
    cincaddr  a0, a0, t2
    lbu       a4, 0(a0)                 # log2 of the access size
    li        t0, 1
    sll       a0, t0, a4                # a0 = access size n
    RANDN     t1, 112, t0               # t1 = access address - buf, in [64, 960), aligned to n
    slli      t1, t1, 3
    RAND      t0
    andi      t0, t0, 7
    srl       t0, t0, a4
    sll       t0, t0, a4
    add       t1, t1, t0
    addi      t1, t1, 64
    RANDN     a3, 232, t0               # a3 = L in [24, 256)
    addi      a3, a3, 24
    RANDN     a2, 21, t0                # a2 = d in [-10, 10]
    addi      a2, a2, -10
    RAND      t0
    andi      t0, t0, 1
    bnez      t0, 1f
    bgez      a2, 2f
    li        t0, 0x81000000            # base edge, d < 0: E = 24, cursor below the base
    cspecialr a1, SCR_MTDC
    csetaddr  a1, a1, t0
    li        t1, 0x01000000
    csetboundsexact a1, a1, t1
    cincaddr  a1, a1, a2
    j         3f
1:  add       a2, a2, a3                # top edge: cursor - base = L + d - n
    sub       a2, a2, a0
2:  sub       t0, t1, a2                # base - buf (a2 = cursor - base)
    DCAP_FAR  a1, buf, a4
    cincaddr  a1, a1, t0
    csetboundsexact a1, a1, a3
    cincaddr  a1, a1, a2                # cursor = the access address
3:  RANDN     t0, 3, a4                 # drop LD / drop SD / neither
    beqz      t0, 5f
    li        t1, 0xFDF
    addi      t0, t0, -1
    beqz      t0, 4f
    li        t1, 0xFFB
4:  candperm  a1, a1, t1
5:  RANDN     t0, 3, a4                 # authority: valid / untagged / sealed
    beqz      t0, 7f
    addi      t0, t0, -1
    bnez      t0, 6f
    ccleartag a1, a1
    j         7f
6:  RANDN     t1, 7, a4
    addi      t1, t1, 9
    cspecialr a4, SCR_MSCRATCHC
    csetaddr  a4, a4, t1
    cseal     a1, a1, a4
7:  RAND      a2                        # store data
    LA_FAR    s0, op_done, t0
    beqz      t2, 10f
    addi      t2, t2, -1
    beqz      t2, 11f
    addi      t2, t2, -1
    beqz      t2, 12f
    addi      t2, t2, -1
    beqz      t2, 13f
    addi      t2, t2, -1
    beqz      t2, 14f
    addi      t2, t2, -1
    beqz      t2, 15f
    addi      t2, t2, -1
    beqz      t2, 16f
    addi      t2, t2, -1
    beqz      t2, 17f
    addi      t2, t2, -1
    beqz      t2, 18f
    j         19f
10: lb        a3, 0(a1)
    j         8f
11: lbu       a3, 0(a1)
    j         8f
12: lh        a3, 0(a1)
    j         8f
13: lhu       a3, 0(a1)
    j         8f
14: lw        a3, 0(a1)
    j         8f
15: clc       a3, a1, 0
    cgethigh  t0, a3
    j         8f
16: sb        a2, 0(a1)
    j         8f
17: sh        a2, 0(a1)
    j         8f
18: sw        a2, 0(a1)
    j         8f
19: cmove     a2, a1
    csc       a2, a1, 0
8:  INC_STAT  ST_LDOK
    j         op_done

# =============================================================================================
# CJALR. cj_build: a1 := cs1 for target a2 (an even address) and immediate a4.
# Clobbers a0, t0, t1, t2.
cj_build:
    RANDN     t0, 10, t1
    li        t1, 6
    bgeu      t0, t1, .Lcb_big
    RANDN     t1, 3, t2                 # base class -> a0
    RAND      t2
    beqz      t1, 1f
    addi      t1, t1, -1
    beqz      t1, 2f
    andi      t2, t2, 7                 # base above the target: P + 1..8
    addi      t2, t2, 1
    add       a0, a2, t2
    j         3f
1:  andi      t0, t2, 1                 # target inside: P - 1..256 or P - 0..8191
    srli      t2, t2, 1
    beqz      t0, 11f
    andi      t2, t2, 255
    addi      t2, t2, 1
    j         12f
11: slli      t2, t2, 19
    srli      t2, t2, 19
12: sub       a0, a2, t2
    j         3f
2:  mv        a0, a2                    # at the base
3:  RANDN     t1, 4, t2                 # top class -> t1
    RAND      t0
    beqz      t1, 4f
    addi      t1, t1, -1
    beqz      t1, 5f
    addi      t1, t1, -1
    beqz      t1, 6f
    andi      t2, t0, 1                 # far: P + 8..263 or P + 8..8199
    srli      t0, t0, 1
    beqz      t2, 13f
    andi      t0, t0, 255
    j         14f
13: slli      t0, t0, 19
    srli      t0, t0, 19
14: addi      t0, t0, 8
    add       t1, a2, t0
    j         7f
4:  andi      t0, t0, 7                 # top = P + 0..7
    add       t1, a2, t0
    j         7f
5:  mv        t1, a2                    # at the top
    j         7f
6:  andi      t0, t0, 15                # above the top: top = P - 1..16
    addi      t0, t0, 1
    sub       t1, a2, t0
7:  bgeu      t1, a0, 8f
    mv        t1, a0
8:  sub       t1, t1, a0
    cspecialr a1, SCR_MTCC
    csetaddr  a1, a1, a0
    csetbounds a1, a1, t1
    j         .Lcb_cursor
.Lcb_big:
    cspecialr a1, SCR_MTCC
    addi      t0, t0, -6
    beqz      t0, .Lcb_cursor           # the root: base 0, top 2^32
    addi      t0, t0, -1
    bnez      t0, 1f
    csetaddr  a1, a1, x0                # [0, 0x81000000)
    li        t1, 0x81000000
    csetbounds a1, a1, t1
    j         .Lcb_cursor
1:  addi      t0, t0, -1
    bnez      t0, .Lcb_edge
    li        t1, 0x80000000            # [0x80000000, 2^32)
    csetaddr  a1, a1, t1
    csetbounds a1, a1, t1
    j         .Lcb_cursor
.Lcb_edge:                              # near an unmapped top: never let it jump
    RAND      t0
    andi      t1, t0, 1
    bnez      t1, 2f
    srli      t0, t0, 1                 # root, target 2^32 - 8/6/4/2
    andi      t0, t0, 3
    slli      t0, t0, 1
    li        a0, 0xFFFFFFF8
    add       a0, a0, t0
    j         3f
2:  srli      t1, t0, 1                 # [0, T), T = 1..32, target T - 0..7, even
    andi      t1, t1, 31
    addi      t1, t1, 1
    csetaddr  a1, a1, x0
    csetbounds a1, a1, t1
    srli      t0, t0, 6
    andi      t0, t0, 7
    sub       a0, t1, t0
    andi      a0, a0, -2
3:  sub       t0, a0, a4
    csetaddr  a1, a1, t0
    RANDN     t0, 3, t1                 # untagged / no EX / sealed non-sentry (6, 7):
    beqz      t0, 4f                    # each faults before the jump, so the tag x EX
    addi      t0, t0, -1                # quadrants are all reached without a fetch
    beqz      t0, 5f
    RAND      t1
    andi      t1, t1, 1
    addi      t1, t1, 6
    cspecialr t0, SCR_MSCRATCHC
    csetaddr  t0, t0, t1
    cseal     a1, a1, t0
    ret
4:  ccleartag a1, a1
    ret
5:  li        t0, PERM_NO_EX
    candperm  a1, a1, t0
    ret
.Lcb_cursor:
    sub       t0, a2, a4                # cursor = target - imm
    csetaddr  a1, a1, t0
    RAND      t0
    andi      t1, t0, 3                 # 1/4: no EX
    bnez      t1, 1f
    li        t1, PERM_NO_EX
    candperm  a1, a1, t1
1:  andi      t1, t0, 0x1c              # 1/8: no SR
    bnez      t1, 2f
    li        t1, PERM_NO_SR
    candperm  a1, a1, t1
2:  srli      t0, t0, 5
    andi      t1, t0, 1                 # 1/2: sealed, otype 1-7 (EX) or 9-15
    beqz      t1, 5f
    srli      t0, t0, 1
    andi      t2, t0, 7
    bnez      t2, 3f
    li        t2, 1
3:  cgetperm  t1, a1
    andi      t1, t1, 0x100
    bnez      t1, 4f
    addi      t2, t2, 8
4:  cspecialr t1, SCR_MSCRATCHC
    csetaddr  t1, t1, t2
    cseal     a1, a1, t1
5:  RAND      t0                        # 1/8: untagged
    andi      t0, t0, 7
    bnez      t0, 6f
    ccleartag a1, a1
6:  ret

# One CJALR variant: if a3 == \k, CJALR \rd, \imm(a1). After it only the cd = ca5 variant
# can land here (the pad returns through ca5, which is then the link); t2 = 1 says it did.
.macro CJV k, rd, imm
    li        t1, \k
    bne       a3, t1, .Lcjv\@
    jalr      \rd, \imm(a1)
    bnez      t2, 7f
    j         cj_fallthrough
.Lcjv\@:
.endm

# A CJALR attempt, continuing at \next.
.macro CJ_ATTEMPT next
    RANDN     a3, 20, t0                # variant: rd class a3 / 5, imm class a3 % 5
    li        t0, 5
    remu      t1, a3, t0
    li        a4, 0
    beqz      t1, 1f
    li        a4, 2046
    addi      t1, t1, -1
    beqz      t1, 1f
    li        a4, -2048
    addi      t1, t1, -1
    beqz      t1, 1f
    li        a4, -8
    addi      t1, t1, -1
    beqz      t1, 1f
    li        a4, -1
1:  RANDN     t1, 4, t0                 # landing pad, pc mod 8 = 0, 2, 4, 6
    bnez      t1, 2f
    LA_FAR    a2, cj_pad0, t0
    j         5f
2:  addi      t1, t1, -1
    bnez      t1, 3f
    LA_FAR    a2, cj_pad2, t0
    j         5f
3:  addi      t1, t1, -1
    bnez      t1, 4f
    LA_FAR    a2, cj_pad4, t0
    j         5f
4:  LA_FAR    a2, cj_pad6, t0
5:  jal       ra, cj_build
    LA_FAR    t1, 7f, t0
    cspecialr a5, SCR_MTCC              # where the pad returns to
    csetaddr  a5, a5, t1
    LA_FAR    s0, 8f, t0                # where a trap resumes
    RAND      t0
    andi      t0, t0, 1
    beqz      t0, 6f
    csrsi     mstatus, 8
    j         .Lcja\@
6:  csrci     mstatus, 8
.Lcja\@:
    li        t2, 0
    CJV        0, x0,     0
    CJV        1, x0,  2046
    CJV        2, x0, -2048
    CJV        3, x0,    -8
    CJV        4, x0,    -1
    CJV        5, ra,     0
    CJV        6, ra,  2046
    CJV        7, ra, -2048
    CJV        8, ra,    -8
    CJV        9, ra,    -1
    CJV       10, t1,     0
    CJV       11, t1,  2046
    CJV       12, t1, -2048
    CJV       13, t1,    -8
    CJV       14, t1,    -1
    CJV       15, a5,     0
    CJV       16, a5,  2046
    CJV       17, a5, -2048
    CJV       18, a5,    -8
    CJV       19, a5,    -1
    j         cj_fallthrough
7:  li        s0, 0                     # landed
    cgethigh  t0, ra                    # link metadata, whichever of cra/ct1/ca5 was cd
    cgethigh  t0, t1
    cgethigh  t0, a5
    INC_STAT  ST_LANDED
    j         \next
8:  nop                                 # trapped (the handler cleared s0)
    csrr      t0, mtval                 # by the CJALR (against cs1: mtval[10] = 0) or by
    andi      t0, t0, 0x400             # the target fetch (against PCC: mtval[10] = 1)?
    bnez      t0, .Lcjf\@
    INC_STAT  ST_CJTRAP
    j         \next
.Lcjf\@:
    INC_STAT  ST_CJFETCH
    j         \next
.endm

op_cjalr:
    CJ_ATTEMPT .Lcj_second
.Lcj_second:
    CJ_ATTEMPT op_done

cj_fallthrough:
    FAIL      4

# Landing pads: set the flag, return through ca5. pc mod 8 = 0, 2, 4, 6.
    .balign 8
cj_pad0:
    li        t2, 1
    jalr      x0, 0(a5)
    ebreak
    .balign 8
    .option rvc
    c.nop
    .option norvc
cj_pad2:
    li        t2, 1
    jalr      x0, 0(a5)
    ebreak
    .option rvc
    c.nop
    .option norvc
    nop
cj_pad4:
    li        t2, 1
    jalr      x0, 0(a5)
    ebreak
    .balign 8
    .option rvc
    c.nop
    .option norvc
    nop
cj_pad6:
    li        t2, 1
    jalr      x0, 0(a5)
    ebreak
    .option rvc
    c.nop
    .option norvc

# =============================================================================================
# CJAL from a bounded PCC. Entered with CJALR (cd = c0) through a1; returns through ca5.
op_cjal:
    LA_FAR    a3, op_done, t0
    RANDN     t2, 8, t0
    li        t0, 5
    bgeu      t2, t0, .Lcjl_big
    andi      t0, t2, 1
    bnez      t0, .Lcjl_bwd
    LA_FAR    a2, cjal_j0, t0           # forward: E = cjal_j0, T = cjal_tf
    LA_FAR    a4, cjal_tf, t0
    RAND      t0
    andi      t1, t0, 63
    sub       a0, a2, t1                # base = E - 0..63
    srli      t0, t0, 6
    andi      t1, t0, 3
    srli      t0, t0, 2
    beqz      t1, 1f
    addi      t1, t1, -1
    beqz      t1, 2f
    addi      t1, t1, -1
    beqz      t1, 3f
    andi      t0, t0, 255               # far: T + 8..263
    addi      t0, t0, 8
    add       t1, a4, t0
    j         .Lcjl_go
1:  andi      t0, t0, 7                 # top = T + 0..7
    add       t1, a4, t0
    j         .Lcjl_go
2:  andi      t0, t0, 15                # above the top: top in [E + 4, E + 19] < T
    addi      t0, t0, 4
    add       t1, a2, t0
    j         .Lcjl_go
3:  mv        t1, a4                    # at the top
    j         .Lcjl_go
.Lcjl_bwd:
    LA_FAR    a2, cjal_j1, t0           # backward: E = cjal_j1, T = cjal_tb
    LA_FAR    a4, cjal_tb, t0
    RAND      t0
    andi      t1, t0, 63
    addi      t1, t1, 4
    add       t1, a2, t1                # top = E + 4..67
    srli      t0, t0, 6
    andi      a0, t0, 3
    srli      t0, t0, 2
    beqz      a0, 1f
    addi      a0, a0, -1
    beqz      a0, 2f
    andi      t0, t0, 255               # inside: base = T - 1..256
    addi      t0, t0, 1
    sub       a0, a4, t0
    j         .Lcjl_go
1:  mv        a0, a4                    # at the base
    j         .Lcjl_go
2:  andi      t0, t0, 15                # below the base: base = T + 1..16 (<= E)
    addi      t0, t0, 1
    add       a0, a4, t0
.Lcjl_go:
    cspecialr a1, SCR_MTCC
    csetaddr  a1, a1, a0
    sub       t1, t1, a0
    csetbounds a1, a1, t1
    j         .Lcjl_enter
.Lcjl_big:
    RAND      t0
    andi      t0, t0, 1
    LA_FAR    a2, cjal_j0, t1
    beqz      t0, 1f
    LA_FAR    a2, cjal_j1, t1
1:  cspecialr a1, SCR_MTCC
    addi      t2, t2, -5
    beqz      t2, .Lcjl_enter           # root
    addi      t2, t2, -1
    bnez      t2, 2f
    csetaddr  a1, a1, x0                # [0, 0x81000000)
    li        t1, 0x81000000
    csetbounds a1, a1, t1
    j         .Lcjl_enter
2:  li        t1, 0x80000000            # [0x80000000, 2^32)
    csetaddr  a1, a1, t1
    csetbounds a1, a1, t1
.Lcjl_enter:
    csetaddr  a4, a1, a2                # entered through ca4: CJALRs through ca1 are the ones under test
    cspecialr a5, SCR_MTCC
    csetaddr  a5, a5, a3
    mv        s0, a3
    jalr      x0, 0(a4)
    ebreak

    .balign 64
cjal_blk:
cjal_tb:                                # +0
    jalr      x0, 0(a5)
    ebreak
    ebreak
    ebreak
cjal_j1:                                # +16
    jal       x0, cjal_tb
    ebreak
cjal_j0:                                # +24
    jal       x0, cjal_tf
    ebreak
    ebreak
    ebreak
    ebreak
    ebreak
cjal_tf:                                # +48
    jalr      x0, 0(a5)
    ebreak

# =============================================================================================
# AUIPCC from a root, an E = 0 ([blk-8, blk+68)), an E = 2 ([blk-16, blk+1024)) and an
# E = 5 ([blk-4096, blk+4096)) PCC. Nothing in the block may trap (s0 stays 0).
op_auipcc:
    LA_FAR    a2, auipcc_blk, t0
    LA_FAR    a3, op_done, t0
    RANDN     t2, 4, t0
    cspecialr a1, SCR_MTCC
    beqz      t2, 4f
    addi      t2, t2, -1
    bnez      t2, 1f
    addi      t0, a2, -8
    li        t1, 76
    j         3f
1:  addi      t2, t2, -1
    bnez      t2, 2f
    addi      t0, a2, -16
    li        t1, 1040
    j         3f
2:  li        t1, 4096
    sub       t0, a2, t1
    li        t1, 8192
3:  csetaddr  a1, a1, t0
    csetbounds a1, a1, t1
4:  csetaddr  a4, a1, a2
    cspecialr a5, SCR_MTCC
    csetaddr  a5, a5, a3
    jalr      x0, 0(a4)
    ebreak

    .balign 64
auipcc_blk:
    .irp imm, 0, 1, 0x7ffff, 0x80000, 0x80001, 0xffffe, 0xfffff
    auipcc    a3, \imm                  # AUIPCC under test (not used as an address)
    cgethigh  t0, a3
    .endr
    jalr      x0, 0(a5)
    ebreak

# =============================================================================================
op_misc:
    li        a0, GF_ALL
    jal       ra, gen_cap
    cmove     a2, a1
    li        a0, GF_ALL
    jal       ra, gen_cap
    RAND      t1
    candperm  a3, a1, t1
    cgethigh  t0, a3
    cgetperm  t0, a3                    # result perms within cs1.perms & rs2
    cgetperm  t2, a1
    and       t2, t2, t1
    not       t2, t2
    and       t0, t0, t2
    beqz      t0, 1f
    FAIL      26
1:  cmove     a3, a1
    cseqx     t0, a3, a1
    li        t1, 1
    beq       t0, t1, 2f
    FAIL      22
2:  ccleartag a3, a1
    cgethigh  t0, a3
    cgettag   t0, a3
    beqz      t0, 3f
    FAIL      23
3:  csub      t0, a1, a2
    csub      t0, a2, a1
    j         op_done

# =============================================================================================
    .data
    .balign 64
stats:
    .word     0                         # ST_ITER
    .word     0                         # ST_LANDED
    .word     0                         # ST_CJTRAP  (CJALR raised its own fault)
    .word     0                         # ST_CJFETCH (the target fetch faulted)
    .word     0                         # ST_LDOK (op_ldst accesses that did not fault)
ldst_lg2:                               # op_ldst kinds: LB LBU LH LHU LW CLC SB SH SW CSC
    .byte     0, 0, 1, 1, 2, 3, 0, 1, 2, 3
    .balign 1024
buf:
    .space    1024
