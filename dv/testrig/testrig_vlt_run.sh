#!/usr/bin/env bash
# TestRIG Verilator RUN script: the Verilator counterpart of testrig_xlm_run.sh, running the
# binary built by testrig_vlt_build.sh (inside `nix develop .#vlt_shell`).
#
# Usage:
#   Call this script from the directory it is stored in, after testrig_vlt_build.sh. The
#   simulation listens for a vengine (QuickCheckVEngine --single-implementation) on +dii_port
#   (default 6000) and checks every retired instruction against the selected Sail model.
#
#   -t <flavour>  cheriot (default) or riscv: selects the sequencer and scoreboard overrides
#   -v            high UVM verbosity
#   Anything after the options (e.g. +dii_port=6001 +dii_sb_corrupt=5) is passed to the binary.
#   No coverage or waveform options: the Verilator build collects neither.

set -euo pipefail

flavour="cheriot"
verbosity_arg="+UVM_VERBOSITY=UVM_LOW"

while getopts "t:v" opt; do
  case $opt in
      t) flavour="$OPTARG" ;;
      v) verbosity_arg="+UVM_VERBOSITY=UVM_HIGH" ;;
      *) exit 1 ;;
   esac
done
shift $((OPTIND - 1))

case "$flavour" in
  cheriot|riscv) ;;
  *) echo "Unknown flavour '$flavour' (expected cheriot or riscv)" >&2; exit 1 ;;
esac

# The build records the ibex_configs.yaml configuration it was built for. A build from before the
# parameters came from ibex_configs.yaml has no record, and one built for another configuration
# than $IBEX_CONFIG (default opentitan) is the wrong core: refuse both rather than run them.
want_cfg="${IBEX_CONFIG:-opentitan}"
have_cfg=$(cat vlt_testrig_out/.ibex_config 2>/dev/null || true)
if [[ "${have_cfg}" != "${want_cfg}" ]]; then
  echo "ERROR: vlt_testrig_out was built for configuration '${have_cfg:-unknown}', not '${want_cfg}':" \
       "rebuild with ./testrig_vlt_build.sh (or REBUILD=1)" >&2
  exit 1
fi

# The Sail DPI libraries, located from this checkout rather than the build's rpath, so the binary
# runs wherever the checkout lives.
PRJ_DIR=$(realpath ../../)
export LD_LIBRARY_PATH="${PRJ_DIR}/dv/cosim/cheriot_sail:${PRJ_DIR}/dv/cosim/riscv_sail${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

./vlt_testrig_out/obj/Vtestrig_tb \
  +UVM_TESTNAME=core_ibex_testrig_test \
  +uvm_set_type_override=ibex_dii_sequencer,ibex_dii_${flavour}_sequencer \
  +uvm_set_type_override=ibex_dii_scoreboard,ibex_dii_${flavour}_sail_scoreboard \
  ${verbosity_arg} \
  "$@" 2>&1 | tee vlt_testrig_out/run.log
