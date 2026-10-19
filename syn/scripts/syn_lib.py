# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""The cell library of a synthesis run, for the report scripts: lib/<name>.cfg (format in
lib/nangate45.cfg) and the run's run_info.txt (lib=, ge_cell=, ge_area=, time_unit_ps=, which both
flows write). A run without them is a NanGate45 one: the only library before there was a choice."""

import os
import re

LIB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'lib')
DEFAULT = 'nangate45'
# What a run that names no library used, if lib/nangate45.cfg is not there to say.
NANGATE45 = {'name': 'nangate45', 'title': 'NanGate45', 'ge_cell': 'NAND2_X1', 'ge_area': '0.798',
             'time_unit_ps': '1000'}


def load(name=DEFAULT):
    """lib/<name>.cfg as a dict; NanGate45's defaults for nangate45 if the file is missing."""
    path = os.path.join(LIB_DIR, name + '.cfg')
    if not os.path.exists(path):
        if name == DEFAULT:
            return dict(NANGATE45)
        raise SystemExit('No cell library {} ({})'.format(name, path))
    cfg = {}
    with open(path) as f:
        for line in f:
            line = re.sub(r'(^|\s+)#.*$', '', line.rstrip('\n')).strip()
            if '=' in line:
                k, _, v = line.partition('=')
                cfg[k.strip()] = v.strip()
    return cfg


def read_run_info(run):
    info = {}
    try:
        with open(os.path.join(run, 'run_info.txt')) as f:
            for line in f:
                k, _, v = line.rstrip('\n').partition('=')
                info[k] = v
    except OSError:
        pass
    return info


def for_run(run):
    """The library of a run directory: the cfg, with the run's own GE and time unit if it recorded
    them. Keys: name, title, ge_cell, ge_area (float), time_unit_ps (float)."""
    info = read_run_info(run)
    lib = info.get('lib') or DEFAULT
    try:
        cfg = load(lib)
    except SystemExit:
        cfg = {'name': lib, 'title': lib}
    out = dict(cfg)
    for k in ('ge_cell', 'ge_area', 'time_unit_ps'):
        if info.get(k):
            out[k] = info[k]
    out.setdefault('name', lib)
    out.setdefault('title', lib)
    out['ge_area'] = float(out.get('ge_area') or NANGATE45['ge_area'])
    out['time_unit_ps'] = float(out.get('time_unit_ps') or NANGATE45['time_unit_ps'])
    out.setdefault('ge_cell', NANGATE45['ge_cell'] if lib == DEFAULT else '?')
    return out


def for_report(report):
    """The library of the run an area report (<run>/reports/area.rpt) belongs to."""
    return for_run(os.path.dirname(os.path.dirname(os.path.abspath(report))))


def ge_label(lib, ge_area=None):
    """'NanGate45, 1 GE = NAND2_X1 = 0.798 µm²'."""
    return '{}, 1 GE = {} = {} µm²'.format(lib['title'], lib['ge_cell'],
                                         lib['ge_area'] if ge_area is None else ge_area)
