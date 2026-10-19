#!/usr/bin/env python3

# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

"""Compare the area of two hierarchical Yosys reports block by block (self-contained HTML).

Both designs are split at the same modules: any module above --max-share of either total is
replaced by its submodules and own logic, in both. Blocks are named by module, so the two copies
of a module (the lockstep core, say) are one row with their instance count.
"""

import argparse
import html
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from area_chart import (clean_name, config_label, find_top, inclusive,  # noqa: E402
                        parse_report, read_config, uncounted_notes)
import syn_lib  # noqa: E402

COLORS_LIGHT = ['#2a78d6', '#eb6834']
COLORS_DARK = ['#3987e5', '#d95926']


class Design:
    def __init__(self, report, label):
        self.report = report
        self.modules, order, _ = parse_report(report)
        if not any(m['children'] for m in self.modules.values()):
            sys.exit('{}: flattened report; synthesise with LR_SYNTH_FLATTEN=0'.format(report))
        self.top = find_top(self.modules, order)
        self.memo = {}
        self.total = inclusive(self.modules, self.top, self.memo)
        self.label = label or config_label(read_config(report)) or os.path.basename(
            os.path.dirname(os.path.dirname(os.path.abspath(report))))
        self.notes = uncounted_notes(self.modules, self.top, self.label + ': ')

    def blocks(self, expand):
        """{label: [area, instances, expandable]} with every module in `expand` split open."""
        out = {}

        def add(label, area, n, expandable):
            b = out.setdefault(label, [0.0, 0, expandable])
            b[0] += area
            b[1] += n

        def walk(name, mult):
            mod = self.modules[name]
            base = clean_name(name)
            if base in expand:
                if mod['area'] > 0:
                    add(base + ' (own logic)', mult * mod['area'], mult, False)
                for ch, c in mod['children'].items():
                    walk(ch, mult * c)
            else:
                add(base, mult * self.memo[name], mult, bool(mod['children']))

        walk(self.top, 1)
        return out


def common_split(designs, max_share):
    expand = {clean_name(designs[0].top)} | {clean_name(d.top) for d in designs}
    while True:
        grow = {lab for d in designs for lab, (area, _, expandable) in d.blocks(expand).items()
                if expandable and area > max_share * d.total}
        if grow <= expand:
            return expand
        expand |= grow


def write_html(out, a, b, rows, ge, notes, lib):
    kge = lambda x: x / ge / 1000  # noqa: E731
    saving = a.total - b.total
    shown = [r for r in rows if max(r[1], r[3]) >= 0.01 * max(a.total, b.total)]
    rest = [r for r in rows if r not in shown]
    if rest:
        shown.append(('Other blocks ({})'.format(len(rest)), sum(r[1] for r in rest), 0,
                      sum(r[3] for r in rest), 0))
    vmax = max(max(r[1], r[3]) for r in shown)

    bar_h, gap, row_h, label_w, plot_w = 12, 2, 40, 230, 520
    svg = []
    for i, (label, aa, an, ba, bn) in enumerate(shown):
        y0 = 8 + i * row_h
        svg.append('<text class="blabel" x="{}" y="{}">{}</text>'.format(
            label_w - 10, y0 + bar_h + 1, html.escape(label)))
        for j, (area, n, d) in enumerate(((aa, an, a), (ba, bn, b))):
            y = y0 + j * (bar_h + gap)
            w = max(plot_w * area / vmax, 0)
            tip = json.dumps({'block': label, 'design': d.label, 'kge': round(kge(area), 2),
                              'n': n, 'pct': round(100 * area / d.total, 1)})
            if area > 0:
                svg.append('<rect class="bar" x="{}" y="{}" width="{:.1f}" height="{}" rx="3" '
                           'style="fill:var(--series-{})" data-tip=\'{}\'></rect>'.format(
                               label_w, y, w, bar_h, j + 1, html.escape(tip, quote=True)))
            svg.append('<text class="bval" x="{:.1f}" y="{}">{}</text>'.format(
                label_w + w + 6, y + bar_h - 2, '{:.1f}'.format(kge(area)) if area > 0 else '—'))
    height = 8 + len(shown) * row_h
    svg_html = ('<svg width="{w}" height="{h}" viewBox="0 0 {w} {h}" role="img" '
                'aria-label="Area by block, {a} and {b}">'
                '<line class="axis" x1="{x}" y1="0" x2="{x}" y2="{h}"></line>{body}</svg>').format(
                    w=label_w + plot_w + 60, h=height, x=label_w, body=''.join(svg),
                    a=html.escape(a.label), b=html.escape(b.label))

    def delta(x, y):
        d = y - x
        pct = '' if x == 0 else '{:+.0f}%'.format(100 * d / x)
        return '{:+.2f}'.format(kge(d)), pct

    trs = []
    for label, aa, an, ba, bn in rows:
        d, p = delta(aa, ba)
        trs.append('<tr><td>{}</td><td class="num">{}</td><td class="num">{:.2f}</td>'
                   '<td class="num">{}</td><td class="num">{:.2f}</td><td class="num">{}</td>'
                   '<td class="num">{}</td></tr>'.format(
                       html.escape(label), an or '', kge(aa), bn or '', kge(ba), d, p))
    d, p = delta(a.total, b.total)
    trs.append('<tr class="tot"><td>Total</td><td></td><td class="num">{:.2f}</td><td></td>'
               '<td class="num">{:.2f}</td><td class="num">{}</td><td class="num">{}</td></tr>'.format(
                   kge(a.total), kge(b.total), d, p))

    dark = ('color-scheme:dark;--surface-1:#1a1a19;--page:#0d0d0d;--text-primary:#f0efec;'
            '--text-secondary:#c3c2b7;--muted:#898781;--grid:#2c2c2a;--axis:#383835;'
            '--series-1:{};--series-2:{};'.format(*COLORS_DARK))
    doc = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Area: {a} vs {b}</title>
