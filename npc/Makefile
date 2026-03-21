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

FST     ?= 0
TRACE   ?= 0
DIFFTEST_SO ?=

# FST：需要在 Verilator 阶段加 --trace-fst，并向 C++ 传宏
ifeq ($(FST), 1)
  VERILATOR_TRACE_FLAGS = --trace-fst --trace-structs
  EXTRA_CFLAGS += -DENABLE_FST
else
  VERILATOR_TRACE_FLAGS =
endif

# Trace：只需向 C++ 传宏
ifeq ($(TRACE), 1)
  EXTRA_CFLAGS += -DENABLE_TRACE
endif

# DiffTest：非空则拼成 -d <path> 传给可执行文件
ifneq ($(DIFFTEST_SO),)
  DIFFTEST_ARG = -d $(DIFFTEST_SO)
else
  DIFFTEST_ARG =
endif

# ELF：非空则拼成 -e <path> 传给可执行文件（ftrace 需要）
ifneq ($(ELF),)
  ELF_ARG = -e $(ELF)
else
  ELF_ARG =
endif

PROG  ?= test/mem.bin
ELF   ?=
BATCH ?= -b
CXXFLAGS += -O3 -march=native
VERILATOR_FLAGS += --x-assign fast --x-initial fast

$(shell mkdir -p $(BUILD_DIR))

# 打印当前功能开关状态
show-config:
	@echo "FST=$(FST)  TRACE=$(TRACE)  DIFFTEST_SO=$(DIFFTEST_SO)  ELF=$(ELF)"
	@echo "Usage examples:"
	@echo "  make build                          # 全关（最快）"
	@echo "  make build TRACE=1                  # 开 trace"
	@echo "  make build FST=1                    # 开波形"
	@echo "  make build FST=1 TRACE=1            # 全开"
	@echo "  make run PROG=x.bin                 # 不带 ftrace/difftest 运行"
	@echo "  make run PROG=x.bin ELF=x.elf TRACE=1  # 开 ftrace"
	@echo "  make run PROG=x.bin DIFFTEST_SO=../nemu/build/riscv32-nemu-interpreter-so"

define VERILATE_CMD
	$(VERILATOR) --top-module top -cc --exe --build -j \
	$(VERILATOR_TRACE_FLAGS) \
	-CFLAGS "-std=c++14 -O3 -I$(shell pwd)/csrc \
	  -I$(shell pwd)/../nemu/tools/capstone/repo/include \
	  -I$(shell pwd)/../nemu/include \
	  $(shell sdl2-config --cflags) \
	  $(EXTRA_CFLAGS)" \
	-LDFLAGS "-lreadline -ldl $(shell sdl2-config --libs)" \
	vsrc/*.v csrc/main.cpp csrc/core/*.cpp csrc/sdb/*.cpp \
	csrc/utils/*.cpp csrc/trace/*.cpp \
	--Mdir $(OBJ_DIR)
endef

# 只编译不运行
build:
	$(call git_commit, "sim RTL") # DO NOT REMOVE THIS LINE!!!
	@echo "-- VERILATE & BUILD [FST=$(FST) TRACE=$(TRACE)] --------"
	@mkdir -p $(WAVE_DIR)
	$(VERILATE_CMD)
	@echo "-- BUILD DONE --------------"

# 编译并运行
run:
	$(call git_commit, "sim RTL") # DO NOT REMOVE THIS LINE!!!
	@echo "-- VERILATE & BUILD [FST=$(FST) TRACE=$(TRACE)] --------"
	@mkdir -p $(WAVE_DIR)
	$(VERILATE_CMD)
	@echo "-- BUILD DONE --------------"
	@if [ ! -f $(OBJ_DIR)/Vtop ]; then \
		echo "Error: Vtop not found after build."; exit 1; \
	fi
	@if [ ! -f "$(PROG)" ]; then \
		echo "Error: Program file '$(PROG)' not found."; exit 1; \
	fi
	@echo "-- RUN [DIFFTEST=$(if $(DIFFTEST_SO),ON,OFF)] -----------"
	@echo "Running: $(OBJ_DIR)/Vtop $(PROG) $(ELF_ARG) $(DIFFTEST_ARG) $(BATCH)"
	@$(OBJ_DIR)/Vtop $(PROG) $(ELF_ARG) $(DIFFTEST_ARG) $(BATCH)
	@echo "-- DONE --------------------"

.PHONY: build sim run clean