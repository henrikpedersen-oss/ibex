#!/usr/bin/env python3
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""One liberty file for the synthesis flows from a library corner's files (lib/syn_lib.sh runs it).

Several files (ASAP7: one per cell group, most gzipped) are merged into one library: the first file's
header, the header groups of the others it lacks (ASAP7's SEQ file names its table templates
differently), then every cell of every file. Cells matching a --dont-use pattern (shell wildcards)
get `dont_use : true`, as OpenROAD-flow-scripts' markDontUse.py does, so that neither Yosys
(dfflibmap, abc) nor Genus maps logic onto them; cells instantiated by name are still used. A single
file is otherwise written unchanged.

  scripts/prepare_liberty.py -o out.lib [--name merged_name] [--dont-use 'pat ...'] in.lib[.gz] ...
"""

import argparse
import fnmatch
import gzip
import os
import re
import sys

# Braces count only outside strings and comments (liberty has /* */ comments only).
TOKEN = re.compile(r'"(?:[^"\\]|\\.)*"|/\*.*?\*/|[{}]', re.S)
GROUP_HEAD = re.compile(r'(\w+)\s*\(\s*"?([^")]*?)"?\s*\)\s*$')
LIBRARY = re.compile(r'(\blibrary\s*\(\s*)"?([^")]*?)"?(\s*\))')
DONT_USE = re.compile(r'\bdont_use\s*:\s*true\b')


def read(path):
    # latin-1 maps every byte to one character, so the text is written back byte for byte.
    opener = gzip.open if path.endswith('.gz') else open
    with opener(path, 'rt', encoding='latin-1', newline='') as f:
        return f.read()


def groups(text, path):
    """The library's top-level groups, [(kind, name, start, head_end, end)]: start is the beginning
    of the line with the group's head, head_end just past its opening brace, end just past its
    closing brace and the newline after it."""
    depth = 0
    closed = False
    out = []
    cur = None
    for m in TOKEN.finditer(text):
        tok = m.group(0)
        if tok == '{':
            if depth == 1:
                line_start = text.rfind('\n', 0, m.start()) + 1
                head = text[line_start:m.start()].strip()
                h = GROUP_HEAD.search(head)
                if not h:
                    sys.exit('{}: cannot read the group head "{}"'.format(path, head[-80:]))
                cur = (h.group(1), h.group(2).strip(), line_start, m.end())
            depth += 1
        elif tok == '}':
            depth -= 1
            if depth == 1 and cur:
                end = m.end() + (1 if text.startswith('\n', m.end()) else 0)
                out.append(cur + (end,))
                cur = None
            elif depth == 0:
                closed = True
            elif depth < 0:
                sys.exit('{}: unbalanced braces'.format(path))
    if not closed or depth != 0:
        sys.exit('{}: no complete library group'.format(path))
    return out


def dont_use_insertions(text, gs, patterns):
    """Offsets (end of each matching cell's head line) where `dont_use : true;` goes."""
    at = []
    for kind, name, start, head_end, end in gs:
        if kind == 'cell' and any(fnmatch.fnmatchcase(name, p) for p in patterns):
            if not DONT_USE.search(text, head_end, end):
                nl = text.find('\n', head_end, end)
                at.append(head_end if nl < 0 else nl)
    return at


def insert(text, offsets, what='\n    dont_use : true;'):
    out, prev = [], 0
    for o in sorted(offsets):
        out += [text[prev:o], what]
        prev = o
    return ''.join(out) + text[prev:]


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('files', nargs='+')
    ap.add_argument('-o', '--out', required=True)
    ap.add_argument('--name', help='library name of a merged library (default: the first file\'s)')
    ap.add_argument('--dont-use', default='', help='space-separated cell name patterns')
    args = ap.parse_args()
    patterns = args.dont_use.split()

    texts = [read(p) for p in args.files]
    parsed = [groups(t, p) for t, p in zip(texts, args.files)]
    ncells = sum(1 for gs in parsed for g in gs if g[0] == 'cell')
    marked = extra = 0

    if len(args.files) == 1:
        at = dont_use_insertions(texts[0], parsed[0], patterns)
        marked = len(at)
        body = insert(texts[0], at)
    else:
        first, g0 = texts[0], parsed[0]
        cells0 = [g for g in g0 if g[0] == 'cell']
        if not cells0:
            sys.exit('{}: no cells'.format(args.files[0]))
        head = first[:cells0[0][2]]
        if args.name:
            head = LIBRARY.sub(lambda m: m.group(1) + args.name + m.group(3), head, count=1)
        have = {(k, n) for k, n, _, _, _ in g0 if k != 'cell'}
        parts, cells, seen = [head], [], set()
        for path, text, gs in zip(args.files, texts, parsed):
            after_cells = False
            for kind, name, start, head_end, end in gs:
                if kind == 'cell':
                    after_cells = True
                    if name in seen:
                        sys.exit('{}: cell {} is in two of the files'.format(path, name))
                    seen.add(name)
                    at = dont_use_insertions(text, [(kind, name, start, head_end, end)], patterns)
                    marked += len(at)
                    cells.append('\n' + insert(text[start:end], [o - start for o in at]))
                elif after_cells:
                    sys.exit('{}: {} ({}) after the cells: not merged'.format(path, kind, name))
                elif (kind, name) not in have:
                    have.add((kind, name))
                    extra += 1
                    parts.append(text[start:end])
        body = ''.join(parts + cells) + '\n}\n'

    tmp = '{}.tmp.{}'.format(args.out, os.getpid())
    with open(tmp, 'w', encoding='latin-1', newline='') as f:
        f.write(body)
    os.replace(tmp, args.out)
    print('prepare_liberty: {} cells from {} file(s), {} marked dont_use, {} header groups added: {}'
          .format(ncells, len(args.files), marked, extra, args.out))


if __name__ == '__main__':
    main()
