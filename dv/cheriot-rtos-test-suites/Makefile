# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# CHERIoT RTOS test SoC: build and run the testbench by hand. See README.md.
#
# This Makefile drives one simulator process. It does not build firmware, keep results or check
# the verdict: in the ibex_cheriot_verification checkout, the root Makefile's sonata-*-xlm targets
# (run_all_tests.sh) do that and are the supported way to run the suites.
#
#   make build [COV=1]                        Xcelium build (elaborate only)
#   make run   ELF=<firmware> [BOOT=<stub>] [COV=1] [GUI=1] [MAX_CYCLES=<n>] [MUTATE=<name>] [PLUSARGS=..]
#   make lint                                 Verilator lint of the testbench (inside nix develop .#vlt_shell)
#   make clean

COV        ?= 0
GUI        ?= 0
ELF        ?=
BOOT       ?=
MAX_CYCLES ?=
MUTATE     ?=
PLUSARGS   ?=

OUT_DIR := xlm_rtos_out
PRJ_DIR := $(realpath $(CURDIR)/../..)
SUPER_DIR := $(realpath $(PRJ_DIR)/..)

_build_args := $(if $(filter 1,$(COV)),-c)
_run_args   := $(if $(filter 1,$(COV)),-c) $(if $(filter 1,$(GUI)),-g)
_run_env    := SONATA_TEST_ELF=$(ELF) $(if $(BOOT),SONATA_BOOT_STUB=$(BOOT)) \
               $(if $(MAX_CYCLES),SONATA_MAX_CYCLES=$(MAX_CYCLES)) $(if $(MUTATE),SONATA_MUTATE=$(MUTATE))

# Same environment the build script exports for the filelist.
_lint_env := RTOS_TB_DIR=$(CURDIR) IBEX_ROOT_DIR=$(PRJ_DIR) \
             OT_CHERIOT_DIR=$(or $(OT_CHERIOT_DIR),$(SUPER_DIR)/opentitan-cheriot)

.PHONY: help build run lint clean

help:
	@sed -n '/^#   make/p' $(firstword $(MAKEFILE_LIST)) | sed 's/^#   //'

build:
	./cheriot_rtos_xlm_build.sh $(_build_args)
	@test -d $(OUT_DIR)/xcelium.d/worklib || \
	  { echo "ERROR: xrun exited but wrote no snapshot; see $(OUT_DIR)/build.log" >&2; exit 1; }

run:
	@test -n "$(ELF)" || { echo "Usage: make run ELF=<firmware ELF> [BOOT=<sim_boot_stub>] ..." >&2; exit 1; }
	$(_run_env) ./cheriot_rtos_xlm_run.sh $(_run_args) -- $(PLUSARGS)

# --timing for the testbench's delays.
lint:
	$(_lint_env) verilator --lint-only --timing -Wno-fatal \
	  -DRVFI -DPRIM_DEFAULT_IMPL=prim_pkg::ImplGeneric \
	  --top-module cheriot_rtos_tb -f cheriot_rtos_dv.f

clean:
	rm -rf $(OUT_DIR) cov_work
