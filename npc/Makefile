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
PERF    ?= 0
FFLASH  ?= 0
DIFFTEST ?= 0

# DIFFTEST=1: 自动选择对应的 NEMU REF .so 并构建
# 用户可显式指定 DIFFTEST_SO 覆盖自动选择 (e.g. make run DIFFTEST=1 DIFFTEST_SO=/path/to/ref.so)
NEMU_HOME ?= $(abspath ../nemu)
ifeq ($(DIFFTEST), 1)
  ifndef DIFFTEST_SO
    ifeq ($(SOC), 1)
      DIFFTEST_SO := $(NEMU_HOME)/build/riscv32-nemu-interpreter-ysyxsoc-so
    else
      DIFFTEST_SO := $(NEMU_HOME)/build/riscv32-nemu-interpreter-standalone-so
    endif
  endif
else
  DIFFTEST_SO ?=
endif

# FST：需要在 Verilator 阶段加 --trace-fst，并向 C++ 传宏
ifeq ($(FST), 1)
  VERILATOR_TRACE_FLAGS = --trace-fst --trace-structs
  EXTRA_CFLAGS += -DENABLE_FST
else
  VERILATOR_TRACE_FLAGS =
endif

ifeq ($(TRACE), 1)
  EXTRA_CFLAGS += -DENABLE_TRACE
  VERILATOR_FLAGS += -DENABLE_TRACE
endif

ifeq ($(PERF), 1)
  VERILATOR_FLAGS += -DENABLE_PERF
endif

ifeq ($(FFLASH), 1)
  VERILATOR_FLAGS += -DFAST_FLASH
  EXTRA_CFLAGS += -DFAST_FLASH
endif

NVBOARD ?= 0

ifeq ($(NVBOARD), 1)
  EXTRA_CFLAGS += -DENABLE_NVBOARD
  ifeq ($(SOC), 1)	
  	NXDC_FILES = constr/soc.nxdc
  else
  	NXDC_FILES = constr/standalone.nxdc
  endif
  SRC_AUTO_BIND = $(abspath $(BUILD_DIR)/auto_bind.cpp)

  $(SRC_AUTO_BIND): $(NXDC_FILES)
	python3 $(NVBOARD_HOME)/scripts/auto_pin_bind.py $^ $@

  include $(NVBOARD_HOME)/scripts/nvboard.mk

  NVBOARD_PREREQ = $(SRC_AUTO_BIND) nvboard-archive
  NVBOARD_CSRCS  = $(SRC_AUTO_BIND)
  NVBOARD_LDFLAGS = $(NVBOARD_ARCHIVE)
else
  NVBOARD_PREREQ =
  NVBOARD_CSRCS  =
  NVBOARD_LDFLAGS =
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

SOC ?= 1

# ysyxSoC paths
YSYXSOC_ROOT ?= $(YSYX_HOME)/ysyxSoC
YSYXSOC_BUILD = $(YSYXSOC_ROOT)/build
YSYXSOC_PERIP = $(YSYXSOC_ROOT)/perip

