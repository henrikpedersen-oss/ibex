# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Builds libriscvsail_rvfi.so: the RISC-V (non-CHERI) Sail model in RVFI-DII mode plus its DPI
# bridge, for the ibex_dii_riscv_sail_scoreboard. Needs gcc, gmp and zlib (the root Makefile's
# build-riscvsail-lib provides them).
#
# Everything is compiled with -fvisibility=hidden and only the riscv_sail_cosim_* DPI functions
# are exported, so this library's Sail symbols (z*, model_init, write_mem, rv_*) never clash
# with libcheriotsail_rvfi.so's when both are linked into one simulation.

RISCV_SAIL_DIR ?= $(abspath $(CURDIR)/../riscv-sail-model)
SAIL_LIB_DIR   ?= $(abspath $(CURDIR)/../sail-0.19.1-runtime)
GEN_C_DIR      := $(RISCV_SAIL_DIR)/generated_definitions/c
EMU_DIR        := $(RISCV_SAIL_DIR)/c_emulator
SOFTFLOAT_DIR  := $(EMU_DIR)/SoftFloat-3e
SOFTFLOAT_BLD  := $(SOFTFLOAT_DIR)/build/Linux-RISCV-GCC
SOFTFLOAT_LIB  := $(SOFTFLOAT_BLD)/softfloat.a

MODEL_C := $(GEN_C_DIR)/riscv_rvfi_model_RV32.c
SAIL_RUNTIME_SRCS := $(addprefix $(SAIL_LIB_DIR)/,sail.c rts.c elf.c sail_failure.c)
PLATFORM_SRCS := $(addprefix $(EMU_DIR)/,riscv_prelude.c riscv_platform_impl.c riscv_platform.c \
                   riscv_softfloat.c)
DPI_SRCS := riscv_sail_cosim_dpi.cc

ALL_SRCS := $(MODEL_C) $(PLATFORM_SRCS) $(SAIL_RUNTIME_SRCS) $(DPI_SRCS)

CC     := gcc
CXX    := g++
CFLAGS := -O2 -fPIC -fvisibility=hidden \
    -DRVFI_DII \
    -I$(SAIL_LIB_DIR) \
    -I$(EMU_DIR) \
    -I$(GEN_C_DIR) \
    -I$(SOFTFLOAT_DIR)/source/include \
    $(shell pkg-config --cflags gmp) \
    $(shell pkg-config --cflags zlib)
CXXFLAGS := $(CFLAGS) -std=c++14

LDFLAGS := -shared -Wl,-Bsymbolic \
    $(shell pkg-config --libs gmp) \
    $(shell pkg-config --libs zlib) \
    -lpthread -ldl -lstdc++

OUT := libriscvsail_rvfi.so

.PHONY: all clean check-model-c model-c-stamp

all: $(OUT)

# The model C is generated from the model's .sail sources, but not by this build: only when it is
# missing. A .sail change without the matching C change would never reach the library (as on
# 2026-10-03, riscv_fetch_rvfi.sail), so refuse to build in that state rather than use stale C.
# The check compares the .sail sources with MODEL_SAIL_STAMP, their hashes as of the last time
# MODEL_C was brought up to date. A timestamp check (.sail newer than MODEL_C) failed on every
# fresh checkout, where file times are checkout order. After applying a .sail change to MODEL_C
# as well, record that with 'make model-c-stamp' and commit the stamp with both.
MODEL_SAIL_STAMP := $(CURDIR)/model_sail.sha256
MODEL_SAIL_HASHES = cd $(RISCV_SAIL_DIR) && find model -name '*.sail' | LC_ALL=C sort | xargs sha256sum

check-model-c:
	@cur="$$( $(MODEL_SAIL_HASHES) )"; \
	if [ "$$cur" != "$$(cat $(MODEL_SAIL_STAMP) 2>/dev/null)" ]; then \
	  echo "ERROR: model .sail sources differ from $(MODEL_SAIL_STAMP), the state $(MODEL_C)" >&2; \
	  echo "  was last brought up to date with; apply the change to it, then 'make model-c-stamp':" >&2; \
	  echo "$$cur" | diff $(MODEL_SAIL_STAMP) - | sed -n 's/^[<>] [0-9a-f]*  /  /p' | sort -u >&2; \
	  exit 1; \
	fi

model-c-stamp:
	( $(MODEL_SAIL_HASHES) ) > $(MODEL_SAIL_STAMP)

$(MODEL_C):
	$(MAKE) -C $(RISCV_SAIL_DIR) generated_definitions/c/riscv_rvfi_model_RV32.c

$(SOFTFLOAT_LIB):
	$(MAKE) -C $(SOFTFLOAT_BLD) SOFTFLOAT_OPTS="-DSOFTFLOAT_ROUND_ODD -fPIC -fvisibility=hidden"

BUILD_DIR := build

C_OBJS   := $(patsubst %.c,$(BUILD_DIR)/%.o,$(notdir $(filter %.c,$(ALL_SRCS))))
CXX_OBJS := $(patsubst %.cc,$(BUILD_DIR)/%.o,$(notdir $(filter %.cc,$(ALL_SRCS))))

$(BUILD_DIR):
	mkdir -p $@

define c_rule
$(BUILD_DIR)/$(notdir $(patsubst %.c,%.o,$(1))): $(1) | $(BUILD_DIR)
	$$(CC) $$(CFLAGS) -c $$< -o $$@
endef

define cxx_rule
$(BUILD_DIR)/$(notdir $(patsubst %.cc,%.o,$(1))): $(1) riscv_sail_cosim_dpi.h | $(BUILD_DIR)
	$$(CXX) $$(CXXFLAGS) -c $$< -o $$@
endef

$(foreach src,$(filter %.c,$(ALL_SRCS)),$(eval $(call c_rule,$(src))))
$(foreach src,$(filter %.cc,$(ALL_SRCS)),$(eval $(call cxx_rule,$(src))))

$(OUT): $(C_OBJS) $(CXX_OBJS) $(SOFTFLOAT_LIB) | check-model-c
	$(CXX) $(C_OBJS) $(CXX_OBJS) $(SOFTFLOAT_LIB) $(LDFLAGS) -o $@
	@echo "Built: $@"
	@test "$$(nm -D --defined-only $@ | grep -c ' T z')" = 0 || \
	  { echo "ERROR: $@ exports Sail model symbols; they would clash with the CHERIoT model" >&2; exit 1; }
	@nm -D --defined-only $@ | grep -q ' T riscv_sail_cosim_step$$' || \
	  { echo "ERROR: $@ does not export riscv_sail_cosim_step" >&2; exit 1; }

clean:
	rm -rf $(OUT) $(BUILD_DIR)
	-$(MAKE) -C $(SOFTFLOAT_BLD) clean
