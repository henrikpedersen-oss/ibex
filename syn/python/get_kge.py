#!/usr/bin/env python3

# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Parse a yosys area report and give a kGE equivalent

import argparse
import gzip
import re

# "cell (NAND2_X1) {" / "cell ("sky130_fd_sc_hd__nand2_1") {", and the cell's "area : 0.798;".
CELL_RE = re.compile(r'^\s*cell\s*\(\s*"?([^")\s]+)"?\s*\)')
AREA_RE = re.compile(r'^\s*area\s*:\s*([^;\s]+)\s*;?')  # ASAP7 INVBUF: no ";"


def read_lib(lib_file_path, ref_cell):
    # Any liberty layout (NanGate45's, SKY130's, ASAP7's), gzipped or not: each cell's first area.
    opener = gzip.open if lib_file_path.endswith('.gz') else open
    with opener(lib_file_path, 'rt', errors='replace') as f:
        lib_file = f.readlines()

    cell_dict = {}
    weighted_dict = {}
    cell_name = None
    for line_idx, line in enumerate(lib_file):
        m = CELL_RE.match(line)
        if m:
            if cell_name is not None:
                raise RuntimeError('{}:{} Found cell while searching for area'
                                   .format(lib_file_path, line_idx + 1))
            cell_name = m.group(1)
            continue
        m = AREA_RE.match(line)
        if m and cell_name is not None:
            try:
                cell_dict[cell_name] = float(m.group(1))
                cell_name = None
            except ValueError:
                raise RuntimeError('{}:{} Area declaration misformatted'
                                   .format(lib_file_path, line_idx + 1))

    if ref_cell not in cell_dict:
        raise RuntimeError('Specified reference cell: {} was not found in '
                           'library: {}' .format(ref_cell, lib_file_path))

    for cell in cell_dict:
        weighted_dict[cell] = cell_dict[cell] / cell_dict[ref_cell]
    return weighted_dict


def get_kge(report_path, weighted_dict):
    with open(report_path, 'r') as f:
        report = f.readlines()
    # A hierarchical report lists each module's own cells once, however often it is instantiated;
    # its "design hierarchy" section has the whole design's cell counts.
    for idx, line in enumerate(report):
        if line.strip() == '=== design hierarchy ===':
            report = report[idx:]
            break
    ge = 0.0
    for line_idx, line in enumerate(report):
        data = line.split()
        if not data:
            continue
        # Older Yosys prints "<cell> <count>", Yosys 0.62 "<count> <area> <cell>".
        if data[0] in weighted_dict:
            cell, count_idx = data[0], 1
        elif data[-1] in weighted_dict:
            cell, count_idx = data[-1], 0
        else:
            continue
        try:
            ge += float(data[count_idx]) * weighted_dict[cell]
        except (IndexError, ValueError):
            raise RuntimeError('{}:{} Cell {} matched but was misformatted'
                               .format(report_path, line_idx + 1, cell))
    print("Area in kGE = ", round(ge/1000, 2))


def main():
    arg_parser = argparse.ArgumentParser(
        description="""Calculate kGE from a Yosys report and LIB file""")

    arg_parser.add_argument('lib_file_path', help='Path to the LIB file')
    arg_parser.add_argument('report_path', help='Path to the report')
    arg_parser.add_argument('--cell', help='Reference cell (default:NAND2_X1)',
                            default='NAND2_X1')

    args = arg_parser.parse_args()

    weighted_dict = read_lib(args.lib_file_path, args.cell)
    get_kge(args.report_path, weighted_dict)


if __name__ == "__main__":
    main()