ifeq ($(SOC),1)
  # ===== SoC 模式 (riscv32-ysyxsoc): 顶层 ysyxSoCFull, csrc/, 接 SoC 外设 =====
  CSRCS_DIR := csrc
  VERILATOR_FLAGS += --top-module ysyxSoCFull -DSOC_MODE -Wno-UNOPTFLAT
  VERILATOR_FLAGS += --x-assign fast --x-initial fast \
  							--timescale "1ns/1ns" \
		    					--no-timing \
		    					-I$(YSYXSOC_PERIP)/uart16550/rtl \
		    					-I$(YSYXSOC_PERIP)/spi/rtl \
								--autoflush
  # Verilog files: ysyxSoC top + peripherals + core RTL
  VERILOG_FILES += $(YSYXSOC_BUILD)/ysyxSoCFull.v
  VERILOG_FILES += $(wildcard $(YSYXSOC_PERIP)/uart16550/rtl/*.v)
  VERILOG_FILES += $(wildcard $(YSYXSOC_PERIP)/spi/rtl/*.v)
  VERILOG_FILES += $(wildcard $(YSYXSOC_PERIP)/sdram/core_sdram_axi4/*.v)
  VERILOG_FILES += $(wildcard $(YSYXSOC_PERIP)/sdram/*.v)
  VERILOG_FILES += $(wildcard $(YSYXSOC_PERIP)/psram/efabless/*.v)
  VERILOG_FILES += $(wildcard $(YSYXSOC_PERIP)/psram/*.v)
  VERILOG_FILES += $(wildcard $(YSYXSOC_PERIP)/vga/*.v)
  VERILOG_FILES += $(wildcard $(YSYXSOC_PERIP)/ps2/*.v)
  VERILOG_FILES += $(wildcard $(YSYXSOC_PERIP)/gpio/*.v)
  VERILOG_FILES += $(wildcard $(YSYXSOC_PERIP)/flash/*.v)
  VERILOG_FILES += $(wildcard $(YSYXSOC_PERIP)/bitrev/*.v)
  VERILOG_FILES += $(wildcard $(YSYXSOC_PERIP)/amba/*.v)
  VERILOG_FILES += $(wildcard vsrc/*.v)
  TOP_CLASS := VysyxSoCFull
else
  CSRCS_DIR := csrc_standalone
  VERILATOR_FLAGS += --top-module top
  VERILATOR_FLAGS += --x-assign fast --x-initial fast \
  							--timescale "1ns/1ns" \
		    					--no-timing --autoflush
  # Verilog files: core RTL + 独立顶层 (pmem/uart 后端)
  VERILOG_FILES += $(wildcard vsrc/*.v)
  VERILOG_FILES += $(wildcard vsrc/standalone/*.v)
  TOP_CLASS := Vtop
endif

$(shell mkdir -p $(BUILD_DIR))

# 打印当前功能开关状态
show-config:
	@echo "SOC=$(SOC)  FST=$(FST)  TRACE=$(TRACE)  PERF=$(PERF)  NVBOARD=$(NVBOARD)  DIFFTEST=$(DIFFTEST)  DIFFTEST_SO=$(DIFFTEST_SO)  ELF=$(ELF)"
	@echo "TOP_CLASS=$(TOP_CLASS)  CSRCS_DIR=$(CSRCS_DIR)"
	@echo "Usage examples:"
	@echo "  === 仿真环境 (SOC 开关) ==="
	@echo "  make run SOC=1 PROG=...             # SoC 模式 (riscv32-ysyxsoc, 默认)"
	@echo "  make run SOC=0 PROG=...             # 独立 NPC 模式 (riscv32e-npc, 快速功能测试)"
	@echo "  make run-soc PROG=...               # 同上, 显式指定 SoC"
	@echo "  make run-npc PROG=...               # 同上, 显式指定独立 NPC"
	@echo "  === 功能开关 ==="
	@echo "  make build                          # 只编译 (全关, 最快)"
	@echo "  make build TRACE=1                  # 开 itrace/mtrace/ftrace"
	@echo "  make build FST=1                    # 开波形"
	@echo "  make run PROG=... DIFFTEST=1        # 开启 Difftest (自动选择对应 REF .so)"
	@echo "  make run NVBOARD=1 PROG=...         # 开 NVBoard (仅 SoC 模式)"

define VERILATE_CMD
	$(VERILATOR) $(VERILATOR_FLAGS) -cc --exe --build -j \
	$(VERILATOR_TRACE_FLAGS) \
	-CFLAGS "-std=c++14 -O3 -I$(shell pwd)/$(CSRCS_DIR) \
	  -I$(shell pwd)/../nemu/tools/capstone/repo/include \
	  -I$(shell pwd)/../nemu/include \
	  -I$(NVBOARD_HOME)/usr/include \
	  $(shell sdl2-config --cflags) \
	  $(EXTRA_CFLAGS)" \
	-LDFLAGS "-lreadline -ldl $(NVBOARD_LDFLAGS) $(shell sdl2-config --libs) -lSDL2_image -lSDL2_ttf" \
	$(CSRCS_DIR)/main.cpp $(CSRCS_DIR)/core/*.cpp $(CSRCS_DIR)/sdb/*.cpp \
	$(CSRCS_DIR)/utils/*.cpp $(CSRCS_DIR)/trace/*.cpp \
	$(NVBOARD_CSRCS) \
	$(VERILOG_FILES) \
	--Mdir $(OBJ_DIR)
endef

# 编译 char-test: 用 riscv gcc 生成 ELF, 再 objcopy 抽取代码节为 binary
char-test: test/char-test.c
	riscv64-linux-gnu-gcc -O2 -march=rv32e_zicsr -mabi=ilp32e \
	  -fno-pic -mcmodel=medany -nostdlib -nostartfiles -ffreestanding -static \
	  -Wl,-e,_start -o test/char-test.elf test/char-test.c
	riscv64-linux-gnu-objcopy -O binary -j .text -j .text.startup -j .rodata \
	  test/char-test.elf test/char-test.bin
	@echo "Built test/char-test.bin"

# 只编译不运行
build: $(NVBOARD_PREREQ) $(if $(filter 1,$(DIFFTEST)),$(DIFFTEST_SO))
	$(call git_commit, "sim RTL") # DO NOT REMOVE THIS LINE!!!
	@echo "-- VERILATE & BUILD [SOC=$(SOC) FST=$(FST) TRACE=$(TRACE) PERF=$(PERF) DIFFTEST=$(DIFFTEST)] --------"
	@mkdir -p $(WAVE_DIR)
	$(VERILATE_CMD)
	@echo "-- BUILD DONE --------------"

# 编译并运行 (默认使用当前 SOC 设置)
run: $(NVBOARD_PREREQ) $(if $(filter 1,$(DIFFTEST)),$(DIFFTEST_SO))
	$(call git_commit, "sim RTL") # DO NOT REMOVE THIS LINE!!!
	@echo "-- VERILATE & BUILD [SOC=$(SOC) FST=$(FST) TRACE=$(TRACE) PERF=$(PERF) DIFFTEST=$(DIFFTEST)] --------"
	@mkdir -p $(WAVE_DIR)
	$(VERILATE_CMD)
	@echo "-- BUILD DONE --------------"
	@if [ ! -f $(OBJ_DIR)/$(TOP_CLASS) ]; then \
		echo "Error: $(TOP_CLASS) not found after build."; exit 1; \
	fi
	@if [ ! -f "$(PROG)" ]; then \
		echo "Error: Program file '$(PROG)' not found."; exit 1; \
	fi
	@echo "-- RUN [SOC=$(SOC) DIFFTEST=$(if $(filter 1,$(DIFFTEST)),ON,OFF)] -----------"
	@echo "Running: $(OBJ_DIR)/$(TOP_CLASS) $(PROG) $(ELF_ARG) $(DIFFTEST_ARG) $(BATCH)"
	@$(OBJ_DIR)/$(TOP_CLASS) $(PROG) $(ELF_ARG) $(DIFFTEST_ARG) $(BATCH)
	@echo "-- DONE --------------------"

run-soc:
	$(MAKE) run SOC=1

run-npc:
	$(MAKE) run SOC=0

build-soc:
	$(MAKE) build SOC=1

build-npc:
	$(MAKE) build SOC=0

# 构建 NEMU REF .so (供 difftest 使用)
difftest-so:
	$(MAKE) -C $(NEMU_HOME) difftest-so

# 显式规则: 触发 NEMU 构建对应的 .so
$(NEMU_HOME)/build/riscv32-nemu-interpreter-standalone-so:
	$(MAKE) -C $(NEMU_HOME) difftest-so-standalone

$(NEMU_HOME)/build/riscv32-nemu-interpreter-ysyxsoc-so:
	$(MAKE) -C $(NEMU_HOME) difftest-so-ysyxsoc

.PHONY: build sim run run-soc run-npc build-soc build-npc clean char-test difftest-so
