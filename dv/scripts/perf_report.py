#!/usr/bin/env python3

# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

"""Performance-test report for the CHERIoT RTOS test SoC (firmware/perf_test).

Reads the kept UART logs perf-<config>-lat<n>.<build>.uart.log, takes each "PERF <workload> cycles
<n> instret <n> words <n>" line, and reports the cycles per workload, configuration and code RAM
latency against Earl Grey 2's boot budget (100 ms at 150 MHz = 15M cycles). Writes a text table
and, with -o, a self-contained HTML page (one line chart per workload, a table under each).
"""

import argparse
import glob
import html
import json
import os
import re
import sys

CLOCK_HZ = 150e6
BUDGET_CYCLES = 15_000_000

LOG_RE = re.compile(r'^perf-(?P<cfg>.+)-lat(?P<lat>\d+)\.[^.]+\.uart\.log$')
PERF_RE = re.compile(r'PERF (?P<wl>\S+) cycles (?P<cyc>\S+)(?: core_cycles (?P<core>\S+))? '
                     r'instret (?P<ins>\S+) words (?P<words>\S+)')
ANSI_RE = re.compile(r'\x1b\[[0-9;]*m')

WORKLOADS = {
    'hash_feed_core': 'ROM_EXT hash feed, by the core',
    'hash_feed_dma': 'ROM_EXT hash feed, by the DMA (core asleep)',
}
COLORS_LIGHT = ['#2a78d6', '#eb6834']
COLORS_DARK = ['#3987e5', '#d95926']


def num(text):
    return int(text, 16) if text.lower().startswith('0x') else int(text)


def read_logs(results_dir):
    """{(cfg, lat): {'ok': bool, 'perf': {workload: (cycles, instret, words)}}}"""
    runs = {}
    for path in sorted(glob.glob(os.path.join(results_dir, 'perf-*.uart.log'))):
        m = LOG_RE.match(os.path.basename(path))
        if not m:
            continue
        with open(path, errors='replace') as f:
            text = ANSI_RE.sub('', f.read())
        # (cycles, instret, words, core awake cycles); logs before core_cycles: the same as cycles.
        perf = {p.group('wl'): (num(p.group('cyc')), num(p.group('ins')), num(p.group('words')),
                                num(p.group('core') or p.group('cyc')))
                for p in PERF_RE.finditer(text)}
        ok = 'All tests finished' in text and 'FAIL' not in text
        runs[(m.group('cfg'), int(m.group('lat')))] = {'ok': ok, 'perf': perf, 'log': path}
    return runs


def text_report(runs, cfgs, lats, workloads):
    out = []
    for wl in workloads:
        out.append('{} ({})'.format(WORKLOADS.get(wl, wl), wl))
        out.append('  {:<14} {:>4} {:>12} {:>11} {:>10} {:>9} {:>9}  {}'.format(
            'config', 'lat', 'cycles', 'core awake', 'instret', 'ms@150', 'budget', 'run'))
        for cfg in cfgs:
            for lat in lats:
                r = runs.get((cfg, lat))
                if not r or wl not in r['perf']:
                    out.append('  {:<14} {:>4} {:>12}'.format(cfg, lat, 'no result'))
                    continue
                cyc, ins, _, core = r['perf'][wl]
                out.append('  {:<14} {:>4} {:>12,} {:>11,} {:>10,} {:>9.3f} {:>8.2f}%  {}'.format(
                    cfg, lat, cyc, core, ins, 1e3 * cyc / CLOCK_HZ, 100 * cyc / BUDGET_CYCLES,
                    'pass' if r['ok'] else 'FAIL'))
        out.append('')
    return '\n'.join(out)


