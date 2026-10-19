#!/usr/bin/env python3

# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

"""Area distribution of a Yosys `stat -liberty` report as a pie chart (self-contained HTML).

A hierarchical report (synthesis with LR_SYNTH_FLATTEN=0) is split by block: starting from the
top module, every block larger than --max-share of the total is replaced by its submodules and
its own logic. A flattened report has one module only and is split by cell class instead.
"""

import argparse
import html
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import syn_lib  # noqa: E402

NANGATE45_NAND2_X1_AREA = 0.798
PIE_SLICES = 5

# Categorical slots 1-5 (validated light and dark), then a neutral for "Other".
COLORS_LIGHT = ['#2a78d6', '#eb6834', '#1baf7a', '#eda100', '#e87ba4']
COLORS_DARK = ['#3987e5', '#d95926', '#199e70', '#c98500', '#d55181']

ROW_RE = re.compile(r'^\s*(\d+)\s+(\S+)\s+(\S+)\s*$')
SECTION_RE = re.compile(r'^=== (.*) ===$')
CHIP_AREA_RE = re.compile(r"Chip area for module '(.*)': ([0-9.]+)")
TOP_AREA_RE = re.compile(r"Chip area for top module '(.*)': ([0-9.]+)")
NOT_CELLS = {'wires', 'bits', 'ports', 'cells', 'memories', 'processes', 'submodules'}


def parse_report(path):
    """Per module: own area, library cells {type: (count, area)}, children {module: count}."""
    modules = {}
    order = []
    cur = None
    top_area = None
    with open(path) as f:
        for line in f:
            line = line.rstrip('\n')
            m = SECTION_RE.match(line)
            if m:
                name = m.group(1)
                if name == 'design hierarchy':
                    cur = None
                    continue
                cur = modules.setdefault(name, {'area': 0.0, 'cells': {}, 'rows': {}})
                order.append(name)
                continue
            m = TOP_AREA_RE.search(line)
            if m:
                top_area = float(m.group(2))
                continue
            if cur is None:
                continue
            m = CHIP_AREA_RE.search(line)
            if m:
                cur['area'] = float(m.group(2))
                continue
            m = ROW_RE.match(line)
            if m and m.group(3) not in NOT_CELLS:
                count, area, typ = int(m.group(1)), m.group(2), m.group(3)
                cur['rows'][typ] = (count, None if area == '-' else float(area))
    if not modules:
        sys.exit('{}: no "=== <module> ===" sections; is this a Yosys stat report?'.format(path))
    for mod in modules.values():
        mod['children'] = {t: c for t, (c, _) in mod['rows'].items() if t in modules}
        mod['cells'] = {t: r for t, r in mod['rows'].items() if t not in modules}
    return modules, order, top_area


def uncounted_cells(modules, top):
    """Cells without a library area, counted per instance from the top: (black-box macros such as
    the iCache's prim_ram_1p arrays, other unmapped cells), each {name: count}."""
    counts = {}

    def walk(name, mult):
        for typ, (c, area) in modules[name]['cells'].items():
            if area is None:
                base = clean_name(typ)
                counts[base] = counts.get(base, 0) + mult * c
        for ch, c in modules[name]['children'].items():
            walk(ch, mult * c)

    walk(top, 1)
    macros = {k: v for k, v in counts.items() if k.startswith('prim_ram_')}
    return macros, {k: v for k, v in counts.items() if k not in macros}


def uncounted_notes(modules, top, prefix=''):
    macros, other = uncounted_cells(modules, top)
    fmt = lambda d: ', '.join('{} ×{}'.format(k, v) for k, v in sorted(d.items()))  # noqa: E731
    notes = []
    if macros:
        notes.append(prefix + 'SRAM macros (black boxes), not counted: ' + fmt(macros) + '.')
    if other:
        notes.append(prefix + 'Not mapped to library cells, so not counted: ' + fmt(other) + '.')
    return notes


def find_top(modules, order):
    instantiated = {c for m in modules.values() for c in m['children']}
    tops = [n for n in order if n not in instantiated]
    return tops[-1] if tops else order[-1]


def clean_name(name):
    """'$paramod$<hash>\\ibex_trvk', '$paramod\\ibex_alu\\RV32B=...', '\\ibex_top' -> base name."""
    parts = name.lstrip('\\').split('\\')
    return parts[1] if parts[0].startswith('$paramod') and len(parts) > 1 else parts[0]


