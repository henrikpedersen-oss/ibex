#!/usr/bin/env python3

# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

"""Tcl for yosys_run_synth.tcl: the parameters of a named ibex_configs.yaml configuration.

Enum values ("ibex_pkg::RV32MSlow") become their numbers from rtl/ibex_pkg.sv, since Yosys'
chparam takes no enum names. --override NAME=VALUE (repeatable, same value syntax) changes one
parameter. Writes `set lr_synth_ibex_params {{Name value} ...}` and lr_synth_ibex_secure_ibex.
"""

import argparse
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
IBEX = os.path.join(HERE, '..', '..')


def read_config(path, name):
    params, found = {}, False
    with open(path) as f:
        for line in f:
            if re.match(r'^{}:\s*$'.format(re.escape(name)), line):
                found = True
                continue
            if found:
                m = re.match(r'^\s+(\w+)\s*:\s*(.+?)\s*$', line)
                if m:
                    params[m.group(1)] = m.group(2).strip('"\'')
                elif line.strip() and not line.startswith((' ', '#')):
                    break
    if not found:
        sys.exit('{}: no configuration named {!r}'.format(path, name))
    return params


def read_enums(pkg):
    with open(pkg) as f:
        return {n: int(v) for n, v in re.findall(r'\b(\w+)\s*=\s*(\d+)\s*[,}/\n]', f.read())}


def value(raw, enums):
    if re.fullmatch(r'\d+', raw):
        return int(raw)
    name = raw.split('::')[-1]
    if name not in enums:
        sys.exit('unknown value {!r}: not a number or an ibex_pkg enum'.format(raw))
    return enums[name]


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('config')
    ap.add_argument('--override', action='append', default=[], metavar='NAME=VALUE')
    ap.add_argument('--config-file', default=os.path.join(IBEX, 'ibex_configs.yaml'))
    ap.add_argument('--pkg', default=os.path.join(IBEX, 'rtl', 'ibex_pkg.sv'))
    args = ap.parse_args()

    params = read_config(args.config_file, args.config)
    for ov in args.override:
        name, _, val = ov.partition('=')
        if name not in params:
            sys.exit('--override {}: {} has no parameter {}'.format(ov, args.config, name))
        params[name] = val
    enums = read_enums(args.pkg)
    values = [(k, value(v, enums)) for k, v in params.items()]

    # ibex_core's ASSERT_INIT parameter checks. Yosys does not evaluate them, so a forbidden
    # combination would synthesise without complaint.
    v = dict(values)
    forbidden = [
        (v.get('BaseIsa') == enums['BaseIsaRV32IorCHERIoT'] and v.get('WritebackStage') == 0,
         'CHERIoT needs WritebackStage=1 (IllegalParamCHERIoTNoWriteback, '
         'doc/03_reference/cheriot.rst)'),
        (v.get('SecureIbex') == 1 and v.get('RV32M') == enums['RV32MNone'],
         'SecureIbex needs M (IllegalParamSecure)'),
    ]
    for bad, why in forbidden:
        if bad:
            sys.exit('{}: unsupported configuration: {}'.format(args.config, why))

    print('# {} {}'.format(args.config, ' '.join(args.override)).rstrip())
    print('set lr_synth_ibex_params {' + ' '.join('{{{} {}}}'.format(k, v) for k, v in values) + '}')
    print('set lr_synth_ibex_secure_ibex {}'.format(dict(values).get('SecureIbex', 0)))


if __name__ == '__main__':
    main()