def svg_chart(wl, runs, cfgs, lats):
    w, h, l, r, t, b = 560, 260, 70, 130, 16, 36
    pts = {cfg: [(lat, runs[(cfg, lat)]['perf'][wl][0]) for lat in lats
                 if (cfg, lat) in runs and wl in runs[(cfg, lat)]['perf']] for cfg in cfgs}
    ymax = max([c for p in pts.values() for _, c in p] + [1]) * 1.1
    x = lambda i: l + (w - l - r) * (i / max(len(lats) - 1, 1))  # noqa: E731
    y = lambda v: t + (h - t - b) * (1 - v / ymax)  # noqa: E731
    parts = []
    for k in range(5):
        v = ymax * k / 4
        parts.append('<line class="grid" x1="{}" x2="{}" y1="{:.1f}" y2="{:.1f}"/>'
                     '<text class="tick" x="{}" y="{:.1f}">{}</text>'.format(
                         l, w - r, y(v), y(v), l - 8, y(v) + 4, '{:,.0f}k'.format(v / 1e3)))
    for i, lat in enumerate(lats):
        parts.append('<text class="xtick" x="{:.1f}" y="{}">{}</text>'.format(x(i), h - b + 18, lat))
    parts.append('<text class="xtick" x="{:.1f}" y="{}">code RAM latency (cycles)</text>'.format(
        (l + w - r) / 2, h - 2))
    for j, cfg in enumerate(cfgs):
        p = pts[cfg]
        if not p:
            continue
        coords = [(x(lats.index(lat)), y(c)) for lat, c in p]
        parts.append('<polyline class="line" style="stroke:var(--series-{})" points="{}"/>'.format(
            j + 1, ' '.join('{:.1f},{:.1f}'.format(*c) for c in coords)))
        for (lat, c), (cx, cy) in zip(p, coords):
            tip = json.dumps({'cfg': cfg, 'lat': lat, 'cycles': c,
                              'ms': round(1e3 * c / CLOCK_HZ, 3),
                              'budget': round(100 * c / BUDGET_CYCLES, 2)})
            parts.append('<circle class="pt" cx="{:.1f}" cy="{:.1f}" r="4" style="fill:var(--series-{})" '
                         'data-tip=\'{}\'/>'.format(cx, cy, j + 1, html.escape(tip, quote=True)))
        lx, ly = coords[-1]
        parts.append('<text class="dlabel" x="{:.1f}" y="{:.1f}">{}</text>'.format(lx + 10, ly + 4,
                                                                                html.escape(cfg)))
    return '<svg width="{w}" height="{h}" viewBox="0 0 {w} {h}" role="img" aria-label="{a}">{p}</svg>'.format(
        w=w, h=h, a=html.escape(WORKLOADS.get(wl, wl)), p=''.join(parts))


