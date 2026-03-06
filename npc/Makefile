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
	-rm -rf $(OBJ_DIR) *.log *.dmp *.vpd core $(WAVE_DIR)
	
all:
	@echo "Write this Makefile by your self."
	
WAVE_DIR = wave
WAVE_FILE = $(WAVE_DIR)/dump.fst

# 默认程序和halt地址
PROG ?= test/mem.bin
HALT ?= 0x1220

sim:
	$(call git_commit, "sim RTL") # DO NOT REMOVE THIS LINE!!!
	@echo "-- VERILATE & BUILD --------"
	@mkdir -p $(WAVE_DIR)
	$(VERILATOR) --top-module top -cc --exe \
	--build -j --trace-fst --trace-structs \
	-CFLAGS "-std=c++14" vsrc/*.v csrc/main.cpp \
	--Mdir $(OBJ_DIR)
	@echo "-- RUN ---------------------"
	@echo "Running: $(OBJ_DIR)/Vtop $(PROG) $(HALT)"
	$(OBJ_DIR)/Vtop $(PROG) $(HALT)
	@echo "-- OPEN WAVEFORM ------------"
	gtkwave $(WAVE_FILE) > /dev/null 2>&1 &
	@echo "-- DONE --------------------"

# 只编译不运行
build:
	$(call git_commit, "sim RTL") # DO NOT REMOVE THIS LINE!!!
	@echo "-- VERILATE & BUILD --------"
	@mkdir -p $(WAVE_DIR)
	$(VERILATOR) --top-module top -cc --exe --build -j --trace-fst --trace-structs -CFLAGS "-std=c++14" vsrc/*.v csrc/main.cpp
	@echo "-- BUILD DONE --------------"

# 只运行（需要先build）
run:
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
	@$(OBJ_DIR)/Vtop $(PROG)
	@echo "-- DONE --------------------"



TOPNAME = top
NXDC_FILES = constr/top.nxdc
INC_PATH ?=

VERILATOR_CFLAGS += -MMD --build -cc  \
				-O3 --x-assign fast --x-initial fast --noassert

BUILD_DIR = ./build
OBJ_DIR = $(BUILD_DIR)/obj_dir
BIN = $(BUILD_DIR)/$(TOPNAME)

$(shell mkdir -p $(BUILD_DIR))

# constraint file
SRC_AUTO_BIND = $(abspath $(BUILD_DIR)/auto_bind.cpp)
$(SRC_AUTO_BIND): $(NXDC_FILES)
	python3 $(NVBOARD_HOME)/scripts/auto_pin_bind.py $^ $@

# project source
VSRCS = $(shell find $(abspath ./vsrc) -name "*.v")
CSRCS = $(shell find $(abspath ./csrc) -name "*.c" -or -name "*.cc" -or -name "*.cpp")
CSRCS += $(SRC_AUTO_BIND)

# rules for NVBoard
include $(NVBOARD_HOME)/scripts/nvboard.mk

# rules for verilator
INCFLAGS = $(addprefix -I, $(INC_PATH))
CXXFLAGS += $(INCFLAGS) -DTOP_NAME="\"V$(TOPNAME)\""

$(BIN): $(VSRCS) $(CSRCS) $(NVBOARD_ARCHIVE)
	@rm -rf $(OBJ_DIR)
	$(VERILATOR) $(VERILATOR_CFLAGS) \
		--top-module $(TOPNAME) $^ \
		$(addprefix -CFLAGS , $(CXXFLAGS)) $(addprefix -LDFLAGS , $(LDFLAGS)) \
		--Mdir $(OBJ_DIR) --exe -o $(abspath $(BIN))

# run: $(BIN)
# 	@$^