<style>
.viz-root {{ color-scheme:light; --surface-1:#fcfcfb; --page:#f9f9f7; --text-primary:#0b0b0b;
  --text-secondary:#52514e; --muted:#898781; --grid:#e1e0d9; --axis:#c3c2b7;
  --series-1:{c1}; --series-2:{c2}; }}
@media (prefers-color-scheme: dark) {{ :root:where(:not([data-theme="light"])) .viz-root {{ {dark} }} }}
:root[data-theme="dark"] .viz-root {{ {dark} }}
body {{ margin:0; }}
.viz-root {{ font-family:system-ui,-apple-system,"Segoe UI",sans-serif; background:var(--page);
  color:var(--text-primary); padding:24px; min-height:100vh; box-sizing:border-box; }}
.card {{ background:var(--surface-1); border:1px solid var(--grid); border-radius:8px; padding:20px 24px;
  max-width:1000px; }}
h1 {{ font-size:20px; margin:0 0 4px; font-weight:600; }}
h2 {{ font-size:15px; margin:28px 0 8px; font-weight:600; }}
.sub, .note {{ color:var(--text-secondary); font-size:13px; margin:4px 0 0; }}
.tiles {{ display:flex; gap:16px; margin:16px 0 8px; flex-wrap:wrap; }}
.tile {{ border:1px solid var(--grid); border-radius:8px; padding:12px 16px; min-width:200px; }}
.tile .k {{ color:var(--text-secondary); font-size:13px; display:flex; align-items:center; gap:6px; }}
.tile .v {{ font-size:34px; font-weight:600; margin-top:4px; }}
.tile .v small {{ font-size:14px; color:var(--text-secondary); font-weight:400; margin-left:4px; }}
.sw {{ width:12px; height:12px; border-radius:3px; display:inline-block; }}
.legend {{ display:flex; gap:20px; font-size:13px; color:var(--text-secondary); margin:12px 0 4px; }}
.legend span {{ display:flex; align-items:center; gap:6px; }}
.blabel {{ fill:var(--text-primary); font-size:13px; text-anchor:end; }}
.bval {{ fill:var(--text-secondary); font-size:12px; font-variant-numeric:tabular-nums; }}
.axis {{ stroke:var(--axis); stroke-width:1; }}
.bar {{ cursor:default; }}
.bar:hover {{ opacity:.8; }}
table {{ border-collapse:collapse; width:100%; font-size:13px; }}
th, td {{ padding:5px 8px; border-bottom:1px solid var(--grid); text-align:left; }}
th {{ color:var(--muted); font-weight:500; }}
.num {{ text-align:right; font-variant-numeric:tabular-nums; }}
tr.tot td {{ font-weight:600; border-top:1px solid var(--axis); }}
#tip {{ position:fixed; pointer-events:none; background:var(--surface-1); color:var(--text-primary);
  border:1px solid var(--grid); border-radius:6px; padding:8px 10px; font-size:13px; display:none;
  box-shadow:0 4px 14px rgba(0,0,0,.12); }}
