PROJECT_DIR := $(abspath $(CURDIR))
WORKBENCH_ROOT := $(abspath $(PROJECT_DIR)/..)
SRC_ROOT := $(PROJECT_DIR)/csrc
NEMU_HOME ?= $(WORKBENCH_ROOT)/nemu
YSYXSOC_ROOT ?= $(WORKBENCH_ROOT)/ysyxSoC
YSYXSOC_BUILD := $(YSYXSOC_ROOT)/build
YSYXSOC_PERIP := $(YSYXSOC_ROOT)/perip

include ../Makefile

ifneq ($(words $(CURDIR)),1)
  $(error Unsupported: GNU Make cannot build in directories containing spaces, build elsewhere: '$(CURDIR)')
endif

ifeq ($(VERILATOR_ROOT),)
  VERILATOR := verilator
else
  export VERILATOR_ROOT
  VERILATOR := $(VERILATOR_ROOT)/bin/verilator
endif

SOC ?= 0
FST ?= 0
TRACE ?= 0
DIFFTEST ?= 0
FFLASH  ?= 0
NVBOARD ?= 0
PERF    ?= 0
F       ?= 0

BUILD_DIR := $(PROJECT_DIR)/build
WAVE_DIR := $(PROJECT_DIR)/wave
$(shell mkdir -p $(BUILD_DIR) $(WAVE_DIR))