def inclusive(modules, name, memo):
    if name not in memo:
        mod = modules[name]
        memo[name] = mod['area'] + sum(c * inclusive(modules, ch, memo)
                                       for ch, c in mod['children'].items())
    return memo[name]


def split_by_block(modules, top, max_share):
    memo = {}
    total = inclusive(modules, top, memo)
    # Slice: (label, area, path, module or None, multiplicity)
    slices = [(clean_name(top), total, clean_name(top), top, 1)]
    while True:
        big = [s for s in slices
               if s[3] and modules[s[3]]['children'] and s[1] > max_share * total]
        if not big:
            break
        s = big[0]
        slices.remove(s)
        _, _, path, name, mult = s
        mod = modules[name]
        if mod['area'] > 0:
            slices.append((clean_name(name) + ' (own logic)', mult * mod['area'], path, None, mult))
        for ch, c in mod['children'].items():
            n = mult * c
            label = clean_name(ch) + (' ×{}'.format(n) if n > 1 else '')
            slices.append((label, n * inclusive(modules, ch, memo),
                           path + ' › ' + clean_name(ch), ch, n))
    return total, [(lab, area, path) for lab, area, path, _, _ in slices], memo


# NanGate45 (DFF_X1, DLH_X1, CLKGATETST_X1, BUF_X2), ASAP7 (DFFHQNx1_ASAP7_75t_R, DHLx1_, ICGx1_,
# BUFx2_), and, after their prefix, SKY130 (sky130_fd_sc_hd__dfrtp_1, dlxtp_1, sdlclkp_1, clkbuf_1,
# buf_2) and IHP (sg13g2_dfrbp_1, dlhq_1, slgcp_1, buf_2).
CELL_CLASSES = [
    ('Flip-flops', re.compile(r'^(S?DFF|SDF[HL]|s?e?df)')),
    ('Latches', re.compile(r'^(DL[HL]_|DHLx|DLLx|dl[xrhl]|\$_DLATCH)')),
    ('Clock buffers and gates', re.compile(r'^(CLK(BUF|GATE)|ICG|CKINV|s?dlclkp|clk(buf|inv|dlybuf)|s?lgcp)')),
    ('Buffers and inverters', re.compile(r'^((BUF|INV)_|(BUF|INV)x|HB\dx|buf|inv)')),
]
LIB_PREFIX = re.compile(r'^(sky130_fd_sc_[a-z]+__|sg13g2_)')


def cell_class(typ):
    base = LIB_PREFIX.sub('', typ)
    return next((c for c, rx in CELL_CLASSES if rx.match(base)), 'Combinational logic')


def split_by_cell_class(mod):
    areas = {}
    for typ, (_, area) in mod['cells'].items():
        cls = cell_class(typ)
        areas[cls] = areas.get(cls, 0.0) + (area or 0.0)
    return [(cls, a, cls) for cls, a in areas.items() if a > 0]


def tree_rows(modules, name, memo, depth=0, mult=1, out=None):
    out = [] if out is None else out
    out.append((depth, clean_name(name), mult, mult * memo[name], mult * modules[name]['area']))
    for ch, c in sorted(modules[name]['children'].items(), key=lambda kv: -kv[1] * memo[kv[0]]):
        tree_rows(modules, ch, memo, depth + 1, mult * c, out)
    return out


def read_config(report_path):
    """Flow settings echoed in log/syn.log, for the subtitle."""
    log = os.path.join(os.path.dirname(report_path), '..', 'log', 'syn.log')
    cfg = {}
    try:
        with open(log) as f:
            for line in f:
                for key, prefix in (('base_isa', 'Base ISA'), ('flatten', 'flatten:'),
                                    ('config', 'Ibex configuration ('),
                                    ('overrides', 'Ibex configuration overrides:')):
                    if line.startswith(prefix):
                        val = line.rsplit(':', 1)[1].strip()
                        cfg[key] = '' if val.endswith('(default)') or not val else val
    except OSError:
        pass
    return cfg


def config_label(cfg):
    """'cheriot-min', 'opentitan (ICache=0 ...)', or the Base ISA of an unnamed configuration."""
    if cfg.get('config'):
        ov = cfg.get('overrides')
        return cfg['config'] + (' ({})'.format(ov) if ov else '')
    return {'0': 'RV32I', '1': 'RV32I or CHERIoT'}.get(cfg.get('base_isa'))


