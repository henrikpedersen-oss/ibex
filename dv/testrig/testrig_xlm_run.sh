#!/usr/bin/env bash

# TestRIG Xcelium RUN script
#
# Usage:
#   Call this script from the directory it is stored in, after testrig_xlm_build.sh. The
#   simulation listens for a vengine (QuickCheckVEngine --single-implementation) on +dii_port
#   (default 6000) and checks every retired instruction against the selected Sail model.
#
#   -t <flavour>  cheriot (default) or riscv: selects the sequencer and scoreboard overrides
#   -c            coverage collection
#   -w            waveform capture
#   -g            waveform capture with the GUI
#   -v            high UVM verbosity
#   Anything after the options (e.g. +dii_port=6001 +dii_sb_corrupt=5) is passed to xrun.

datetime=$(date +%F_%H%M.%S)

flavour="cheriot"
coverage_arg=""
verbosity_arg="+UVM_VERBOSITY=UVM_LOW"
wave_arg=""
gui_arg=""

while getopts "t:cvwg" opt; do
  case $opt in
      t) flavour="$OPTARG" ;;
      c) coverage_arg="\
  -covmodeldir xlm_testrig_out/coverage \
  -covworkdir xlm_testrig_out \
  -covscope coverage \
  -covtest ${datetime} \
  +enable_ibex_fcov=1" ;;
      v) verbosity_arg="+UVM_VERBOSITY=UVM_HIGH" ;;
      w) wave_arg="-input waves.tcl" ;;
      g) wave_arg="-input waves.tcl"; gui_arg="-gui" ;;
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
have_cfg=$(cat xlm_testrig_out/.ibex_config 2>/dev/null || true)
if [[ "${have_cfg}" != "${want_cfg}" ]]; then
  echo "ERROR: xlm_testrig_out was built for configuration '${have_cfg:-unknown}', not '${want_cfg}':" \
       "rebuild with ./testrig_xlm_build.sh (or REBUILD=1)" >&2
  exit 1
fi

# Name the coverage run after its flavour, so a merge can tell CHERIoT-mode runs from RISC-V-mode
# ones. Done after option parsing: -t may follow -c.
coverage_arg="${coverage_arg/-covtest ${datetime}/-covtest ${flavour}_${datetime}}"
# Without -c, a snapshot built with coverage still writes a database -- to the default
# ./cov_work/scope/test, which the next such run refuses to overwrite (*F,C58EXS): on 2026-09-30
# seven of the eight COVERAGE=0 fault-injection runs died that way within a second of starting.
# Route it to a scratch directory instead, as ../cheriot-rtos-test-suites/cheriot_rtos_xlm_run.sh does.
if [[ -z "${coverage_arg}" ]]; then
  cov_scratch=$(mktemp -d /tmp/testrig_xlm_cov_XXXXXX)
  trap 'rm -rf "${cov_scratch}"' EXIT
  coverage_arg="-covworkdir ${cov_scratch} -covtest t"
fi
flavour_args="\
  +uvm_set_type_override=ibex_dii_sequencer,ibex_dii_${flavour}_sequencer \
  +uvm_set_type_override=ibex_dii_scoreboard,ibex_dii_${flavour}_sail_scoreboard"

# Run Xcelium (which will wait for a connection from TestRIG)
xrun \
  -64bit \
  -R \
  -l xlm_testrig_out/run.log \
  -xmlibdirname xlm_testrig_out/xcelium.d \
  +UVM_TESTNAME=core_ibex_testrig_test \
  -licqueue \
  $flavour_args \
  $coverage_arg \
  $wave_arg \
  $gui_arg \
  $verbosity_arg \
  "$@"
