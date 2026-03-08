######################################################################
#
# DESCRIPTION: Verilator Example: Small Makefile
#
# This calls the object directory makefile.  That allows the objects to
# be placed in the "current directory" which simplifies the Makefile.
#
# This file ONLY is placed under the Creative Commons Public Domain, for
# any use, without warranty, 2020 by Wilson Snyder.
# SPDX-License-Identifier: CC0-1.0
#
######################################################################
# Check for sanity to avoid later confusion

	
include ../Makefile

ifneq ($(words $(CURDIR)),1)
  $(error Unsupported: GNU Make cannot build in directories containing spaces, build elsewhere: '$(CURDIR)')
endif

######################################################################

# This is intended to be a minimal example.  Before copying this to start a
# real project, it is better to start with a more complete example,
# e.g. examples/make_tracing_c.

# If $VERILATOR_ROOT isn't in the environment, we assume it is part of a
# package install, and verilator is in your path. Otherwise find the
# binary relative to $VERILATOR_ROOT (such as when inside the git sources).
ifeq ($(VERILATOR_ROOT),)
  VERILATOR = verilator
else
  export VERILATOR_ROOT
  VERILATOR = $(VERILATOR_ROOT)/bin/verilator
endif

#default:
#	@echo "-- Verilator hello-world simple example"
#	@echo "-- VERILATE & BUILD --------"
#	$(VERILATOR) -cc --exe --build -j top.v sim_main.cpp
#	@echo "-- RUN ---------------------"
#	obj_dir/Vtop
#	@echo "-- DONE --------------------"
#	@echo "Note: Once this example is understood, see examples/make_tracing_c."
#	@echo "Note: See also https://verilator.org/guide/latest/examples.html"

######################################################################

maintainer-copy::
clean mostlyclean distclean maintainer-clean::
	-rm -rf $(OBJ_DIR) *.log *.dmp *.vpd core $(WAVE_DIR) ./build
	
all:
	@echo "Write this Makefile by your self."
	
WAVE_DIR = wave
WAVE_FILE = $(WAVE_DIR)/dump.fst

BUILD_DIR = ./build
OBJ_DIR = $(BUILD_DIR)/obj_dir

# 默认程序和halt地址
PROG ?= test/mem.bin
HALT ?= 0x1220
DIFFTEST ?= -d ../nemu/build/riscv32-nemu-interpreter-so
CXXFLAGS += -O3 -march=native
VERILATOR_FLAGS += --x-assign fast --x-initial fast

$(shell mkdir -p $(BUILD_DIR))

# 只编译不运行
build:
	$(call git_commit, "sim RTL") # DO NOT REMOVE THIS LINE!!!
	@echo "-- VERILATE & BUILD --------"
	@mkdir -p $(WAVE_DIR)
	$(VERILATOR) --top-module top -cc --exe --build -j --trace-fst --trace-structs \
	-CFLAGS "-std=c++14 -I$(shell pwd)/csrc -I$(shell pwd)/../nemu/tools/capstone/repo/include -I$(shell pwd)/../nemu/include" \
	-LDFLAGS "-lreadline -ldl" \
	vsrc/*.v csrc/main.cpp csrc/core/*.cpp csrc/sdb/*.cpp csrc/utils/*.cpp csrc/trace/*.cpp \
	--Mdir $(OBJ_DIR)
	@echo "-- BUILD DONE --------------"

# 编译运行
run:
	$(call git_commit, "sim RTL") # DO NOT REMOVE THIS LINE!!!
	@echo "-- VERILATE & BUILD --------"
	@mkdir -p $(WAVE_DIR)
	$(VERILATOR) --top-module top -cc --exe --build -j --trace-fst --trace-structs \
	-CFLAGS "-std=c++14 -I$(shell pwd)/csrc -I$(shell pwd)/../nemu/tools/capstone/repo/include -I$(shell pwd)/../nemu/include" \
	-LDFLAGS "-lreadline -ldl" \
	vsrc/*.v csrc/main.cpp csrc/core/*.cpp csrc/sdb/*.cpp csrc/utils/*.cpp csrc/trace/*.cpp \
	--Mdir $(OBJ_DIR)
	@echo "-- BUILD DONE --------------"
	@if [ ! -f $(OBJ_DIR)/Vtop ]; then \
		echo "Error: NPC not built. Please run 'make build' first."; \
		exit 1; \
	fi
	@if [ -z "$(PROG)" ]; then \
		echo "Error: PROG not specified. Usage: make run PROG=<program.bin>"; \
		exit 1; \
	fi
	@if [ ! -f "$(PROG)" ]; then \
		echo "Error: Program file '$(PROG)' not found."; \
		exit 1; \
	fi
	@echo "-- RUN ---------------------"
	@echo "Running: $(OBJ_DIR)/Vtop $(PROG)"
	@$(OBJ_DIR)/Vtop $(PROG) $(DIFFTEST)
	@echo "-- DONE --------------------"

.PHONY: build sim run clean