def pie_paths(slices, total, cx, cy, r):
    import math
    paths, a0 = [], -math.pi / 2
    for _, area, _ in slices:
        frac = area / total
        a1 = a0 + frac * 2 * math.pi
        if frac >= 0.9999:
            d = 'M{cx},{t} A{r},{r} 0 1,1 {cx},{b} A{r},{r} 0 1,1 {cx},{t} Z'.format(
                cx=cx, t=cy - r, b=cy + r, r=r)
        else:
            x0, y0 = cx + r * math.cos(a0), cy + r * math.sin(a0)
            x1, y1 = cx + r * math.cos(a1), cy + r * math.sin(a1)
            d = 'M{},{} L{:.2f},{:.2f} A{},{} 0 {},1 {:.2f},{:.2f} Z'.format(
                cx, cy, x0, y0, r, r, 1 if frac > 0.5 else 0, x1, y1)
        mid = (a0 + a1) / 2
        lx, ly = cx + 0.68 * r * math.cos(mid), cy + 0.68 * r * math.sin(mid)
        paths.append((d, frac, lx, ly))
        a0 = a1
    return paths


def write_html(out, title, subtitle, notes, slices, total, ge, table, tree):
    ranked = sorted(slices, key=lambda s: -s[1])
    pie = ranked[:PIE_SLICES]
    rest = ranked[PIE_SLICES:]
    if rest:
        pie.append(('Other ({} blocks)'.format(len(rest)) if len(rest) > 1 else rest[0][0],
                    sum(s[1] for s in rest),
                    ', '.join(s[0] for s in rest)))
    other_idx = PIE_SLICES if rest and len(rest) > 1 else None

    cx = cy = 160
    r = 140
    svg, legend = [], []
    for i, ((label, area, path), (d, frac, lx, ly)) in enumerate(zip(pie, pie_paths(pie, total, cx, cy, r))):
        var = 'var(--other)' if i == other_idx else 'var(--series-{})'.format(i + 1)
        tip = json.dumps({'name': label, 'path': path, 'um2': round(area, 1),
                          'kge': round(area / ge / 1000, 2), 'pct': round(100 * frac, 1)})
        svg.append('<path class="slice" d="{}" style="fill:{}" data-i="{}" data-tip=\'{}\'>'
                   '<title>{}: {:.1f}%</title></path>'.format(
                       d, var, i, html.escape(tip, quote=True), html.escape(label), 100 * frac))
        if frac >= 0.06:
            svg.append('<text class="pct" x="{:.1f}" y="{:.1f}">{:.0f}%</text>'.format(lx, ly, 100 * frac))
        legend.append('<li data-i="{}"><span class="sw" style="background:{}"></span>'
                      '<span class="lname">{}</span><span class="num">{:.1f} kGE</span>'
                      '<span class="num">{:.1f}%</span></li>'.format(
                          i, var, html.escape(label), area / ge / 1000, 100 * frac))

    rows = ''.join('<tr><td>{}</td><td class="path">{}</td><td class="num">{:,.0f}</td>'
                   '<td class="num">{:.2f}</td><td class="num">{:.1f}%</td></tr>'.format(
                       html.escape(l), html.escape(p), a, a / ge / 1000, 100 * a / total)
                   for l, a, p in ranked)
    tree_html = ''
    if tree:
        tree_html = ('<h2>Hierarchy</h2><table><thead><tr><th>Module</th><th class="num">Instances</th>'
                     '<th class="num">Area incl. submodules (µm²)</th><th class="num">kGE</th>'
                     '<th class="num">Own logic (µm²)</th></tr></thead><tbody>' +
                     ''.join('<tr><td style="padding-left:{}px">{}</td><td class="num">{}</td>'
                             '<td class="num">{:,.0f}</td><td class="num">{:.2f}</td>'
                             '<td class="num">{:,.0f}</td></tr>'.format(
                                 8 + 16 * d, html.escape(n), m, a, a / ge / 1000, own)
                             for d, n, m, a, own in tree) + '</tbody></table>')

    colors = ''.join('--series-{}:{};'.format(i + 1, c) for i, c in enumerate(COLORS_LIGHT))
    colors_dark = ''.join('--series-{}:{};'.format(i + 1, c) for i, c in enumerate(COLORS_DARK))
    dark = ('color-scheme:dark;--surface-1:#1a1a19;--page:#0d0d0d;--text-primary:#f0efec;'
            '--text-secondary:#c3c2b7;--muted:#898781;--grid:#2c2c2a;--other:#6b6a65;' + colors_dark)
    notes_html = ''.join('<p class="note">{}</p>'.format(html.escape(n)) for n in notes)
    doc = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>{title}</title>