#tip .p {{ color:var(--muted); font-size:12px; }}
</style></head>
<body><div class="viz-root"><div class="card">
<h1>Area: {a} vs {b}</h1>
<p class="sub">{lib}, 1 GE = {ge_cell} = {ge} &micro;m&sup2; &middot; hierarchical synthesis (no optimisation across module boundaries)</p>
<div class="tiles">
<div class="tile"><div class="k"><span class="sw" style="background:var(--series-1)"></span>{a}</div><div class="v">{ka:.1f}<small>kGE</small></div></div>
<div class="tile"><div class="k"><span class="sw" style="background:var(--series-2)"></span>{b}</div><div class="v">{kb:.1f}<small>kGE</small></div></div>
<div class="tile"><div class="k">Difference</div><div class="v">{kd:+.1f}<small>kGE &middot; {pd:+.0f}%</small></div></div>
</div>
{notes}
<h2>By block (kGE)</h2>
<div class="legend"><span><i class="sw" style="background:var(--series-1)"></i>{a}</span><span><i class="sw" style="background:var(--series-2)"></i>{b}</span></div>
{svg}
<h2>All blocks</h2>
<table><thead><tr><th>Block</th><th class="num">Inst.</th><th class="num">{a} kGE</th>
<th class="num">Inst.</th><th class="num">{b} kGE</th><th class="num">&Delta; kGE</th><th class="num">&Delta;</th></tr></thead>
<tbody>{rows}</tbody></table>
<p class="note">Reports: {ra} &middot; {rb}</p>
</div><div id="tip"></div></div>
<script>
const tip = document.getElementById('tip');
document.querySelectorAll('.bar').forEach(r => {{
  r.addEventListener('mousemove', e => {{
    const d = JSON.parse(r.dataset.tip);
    tip.innerHTML = '<div class="p"></div><b></b><div></div>';
    tip.children[0].textContent = d.design; tip.children[1].textContent = d.block;
    tip.children[2].textContent = d.kge.toFixed(2) + ' kGE \\u00b7 ' + d.pct + '% of ' + d.design + (d.n > 1 ? ' \\u00b7 ' + d.n + ' instances' : '');
    tip.style.display = 'block'; tip.style.left = (e.clientX + 14) + 'px'; tip.style.top = (e.clientY + 14) + 'px';
  }});
  r.addEventListener('mouseleave', () => {{ tip.style.display = 'none'; }});
}});
</script></body></html>
""".format(a=html.escape(a.label), b=html.escape(b.label), c1=COLORS_LIGHT[0], c2=COLORS_LIGHT[1],
           dark=dark, ge=ge, lib=html.escape(lib['title']), ge_cell=html.escape(lib['ge_cell']),
           ka=kge(a.total), kb=kge(b.total), kd=kge(-saving),
           pd=-100 * saving / a.total, notes=''.join('<p class="note">{}</p>'.format(html.escape(n))
                                                     for n in notes),
           svg=svg_html, rows=''.join(trs), ra=html.escape(os.path.abspath(a.report)),
           rb=html.escape(os.path.abspath(b.report)))
    with open(out, 'w') as f:
        f.write(doc)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('report_a', help='reference design (e.g. opentitan) area.rpt')
    ap.add_argument('report_b', help='design compared with it (e.g. cheriot-min) area.rpt')
    ap.add_argument('-o', '--out', default='area_compare.html')
    ap.add_argument('--label-a')
    ap.add_argument('--label-b')
    ap.add_argument('--max-share', type=float, default=0.30)
    ap.add_argument('--ge-area', type=float,
                    help='um^2 (default: the library of report_a\'s run, its run_info.txt)')
    args = ap.parse_args()

    a, b = Design(args.report_a, args.label_a), Design(args.report_b, args.label_b)
    lib, lib_b = syn_lib.for_report(args.report_a), syn_lib.for_report(args.report_b)
    if args.ge_area is None:
        args.ge_area = lib['ge_area']
    expand = common_split([a, b], args.max_share)
    ba, bb = a.blocks(expand), b.blocks(expand)
    rows = sorted(((lab, ba.get(lab, [0, 0])[0], ba.get(lab, [0, 0])[1],
                    bb.get(lab, [0, 0])[0], bb.get(lab, [0, 0])[1]) for lab in set(ba) | set(bb)),
                  key=lambda r: -max(r[1], r[3]))
    notes = a.notes + b.notes
    if lib_b['name'] != lib['name']:
        notes.append('The two runs used different cell libraries ({}: {}, {}: {}); both are in {} '
                     'gate equivalents.'.format(a.label, lib['title'], b.label, lib_b['title'],
                                                lib['title']))
    write_html(args.out, a, b, rows, args.ge_area, notes, lib)

    g = args.ge_area * 1000
    print('{:<34} {:>12} {:>12} {:>9}'.format('Block', a.label[:12], b.label[:12], 'delta'))
    for lab, aa, an, bva, bn in rows:
        print('{:<34} {:>12.2f} {:>12.2f} {:>+9.2f}'.format(lab[:34], aa / g, bva / g, (bva - aa) / g))
    print('{:<34} {:>12.2f} {:>12.2f} {:>+9.2f}  ({:+.0f}%)'.format(
        'Total', a.total / g, b.total / g, (b.total - a.total) / g,
        100 * (b.total - a.total) / a.total))
    for n in notes:
        print('Note: ' + n)
    print('Comparison: ' + os.path.abspath(args.out))


if __name__ == '__main__':
    main()
