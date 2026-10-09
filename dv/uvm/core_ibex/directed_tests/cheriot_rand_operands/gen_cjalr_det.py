#!/usr/bin/env python3
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""Generate cjalr_det_cases.inc for cheriot_rand_operands.S: CJALR cases over the bins of
cheriot_cjalr_cross1 = cs1 tag x cs1 EX x cp_cheri_cjalr_bound (fcov_bound_check_cases(cs1,
target), 63 values) x cp_cheri_imm12 class (0 / 1..2047 / -2048 / -2047..-2 / -1).

Every expectation comes from a model of the CHERIoT-Sail semantics, below:
  decode()        getCapBoundsBits (cheri_cap_common.sail): base32/top33 from E, B, T, address
  set_bounds()    setCapBounds: CSetBoundsExact from MTCC, used only when exact
  representable() setCapAddr: CSetAddr keeps the tag iff the decoded bounds do not change
  CJALR           cheri_insts.sail: tag, then seal, then EX is checked on cs1; the target is
                  (cs1.address + imm) with bit 0 cleared; PCC := cs1 (address unchanged, so its
                  bounds are those decoded at the cursor) and nothing checks the target bounds
  fetch           cheri_addr_checks.sail ext_fetch_check_pc: inCapBounds(PCC, pc, 2) per
                  2-byte granule, so a 32-bit instruction needs 4 bytes in bounds
  link            CJAL/CJALR assert that the link (pc + 4) is representable against PCC
                  (cheri_insts.sail), so no landing zone ends in a linking jump whose link
                  could wrap past 2^32 or leave the representable range
The RTL is only used as a cross-check: rtl_representable() is cheriot_set_address
(ibex_cheriot_pkg.sv), and a cursor on which it disagrees with Sail is never used.

Search: for each cs1 shape (MTCC CSetBoundsExact at E = 0, 3 and 24, the MTCC root, and raw
CSetHigh metadata, which is untagged), target near the base, the top, 0, 2^32 and 2048 beyond
them, immediate (IMMS) and cursor = target - imm or target - imm + 1 (the sum's bit 0 is
cleared, so both give the target), the model gives the bound value and which of the four tag x EX
rows the case reaches. Cases are then picked greedily until no new bin is added.

The rows and what each attempt does (every one ends in the test's trap handler or the landing
check; none runs code the test does not control):
  untagged, EX or not; tagged without EX  -> CJALR faults on cs1 (tag / EX violation)
  tagged with EX, target fetch out of bounds -> the jump happens, the fetch faults: mtval 0x401
  tagged with EX, target fetch in bounds  -> only when the target is in a landing zone, which
      the test writes: c.addi t2, 1 in every halfword, ended by a jump back to the attempt.
      The model gives the number of c.addi executed before the fetch leaves PCC's bounds (n),
      and whether the jump back is fetched (ret) or faults instead.

