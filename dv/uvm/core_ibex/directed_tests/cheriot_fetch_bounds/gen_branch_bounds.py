#!/usr/bin/env python3
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""Generate branch_bounds_cases.inc for cheriot_fetch_bounds sections 11 and 12.

Section 11 runs one taken conditional branch per reachable value of cp_cheri_branch_bound
(fcov_bound_check_cases(PCC, branch target), core_ibex_fcov_if.sv) that neither the random
streams nor sections 1-10 produce: the target below, at, inside, 1..7 bytes under, at and above
the top of an exact small PCC, and the same against a PCC whose top is 2^32 or whose base is 0.
Each case is checked here against a copy of fcov_bound_check_cases(), so a layout that does not
produce the value it is listed under fails generation.

Section 12 runs what needs code at the ends of the address space, in the windows the bench maps
with +far_code_windows=1 ([0, 0x1000) and [0xFFFFF000, 2^32), ibex_cosim_scoreboard.sv): the
cheriot_instr_branch_cross values with the target 2..6 bytes under a top of 2^32, at a base of 0
or 1..7 bytes under an odd top over a base of 0 (exponent 0), and the root-PCC targets 0 and
2^32 - 2/4/6; the same layouts for CJAL (cp_cheri_cjal_bound), including the ones section 11
reaches only with branches (its small regions 0x041..0x072, run from a copy at 0x80FFFFF0, and
0x020, 0x070, 0x081, 0x104, 0x108, 0x120, 0x140, 0x160); and one AUIPCC per cheriot_cauipcc_cross bin whose result must wrap
past 0 or 2^32 to leave the representable range (case1 with a positive immediate, case2 with a
negative one, for exponent 0 and 1..14). Every expected value comes from the CHERIoT-Sail
functions copied below (setCapBounds, getCapBoundsBits, setCapAddr), and each case is also
checked against fcov_bound_check_cases() / fcov_repr_cases().

