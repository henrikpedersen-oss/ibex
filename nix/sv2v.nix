# Copyright lowRISC Contributors.
# Licensed under the MIT License, see LICENSE for details.
# SPDX-License-Identifier: MIT

# Taken from:
# https://github.com/deemp/gists/blob/master/haskellPackage/flake.nix

{
  inputs,
  pkgs,
  ...
}: let
  packageName = "sv2v";

  inherit (pkgs.haskell.lib) overrideCabal justStaticExecutables;
  # nixpkgs' default GHC package set (binary-cached). A pinned "ghc928" stopped evaluating when the
  # flake moved to nixos-26.05, which no longer has that compiler, and broke syn_shell.
  hpkgs = pkgs.haskellPackages;

  # executableToolDepends - from "sv2v" expression in https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-unstable/pkgs/development/haskell-modules/hackage-packages.nix
  package = overrideCabal (hpkgs.callCabal2nix packageName inputs.sv2v.outPath { })
    (x: {
      executableToolDepends = (x.executableToolDepends or [ ]) ++ (
        # Add the following extra dependencies
        with pkgs; [
          alex
          happy
        ]
      );
    });

in {
  default = justStaticExecutables package;
  inherit package;
}
