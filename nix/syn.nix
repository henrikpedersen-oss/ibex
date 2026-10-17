# Copyright lowRISC Contributors.
# Licensed under the MIT License, see LICENSE for details.
# SPDX-License-Identifier: MIT

# Deps for Ibex synthesis jobs

{
  inputs,
  pkgs,
  ...
}: let

  sv2v_local = import ./sv2v.nix {inherit inputs pkgs;};

  ibex_syn_deps = [
    sv2v_local.default
  ] ++ (with pkgs; [
    # haskellPackages.sv2v # broken
    yosys
    openroad
  ]);

  # Create a dumb package of nangate45
  # > All we need is a path to the sources
  nangate45 = pkgs.stdenv.mkDerivation rec {
    pname = "openroad-nangate45";
    version = "PDKv1.3_v2010_12.Apache.CCL";
    src = pkgs.fetchFromGitHub {
      owner = "The-OpenROAD-Project";
      repo = "OpenROAD-flow-scripts";
      rev = "181e9133776117ea1b9f74dbacbfdaadff8c331b"; # Tag: v3.0
      hash = "sha256-fYAdhBsMcuCXmPMQVCRdm75Tk0rd9zLnLfJdjhnhC00=";
    };
    sourceRoot = "${src.name}/flow/platforms/nangate45";
    phases = [ "unpackPhase" "installPhase" ];
    installPhase = ''
        mkdir -p $out
        cp -r ./* $out
      '';
  };

  # The slow corner (0.95 V, 125 C) of the same library, NangateOpenCellLibrary_slow of 2011, as
  # OpenROAD ships it for its multi-corner tests; the flow scripts' platform has the typical corner
  # (1.10 V, 25 C) only. Same cells and cell areas (apart from the physical-only TAPCELL_X1), so
  # areas compare across corners. syn_setup.sh selects it with LR_SYNTH_CORNER=slow.
  ibex_syn_profile = ''
    export LR_SYNTH_CELL_LIBRARY_NAME=nangate
    export LR_SYNTH_CELL_LIBRARY_PATH=${nangate45}/lib/NangateOpenCellLibrary_typical.lib
    export LR_SYNTH_CELL_LIBRARY_PATH_TYPICAL=${nangate45}/lib/NangateOpenCellLibrary_typical.lib
    export LR_SYNTH_CELL_LIBRARY_PATH_SLOW=${pkgs.openroad.src}/test/Nangate45/Nangate45_slow.lib
  '';

in {

  deps = ibex_syn_deps;
  profile = ibex_syn_profile;

}