CORE_RTL_SRCS := $(sort \
  $(wildcard $(PROJECT_DIR)/vsrc/*.v) \
  $(wildcard $(PROJECT_DIR)/vsrc/*.sv))
SIM_SRCS := \
  $(SRC_ROOT)/main.cpp \
  $(wildcard $(SRC_ROOT)/core/*.cpp) \
  $(wildcard $(SRC_ROOT)/sdb/*.cpp) \
  $(wildcard $(SRC_ROOT)/utils/*.cpp) \
  $(wildcard $(SRC_ROOT)/trace/*.cpp)

EXTRA_CFLAGS :=
VERILATOR_TRACE_FLAGS :=

ifeq ($(SOC),1)
  MODE := soc
  TOP := ysyxSoCFull
  TOP_CLASS := VysyxSoCFull
  OBJ_DIR := $(BUILD_DIR)/obj_dir_soc
  PROG ?= /dev/null
  DIFFTEST_SO ?= $(NEMU_HOME)/build/riscv32-nemu-interpreter-ysyxsoc-so
  SOC_RTL_SRCS := \
    $(YSYXSOC_BUILD)/ysyxSoCFull.v \
    $(wildcard $(YSYXSOC_PERIP)/uart16550/rtl/*.v) \
    $(wildcard $(YSYXSOC_PERIP)/spi/rtl/*.v) \
    $(wildcard $(YSYXSOC_PERIP)/sdram/core_sdram_axi4/*.v) \
    $(wildcard $(YSYXSOC_PERIP)/sdram/*.v) \
    $(wildcard $(YSYXSOC_PERIP)/psram/efabless/*.v) \
    $(wildcard $(YSYXSOC_PERIP)/psram/*.v) \
    $(wildcard $(YSYXSOC_PERIP)/vga/*.v) \
    $(wildcard $(YSYXSOC_PERIP)/ps2/*.v) \
    $(wildcard $(YSYXSOC_PERIP)/gpio/*.v) \
    $(wildcard $(YSYXSOC_PERIP)/flash/*.v) \
    $(wildcard $(YSYXSOC_PERIP)/bitrev/*.v) \
    $(wildcard $(YSYXSOC_PERIP)/amba/*.v)
  RTL_SRCS := $(SOC_RTL_SRCS) $(CORE_RTL_SRCS)
  EXTRA_CFLAGS += -DSOC_MODE
  VERILATOR_MODE_FLAGS := \
    -DSOC_MODE \
    -I$(YSYXSOC_PERIP)/uart16550/rtl \
    -I$(YSYXSOC_PERIP)/spi/rtl \
	  --autoflush
  MODE_PREREQUISITE := check-soc
else
  MODE := standalone
  TOP := top
  TOP_CLASS := Vtop
  OBJ_DIR := $(BUILD_DIR)/obj_dir
  PROG ?= test/mem.bin
  DIFFTEST_SO ?= $(NEMU_HOME)/build/riscv32-nemu-interpreter-standalone-so
  RTL_SRCS := $(CORE_RTL_SRCS)
endif

ifeq ($(NVBOARD), 1)
  EXTRA_CFLAGS += -DENABLE_NVBOARD
  NVBOARD_PREREQ = $(SRC_AUTO_BIND) nvboard-archive
  NVBOARD_CSRCS  = $(SRC_AUTO_BIND)
  NVBOARD_LDFLAGS = $(NVBOARD_ARCHIVE)
  NVBOARD_HOME ?= /home/zhangshenlu/ysyx-workbench/nvboard
  NXDC_FILES = $(PROJECT_DIR)/constr/soc.nxdc
  SRC_AUTO_BIND = $(BUILD_DIR)/auto_bind.cpp

$(SRC_AUTO_BIND): $(NXDC_FILES)
	python3 $(NVBOARD_HOME)/scripts/auto_pin_bind.py $^ $@

include $(NVBOARD_HOME)/scripts/nvboard.mk
else
  NVBOARD_PREREQ =
  NVBOARD_CSRCS  =
  NVBOARD_LDFLAGS =
endif

PROG_ABS := $(abspath $(PROG))
ELF ?=
ELF_ABS := $(if $(ELF),$(abspath $(ELF)))
BATCH ?= -b

VERILATOR_FLAGS := \
  --top-module $(TOP) \
  --x-assign fast --x-initial fast \
  --timescale "1ns/1ns" --no-timing \
  $(VERILATOR_MODE_FLAGS)

ifeq ($(FST),1)
  VERILATOR_TRACE_FLAGS += --trace-fst --trace-structs
  EXTRA_CFLAGS += -DENABLE_FST
endif

ifeq ($(TRACE),1)
  EXTRA_CFLAGS += -DENABLE_TRACE
endif

ifneq ($(ELF),)
  ELF_ARG := -e $(ELF_ABS)
endif

ifeq ($(DIFFTEST),1)
  DIFFTEST_ARG := -d $(DIFFTEST_SO)
endif

ifeq ($(FFLASH), 1)
  VERILATOR_FLAGS += -DFAST_FLASH
  EXTRA_CFLAGS += -DFAST_FLASH
endif

ifeq ($(PERF), 1)
  VERILATOR_FLAGS += -DENABLE_PERF
  EXTRA_CFLAGS += -DENABLE_PERF
endif

ifneq ($(F),0)
  EXTRA_CFLAGS += -DF=$(F)
endif

SDL_CFLAGS := $(shell sdl2-config --cflags)
SDL_LIBS := $(shell sdl2-config --libs) -lSDL2_image -lSDL2_ttf

define VERILATE_CMD
	$(VERILATOR) $(VERILATOR_FLAGS) $(VERILATOR_TRACE_FLAGS) \
	  -cc --exe --build -j \
	  -CFLAGS "-std=c++14 -O3 \
	    -I$(SRC_ROOT) \
	    -I$(NEMU_HOME)/tools/capstone/repo/include \
	    -I$(NEMU_HOME)/include \
      -I$(NVBOARD_HOME)/usr/include \
	    $(SDL_CFLAGS) $(EXTRA_CFLAGS)" \
	  -LDFLAGS "$(NVBOARD_LDFLAGS) -lreadline -ldl $(SDL_LIBS)" \
	  $(RTL_SRCS) $(SIM_SRCS) \
	  --Mdir $(OBJ_DIR) \
    $(NVBOARD_CSRCS)
endef

all: build

show-config:
	@echo "MODE=$(MODE) SOC=$(SOC) TOP=$(TOP) TOP_CLASS=$(TOP_CLASS)"
	@echo "OBJ_DIR=$(OBJ_DIR)"
	@echo "FST=$(FST) TRACE=$(TRACE) DIFFTEST=$(DIFFTEST) FFLASH=$(FFLASH)"
	@echo "PERF=$(PERF) NVBOARD=$(NVBOARD) F=$(F)"
	@echo "PROG=$(PROG_ABS) ELF=$(ELF_ABS)"
	@echo "YSYXSOC_ROOT=$(YSYXSOC_ROOT)"

check-soc:
	@test -f "$(YSYXSOC_BUILD)/ysyxSoCFull.v" || { \
	  echo "Error: missing $(YSYXSOC_BUILD)/ysyxSoCFull.v; run 'make -C $(YSYXSOC_ROOT) verilog'."; \
	  exit 1; \
	}
	@grep -q 'ysyx_26020070' "$(YSYXSOC_BUILD)/ysyxSoCFull.v" || { \
	  echo "Error: ysyxSoCFull.v does not instantiate ysyx_26020070."; \
	  exit 1; \
	}

lint: $(MODE_PREREQUISITE)
	$(VERILATOR) --lint-only -Wno-fatal $(VERILATOR_FLAGS) $(RTL_SRCS)

build: $(NVBOARD_PREREQ) $(MODE_PREREQUISITE) $(if $(filter 1,$(DIFFTEST)),$(DIFFTEST_SO))
	@mkdir -p $(BUILD_DIR) $(WAVE_DIR)
	@echo "-- BUILD NPC [MODE=$(MODE) FST=$(FST) TRACE=$(TRACE) FFLASH=$(FFLASH)] --"
	$(VERILATE_CMD)

run: build
	@if [ ! -r "$(PROG_ABS)" ]; then \
	  echo "Error: program '$(PROG_ABS)' not found."; exit 1; \
	fi
	@if [ "$(DIFFTEST)" = "1" ] && [ ! -f "$(DIFFTEST_SO)" ]; then \
	  echo "Error: DiffTest REF '$(DIFFTEST_SO)' not found."; exit 1; \
	fi
	$(call git_commit, "sim RTL") # DO NOT REMOVE THIS LINE!!!
	@echo "-- RUN NPC [MODE=$(MODE) DIFFTEST=$(DIFFTEST)] --"
	@cd $(PROJECT_DIR) && \
	  $(OBJ_DIR)/$(TOP_CLASS) $(PROG_ABS) \
	  -l $(PROJECT_DIR)/npc.log $(ELF_ARG) $(DIFFTEST_ARG) $(BATCH)

clean:
	-rm -rf $(BUILD_DIR) $(WAVE_DIR) $(PROJECT_DIR)/npc.log


# 构建 NEMU REF .so (供 difftest 使用)
difftest-so:
	$(MAKE) -C $(NEMU_HOME) difftest-so

# 显式规则: 触发 NEMU 构建对应的 .so
$(NEMU_HOME)/build/riscv32-nemu-interpreter-standalone-so:
	$(MAKE) -C $(NEMU_HOME) difftest-so-standalone

$(NEMU_HOME)/build/riscv32-nemu-interpreter-ysyxsoc-so:
	$(MAKE) -C $(NEMU_HOME) difftest-so-ysyxsoc

.PHONY: all show-config check-soc lint build run \
	build-standalone run-standalone build-soc run-soc clean difftest-so