Landing zones (ZONES):
  main    [0x80FFFF80, 0x81000080) with `cjalr c0, ca5` at 0x81000080: always written; in
          bench memory and in the CHERIoT-Sail model's default RAM (0x80000000 + 256 MiB).
  bottom  [0, 0x80) with `cjalr c0, ca5` at 0x80, and
  top     [0xFFFFFF80, 0xFFFFFFFE) with `c.beqz a0, CJ_TRET` at 0xFFFFFFFE (a0 = 0 in every
          attempt; a branch has no link, so Sail's link assert cannot fire at 2^32 - 2) back to
          `cjalr c0, ca5` at CJ_TRET = 0xFFFFFF78. No fetch crosses 2^32: the last halfword in
          the zone is a 2-byte instruction, and nothing is placed at 2^32 - 2 that would need 4
          bytes.
  The bottom and top zones exist only in the FAR_WINDOWS build (cheriot_rand_operands_far:
  -DFAR_WINDOWS, run with +far_code_windows=1, which makes CHERIoT-Sail map [0, 0x1000) and
  [0x80000000, 2^32); the bench and Spike answer every address). Their cases are emitted in a
  separate `#ifdef FAR_WINDOWS` section after the default cases, so the default build's part of
  the .inc does not depend on them, and are chosen only for bins the default cases leave out:
  the tagged + EX bins whose target is fetched in bounds within 7 bytes of 0 or of 2^32, i.e.
  cp_cheri_cjalr_bound 0x0a0/0x0c0/0x0e0 (top33 = 2^32, room 2/4/6), 0x0a2/0x0c2/0x0e2 (the
  same at the base), 0x102 and 0x182 (base 0, target at the base, E = 24 / root), 0x122..0x172
  (base 0 at the base with room 2..7) and 0x130/0x150/0x170 (base 0, odd room) over the
  immediate classes the search reaches: 63 bins (the far section's header lists them), plus
  the 24 bins of RANDOM_HIT (0x1a0/0x1c0/0x1e0 under the root and the rest of 0x130/0x150/
  0x170/0x172), which the same zones reach and the regression's random loop also hits.
  CJD_NTRY counts the default attempts and CJD_NTRY_FAR the far ones, each from its own cases.

The bins no case reaches (-v lists each with its reason) are the memory-map ones above in the
default build ("far"), the five groups the fcov closure review of 2026-10-07 found unreachable
for every encoding ("unreachable <group>": imm -2048 with an odd room, m2048_oddroom, or at a
base with room <= 7, m2048_atbase_short, as the window is <= 2048 bytes; top33 = 2^32 with the
target in the last bytes, top32_last_bytes / top32_last2_neg; tagged below a base with room <= 7
and imm > 0 or -2048, tag_below_short; tagged zero length with imm -2048, tag_zerolen_m2048),
and the bins the random cjalr group of the regression already hits ("random loop",
RANDOM_HIT). The search finding an unreachable one would contradict that review, and a bin in
no class is reported as UNEXPLAINED.

Run: python3 gen_cjalr_det.py > cjalr_det_cases.inc   (-v lists the bins left uncovered)
"""

import sys

TOP32 = 1 << 32
M32 = TOP32 - 1
M33 = (1 << 33) - 1
GENERIC = 0x80030000          # any even base away from the edges of the address space
ZLO, ZHI = 0x80FFFF80, 0x81000080   # main landing zone; 0x81000000 is in it (E = 24 bases, tops)
ZB = 0x80FFFFC0               # E = 0 / E = 3 bases whose regions lie in the main zone

# Landing zones: (name, lo, hi, ret, branch, far). c.addi t2, 1 fills [lo, hi); the jump back
# to the attempt is `cjalr c0, ca5` at ret, reached straight from hi (branch = False, ret == hi)
# or by a `c.beqz a0` at hi (branch = True; the target may then be hi itself). far: only in
# the FAR_WINDOWS build.
ZONE_MAIN = ("main", ZLO, ZHI, ZHI, False, False)
ZONE_BOT = ("bottom", 0x00000000, 0x00000080, 0x00000080, False, True)
ZONE_TOP = ("top", 0xFFFFFF80, 0xFFFFFFFE, 0xFFFFFF78, True, True)
ZONES = [ZONE_MAIN, ZONE_BOT, ZONE_TOP]
assert ZONE_TOP[3] + 8 == ZONE_TOP[1]      # cjalr, ebreak, then the c.addi (CJ_ZONE_FAR_INIT)
assert ZONE_TOP[2] + 2 == TOP32            # the c.beqz is the last halfword below 2^32

CLASSES = ["bin1", "bin2", "bin3", "bin4", "bin5"]
IMMS = [0, 1, 2, 6, 8, 2047, -2048, -2, -3, -4, -5, -6, -7, -8, -16, -2047, -1]
VALUES = [0x000, 0x001, 0x002, 0x004, 0x008, 0x00a, 0x010, 0x011, 0x012, 0x020, 0x021, 0x022,
          0x030, 0x031, 0x032, 0x040, 0x041, 0x042, 0x050, 0x051, 0x052, 0x060, 0x061, 0x062,
          0x070, 0x071, 0x072, 0x080, 0x081, 0x082, 0x0a0, 0x0a1, 0x0a2, 0x0c0, 0x0c1, 0x0c2,
          0x0e0, 0x0e1, 0x0e2, 0x100, 0x102, 0x104, 0x108, 0x10a, 0x110, 0x112, 0x120, 0x122,
          0x130, 0x132, 0x140, 0x142, 0x150, 0x152, 0x160, 0x162, 0x170, 0x172, 0x180, 0x182,
          0x1a0, 0x1c0, 0x1e0]  # the 78 bound values minus the 15 top32/odd-room ones
ROWS = [(0, 0), (0, 1), (1, 0), (1, 1)]   # (cs1 tag, cs1 EX)
META_EX = 0x2F                # cperms: GL + executable format with SR, LM, LG

# The five groups the fcov closure review of 2026-10-07 found unreachable for every encoding
# (tech-notes/fcov_closure_2026-10-07.md, cheriot_cjalr_cross1): (name, rows or None for all,
# values, classes). A bin is in the first group that matches.
UNREACHABLE = [
    ("m2048_oddroom", None, [0x010, 0x011, 0x030, 0x031, 0x050, 0x051, 0x070, 0x071, 0x110,
                             0x130, 0x150, 0x170], ["bin3"]),
    ("m2048_atbase_short", None, [0x012, 0x022, 0x032, 0x042, 0x052, 0x062, 0x072, 0x0a2,
                                  0x0c2, 0x0e2, 0x112, 0x122, 0x132, 0x142, 0x152, 0x162,
                                  0x172], ["bin3"]),
    ("top32_last_bytes", None, [0x0a1, 0x0c1, 0x0e1], ["bin2", "bin3"]),
    ("top32_last2_neg", None, [0x0a1, 0x0a2], ["bin4"]),
    ("tag_below_short", [(1, 0), (1, 1)], [0x011, 0x021, 0x031, 0x041, 0x051, 0x061, 0x071],
     ["bin2", "bin3"]),
    ("tag_zerolen_m2048", [(1, 0), (1, 1)], [0x00a, 0x10a], ["bin3"]),
]
# Tagged + EX bins the regression's random cjalr group already hits (fcov closure review of
# 2026-10-07, cheriot_cjalr_cross1 needs_stimulus): not searched for here.
RANDOM_HIT = {((1, 1), v, c) for v, cs in [(0x1a0, CLASSES), (0x1c0, CLASSES), (0x1e0, CLASSES),
                                            (0x130, ["bin1", "bin4", "bin5"]),
                                            (0x150, ["bin1", "bin4", "bin5"]),
                                            (0x170, ["bin1", "bin5"]), (0x172, ["bin4"])]
              for c in cs}


def imm_class(imm):
    if imm == 0:
        return "bin1"
    if imm == -2048:
        return "bin3"
    if imm == -1:
        return "bin5"
    return "bin2" if imm > 0 else "bin4"


def decode(e, b, t, addr):
    """getCapBoundsBits: (base32, top33) of a capability with exponent e (0..14, 24),
    mantissas b, t and address addr."""
    a_hi = 1 if ((addr >> e) & 0x1FF) < b else 0
    t_hi = 1 if t < b else 0
    a_top = addr >> (e + 9)
    base = (((a_top - a_hi) << (e + 9)) | (b << e)) & M32
    top = (((a_top + t_hi - a_hi) << (e + 9)) | (t << e)) & M33
    return base, top


def set_bounds(base, length):
    """setCapBounds: (exact, (e, B, T))."""
    top = base + length
    l23 = length >> 9
    e = l23.bit_length()                  # 23 - count_leading_zeros(truncateLSB(length, 23))
    es = 24 if e > 14 else e

    def mant(es):
        b = (base >> es) & 0x3FF
        t = (top >> es) & 0x3FF
        lost_top = (top & ((1 << es) - 1)) != 0
        if lost_top:
            t = (t + 1) & 0x3FF
        return b, t, lost_top
    b, t, lost_top = mant(es)
    if ((t - b) & 0x3FF) > 0x1FF:
        es = es + 1 if es < 14 else 24
        b, t, lost_top = mant(es)
    lost_base = (base & ((1 << es) - 1)) != 0
    return not (lost_base or lost_top), (es, b & 0x1FF, t & 0x1FF)


def representable(meta, old, new):
    """setCapAddr: the decoded bounds are the same at the new address."""
    return decode(*meta, old) == decode(*meta, new)


def rtl_representable(meta, base32, newptr):
    """cheriot_set_address (ibex_cheriot_pkg.sv), for the cross-check only."""
    e = meta[0]
    mask = 0 if e == 24 else (((1 << 24) - 1) << e) & ((1 << 24) - 1)
    return (((newptr - base32) & M33) >> 9) & mask == 0


def bound_case(base, top33, addr):
    """fcov_bound_check_cases() in core_ibex_fcov_if.sv."""
    r = 0
    r |= (addr < base) << 0
    r |= (addr == base) << 1
    r |= (addr > top33) << 2
    r |= (addr == top33) << 3
    room = (top33 - addr) % (1 << 34)
    if 0 < room < 8:
        r |= (room & 7) << 4
    r |= (top33 == TOP32) << 7
    r |= (base == 0) << 8
    return r


def fetch_ok(base, top, pc, size=2):
    return base <= pc and pc + size <= top


def c_beqz(rs1, off):
    """Encoding of c.beqz x\\rs1, off (rs1 in x8..x15, off even in -256..254)."""
    assert 8 <= rs1 <= 15 and off % 2 == 0 and -256 <= off < 256
    o = off & 0x1FF
    bit = lambda i: (o >> i) & 1
    return (0b110 << 13 | bit(8) << 12 | bit(4) << 11 | bit(3) << 10 | (rs1 - 8) << 7
            | bit(7) << 6 | bit(6) << 5 | bit(2) << 4 | bit(1) << 3 | bit(5) << 2 | 0b01)


def zone_of(x, zones):
    for z in zones:
        _, lo, hi, _, branch, _ = z
        if lo <= x < hi or (branch and x == hi):
            return z
    return None


def landing(zone, base, top, target):
    """(n, ret) for a jump to target in zone: c.addi executed, jump back fetched."""
    _, _, hi, ret, branch, _ = zone
    n, pc = 0, target
    while pc < hi:
        if not fetch_ok(base, top, pc):
            return n, 0
        n, pc = n + 1, pc + 2
    if branch and not fetch_ok(base, top, hi):
        return n, 0
    return n, int(fetch_ok(base, top, ret, 4))


def shapes():
    """(kind, args, meta, build address, tagged). kind: CJD (MTCC, CSetBoundsExact), CJDR (the
    root) or CJH (raw metadata through CSetHigh, untagged, EX)."""
    out = []
    e0_lens = list(range(0, 25)) + [32, 63, 64, 65, 255, 256, 511]
    for ln in e0_lens:
        bases = [GENERIC, GENERIC + 1, ZB, ZB + 1, 0, 1, TOP32 - ln, TOP32 - ln - 1,
                 0x81000000 - ln, 0x81000000 - ln - 1]
        for b in bases:
            out.append(("CJD", b, ln))
    for b, ln in [(GENERIC, 2048), (ZB, 2048), (0x81000000 - 2048, 2048),
                  (0x81000000 - 2056, 2048), (0x81000000 - 2048, 2040), (0, 2048),
                  (TOP32 - 2048, 2048), (GENERIC, 4088)]:
        out.append(("CJD", b, ln))
    for k, m in [(0x80, 1), (0x81, 1), (0x80, 0x80), (0x81, 0x7F), (0, 0x81), (0, 1),
                 (0xFF, 1), (1, 1), (0, 0x82), (0x80, 2), (0x7F, 2)]:
        out.append(("CJD", k << 24, m << 24))
    res = []
    for kind, b, ln in out:
        if not 0 <= b < TOP32 or b + ln > TOP32:
            continue
        exact, meta = set_bounds(b, ln)
        if not exact:
            continue
        assert decode(*meta, b) == (b, b + ln), (hex(b), ln, meta)
        res.append(("CJD", (b, ln), meta, b, True))
    res.append(("CJDR", (), (24, 0, 0x100), 0, True))
    # Raw metadata (untagged): zero-length E = 24 and E = 3, E = 24 with B > T, E = 0 with a
    # wrapped base (address below T), at the reference address given.
    for meta, ref in [((24, 0x81, 0x81), 0x81000000), ((24, 0x90, 0x90), 0x90000000),
                      ((24, 0x00, 0x00), 0), ((24, 0x120, 0x010), 0x20000000),
                      ((24, 0x1FF, 0x100), 0xFF000000), ((3, 0x100, 0x100), GENERIC),
                      ((0, 0x100, 0x005), 0), ((0, 0x100, 0x003), 0), ((0, 0x100, 0x007), 2),
                      ((0, 0x1FE, 0x010), 5), ((3, 0x100, 0x101), GENERIC)]:
        res.append(("CJH", (), meta, ref, False))
    return res


def candidates(far):
    """Yield (shape, cursor, imm, value, rows, tex, n, ret, zone). far: the FAR_WINDOWS zones
    are landing zones too (otherwise a target in them is just a target outside the main zone,
    as in the default build)."""
    zones = [z for z in ZONES if far or not z[5]]
    offs = range(-24, 25)
    for shape in shapes():
        kind, args, meta, ref, tagged = shape
        b0, t0 = decode(*meta, ref)
        targets = set()
        for d in offs:
            targets.add((b0 + d) & M32)
            targets.add((t0 + d) & M32)
        for d in (-2048, -2050, -1600, 1600, 2048, 2050):
            targets.add((b0 + d) & M32)
            targets.add((t0 + d) & M32)
        for d in range(0, 10, 2):
            targets.add(d)
            targets.add((-d - 2) & M32)
        targets |= {ZB, 0x81000000}
        for tgt in sorted(targets):
            for imm in IMMS:
                for c in sorted({(tgt - imm) & M32, (tgt - imm + 1) & M32}):
                    x = (c + imm) & M32 & ~1
                    base, top = decode(*meta, c)
                    v = bound_case(base, top, x)
                    if v not in VALUES:
                        continue
                    tag = tagged and representable(meta, ref, c)
                    if tagged and tag != rtl_representable(meta, b0, c):
                        print(f"RTL/Sail representability differ: {kind} {args} cursor "
                              f"0x{c:08x}: not used", file=sys.stderr)
                        continue
                    tex, n, ret, zone = 0, 0, 0, None
                    if tag:
                        rows = {(0, 0), (0, 1), (1, 0)}
                        if not fetch_ok(base, top, x):
                            tex = 1
                        else:
                            zone = zone_of(x, zones)
                            if zone:
                                tex = 2
                                n, ret = landing(zone, base, top, x)
                                # The jump back links to ret + 4 against PCC = cs1: Sail
                                # asserts it is representable (never wraps: ret + 4 < 2^32).
                                if ret and decode(*meta, zone[3] + 4) != (base, top):
                                    print(f"link 0x{zone[3] + 4:08x} not representable: "
                                          f"{kind} {args} cursor 0x{c:08x}: not used",
                                          file=sys.stderr)
                                    continue
                        if tex:
                            rows.add((1, 1))
                    else:
                        rows = {(0, 0), (0, 1)}
                    yield shape, c, imm, v, frozenset(rows), tex, n, ret, zone


def choose(best, covered):
    """Greedy pick per (value, class) from best[(value, class)][rows] until no candidate adds
    a row to the ones in covered. Returns the cases; adds the bins reached to covered."""
    chosen = []
    for v in VALUES:
        for cls in CLASSES:
            need = set()
            cands = list(best.get((v, cls), {}).values())
            for cand in cands:
                need |= cand[4]
            have = {r for r in ROWS if (r, v, cls) in covered}
            need |= have
            while have != need:
                pick = max(cands, key=lambda cd: len(cd[4] - have))
                chosen.append(pick)
                have |= pick[4]
            covered |= {(r, v, cls) for r in have}
    return chosen


def emit(chosen):
    """Lines for the cases; (lines, attempts, landings)."""
    out, n_tries, n_land = [], 0, 0
    for shape, c, imm, v, rows, tex, n, ret, zone in chosen:
        kind, args, meta, ref, tagged = shape
        cls = imm_class(imm)
        rws = " ".join(f"{t}{e}" for t, e in sorted(rows))
        note = f"   # 0x{v:03x} {cls}  {rws}"
        if tex == 2:
            where = "" if zone is ZONE_MAIN else f" ({zone[0]})"
            note += f"  lands{where}: {n} c.addi, {'returns' if ret else 'fetch fault'}"
            n_land += 1
        if kind == "CJD":
            b, ln = args
            lns = f"{ln}" if ln < 0x10000 else f"0x{ln:08x}"
            tag = int((1, 0) in rows)
            out.append(f"    CJD 0x{b:08x}, {lns}, 0x{c:08x}, {imm}, {tag}, {tex}, {n}, {ret}"
                       f"{note}")
            n_tries += 3 + int(tex > 0)
        elif kind == "CJDR":
            out.append(f"    CJDR 0x{c:08x}, {imm}, {tex}, {n}, {ret}{note}")
            n_tries += 3 + int(tex > 0)
        else:
            e, b, t = meta
            word = (META_EX << 25) | ((15 if e == 24 else e) << 18) | (t << 9) | b
            out.append(f"    CJH 0x{word:08x}, 0x{c:08x}, {imm}{note}")
            n_tries += 2
    return out, n_tries, n_land


def bin_list(bins):
    """'0x0a0 bin1-5, 0x0a2 bin1/2/5, ...' for a set of (row, value, class)."""
    parts = []
    for v in VALUES:
        for row in ROWS:
            cls = [c for c in CLASSES if (row, v, c) in bins]
            if not cls:
                continue
            s = "bin1-5" if len(cls) == 5 else "bin" + "/".join(c[3:] for c in cls)
            r = "" if row == (1, 1) else f" row {row[0]}{row[1]}"
            parts.append(f"0x{v:03x} {s}{r}")
    return ", ".join(parts)


def reason(b, far_bins):
    row, v, cls = b
    if b in far_bins:
        also = " (the random loop hits it too)" if b in RANDOM_HIT else ""
        return f"far: covered by the FAR_WINDOWS cases (+far_code_windows=1){also}"
    for name, rows, vals, classes in UNREACHABLE:
        if (rows is None or row in rows) and v in vals and cls in classes:
            return f"unreachable {name}"
    if b in RANDOM_HIT:
        return "random loop: the regression's cjalr group hits it"
    return "UNEXPLAINED"


def main():
    verbose = "-v" in sys.argv[1:]
    # Default build: the main zone only.
    best = {}                        # (value, class) -> {rows: first candidate found}
    for cand in candidates(False):
        key = (cand[3], imm_class(cand[2]))
        best.setdefault(key, {}).setdefault(cand[4], cand)
    covered = set()
    chosen = choose(best, covered)
    out, n_tries, n_land = emit(chosen)
    total = len(ROWS) * len(VALUES) * len(CLASSES)
    print("// GENERATED by gen_cjalr_det.py -- do not edit by hand.")
    print(f"// {len(chosen)} cases, {n_tries} CJALR attempts ({n_land} land in the zone); "
          f"{len(covered)} of the {total} (tag, EX, value, imm class) bins.")
    print(f".equ CJD_NTRY, {n_tries}")
    print(f".equ CJ_ZLO, 0x{ZLO:08x}")
    print(f".equ CJ_ZHI, 0x{ZHI:08x}")
    print("    CJ_ZONE_INIT")
    print("\n".join(out))

    # FAR_WINDOWS build: cases landing in the bottom / top zones, for the bins left over.
    best_far = {}
    for cand in candidates(True):
        if cand[8] is not None and cand[8][5]:
            key = (cand[3], imm_class(cand[2]))
            best_far.setdefault(key, {}).setdefault(cand[4], cand)
    covered_far = set(covered)
    chosen_far = choose(best_far, covered_far)
    far_bins = covered_far - covered
    out, n_tries_far, n_land_far = emit(chosen_far)
    assert n_land_far == len(chosen_far)
    _, blo, bhi, bret, _, _ = ZONE_BOT
    _, tlo, tbr, tret, _, _ = ZONE_TOP
    beqz = c_beqz(10, tret - tbr)          # c.beqz a0, CJ_TRET at CJ_TBR
    print()
    print("#ifdef FAR_WINDOWS")
    print(f"// FAR_WINDOWS (cheriot_rand_operands_far, +far_code_windows=1): {len(chosen_far)} "
          f"more cases, {n_tries_far} CJALR attempts, all landing in the bottom / top zones; "
          f"{len(far_bins)} more bins, {len(far_bins - RANDOM_HIT)} of them reachable in no "
          f"other build and {len(far_bins & RANDOM_HIT)} that the random loop also hits:")
    print(f"// {bin_list(far_bins - RANDOM_HIT)}")
    print(f"// random loop too: {bin_list(far_bins & RANDOM_HIT)}")
    print(f".equ CJD_NTRY_FAR, {n_tries_far}")
    print(f".equ CJ_BLO, 0x{blo:08x}")
    print(f".equ CJ_BHI, 0x{bhi:08x}")
    print(f".equ CJ_TRET, 0x{tret:08x}")
    print(f".equ CJ_TLO, 0x{tlo:08x}")
    print(f".equ CJ_TBR, 0x{tbr:08x}")
    print(f".equ CJ_TBRW, 0x{beqz << 16 | 0x0385:08x}    "
          f"// c.addi t2, 1 at CJ_TBR - 2; c.beqz a0, {tret - tbr} (CJ_TRET) at CJ_TBR")
    print("    CJ_ZONE_FAR_INIT")
    print("\n".join(out))
    print("#endif")
    if verbose:
        n_far = n_unr = n_rnd = n_unx = 0
        for v in VALUES:
            for cls in CLASSES:
                for row in ROWS:
                    b = (row, v, cls)
                    if b in covered:
                        continue
                    why = reason(b, far_bins)
                    n_far += why.startswith("far")
                    n_unr += why.startswith("unreachable")
                    n_rnd += why.startswith("random")
                    n_unx += why.startswith("UNEXPLAINED")
                    print(f"uncovered 0x{v:03x} {cls} {row[0]}{row[1]}: {why}", file=sys.stderr)
        print(f"uncovered in the default build: {total - len(covered)} = {n_far} far + "
              f"{n_unr} unreachable + {n_rnd} random loop + {n_unx} unexplained",
              file=sys.stderr)


if __name__ == "__main__":
    main()
