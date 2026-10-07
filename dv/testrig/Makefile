# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# TestRIG UVM testbench: build and run the bench by hand. See README.md.
#
# This Makefile drives one simulator process. It does not start QuickCheckVEngine, keep results,
# or check the verdict: in the ibex_cheriot_verification checkout, the root Makefile's testrig-*
# targets (run_all_tests.sh) do that and are the supported way to run TestRIG.
#
#   make build-xlm [COV=1]                     Xcelium build (elaborate only)
#   make run-xlm   [FLAVOUR=..] [COV=1] [WAVES=1|GUI=1] [PLUSARGS=..]
#   make build-vlt                             Verilator build (inside nix develop .#vlt_shell)
#   make run-vlt   [FLAVOUR=..] [PLUSARGS=..]
#   make vengine   [FLAVOUR=..] [N=..] [PORT=..]   QuickCheckVEngine against a running sim
#   make sail-libs                             Build the two Sail DPI libraries the bench links
#   make clean

FLAVOUR  ?= cheriot
COV      ?= 0
WAVES    ?= 0
GUI      ?= 0
VERBOSE  ?= 0
PORT     ?= 6000
N        ?=
PLUSARGS ?=
QCVENGINE ?= QCVEngine

PRJ_DIR := $(realpath $(CURDIR)/../..)

ifeq ($(FLAVOUR),cheriot)
  ARCH := rv32emcZifencei_Xcheriot
else ifeq ($(FLAVOUR),riscv)
  ARCH := rv32emcZifencei
else
  $(error FLAVOUR must be cheriot or riscv, not '$(FLAVOUR)')
endif

_xlm_build_args := $(if $(filter 1,$(COV)),-c)
_xlm_run_args   := -t $(FLAVOUR) $(if $(filter 1,$(COV)),-c) $(if $(filter 1,$(VERBOSE)),-v) \
                   $(if $(filter 1,$(GUI)),-g,$(if $(filter 1,$(WAVES)),-w))
_vlt_run_args   := -t $(FLAVOUR) $(if $(filter 1,$(VERBOSE)),-v)
_port_arg       := $(if $(filter-out 6000,$(PORT)),+dii_port=$(PORT))

.PHONY: help build-xlm run-xlm build-vlt run-vlt vengine sail-libs clean

help:
	@sed -n '/^#   make/p' $(firstword $(MAKEFILE_LIST)) | sed 's/^#   //'

build-xlm:
	./testrig_xlm_build.sh $(_xlm_build_args)
	@test -d xlm_testrig_out/xcelium.d/worklib || \
	  { echo "ERROR: xrun exited but wrote no snapshot; see xlm_testrig_out/build.log" >&2; exit 1; }

run-xlm:
	./testrig_xlm_run.sh $(_xlm_run_args) $(_port_arg) $(PLUSARGS)

build-vlt:
	./testrig_vlt_build.sh

run-vlt:
	./testrig_vlt_run.sh $(_vlt_run_args) $(_port_arg) $(PLUSARGS)

# Same QuickCheckVEngine options as run_all_tests.sh, minus the saved-failure directory.
vengine:
	$(QCVENGINE) -a $(PORT) --single-implementation -r $(ARCH) \
	  -x 'interrupt|unstructured' --force-RVFI-v1 $(if $(N),-n $(N))

sail-libs:
	$(MAKE) -C $(PRJ_DIR)/dv/cosim/cheriot_sail
	$(MAKE) -C $(PRJ_DIR)/dv/cosim/riscv_sail

clean:
	rm -rf xlm_testrig_out vlt_testrig_out cov_work
