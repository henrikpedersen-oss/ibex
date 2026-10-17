#!/usr/bin/env python3
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""The open synthesis flow (Yosys + OpenSTA, syn_yosys.sh) against Genus (genus/run_genus.sh) for
several ibex_configs.yaml configurations, as one self-contained HTML page: area (um^2 and kGE),
cells, flops, worst slack and the clock frequency it implies.

For each configuration and flow the newest run with the given corner and clock period is used (its
run_info.txt, which both flows write). A flattened Yosys run is preferred, as Genus optimises across
the whole design; a hierarchical one is used, and flagged, only if there is no flattened run.

  scripts/compare_flows.py [--configs opentitan small] [--corner slow] [--period 6667] [-o out.html]
"""

import argparse
import datetime
import html
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from area_chart import (NANGATE45_NAND2_X1_AREA, find_top, inclusive,  # noqa: E402
                        parse_report)
from area_compare import COLORS_DARK, COLORS_LIGHT  # noqa: E402

SYN = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
FLOWS = (('yosys', 'Yosys + OpenSTA'), ('genus', 'Genus'))
STA_GROUPS = ('reg2reg', 'in2reg', 'reg2out', 'in2out')
SEQ_CELL = re.compile(r'^(DFF|SDFF|DLL|DLH)')
STA_SLACK = re.compile(r'^\s*(-?\d+(?:\.\d+)?)\s+slack \((?:VIOLATED|MET)\)', re.M)
# Genus report_timing (ps), in the forms its versions print.
GENUS_SLACK = (re.compile(r'Path 1:\s*(?:VIOLATED|MET)\s*\((-?\d+(?:\.\d+)?)\s*ps\)'),
               re.compile(r'Timing slack\s*:\s*(-?\d+(?:\.\d+)?)\s*ps'),
               re.compile(r'Slack:=\s*(-?\d+(?:\.\d+)?)'))
START = re.compile(r'Startpoint:\s*(?:\([RF]\)\s*)?(\S+)')
END = re.compile(r'Endpoint:\s*(?:\([RF]\)\s*)?(\S+)')


def read_info(run):
    info = {}
    try:
        with open(os.path.join(run, 'run_info.txt')) as f:
            for line in f:
                k, _, v = line.rstrip('\n').partition('=')
                info[k] = v
    except OSError:
        pass
    return info


def find_run(root, flow, cfg, corner, period):
    """The newest run of `flow` for this configuration, corner and period: (dir, info) or None."""
    found = []
    if not os.path.isdir(root):
        return None
    for d in os.listdir(root):
        run = os.path.join(root, d)
        info = read_info(run)
        if (info.get('flow', 'yosys' if root.endswith('syn_out') else 'genus') == flow and
                info.get('config') == cfg and info.get('corner') == corner and
                info.get('clk_period_ps', '').split('.')[0] == str(period) and
                not info.get('overrides')):
            flat = info.get('flatten', '1') == '1'
            found.append((flat, os.path.getmtime(os.path.join(run, 'run_info.txt')), run, info))
    if not found:
        return None
    found.sort()
    _, _, run, info = found[-1]
    return run, info


def read(path):
    try:
        with open(path, errors='replace') as f:
            return f.read()
    except OSError:
        return ''


def yosys_metrics(run, info):
    m = {'run': run, 'notes': []}
    rpt = os.path.join(run, 'reports', 'area.rpt')
    if os.path.exists(rpt):
        modules, order, top_area = parse_report(rpt)
        top = find_top(modules, order)
        m['area'] = top_area or inclusive(modules, top, {})
        cells = seq = 0

        def walk(name, mult):
            nonlocal cells, seq
            for typ, (c, area) in modules[name]['cells'].items():
                if area is not None:
                    cells += mult * c
                    if SEQ_CELL.match(typ):
                        seq += mult * c
            for ch, c in modules[name]['children'].items():
                walk(ch, mult * c)
        walk(top, 1)
        m['cells'], m['flops'] = cells, seq
    worst = None
    for g in STA_GROUPS:
        text = read(os.path.join(run, 'reports', 'timing', g + '.rpt'))
        s = STA_SLACK.search(text)
        if s and (worst is None or float(s.group(1)) < worst[0]):
            st, en = START.search(text), END.search(text)
            worst = (float(s.group(1)), g, st.group(1) if st else '', en.group(1) if en else '')
    if worst:
        m['wns'], m['group'], m['start'], m['end'] = worst
    if info.get('flatten') == '0':
        m['notes'].append('hierarchical run (no flattened one found): no optimisation across '
                          'module boundaries')
    return m


def genus_metrics(run, info):
    m = {'run': run, 'notes': []}
    area_txt = read(os.path.join(run, 'reports', 'area.rpt'))
    qor = read(os.path.join(run, 'reports', 'qor.rpt'))
    for line in area_txt.splitlines():
        tok = line.split()
        if tok and tok[0] == 'ibex_top':
            nums = [t for t in tok[1:] if re.fullmatch(r'-?\d+(?:\.\d+)?', t)]
            if len(nums) >= 2:
                m['cells'], m['area'] = int(float(nums[0])), float(nums[1])
            break
    if 'area' not in m:
        a = re.search(r'(?:Total )?Cell Area\s+(\d+(?:\.\d+)?)', qor)
        if a:
            m['area'] = float(a.group(1))
    s = re.search(r'Sequential Instance Count\s+(\d+)', qor)
    if s:
        m['flops'] = int(s.group(1))
    if 'cells' not in m:
        c = re.search(r'Leaf Instance Count\s+(\d+)', qor)
        if c:
            m['cells'] = int(c.group(1))
    timing = read(os.path.join(run, 'reports', 'timing.rpt'))
    for rx in GENUS_SLACK:
        s = rx.search(timing)
        if s:
            m['wns'] = float(s.group(1)) / 1000.0
            st, en = START.search(timing), END.search(timing)
            m['start'], m['end'] = (st.group(1) if st else ''), (en.group(1) if en else '')
            m['group'] = 'all paths'
            break
    for k, what in (('area', 'area'), ('wns', 'worst slack')):
        if k not in m:
            m['notes'].append('{} not found in its reports (format?)'.format(what))
    return m


def bars(rows, value, fmt, series_labels, unit, target=None):
    """Grouped horizontal bars: one group per configuration, one bar per flow (series 1, 2)."""
    bar_h, gap, row_h, label_w, plot_w = 14, 2, 46, 130, 520
    vals = [v for r in rows for v in (value(r[1]), value(r[2])) if v is not None]
    vmax = max(vals + ([target] if target else [])) if vals else 1
    svg = []
    for i, (cfg, a, b) in enumerate(rows):
        y0 = 8 + i * row_h
        svg.append('<text class="blabel" x="{}" y="{}">{}</text>'.format(
            label_w - 10, y0 + bar_h + 2, html.escape(cfg)))
        for j, (m, label) in enumerate(zip((a, b), series_labels)):
            v = value(m)
            y = y0 + j * (bar_h + gap)
            if v is None:
                svg.append('<text class="bval" x="{}" y="{}">no run</text>'.format(
                    label_w + 6, y + bar_h - 3))
                continue
            w = max(plot_w * v / vmax, 1)
            tip = json.dumps({'design': cfg, 'flow': label, 'v': fmt(v) + ' ' + unit})
            svg.append('<rect class="bar" x="{}" y="{}" width="{:.1f}" height="{}" rx="4" '
                       'style="fill:var(--series-{})" data-tip=\'{}\'></rect>'.format(
                           label_w, y, w, bar_h, j + 1, html.escape(tip, quote=True)))
            svg.append('<text class="bval" x="{:.1f}" y="{}">{}</text>'.format(
                label_w + w + 6, y + bar_h - 3, fmt(v)))
    h = 8 + len(rows) * row_h
    if target:
        x = label_w + plot_w * target / vmax
        svg.append('<line class="target" x1="{x:.1f}" y1="0" x2="{x:.1f}" y2="{h}"></line>'
                   '<text class="bval" x="{x:.1f}" y="{y}" text-anchor="middle">target {t}</text>'
                   .format(x=x, h=h, y=h + 14, t=fmt(target)))
        h += 18
    return ('<svg width="{w}" height="{h}" viewBox="0 0 {w} {h}" role="img">'
            '<line class="axis" x1="{x}" y1="0" x2="{x}" y2="{hh}"></line>{body}</svg>').format(
                w=label_w + plot_w + 80, h=h, x=label_w, hh=8 + len(rows) * row_h,
                body=''.join(svg))


def fmax_mhz(m, period_ns):
    if m.get('wns') is None:
        return None
    t = period_ns - m['wns']
    return 1000.0 / t if t > 0 else None


def write_html(out, rows, corner, period, ge):
    period_ns = period / 1000.0
    kge = lambda m: m['area'] / ge / 1000 if m.get('area') is not None else None  # noqa: E731
    labels = [lab for _, lab in FLOWS]
    area_svg = bars(rows, kge, lambda v: '{:.1f}'.format(v), labels, 'kGE')
    fmax_svg = bars(rows, lambda m: fmax_mhz(m, period_ns), lambda v: '{:.0f}'.format(v), labels,
                    'MHz', target=1000.0 / period_ns)

    def cell(m, key, fmt):
        v = m.get(key)
        return '<td class="num">{}</td>'.format('—' if v is None else fmt(v))

    trs, notes, runs = [], [], []
    for cfg, a, b in rows:
        for m, (flow, label) in zip((a, b), FLOWS):
            if not m.get('run'):
                trs.append('<tr><td>{}</td><td>{}</td><td colspan="7">no run</td></tr>'.format(
                    html.escape(cfg), label))
                continue
            f = fmax_mhz(m, period_ns)
            path = '{} → {}'.format(m.get('start', ''), m.get('end', '')) if m.get('start') else ''
            trs.append('<tr><td>{}</td><td>{}</td>{}{}{}{}{}<td class="num">{}</td>'
                       '<td class="path">{}</td></tr>'.format(
                           html.escape(cfg), label,
                           cell(m, 'area', lambda v: '{:,.0f}'.format(v)),
                           '<td class="num">{}</td>'.format('—' if kge(m) is None else '{:.1f}'.format(kge(m))),
                           cell(m, 'cells', lambda v: '{:,}'.format(v)),
                           cell(m, 'flops', lambda v: '{:,}'.format(v)),
                           cell(m, 'wns', lambda v: '{:+.2f}'.format(v)),
                           '—' if f is None else '{:.0f}'.format(f),
                           html.escape(path + (' ({})'.format(m['group']) if m.get('group') else ''))))
            notes += ['{} / {}: {}'.format(cfg, label, n) for n in m['notes']]
            runs.append('{} / {}: {}'.format(cfg, label, os.path.abspath(m['run'])))
        if a.get('area') and b.get('area'):
            notes.append('{}: Genus area is {:+.0f}% of Yosys'.format(
                cfg, 100 * (b['area'] - a['area']) / a['area']))

    dark = ('color-scheme:dark;--surface-1:#1a1a19;--page:#0d0d0d;--text-primary:#f0efec;'
            '--text-secondary:#c3c2b7;--muted:#898781;--grid:#2c2c2a;--axis:#383835;'
            '--series-1:{};--series-2:{};'.format(*COLORS_DARK))
    doc = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Synthesis flows: Yosys + OpenSTA vs Genus</title>
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
  max-width:1100px; }}
h1 {{ font-size:20px; margin:0 0 4px; font-weight:600; }}
h2 {{ font-size:15px; margin:28px 0 8px; font-weight:600; }}
.sub, .note {{ color:var(--text-secondary); font-size:13px; margin:4px 0 0; }}
.sw {{ width:12px; height:12px; border-radius:3px; display:inline-block; }}
.legend {{ display:flex; gap:20px; font-size:13px; color:var(--text-secondary); margin:12px 0 4px; }}
.legend span {{ display:flex; align-items:center; gap:6px; }}
.blabel {{ fill:var(--text-primary); font-size:13px; text-anchor:end; }}
.bval {{ fill:var(--text-secondary); font-size:12px; font-variant-numeric:tabular-nums; }}
.axis {{ stroke:var(--axis); stroke-width:1; }}
.target {{ stroke:var(--muted); stroke-width:1; stroke-dasharray:4 3; }}
.bar {{ cursor:default; }}
.bar:hover {{ opacity:.8; }}
table {{ border-collapse:collapse; width:100%; font-size:13px; }}
th, td {{ padding:5px 8px; border-bottom:1px solid var(--grid); text-align:left; vertical-align:top; }}
th {{ color:var(--muted); font-weight:500; }}
.num {{ text-align:right; font-variant-numeric:tabular-nums; white-space:nowrap; }}
.path {{ font-size:12px; color:var(--text-secondary); word-break:break-all; }}
#tip {{ position:fixed; pointer-events:none; background:var(--surface-1); color:var(--text-primary);
  border:1px solid var(--grid); border-radius:6px; padding:8px 10px; font-size:13px; display:none;
  box-shadow:0 4px 14px rgba(0,0,0,.12); }}
#tip .p {{ color:var(--muted); font-size:12px; }}
</style></head>
<body><div class="viz-root"><div class="card">
<h1>Synthesis flows: Yosys + OpenSTA vs Genus</h1>
<p class="sub">NanGate45 {corner} corner, clock {period_ns:.3f} ns ({target:.0f} MHz) &middot; 1 GE = NAND2_X1 = {ge} &micro;m&sup2; &middot; generated {when}</p>
<div class="legend"><span><i class="sw" style="background:var(--series-1)"></i>{l1}</span><span><i class="sw" style="background:var(--series-2)"></i>{l2}</span></div>
<h2>Area (kGE)</h2>
{area_svg}
<h2>Clock frequency the worst slack allows (MHz)</h2>
{fmax_svg}
<p class="note">1 / (period &minus; worst slack), over all path groups. Yosys + OpenSTA does no buffering or
sizing of high-fanout nets (no placement either), so its worst path is often an unbuffered net and its
frequency a lower bound; Genus maps with timing-driven optimisation. Genus area is cell area, without the
wire-load net area, as Yosys reports it.</p>
<h2>All numbers</h2>
<table><thead><tr><th>Configuration</th><th>Flow</th><th class="num">Area &micro;m&sup2;</th>
<th class="num">kGE</th><th class="num">Cells</th><th class="num">Flops</th><th class="num">Worst slack ns</th>
<th class="num">MHz</th><th>Worst path</th></tr></thead>
<tbody>{rows}</tbody></table>
{notes}
<p class="note">NanGate45 is a generic library: compare the flows and the configurations with each
other, not with a production node.</p>
<p class="note">Runs: {runs}</p>
</div><div id="tip"></div></div>
<script>
const tip = document.getElementById('tip');
document.querySelectorAll('.bar').forEach(r => {{
  r.addEventListener('mousemove', e => {{
    const d = JSON.parse(r.dataset.tip);
    tip.innerHTML = '<div class="p"></div><b></b>';
    tip.children[0].textContent = d.flow; tip.children[1].textContent = d.design + ': ' + d.v;
    tip.style.display = 'block'; tip.style.left = (e.clientX + 14) + 'px'; tip.style.top = (e.clientY + 14) + 'px';
  }});
  r.addEventListener('mouseleave', () => {{ tip.style.display = 'none'; }});
}});
</script></body></html>
""".format(c1=COLORS_LIGHT[0], c2=COLORS_LIGHT[1], dark=dark, corner=html.escape(corner),
           period_ns=period_ns, target=1000.0 / period_ns, ge=ge,
           when=datetime.datetime.now().strftime('%Y-%m-%d %H:%M'), l1=labels[0], l2=labels[1],
           area_svg=area_svg, fmax_svg=fmax_svg, rows=''.join(trs),
           notes=''.join('<p class="note">{}</p>'.format(html.escape(n)) for n in notes),
           runs=' &middot; '.join(html.escape(r) for r in runs) or 'none')
    with open(out, 'w') as f:
        f.write(doc)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--configs', nargs='+', default=['opentitan', 'small'])
    ap.add_argument('--corner', default='slow')
    ap.add_argument('--period', type=int, default=6667, help='clock period in ps')
    ap.add_argument('--syn-out', default=os.path.join(SYN, 'syn_out'))
    ap.add_argument('--genus-out', default=os.path.join(SYN, 'genus_out'))
    ap.add_argument('--ge-area', type=float, default=NANGATE45_NAND2_X1_AREA)
    ap.add_argument('-o', '--out')
    args = ap.parse_args()

    rows, missing = [], []
    for cfg in args.configs:
        ms = []
        for (flow, label), root, fn in zip(FLOWS, (args.syn_out, args.genus_out),
                                           (yosys_metrics, genus_metrics)):
            r = find_run(root, flow, cfg, args.corner, args.period)
            if r:
                ms.append(fn(*r))
            else:
                ms.append({'notes': []})
                missing.append('{} / {}'.format(cfg, label))
        rows.append((cfg, ms[0], ms[1]))
    if len(missing) == 2 * len(args.configs):
        sys.exit('No runs for {} at the {} corner and {} ps (run_info.txt in {} and {})'.format(
            ', '.join(args.configs), args.corner, args.period, args.syn_out, args.genus_out))
    out = args.out or os.path.join(args.syn_out, 'compare_flows_{}_{}ps_{}.html'.format(
        args.corner, args.period, datetime.datetime.now().strftime('%Y%m%d_%H%M%S')))
    write_html(out, rows, args.corner, args.period, args.ge_area)
    for cfg, a, b in rows:
        for m, (_, label) in zip((a, b), FLOWS):
            if m.get('area') is not None:
                print('{:12s} {:16s} {:8.1f} kGE  worst slack {}'.format(
                    cfg, label, m['area'] / args.ge_area / 1000,
                    '{:+.2f} ns'.format(m['wns']) if m.get('wns') is not None else 'n/a'))
    if missing:
        print('No run for: ' + ', '.join(missing))
    print('Comparison: ' + os.path.abspath(out))


if __name__ == '__main__':
    main()