<style>
.viz-root {{ color-scheme:light; --surface-1:#fcfcfb; --page:#f9f9f7; --text-primary:#0b0b0b;
  --text-secondary:#52514e; --muted:#898781; --grid:#e1e0d9; --other:#b5b4ae; {colors} }}
@media (prefers-color-scheme: dark) {{ :root:where(:not([data-theme="light"])) .viz-root {{ {dark} }} }}
:root[data-theme="dark"] .viz-root {{ {dark} }}
body {{ margin:0; }}
.viz-root {{ font-family:system-ui,-apple-system,"Segoe UI",sans-serif; background:var(--page);
  color:var(--text-primary); padding:24px; min-height:100vh; box-sizing:border-box; }}
.card {{ background:var(--surface-1); border:1px solid var(--grid); border-radius:8px; padding:20px 24px;
  max-width:980px; }}
h1 {{ font-size:20px; margin:0 0 4px; font-weight:600; }}
h2 {{ font-size:15px; margin:28px 0 8px; font-weight:600; }}
.sub {{ color:var(--text-secondary); margin:0 0 4px; font-size:14px; }}
.hero {{ font-size:48px; font-weight:600; margin:12px 0 0; line-height:1; }}
.hero small {{ font-size:16px; color:var(--text-secondary); font-weight:400; margin-left:6px; }}
.note {{ color:var(--text-secondary); font-size:13px; margin:6px 0 0; }}
.chart {{ display:flex; gap:32px; align-items:center; flex-wrap:wrap; margin-top:16px; }}
svg {{ flex:none; }}
.slice {{ stroke:var(--surface-1); stroke-width:2; stroke-linejoin:round; cursor:default;
  transition:opacity .12s; }}
.dim .slice:not(.on) {{ opacity:.35; }}
.pct {{ fill:#fff; font-size:13px; font-weight:600; text-anchor:middle; dominant-baseline:middle;
  pointer-events:none; paint-order:stroke; stroke:rgba(0,0,0,.35); stroke-width:2px; }}
ul.legend {{ list-style:none; margin:0; padding:0; min-width:320px; }}
ul.legend li {{ display:grid; grid-template-columns:14px 1fr 80px 56px; gap:10px; align-items:center;
  padding:5px 4px; border-radius:4px; font-size:14px; }}
ul.legend li:hover {{ background:var(--grid); }}
.sw {{ width:12px; height:12px; border-radius:3px; }}
.num {{ text-align:right; font-variant-numeric:tabular-nums; color:var(--text-secondary); }}
table {{ border-collapse:collapse; width:100%; font-size:13px; }}
th, td {{ padding:5px 8px; border-bottom:1px solid var(--grid); text-align:left; }}
th {{ color:var(--muted); font-weight:500; }}
td.path {{ color:var(--muted); }}
#tip {{ position:fixed; pointer-events:none; background:var(--surface-1); color:var(--text-primary);
  border:1px solid var(--grid); border-radius:6px; padding:8px 10px; font-size:13px; display:none;
  box-shadow:0 4px 14px rgba(0,0,0,.12); max-width:340px; }}
