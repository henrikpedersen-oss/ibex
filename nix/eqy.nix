# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# EQY, the Yosys equivalence checker. Its plugins are built against nixpkgs' Yosys, so the input
# tag must match that Yosys version.
{
  pkgs,
  src,
}:
pkgs.stdenv.mkDerivation {
  pname = "eqy";
  version = "0.62";
  inherit src;

  nativeBuildInputs = [pkgs.yosys];
  buildInputs = [(pkgs.python3.withPackages (p: [p.click]))];

  makeFlags = ["PREFIX=$(out)"];
  buildFlags = ["build"];
}