Cases not generated:
  - excluded by FCOV_EVEN_TARGET_IGNORE / pcc_len_lt2 (the spec's exclusion chapter);
  - branches and CJALs to themselves (target at the base of a PCC of length 2 or 3: 0x022,
    0x032, 0x0a2, 0x122, 0x132, and 0x0c2 for CJAL): they leave the region only through an
    interrupt, so they are in cheriot_branch_self_loop;
  - CJAL 0x0a2 and 0x0c1 (PCC [2^32 - 2, 2^32), CJAL at its base, to itself or 2 bytes
    below): the link address wraps to 0, which
    CHERIoT-Sail cannot represent against that PCC, and its CJAL asserts the link is always
    representable (cheri_insts.sail). The same holds for CJALR, so no landing pad (c.jr) sits at
    2^32 - 2 under a PCC with exponent < 24; link_ok() below enforces it. Both CJAL cases run
    in cheriot_cjal_link_wrap, with the cosim off.

What a landed case proves: BR_LANDED checks only that no trap happened, i.e. that execution
reached some c.jr a3 landing pad; it does not record which pad. Regions and blocks are shared
(the packer puts several cases' branches and pads in one block), so if a c.beqz were not taken
it would fall into the next slot, which can be another case's branch or pad, and the case would
still pass. The condition is a4 = 0, so a not-taken c.beqz would itself be an RTL defect, and
every unused slot is c.ebreak; the gap is only that the branch's target is not confirmed. A pad
that records its slot (c.li t1, n; c.jr a3) needs 4 bytes, which the 2..7-byte PCCs at 0 and at
the top of the address space (0x142..0x172, 0x0c2, 0x0e2, and section 11's 0x042..0x072)
cannot hold next to their branch, so it is not done. Faulting cases are not affected: their MEPCC.address check names the
target.

Output: the .inc defines BRANCH_BOUNDS_MAIN and BRANCH_FAR_MAIN (setup, entry and checks, run
from main) and the code they copy or enter (BRANCH_BOUNDS_REGIONS, BRANCH_FAR_BLOCKS).
Run: ./gen_branch_bounds.py > branch_bounds_cases.inc
"""

TOP = 1 << 32


def bound_case(base, top33, addr):
    """fcov_bound_check_cases() of core_ibex_fcov_if.sv."""
    r = 0
    r |= (addr < base) << 0
    r |= (addr == base) << 1
    r |= (addr > top33) << 2
    r |= (addr == top33) << 3
    room = (top33 - addr) & ((1 << 34) - 1)
    if 0 < room < 8:
        r |= (room & 7) << 4
    r |= (top33 == TOP) << 7
    r |= (base == 0) << 8
    return r


def lands(base, top33, addr):
    """Sail inCapBounds(PCC, addr, 2): the 2-byte fetch at the target is in bounds."""
    return base <= addr and addr + 2 <= top33


# Region cases in .text: (value, length, branch offset, target offset), offsets from the base.
# The base is 4-aligned (any alignment works: length <= 511 is exact at E = 0).
REGION = [
    (0x000, 16, 0, 4),
    (0x001, 16, 0, -4),
    (0x002, 16, 4, 0),
    (0x004, 16, 0, 20),
    (0x008, 16, 0, 16),
    (0x010, 9, 0, 8),
    (0x020, 8, 0, 6),
    (0x030, 9, 0, 6),
    (0x040, 8, 0, 4),
    (0x041, 2, 0, -2),
    (0x042, 4, 2, 0),
    (0x050, 9, 0, 4),
    (0x051, 3, 0, -2),
    (0x052, 5, 2, 0),
    (0x060, 8, 0, 2),
    (0x061, 4, 0, -2),
    (0x062, 6, 2, 0),
    (0x070, 9, 0, 2),
    (0x071, 5, 0, -2),
    (0x072, 7, 2, 0),
]

# Copied blocks: PCC base/length, block address, 2-byte slots (offset -> branch target offset
# or 'land'), and the cases (value, branch offset) entered through them.
HI_BASE = 0x81000000                     # [0x81000000, 2^32): E = 24 (CHERIoT has E 0..14 and 24), exact
HI_LEN = TOP - HI_BASE
HI_SLOTS = {0: "land", 2: 0, 4: -4, 6: 10, 10: "land"}
HI_CASES = [(0x082, 2), (0x080, 6), (0x081, 4)]

LO_TOP = 0x81000000                      # [0, 0x81000000): E = 24, exact
LO_BLK = LO_TOP - 32
LO_SLOTS = {0: 36, 2: 32, 4: 12, 6: 26, 8: 28, 10: 30, 12: "land", 26: "land", 28: "land",
            30: "land"}
LO_CASES = [(0x100, 4), (0x160, 6), (0x140, 8), (0x120, 10), (0x104, 0), (0x108, 2)]


def rtype(funct7, rs2, rs1, rd):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (rd << 7) | 0x5B


A1, A3, A5, T0, T1, T2, RA, TP = 11, 13, 15, 5, 6, 7, 1, 4
MTCC, MTDC = 28, 29
ENC = {
    "cspecialr ca1, mtcc": rtype(0x01, MTCC, 0, A1),
    "cspecialr ca3, mtcc": rtype(0x01, MTCC, 0, A3),
    "cspecialr ca1, mtdc": rtype(0x01, MTDC, 0, A1),
    "cspecialr ca5, mtdc": rtype(0x01, MTDC, 0, A5),
    "csetaddr ca1, ca1, t0": rtype(0x10, T0, A1, A1),
    "csetaddr ca3, ca3, t0": rtype(0x10, T0, A3, A3),
    "csetaddr ca5, ca5, t0": rtype(0x10, T0, A5, A5),
    "csetboundsexact ca1, ca1, t2": rtype(0x09, T2, A1, A1),
    "cgettag t1, ca1": rtype(0x7F, 0x04, A1, T1),
    # Section 12
    "cgettag t2, ct1": rtype(0x7F, 0x04, T1, T2),
    "cgettype t2, ct1": rtype(0x7F, 0x01, T1, T2),
    "cgetaddr t2, ct1": rtype(0x7F, 0x0F, T1, T2),
    "cgettag t2, cra": rtype(0x7F, 0x04, RA, T2),
    "cgettype t2, cra": rtype(0x7F, 0x01, RA, T2),
    "cgetaddr t2, cra": rtype(0x7F, 0x0F, RA, T2),
    "cgettag t1, ca5": rtype(0x7F, 0x04, A5, T1),
    "cgetaddr t1, ca5": rtype(0x7F, 0x0F, A5, T1),
    "cmove ctp, cra": rtype(0x7F, 0x0A, RA, TP),
    "cmove cra, ctp": rtype(0x7F, 0x0A, TP, RA),
}
# Encodings shared with the hand-written part of the test (its header table).
assert ENC["cspecialr ca1, mtcc"] == 0x03C005DB
assert ENC["csetaddr ca1, ca1, t0"] == 0x205585DB
assert ENC["csetboundsexact ca1, ca1, t2"] == 0x127585DB
assert ENC["cgettag t1, ca1"] == 0xFE45835B
assert ENC["cgettag t2, ct1"] == 0xFE4303DB
assert ENC["cgettype t2, ct1"] == 0xFE1303DB
assert ENC["cgetaddr t2, ct1"] == 0xFEF303DB


def w(insn):
    return f"    .word   0x{ENC[insn]:08X}              # {insn}"


def main():
    out = []
    emit = out.append
    emit("// Generated by gen_branch_bounds.py -- do not edit.")
    emit("// Section 11 of cheriot_fetch_bounds: one taken branch per cp_cheri_branch_bound value.")
    emit("")
    emit("// Enter the region in ca1 (cursor = the branch) with a3 = MTCC at \\chk; a landing pad")
    emit("// (c.jr a3) and a fetch fault (MTCC = .Lvec_br: jalr zero, 0(a3)) both continue at \\chk.")
    emit(".macro BR_ENTER chk")
    emit("    LA_PC   t0, \\chk")
    emit(w("cspecialr ca3, mtcc"))
    emit(w("csetaddr ca3, ca3, t0"))
    emit("    SET_TRAP_VECTOR .Lvec_br")
    emit("    csrw    mcause, zero")
    emit("    jalr    zero, 0(a1)")
    emit(".endm")
    emit("")
    emit("// The branch target was fetched and ran its landing pad: no trap.")
    emit(".macro BR_LANDED code")
    emit("    csrr    t1, mcause")
    emit("    CHECK_EQ t1, zero, \\code+2")
    emit(".endm")
    emit("")
    emit("// The fetch of the target faulted (t2 = target): mcause 28, mtval 0x401, MEPCC = target.")
    emit(".macro BR_FAULTED code")
    emit("    mv      a5, t2")
    emit("    csrr    t1, mcause")
    emit("    li      t2, 28")
    emit("    CHECK_EQ t1, t2, \\code+2")
    emit("    csrr    t1, mtval")
    emit("    li      t2, 0x401")
    emit("    CHECK_EQ t1, t2, \\code+3")
    emit("    .word   0x03F0035B              # cspecialr       ct1, mepcc")
    emit("    .word   0xFEF3035B              # cgetaddr        t1, ct1")
    emit("    CHECK_EQ t1, a5, \\code+3")
    emit(".endm")
    emit("")

    main_lines = []
    m = main_lines.append
    regions = []
    code = 300
    count = {"land": 0, "fault": 0}

    def check(kind, target_load):
        if kind == "land":
            m(f"    BR_LANDED {code}")
        else:
            m(target_load)
            m(f"    BR_FAULTED {code}")
        count[kind] += 1

    m(".macro BRANCH_BOUNDS_MAIN")
    m("    li      a4, 0                   # c.beqz a4 is always taken")
    # Copy the two far blocks (word by word, through MTDC) and make them fetchable.
    for src, dst, size in ((".Lbrc_hi", HI_BASE, 16), (".Lbrc_lo", LO_BLK, 32)):
        m(f"    LA_PC   t0, {src}")
        m(w("cspecialr ca5, mtdc"))
        m(w("csetaddr ca5, ca5, t0"))
        m(f"    li      t0, 0x{dst:08X}")
        m(w("cspecialr ca1, mtdc"))
        m(w("csetaddr ca1, ca1, t0"))
        for k in range(0, size, 4):
            m(f"    lw      t1, {k}(a5)")
            m(f"    sw      t1, {k}(a1)")
    m("    fence.i")

    for i, (val, length, e, o) in enumerate(REGION):
        base = 0x1000 * (i + 1)          # any base: only the offsets matter
        got = bound_case(base, base + length, base + o)
        assert got == val, (hex(val), hex(got))
        assert 0 <= e and e + 2 <= length, val
        kind = "land" if lands(base, base + length, base + o) else "fault"
        lbl = f".Lbr{i}"
        m(f"    # 0x{val:03x}: length {length}, branch at base+{e}, target base{o:+d} ({kind})")
        m("    li      s0, 11")
        m("    SET_TRAP_VECTOR .Lvec_unexpected")
        m(f"    BUILD_REGION {lbl}_base, {lbl}_base+{length}, {code}")
        if e:
            m(f"    LA_PC   t0, {lbl}_base+{e}")
            m(w("csetaddr ca1, ca1, t0"))
        m(f"    BR_ENTER {lbl}_chk")
        m(f"{lbl}_chk:")
        check(kind, f"    LA_PC   t2, {lbl}_base{o:+d}")
        code += 4
        # Region: 2-byte slots from the base; the branch, a landing pad at the target, and
        # c.ebreak everywhere else (anything else that runs traps with mcause 3).
        slots = {e: f"c.beqz  a4, {lbl}_base{o:+d}"}
        if kind == "land":
            slots[o] = "c.jr    a3"
        r = ["    ALIGN4", f"{lbl}_base:"]
        for k in range(0, length + (length & 1), 2):
            r.append(f"    {slots.get(k, 'c.ebreak')}")
        regions.append("\n".join(r))

    for name, pbase, plen, blk, slots, cases in (
            ("hi", HI_BASE, HI_LEN, HI_BASE, HI_SLOTS, HI_CASES),
            ("lo", 0, LO_TOP, LO_BLK, LO_SLOTS, LO_CASES)):
        top33 = pbase + plen
        for val, e in cases:
            o = slots[e]
            assert o != "land"
            pc, target = blk + e, blk + o
            got = bound_case(pbase, top33, target)
            assert got == val, (name, hex(val), hex(got))
            assert pbase <= pc and pc + 2 <= top33
            kind = "land" if lands(pbase, top33, target) else "fault"
            assert kind == "fault" or slots.get(o) == "land", (name, hex(val))
            m(f"    # 0x{val:03x}: PCC [0x{pbase:08x}, 0x{top33:09x}), branch at 0x{pc:08x}, "
              f"target 0x{target:08x} ({kind})")
            m("    li      s0, 11")
            m("    SET_TRAP_VECTOR .Lvec_unexpected")
            m(w("cspecialr ca1, mtcc"))
            m(f"    li      t0, 0x{pbase:08X}")
            m(w("csetaddr ca1, ca1, t0"))
            m(f"    li      t2, 0x{plen & 0xFFFFFFFF:08X}")
            m(w("csetboundsexact ca1, ca1, t2"))
            m(w("cgettag t1, ca1"))
            m("    li      t2, 1")
            m(f"    CHECK_EQ t1, t2, {code}")
            m(f"    li      t0, 0x{pc:08X}")
            m(w("csetaddr ca1, ca1, t0"))
            m(w("cgettag t1, ca1"))
            m(f"    CHECK_EQ t1, t2, {code}+1")
            m(f"    BR_ENTER .Lbrc{code}_chk")
            m(f".Lbrc{code}_chk:")
            check(kind, f"    li      t2, 0x{target:08X}")
            code += 4
        size = 16 if name == "hi" else 32
        r = ["    ALIGN4", f".Lbrc_{name}:"]
        for k in range(0, size, 2):
            s = slots.get(k, None)
            if s is None:
                r.append("    c.ebreak")
            elif s == "land":
                r.append("    c.jr    a3")
            else:
                r.append(f"    c.beqz  a4, .Lbrc_{name}{s:+d}")
        regions.append("\n".join(r))
    m(".endm")
    # The last case must fault: the test's final check expects mcause = 28.
    assert LO_CASES[-1][0] == 0x108

    out.extend(main_lines)
    emit("")
    emit(f"// {count['land'] + count['fault']} cases: {count['land']} land, "
         f"{count['fault']} fault. Codes 300..{code - 1}.")
    emit("")
    emit(".macro BRANCH_BOUNDS_REGIONS")
    emit("    .option push")
    emit("    .option rvc")
    out.extend(regions)
    emit("    .option pop")
    emit(".endm")
    emit("")
    out.extend(far_section())
    print("\n".join(out))


# ---- Section 12: code at both ends of the address space -------------------------------------

def sail_set_bounds(base, length):
    """CHERIoT-Sail setCapBounds (cheri_cap_common.sail): (exact, E, B, T)."""
    top = base + length
    e = (length >> 9).bit_length()                     # 23 - count_leading_zeros(length[31:9])
    e_sat = 24 if e > 14 else e

    def bt(es):
        b = (base >> es) & 0x3FF
        t = (top >> es) & 0x3FF
        lost = (top & ((1 << es) - 1)) != 0
        return b, (t + lost) & 0x3FF, lost
    b, t, lost_top = bt(e_sat)
    if (t - b) & 0x3FF > 0x1FF:
        e_sat = e_sat + 1 if e_sat < 14 else 24
        b, t, lost_top = bt(e_sat)
    lost_base = (base & ((1 << e_sat) - 1)) != 0
    return not (lost_base or lost_top), e_sat, b & 0x1FF, t & 0x1FF


def sail_bounds(cap, addr):
    """CHERIoT-Sail getCapBoundsBits for capability (E, B, T) with address addr: (base, top)."""
    e, b, t = cap
    a_hi = 1 if ((addr >> e) & 0x1FF) < b else 0
    t_hi = 1 if t < b else 0
    a_top = addr >> (e + 9)
    base = ((((a_top - a_hi) & 0xFFFFFFFF) << (e + 9)) | (b << e)) & 0xFFFFFFFF
    top = ((((a_top + t_hi - a_hi) & 0xFFFFFFFF) << (e + 9)) | (t << e)) & 0x1FFFFFFFF
    return base, top


def representable(cap, old, new):
    """CHERIoT-Sail setCapAddr: the bounds decode the same with the new address."""
    return sail_bounds(cap, old) == sail_bounds(cap, new & 0xFFFFFFFF)


ROOT_CAP = (24, 0, 0x100)               # MTCC at reset: [0, 2^32), T = cap_reset_T


def pcc_cap(base, length):
    """The PCC a case runs under: root MTCC (length None) or CSetBoundsExact(base, length)."""
    if length is None:
        return ROOT_CAP
    exact, e, b, t = sail_set_bounds(base, length)
    assert exact, (hex(base), length)
    assert sail_bounds((e, b, t), base) == (base, base + length), (hex(base), length)
    return (e, b, t)


def link_ok(cap, pc, next_pc):
    """CJAL/CJALR assert that the link, PCC with address next_pc, is representable."""
    return representable(cap, pc, next_pc)


# Windows the blocks are copied to (address, size). bot/top need +far_code_windows=1; hi/lo are
# the section 11 blocks' places in bench memory.
WINDOWS = {
    "bot": (0x00000000, 48),
    "top": (TOP - 32, 32),
    "hi":  (0x81000000, 16),
    "lo":  (0x80FFFFE0, 32),
}

HI_PCC = (HI_BASE, HI_LEN)               # [0x81000000, 2^32), E = 24
ROOT = (0, None)

# (value, kind, window, offset, arg, PCC (base, length)). kind: "b" c.beqz a4 (always taken) to
# window+arg; "j" CJAL ct1 (32-bit jal t1) to window+arg; "cj" CJAL cra (c.jal) to window+arg;
# "auipcc" AUIPCC ca5 with imm20 = arg. Offsets are from the window base.
FAR_CASES = [
    # cheriot_instr_branch_cross / cp_cheri_branch_bound
    (0x0a0, "b", "top", 12, 30, HI_PCC),
    (0x0c0, "b", "top", 14, 28, HI_PCC),
    (0x0e0, "b", "top", 16, 26, HI_PCC),
    (0x1a0, "b", "top", 12, 30, ROOT),
    (0x1c0, "b", "top", 14, 28, ROOT),
    (0x1e0, "b", "top", 16, 26, ROOT),
    (0x0c2, "b", "top", 30, 28, (TOP - 4, 4)),
    (0x0e1, "b", "top", 28, 26, (TOP - 4, 4)),
    (0x0e2, "b", "top", 28, 26, (TOP - 6, 6)),
    (0x102, "b", "bot", 2, 0, (0, 16)),
    (0x142, "b", "bot", 2, 0, (0, 4)),
    (0x152, "b", "bot", 2, 0, (0, 5)),
    (0x162, "b", "bot", 2, 0, (0, 6)),
    (0x172, "b", "bot", 2, 0, (0, 7)),
    (0x182, "b", "bot", 2, 0, ROOT),
    (0x110, "b", "bot", 4, 40, (0, 41)),
    (0x130, "b", "bot", 6, 38, (0, 41)),
    (0x150, "b", "bot", 8, 36, (0, 41)),
    (0x170, "b", "bot", 10, 34, (0, 41)),
    # cp_cheri_cjal_bound
    (0x0a0, "j", "top", 0, 30, HI_PCC),
    (0x0c0, "j", "top", 4, 28, HI_PCC),
    (0x0e0, "j", "top", 8, 26, HI_PCC),
    (0x1a0, "j", "top", 0, 30, ROOT),
    (0x1c0, "j", "top", 4, 28, ROOT),
    (0x1e0, "j", "top", 8, 26, ROOT),
    (0x0e1, "cj", "top", 28, 26, (TOP - 4, 4)),
    (0x0e2, "cj", "top", 28, 26, (TOP - 6, 6)),
    (0x102, "j", "bot", 12, 0, (0, 16)),
    (0x142, "cj", "bot", 2, 0, (0, 4)),
    (0x152, "cj", "bot", 2, 0, (0, 5)),
    (0x162, "j", "bot", 2, 0, (0, 6)),
    (0x172, "j", "bot", 2, 0, (0, 7)),
    (0x182, "j", "bot", 2, 0, ROOT),
    (0x110, "j", "bot", 12, 40, (0, 41)),
    (0x130, "j", "bot", 16, 38, (0, 41)),
    (0x150, "j", "bot", 20, 36, (0, 41)),
    (0x170, "j", "bot", 24, 34, (0, 41)),
    (0x082, "j", "hi", 4, 0, HI_PCC),
    (0x081, "j", "hi", 8, -4, HI_PCC),
    (0x120, "j", "lo", 0, 30, (0, LO_TOP)),
    (0x140, "j", "lo", 4, 28, (0, LO_TOP)),
    (0x160, "j", "lo", 8, 26, (0, LO_TOP)),
    (0x104, "j", "lo", 12, 40, (0, LO_TOP)),
    (0x108, "j", "lo", 16, 32, (0, LO_TOP)),
    # Section 11's small regions for CJAL: c.jal 2 bytes below the base of a PCC of length
    # 2..5, or from base + 2 back to the base of one of length 4..7
    (0x041, "cj", "lo", 16, 14, (LO_BLK + 16, 2)),
    (0x051, "cj", "lo", 16, 14, (LO_BLK + 16, 3)),
    (0x061, "cj", "lo", 16, 14, (LO_BLK + 16, 4)),
    (0x071, "cj", "lo", 16, 14, (LO_BLK + 16, 5)),
    (0x042, "cj", "lo", 18, 16, (LO_BLK + 16, 4)),
    (0x052, "cj", "lo", 18, 16, (LO_BLK + 16, 5)),
    (0x062, "cj", "lo", 18, 16, (LO_BLK + 16, 6)),
    (0x072, "cj", "lo", 18, 16, (LO_BLK + 16, 7)),
    # The in-range value under an odd top that section 11 reaches only with a branch: c.jal from
    # the base of a PCC of length 9 to base + 2, 7 bytes under the top (fcov merge 2026-10-09:
    # cp_cheri_cjal_bound 0x070 the one bin no source produced)
    (0x070, "cj", "lo", 16, 18, (LO_BLK + 16, 9)),
    # The same for 0x020: c.jal from the base of a PCC of length 8 to base + 6, 2 bytes under the
    # top, where its c.jr a3 pad fits exactly (fcov merge 2026-10-09 21:22, seed 4408: 0 hits;
    # only cheriot_rand_operands' random cjal group had produced it, on other seeds)
    (0x020, "cj", "lo", 16, 22, (LO_BLK + 16, 8)),
    # cheriot_cauipcc_cross: (repr case, exponent bin, imm20 bin) in the comment
    (None, "auipcc", "top", 20, 0x00001, (TOP - 32, 32)),     # case1, E = 0, bin2
    (None, "auipcc", "top", 20, 0x00001, (TOP - 1024, 1024)), # case1, E = 2, bin2
    (None, "auipcc", "bot", 20, 0x80000, (0, 48)),            # case2, E = 0, bin3
    (None, "auipcc", "bot", 20, 0xFFFFE, (0, 48)),            # case2, E = 0, bin4
    (None, "auipcc", "bot", 20, 0xFFFFF, (0, 48)),            # case2, E = 0, bin5
    (None, "auipcc", "bot", 20, 0x80000, (0, 1024)),          # case2, E = 2, bin3
    (None, "auipcc", "bot", 20, 0xFFFFE, (0, 1024)),          # case2, E = 2, bin4
    (None, "auipcc", "bot", 20, 0xFFFFF, (0, 1024)),          # case2, E = 2, bin5
    # Last: a fault, so that main's final mcause check (28) still holds.
    (0x0c1, "b", "top", 30, 28, (TOP - 2, 2)),
]

INSN_LEN = {"b": 2, "cj": 2, "j": 4, "auipcc": 4, "land": 2}
A5_REG = 15


def far_case_layout(case):
    """Check one case against the RTL coverage functions and Sail; return what it needs."""
    val, kind, win, off, arg, (pbase, plen) = case
    wbase, wsize = WINDOWS[win]
    cap = pcc_cap(pbase, plen)
    top33 = TOP if plen is None else pbase + plen
    pc = wbase + off
    assert pbase <= pc and pc + INSN_LEN[kind] <= top33, case          # fetchable
    assert 0 <= off and off + INSN_LEN[kind] <= wsize, case
    slots = {off: (kind, arg)}
    if kind == "auipcc":
        imm = arg
        offset = ((imm ^ 0x80000) - 0x80000) << 11
        result = (pc + offset) & 0xFFFFFFFF
        e = cap[0]
        rbase, _ = sail_bounds(cap, pc)
        rc = 0 if e == 24 else 1 if result < rbase else 2 if result - rbase >= (1 << (9 + e)) else 0
        assert rc in (1, 2), case                                       # wraps out of range
        tag = representable(cap, pc, result)
        land = off + 4
        assert link_ok(cap, wbase + land, wbase + land + 2), case
        slots[land] = ("land", None)
        return dict(cap=cap, pc=pc, slots=slots, landed=True, result=result, tag=tag,
                    rcase=rc, ebin=0 if e == 0 else 1 if e <= 14 else 2)
    target = (wbase + arg) & 0xFFFFFFFF
    assert bound_case(pbase, top33, target) == val, (case, hex(bound_case(pbase, top33, target)))
    assert target != pc, case                                           # not a self-loop
    landed = lands(pbase, top33, target)
    if kind in ("j", "cj"):
        assert link_ok(cap, pc, pc + INSN_LEN[kind]), case
    if landed:
        assert 0 <= arg and arg + 2 <= wsize, case
        assert link_ok(cap, target, target + 2), case                   # its c.jr a3
        slots[arg] = ("land", None)
    return dict(cap=cap, pc=pc, target=target, slots=slots, landed=landed)


def pack_blocks(cases):
    """First-fit cases into blocks per window: a block holds cases whose code does not clash."""
    blocks = []
    for case in cases:
        lay = far_case_layout(case)
        units = {}
        for o, (k, a) in lay["slots"].items():
            for u in range(0, INSN_LEN[k], 2):
                units[o + u] = (o, k, a)
        for blk in blocks:
            if blk["win"] == case[2] and all(blk["units"].get(u, v) == v for u, v in units.items()):
                break
        else:
            blk = {"win": case[2], "units": {}, "cases": []}
            blocks.append(blk)
        blk["units"].update(units)
        blk["cases"].append((case, lay))
    return blocks


def far_section():
    out = []
    m = out.append
    blocks = pack_blocks(FAR_CASES)
    # Run the blocks in order, but keep the case listed last (a fault) last.
    last = FAR_CASES[-1]
    blocks.sort(key=lambda blk: any(c is last for c, _ in blk["cases"]))
    # The AUIPCC cases are exactly the cheriot_cauipcc_cross bins that need a wrapped result:
    # (cp_cheri_cd_pcc_repr_cases, cp_cheri_pcc_exp bin0/bin1, cp_cheri_imm20 bin2..bin5).
    def imm_bin(i):
        return 1 if i == 0 else 2 if i < 0x80000 else 3 if i == 0x80000 else 5 if i == 0xFFFFF else 4
    got = {(lay["rcase"], lay["ebin"], imm_bin(c[4]))
           for blk in blocks for c, lay in blk["cases"] if c[1] == "auipcc"}
    assert got == {(1, 0, 2), (1, 1, 2)} | {(2, e, b) for e in (0, 1) for b in (3, 4, 5)}, got
    m("// Section 12 of cheriot_fetch_bounds: code copied to both ends of the address space")
    m("// (+far_code_windows=1) and to the section 11 blocks' places. Per block: copy it, then run")
    m("// its cases. Case n uses codes 500+6n .. 500+6n+5.")
    m(".macro BRANCH_FAR_MAIN")
    m("    li      a4, 0                   # c.beqz a4 is always taken")
    code = 500
    n_land = n_fault = n_auipcc = 0
    for k, blk in enumerate(blocks):
        wbase, wsize = WINDOWS[blk["win"]]
        m(f"    # block {k}: {blk['win']} window, copied to 0x{wbase:08X}")
        # A trap during the copy reports 912, not the previous case's code through its .Lvec_br.
        m("    li      s0, 12")
        m("    SET_TRAP_VECTOR .Lvec_unexpected")
        m(f"    LA_PC   t0, .Lfar{k}")
        m(w("cspecialr ca5, mtdc"))
        m(w("csetaddr ca5, ca5, t0"))
        m(f"    li      t0, 0x{wbase:08X}")
        m(w("cspecialr ca1, mtdc"))
        m(w("csetaddr ca1, ca1, t0"))
        for o in range(0, wsize, 4):
            m(f"    lw      t1, {o}(a5)")
            m(f"    sw      t1, {o}(a1)")
        m("    fence.i")
        for (val, kind, win, off, arg, (pbase, plen)), lay in blk["cases"]:
            pc = lay["pc"]
            e = lay["cap"][0]
            pcc_txt = ("root PCC" if plen is None else
                       f"PCC [0x{pbase:08x}, 0x{pbase + plen:09x}) E={e}")
            if kind == "auipcc":
                m(f"    # AUIPCC ca5, 0x{arg:05x} at 0x{pc:08x}, {pcc_txt}: result "
                  f"0x{lay['result']:08x}, case{lay['rcase']}, tag {int(lay['tag'])}")
            else:
                insn = {"b": "c.beqz", "j": "CJAL ct1", "cj": "CJAL cra (c.jal)"}[kind]
                m(f"    # 0x{val:03x}: {insn} at 0x{pc:08x} to 0x{lay['target']:08x}, {pcc_txt} "
                  f"({'land' if lay['landed'] else 'fault'})")
            m("    li      s0, 12")
            m("    SET_TRAP_VECTOR .Lvec_unexpected")
            m(w("cspecialr ca1, mtcc"))
            m("    li      t2, 1")
            if plen is not None:
                m(f"    li      t0, 0x{pbase:08X}")
                m(w("csetaddr ca1, ca1, t0"))
                m(f"    li      t2, 0x{plen:08X}")
                m(w("csetboundsexact ca1, ca1, t2"))
                m(w("cgettag t1, ca1"))
                m("    li      t2, 1")
                m(f"    CHECK_EQ t1, t2, {code}")
            m(f"    li      t0, 0x{pc:08X}")
            m(w("csetaddr ca1, ca1, t0"))
            m(w("cgettag t1, ca1"))
            m(f"    CHECK_EQ t1, t2, {code}+1")
            m(f"    BR_ENTER .Lfc{code}_chk")
            m(f".Lfc{code}_chk:")
            if kind in ("j", "cj"):
                reg, otype, ln = ("ct1", 0, 4) if kind == "j" else ("cra", 4, 2)
                m(w(f"cgettag t2, {reg}"))
                m("    li      t0, 1")
                m(f"    CHECK_EQ t2, t0, {code}+4")
                m(w(f"cgettype t2, {reg}"))
                m(f"    li      t0, {otype}" + ("                   # otype_sentry_bid: MIE = 0"
                                                if otype else ""))
                m(f"    CHECK_EQ t2, t0, {code}+4")
                m(w(f"cgetaddr t2, {reg}"))
                m(f"    li      t0, 0x{(pc + ln) & 0xFFFFFFFF:08X}")
                m(f"    CHECK_EQ t2, t0, {code}+5")
            if lay["landed"]:
                m(f"    BR_LANDED {code}")
                n_land += 1
            else:
                m(f"    li      t2, 0x{lay['target']:08X}")
                m(f"    BR_FAULTED {code}")
                n_fault += 1
            if kind == "auipcc":
                m(w("cgettag t1, ca5"))
                m(f"    li      t2, {int(lay['tag'])}")
                m(f"    CHECK_EQ t1, t2, {code}+4")
                m(w("cgetaddr t1, ca5"))
                m(f"    li      t2, 0x{lay['result']:08X}")
                m(f"    CHECK_EQ t1, t2, {code}+5")
                n_auipcc += 1
            code += 6
    assert blocks[-1]["cases"][-1][0] is last and not blocks[-1]["cases"][-1][1]["landed"]
    assert code < 900                        # 900 + section: unexpected trap
    m(".endm")
    m("")
    m(f"// {len(FAR_CASES)} cases: {n_land - n_auipcc} land, {n_fault} fault, {n_auipcc} AUIPCC. "
      f"Codes 500..{code - 1}.")
    m("")
    m(".macro BRANCH_FAR_BLOCKS")
    m("    .option push")
    m("    .option rvc")
    for k, blk in enumerate(blocks):
        wbase, wsize = WINDOWS[blk["win"]]
        m("    ALIGN4")
        m(f".Lfar{k}:                            # copied to 0x{wbase:08X}")
        o = 0
        while o < wsize:
            ent = blk["units"].get(o)
            if ent is None:
                m("    c.ebreak")
                o += 2
                continue
            start, kind, arg = ent
            assert start == o
            if kind == "land":
                m("    c.jr    a3")
            elif kind == "b":
                m(f"    c.beqz  a4, .Lfar{k}{arg:+d}")
            elif kind == "cj":
                m(f"    c.jal   .Lfar{k}{arg:+d}")
            elif kind == "j":
                m(f"    jal     t1, .Lfar{k}{arg:+d}")
            else:
                enc = (arg << 12) | (A5_REG << 7) | 0x17
                m(f"    .word   0x{enc:08X}              # auipcc ca5, 0x{arg:05x}")
            o += INSN_LEN[kind]
    m("    .option pop")
    m(".endm")
    return out


if __name__ == "__main__":
    main()
