#!/usr/bin/env bash
# Run python3 with what dvsim's testplanner needs (hjson, tabulate, mistletoe): the eda_shell's own
# python (the ibex UVM env has all three) when it is on PATH, otherwise a throwaway nix one.
if python3 -c 'import hjson, tabulate, mistletoe' 2>/dev/null; then
  exec python3 "$@"
fi
exec nix shell --impure --expr \
  '(builtins.getFlake "nixpkgs").legacyPackages.${builtins.currentSystem}.python3.withPackages (p: [p.hjson p.tabulate p.mistletoe])' \
  --command python3 "$@"
