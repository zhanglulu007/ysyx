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

# NVBoard：接入 NVBoard 可视化板卡.
# 开启后, 仿真循环将把 ysyxSoCFull 的 GPIO 引脚绑定到 NVBoard 的 LED/拨码开关,
# 并在每次取指循环中调用 nvboard_update() 刷新板卡显示.
# 需要设置环境变量 NVBOARD_HOME 指向 nvboard 项目目录.
NVBOARD ?= 0
ifeq ($(NVBOARD), 1)
  NVBOARD_HOME ?= $(YSYX_HOME)/nvboard
  include $(NVBOARD_HOME)/scripts/nvboard.mk
  # 注意: nvboard 有两个同名 nvboard.h:
  #   $(NVBOARD_INC)      = nvboard/include       (内部实现头文件, 含 SDL/component)
  #   $(NVBOARD_USR_INC)  = nvboard/usr/include   (用户头文件, 声明 nvboard_init/bind/update)
  # 仿真代码 #include <nvboard.h> 期望解析到用户头文件, 故用户路径必须排在前面.
  EXTRA_CFLAGS += -DENABLE_NVBOARD -I$(NVBOARD_USR_INC) -I$(NVBOARD_INC)
  NVBOARD_NXDC ?= $(CURDIR)/constr/top.nxdc
  SRC_AUTO_BIND = $(abspath $(BUILD_DIR)/auto_bind.cpp)
  $(SRC_AUTO_BIND): $(NVBOARD_NXDC)
	python3 $(NVBOARD_HOME)/scripts/auto_pin_bind.py $^ $@
  NVBOARD_EXTRA_CSRCS = $(SRC_AUTO_BIND)
  NVBOARD_CXXSRC_FLAGS = $(NVBOARD_ARCHIVE)
  # NVBoard 依赖 SDL2_image / SDL2_ttf, 在链接时需要加上
  NVBOARD_LDFLAGS = -lSDL2_image -lSDL2_ttf
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

# ysyxSoC paths
YSYXSOC_ROOT ?= $(YSYX_HOME)/ysyxSoC
YSYXSOC_BUILD = $(YSYXSOC_ROOT)/build
YSYXSOC_PERIP = $(YSYXSOC_ROOT)/perip

VERILATOR_FLAGS += --top-module ysyxSoCFull
VERILATOR_FLAGS += --x-assign fast --x-initial fast \
						--timescale "1ns/1ns" \
    					--no-timing \
    					-I$(YSYXSOC_PERIP)/uart16550/rtl \
    					-I$(YSYXSOC_PERIP)/spi/rtl \
						--autoflush
#VERILATOR_FLAGS += -Wno-UNOPTTHREADS --threads 2
#VERILATOR_FLAGS += -DFAST_FLASH

# Verilog files: ysyxSoC top + peripherals
VERILOG_FILES += \
    				$(YSYXSOC_BUILD)/ysyxSoCFull.v

# Add ysyxSoC peripheral verilog files (use wildcard to expand)
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

$(shell mkdir -p $(BUILD_DIR))

# 打印当前功能开关状态
show-config:
	@echo "FST=$(FST)  TRACE=$(TRACE)  NVBOARD=$(NVBOARD)  DIFFTEST_SO=$(DIFFTEST_SO)  ELF=$(ELF)"
	@echo "YSYXSOC_ROOT=$(YSYXSOC_ROOT)"
	@echo "Usage examples:"
	@echo "  make build                          # 全关（最快）"
	@echo "  make build TRACE=1                  # 开 trace"
	@echo "  make build FST=1                    # 开波形"
	@echo "  make build FST=1 TRACE=1            # 全开"
	@echo "  make build NVBOARD=1                # 接入 NVBoard (流水灯/拨码开关)"
	@echo "  make run NVBOARD=1 PROG=xxx.bin     # 接入 NVBoard 运行"
	@echo "  make run PROG=x.bin                 # 不带 ftrace/difftest 运行"
	@echo "  make run PROG=x.bin ELF=x.elf TRACE=1  # 开 ftrace"
	@echo "  make run PROG=x.bin DIFFTEST_SO=../nemu/build/riscv32-nemu-interpreter-so"

define VERILATE_CMD
	$(VERILATOR) $(VERILATOR_FLAGS) -cc --exe --build -j \
	$(VERILATOR_TRACE_FLAGS) \
	-CFLAGS "-std=c++14 -O3 -I$(shell pwd)/csrc \
	  -I$(shell pwd)/../nemu/tools/capstone/repo/include \
	  -I$(shell pwd)/../nemu/include \
	  $(shell sdl2-config --cflags) \
	  $(EXTRA_CFLAGS)" \
	-LDFLAGS "-lreadline -ldl $(shell sdl2-config --libs) $(NVBOARD_LDFLAGS)" \
	vsrc/*.v csrc/main.cpp csrc/core/*.cpp csrc/sdb/*.cpp \
	csrc/utils/*.cpp csrc/trace/*.cpp \
	$(NVBOARD_EXTRA_CSRCS) \
	$(VERILOG_FILES) \
	$(NVBOARD_CXXSRC_FLAGS) \
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

# NVBoard=1 时, build/run 需要先准备好 auto_bind.cpp 和 nvboard.a.
# 通过把 NVBOARD_PREREQS 作为依赖追加到 build/run 上来实现.
NVBOARD_PREREQS :=
ifeq ($(NVBOARD), 1)
NVBOARD_PREREQS := nvboard-prepare
endif

# 只编译不运行
build: $(NVBOARD_PREREQS)
	$(call git_commit, "sim RTL") # DO NOT REMOVE THIS LINE!!!
	@echo "-- VERILATE & BUILD [FST=$(FST) TRACE=$(TRACE) NVBOARD=$(NVBOARD)] --------"
	@mkdir -p $(WAVE_DIR)
	$(VERILATE_CMD)
	@echo "-- BUILD DONE --------------"

# 编译并运行
run: $(NVBOARD_PREREQS)
	$(call git_commit, "sim RTL") # DO NOT REMOVE THIS LINE!!!
	@echo "-- VERILATE & BUILD [FST=$(FST) TRACE=$(TRACE) NVBOARD=$(NVBOARD)] --------"
	@mkdir -p $(WAVE_DIR)
	$(VERILATE_CMD)
	@echo "-- BUILD DONE --------------"
	@if [ ! -f $(OBJ_DIR)/VysyxSoCFull ]; then \
		echo "Error: VysyxSoCFull not found after build."; exit 1; \
	fi
	@if [ ! -f "$(PROG)" ]; then \
		echo "Error: Program file '$(PROG)' not found."; exit 1; \
	fi
	@echo "-- RUN [DIFFTEST=$(if $(DIFFTEST_SO),ON,OFF)] -----------"
	@echo "Running: $(OBJ_DIR)/VysyxSoCFull $(PROG) $(ELF_ARG) $(DIFFTEST_ARG) $(BATCH)"
	@$(OBJ_DIR)/VysyxSoCFull $(PROG) $(ELF_ARG) $(DIFFTEST_ARG) $(BATCH)
	@echo "-- DONE --------------------"

# NVBoard 预备: 生成引脚自动绑定代码 + 编译 nvboard.a
nvboard-prepare: $(NVBOARD_ARCHIVE) $(SRC_AUTO_BIND)
	@echo "-- NVBoard prepared --------"

.PHONY: build sim run clean char-test nvboard-prepare