#tip .p {{ color:var(--muted); font-size:12px; margin-bottom:4px; }}
#tip b {{ font-weight:600; }}
</style></head>
<body><div class="viz-root"><div class="card">
<h1>{title}</h1><p class="sub">{subtitle}</p>
<p class="hero">{kge:.1f}<small>kGE &middot; {um2:,.0f} &micro;m&sup2;</small></p>
{notes}
<div class="chart" id="chart">
<svg width="320" height="320" viewBox="0 0 320 320" role="img" aria-label="Area by block">{svg}</svg>
<ul class="legend">{legend}</ul>
</div>
<h2>{table_title}</h2>
<table><thead><tr><th>Block</th><th>Path</th><th class="num">Area (&micro;m&sup2;)</th>
<th class="num">kGE</th><th class="num">Share</th></tr></thead><tbody>{rows}</tbody></table>
{tree}
</div><div id="tip"></div></div>
<script>
const chart = document.getElementById('chart'), tip = document.getElementById('tip');
const slices = [...document.querySelectorAll('.slice')];
function on(i) {{ chart.classList.add('dim'); slices.forEach(s => s.classList.toggle('on', s.dataset.i == i)); }}
function off() {{ chart.classList.remove('dim'); slices.forEach(s => s.classList.remove('on')); tip.style.display = 'none'; }}
slices.forEach(s => {{
  s.addEventListener('mousemove', e => {{
    const d = JSON.parse(s.dataset.tip); on(s.dataset.i);
    tip.innerHTML = '<div class="p"></div><b></b><div></div>';
    tip.children[0].textContent = d.path; tip.children[1].textContent = d.name;
    tip.children[2].textContent = d.kge.toFixed(2) + ' kGE \\u00b7 ' + d.um2.toLocaleString() + ' \\u00b5m\\u00b2 \\u00b7 ' + d.pct + '%';
    tip.style.display = 'block'; tip.style.left = (e.clientX + 14) + 'px'; tip.style.top = (e.clientY + 14) + 'px';
  }});
  s.addEventListener('mouseleave', off);
}});
document.querySelectorAll('ul.legend li').forEach(li => {{
  li.addEventListener('mouseenter', () => on(li.dataset.i)); li.addEventListener('mouseleave', off);
}});
</script></body></html>
""".format(title=html.escape(title), subtitle=html.escape(subtitle), colors=colors, dark=dark,
           kge=total / ge / 1000, um2=total, notes=notes_html, svg=''.join(svg),
           legend=''.join(legend), table_title=table, rows=rows, tree=tree_html)
    with open(out, 'w') as f:
        f.write(doc)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('report', help='Yosys stat report (syn_out/<run>/reports/area.rpt)')
    ap.add_argument('-o', '--out', help='HTML output (default: area_chart.html beside the report)')
    ap.add_argument('--max-share', type=float, default=0.30,
                    help='split any block above this share of the total into its parts (default 0.30)')
    ap.add_argument('--ge-area', type=float,
                    help='area of one gate equivalent, um^2 (default: the run\'s library, '
                         'run_info.txt; NanGate45 NAND2_X1, 0.798, for a run without one)')
    args = ap.parse_args()
    lib = syn_lib.for_report(args.report)
    if args.ge_area is None:
        args.ge_area = lib['ge_area']

    modules, order, top_area = parse_report(args.report)
    top = find_top(modules, order)
    cfg = read_config(args.report)
    isa = config_label(cfg)
    hierarchical = any(m['children'] for m in modules.values())

    notes = uncounted_notes(modules, top)

    if hierarchical:
        total, slices, memo = split_by_block(modules, top, args.max_share)
        tree = tree_rows(modules, top, memo)
        table = 'All blocks'
        notes.append('Hierarchical synthesis (LR_SYNTH_FLATTEN=0): no optimisation across module '
                     'boundaries, so the total is a little above the flattened result.')
    else:
        mod = modules[top]
        slices = split_by_cell_class(mod)
        total = sum(a for _, a, _ in slices)
        tree = None
        table = 'All cell classes'
        notes.append('Flattened netlist: split by cell class. For a split by block, synthesise '
                     'with LR_SYNTH_FLATTEN=0 (make yosys-synth-cheriot SYN_FLATTEN=0).')
    if top_area is not None and abs(top_area - total) > 0.01 * total:
        notes.append('Yosys reports {:,.0f} µm² for the top module; '
                     'the blocks add up to {:,.0f}.'.format(top_area, total))

    title = '{} area by {}'.format(clean_name(top), 'block' if hierarchical else 'cell class')
    subtitle = ' · '.join(x for x in (isa, syn_lib.ge_label(lib, args.ge_area),
                                           os.path.basename(os.path.dirname(os.path.dirname(
                                               os.path.abspath(args.report))))) if x)
    out = args.out or os.path.join(os.path.dirname(args.report), 'area_chart.html')
    write_html(out, title, subtitle, notes, slices, total, args.ge_area, table, tree)

    print('{}: {:.2f} kGE ({:,.0f} um^2)'.format(title, total / args.ge_area / 1000, total))
    for label, area, path in sorted(slices, key=lambda s: -s[1]):
        print('  {:>6.1f}%  {:>7.2f} kGE  {}'.format(100 * area / total, area / args.ge_area / 1000,
                                                     label if label == path else '{}  ({})'.format(label, path)))
    for n in notes:
        print('Note: ' + n)
    print('Chart: ' + os.path.abspath(out))


if __name__ == '__main__':
    main()