def html_report(out, runs, cfgs, lats, workloads, text):
    sections = []
    for wl in workloads:
        rows = []
        for cfg in cfgs:
            for lat in lats:
                r = runs.get((cfg, lat))
                if not r or wl not in r['perf']:
                    continue
                cyc, ins, _, core = r['perf'][wl]
                rows.append('<tr><td>{}</td><td class="num">{}</td><td class="num">{:,}</td>'
                            '<td class="num">{:,}</td><td class="num">{:,}</td><td class="num">{:.3f}</td>'
                            '<td class="num">{:.2f}%</td><td>{}</td></tr>'.format(
                                html.escape(cfg), lat, cyc, core, ins, 1e3 * cyc / CLOCK_HZ,
                                100 * cyc / BUDGET_CYCLES, 'pass' if r['ok'] else '<b>FAIL</b>'))
        sections.append('<h2>{}</h2>{}<table><thead><tr><th>Configuration</th><th class="num">Latency</th>'
                        '<th class="num">Cycles</th><th class="num">Core awake</th><th class="num">Instructions</th>'
                        '<th class="num">ms at 150 MHz</th><th class="num">Of 15M budget</th>'
                        '<th>Run</th></tr></thead><tbody>{}</tbody></table>'.format(
                            html.escape(WORKLOADS.get(wl, wl)), svg_chart(wl, runs, cfgs, lats),
                            ''.join(rows)))
    legend = ''.join('<span><i class="sw" style="background:var(--series-{})"></i>{}</span>'.format(
        j + 1, html.escape(c)) for j, c in enumerate(cfgs))
    colors = ''.join('--series-{}:{};'.format(i + 1, c) for i, c in enumerate(COLORS_LIGHT))
    dark = ('color-scheme:dark;--surface-1:#1a1a19;--page:#0d0d0d;--text-primary:#f0efec;'
            '--text-secondary:#c3c2b7;--muted:#898781;--grid:#2c2c2a;' +
            ''.join('--series-{}:{};'.format(i + 1, c) for i, c in enumerate(COLORS_DARK)))
    doc = """<!doctype html><html lang="en"><head><meta charset="utf-8">
<title>Earl Grey 2 boot workload: performance</title><style>
.viz-root {{ color-scheme:light; --surface-1:#fcfcfb; --page:#f9f9f7; --text-primary:#0b0b0b;
  --text-secondary:#52514e; --muted:#898781; --grid:#e1e0d9; {colors} }}
@media (prefers-color-scheme: dark) {{ :root:where(:not([data-theme="light"])) .viz-root {{ {dark} }} }}
:root[data-theme="dark"] .viz-root {{ {dark} }}
body {{ margin:0; }}
.viz-root {{ font-family:system-ui,-apple-system,"Segoe UI",sans-serif; background:var(--page);
  color:var(--text-primary); padding:24px; min-height:100vh; box-sizing:border-box; }}
.card {{ background:var(--surface-1); border:1px solid var(--grid); border-radius:8px; padding:20px 24px; max-width:900px; }}
h1 {{ font-size:20px; margin:0 0 4px; font-weight:600; }}
h2 {{ font-size:15px; margin:28px 0 8px; font-weight:600; }}
.sub {{ color:var(--text-secondary); font-size:13px; margin:4px 0; }}
.legend {{ display:flex; gap:20px; font-size:13px; color:var(--text-secondary); margin:12px 0 0; }}
.legend span {{ display:flex; align-items:center; gap:6px; }}
.sw {{ width:12px; height:12px; border-radius:3px; display:inline-block; }}
.grid {{ stroke:var(--grid); stroke-width:1; }}
.tick {{ fill:var(--muted); font-size:11px; text-anchor:end; font-variant-numeric:tabular-nums; }}
.xtick {{ fill:var(--muted); font-size:11px; text-anchor:middle; }}
.line {{ fill:none; stroke-width:2; }}
.pt {{ stroke:var(--surface-1); stroke-width:2; }}
.dlabel {{ fill:var(--text-secondary); font-size:12px; }}
table {{ border-collapse:collapse; width:100%; font-size:13px; margin-top:8px; }}
th, td {{ padding:5px 8px; border-bottom:1px solid var(--grid); text-align:left; }}
th {{ color:var(--muted); font-weight:500; }}
.num {{ text-align:right; font-variant-numeric:tabular-nums; }}
#tip {{ position:fixed; pointer-events:none; background:var(--surface-1); color:var(--text-primary);
  border:1px solid var(--grid); border-radius:6px; padding:8px 10px; font-size:13px; display:none; }}
</style></head><body><div class="viz-root"><div class="card">
<h1>Earl Grey 2 boot workload on the CHERIoT RTOS test SoC</h1>
<p class="sub">EG2 requirement: power-on reset to the end of ROM, including ML-DSA-87 verification of a 128 KiB
ROM_EXT in RRAM, in 100 ms = {budget:,} cycles at 150 MHz. Shown here: the core's share, feeding the image to the
hash engine. The code RAM stands in for ROM/RRAM; its latency applies to instruction fetch and to the image reads.</p>
<div class="legend">{legend}</div>
{sections}
<h2>Text summary</h2><pre style="font-size:12px">{text}</pre>
</div><div id="tip"></div></div>
<script>
const tip = document.getElementById('tip');
document.querySelectorAll('.pt').forEach(p => {{
  p.addEventListener('mousemove', e => {{
    const d = JSON.parse(p.dataset.tip);
    tip.textContent = d.cfg + ', latency ' + d.lat + ': ' + d.cycles.toLocaleString() + ' cycles, ' + d.ms + ' ms, ' + d.budget + '% of budget';
    tip.style.display = 'block'; tip.style.left = (e.clientX + 14) + 'px'; tip.style.top = (e.clientY + 14) + 'px';
  }});
  p.addEventListener('mouseleave', () => {{ tip.style.display = 'none'; }});
}});
</script></body></html>
""".format(colors=colors, dark=dark, budget=BUDGET_CYCLES, legend=legend,
           sections=''.join(sections), text=html.escape(text))
    with open(out, 'w') as f:
        f.write(doc)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('results_dir')
    ap.add_argument('-o', '--out', help='HTML report')
    args = ap.parse_args()

    runs = read_logs(args.results_dir)
    if not runs:
        sys.exit('{}: no perf-<config>-lat<n> UART logs'.format(args.results_dir))
    order = ['opentitan', 'cheriot-min']
    cfgs = sorted({c for c, _ in runs}, key=lambda c: (order.index(c) if c in order else 99, c))
    lats = sorted({l for _, l in runs})
    workloads = [w for w in WORKLOADS if any(w in r['perf'] for r in runs.values())]
    workloads += sorted({w for r in runs.values() for w in r['perf']} - set(workloads))

    text = text_report(runs, cfgs, lats, workloads)
    print(text)
    for (cfg, lat), r in sorted(runs.items()):
        if not r['ok']:
            print('FAIL: {} latency {}: {}'.format(cfg, lat, r['log']))
    if args.out:
        html_report(args.out, runs, cfgs, lats, workloads, text)
        print('Report: ' + os.path.abspath(args.out))
    sys.exit(0 if all(r['ok'] for r in runs.values()) else 1)


if __name__ == '__main__':
    main()
