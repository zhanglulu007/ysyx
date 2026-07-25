PROJECT_DIR := $(abspath $(CURDIR))
NPC_ROOT := $(abspath $(PROJECT_DIR)/..)
WORKBENCH_ROOT := $(abspath $(NPC_ROOT)/..)
SIM_ROOT := $(NPC_ROOT)/csrc_standalone
NEMU_HOME := $(WORKBENCH_ROOT)/nemu

ifeq ($(VERILATOR_ROOT),)
  VERILATOR := verilator
else
  export VERILATOR_ROOT
  VERILATOR := $(VERILATOR_ROOT)/bin/verilator
endif

TOP := top
TOP_CLASS := Vtop
SOC ?= 0
FFLASH ?= 0
BUILD_DIR := $(PROJECT_DIR)/build
WAVE_DIR := $(PROJECT_DIR)/wave

CORE_RTL_SRCS := $(sort $(wildcard $(PROJECT_DIR)/vsrc/*.v) $(wildcard $(PROJECT_DIR)/vsrc/*.sv))
ADAPTER_SRCS := $(sort $(wildcard $(PROJECT_DIR)/csrc/adapter/*.cpp))
SHARED_CORE_SRCS := $(filter-out \
  $(SIM_ROOT)/core/cpu.cpp \
  $(SIM_ROOT)/core/npc.cpp \
  $(SIM_ROOT)/core/ftrace_dpi.cpp, \
  $(wildcard $(SIM_ROOT)/core/*.cpp))
STANDALONE_SRCS := \
  $(SIM_ROOT)/main.cpp \
  $(SHARED_CORE_SRCS) \
  $(wildcard $(SIM_ROOT)/sdb/*.cpp) \
  $(wildcard $(SIM_ROOT)/utils/*.cpp) \
  $(wildcard $(SIM_ROOT)/trace/*.cpp)

FST ?= 0
TRACE ?= 0
DIFFTEST ?= 0
ifeq ($(SOC),1)
  DIFFTEST_SO ?= $(NEMU_HOME)/build/riscv32-nemu-interpreter-ysyxsoc-so
else
  DIFFTEST_SO ?= $(NEMU_HOME)/build/riscv32-nemu-interpreter-standalone-so
endif

PROG ?= test/mem.bin
ELF ?=
BATCH ?= -b

PROG_ABS := $(abspath $(PROG))
ELF_ABS := $(if $(ELF),$(abspath $(ELF)))

VERILATOR_FLAGS := \
  --x-assign fast --x-initial fast \
  --timescale "1ns/1ns" --no-timing --autoflush \

EXTRA_CFLAGS :=
VERILATOR_TRACE_FLAGS :=

YSYXSOC_ROOT ?= $(WORKBENCH_ROOT)/ysyxSoC
YSYXSOC_BUILD := $(YSYXSOC_ROOT)/build
YSYXSOC_PERIP := $(YSYXSOC_ROOT)/perip
YSYXSOC_SDRAM_DIR := $(firstword $(wildcard \
  $(YSYXSOC_PERIP)/sdram \
  $(YSYXSOC_PERIP)/ps2/sdram))

ifeq ($(SOC),1)
  TOP := ysyxSoCFull
  TOP_CLASS := VysyxSoCFull
  OBJ_DIR := $(BUILD_DIR)/obj_dir_soc
  SIM_SRCS := \
    $(wildcard $(NPC_ROOT)/csrc/main.cpp) \
    $(wildcard $(NPC_ROOT)/csrc/core/*.cpp) \
    $(wildcard $(NPC_ROOT)/csrc/sdb/*.cpp) \
    $(wildcard $(NPC_ROOT)/csrc/utils/*.cpp) \
    $(wildcard $(NPC_ROOT)/csrc/trace/*.cpp)
  RTL_SRCS := \
    $(YSYXSOC_BUILD)/ysyxSoCFull.v \
    $(wildcard $(YSYXSOC_PERIP)/uart16550/rtl/*.v) \
    $(wildcard $(YSYXSOC_PERIP)/spi/rtl/*.v) \
    $(wildcard $(YSYXSOC_SDRAM_DIR)/core_sdram_axi4/*.v) \
    $(wildcard $(YSYXSOC_SDRAM_DIR)/*.v) \
    $(wildcard $(YSYXSOC_PERIP)/psram/efabless/*.v) \
    $(wildcard $(YSYXSOC_PERIP)/psram/*.v) \
    $(wildcard $(YSYXSOC_PERIP)/vga/*.v) \
    $(wildcard $(YSYXSOC_PERIP)/ps2/*.v) \
    $(wildcard $(YSYXSOC_PERIP)/gpio/*.v) \
    $(wildcard $(YSYXSOC_PERIP)/flash/*.v) \
    $(wildcard $(YSYXSOC_PERIP)/bitrev/*.v) \
    $(wildcard $(YSYXSOC_PERIP)/amba/*.v) \
    $(CORE_RTL_SRCS)
  VERILATOR_FLAGS += -DSOC_MODE \
    -I$(YSYXSOC_PERIP)/uart16550/rtl \
    -I$(YSYXSOC_PERIP)/spi/rtl
else
  OBJ_DIR := $(BUILD_DIR)/obj_dir
  SIM_SRCS := $(ADAPTER_SRCS) $(STANDALONE_SRCS)
  RTL_SRCS := $(CORE_RTL_SRCS)
endif

ifeq ($(FST),1)
  VERILATOR_TRACE_FLAGS += --trace-fst --trace-structs
  EXTRA_CFLAGS += -DENABLE_FST
endif

ifeq ($(TRACE),1)
  EXTRA_CFLAGS += -DENABLE_TRACE
endif

ifeq ($(FFLASH),1)
  VERILATOR_FLAGS += -DFAST_FLASH
  EXTRA_CFLAGS += -DFAST_FLASH
endif

ifneq ($(ELF),)
  ELF_ARG := -e $(ELF_ABS)
endif

ifeq ($(DIFFTEST),1)
  DIFFTEST_ARG := -d $(DIFFTEST_SO)
endif

SDL_CFLAGS := $(shell sdl2-config --cflags)
SDL_LIBS := $(shell sdl2-config --libs) -lSDL2_image -lSDL2_ttf

define VERILATE_CMD
	$(VERILATOR) --top-module $(TOP) $(VERILATOR_FLAGS) $(VERILATOR_TRACE_FLAGS) \
	  -cc --exe --build -j \
	  -CFLAGS "-std=c++14 -O3 \
	    -I$(SIM_ROOT) \
	    -I$(NPC_ROOT)/csrc \
	    -I$(NEMU_HOME)/tools/capstone/repo/include \
	    -I$(NEMU_HOME)/include \
	    $(SDL_CFLAGS) $(EXTRA_CFLAGS)" \
	  -LDFLAGS "-lreadline -ldl $(SDL_LIBS)" \
	  $(RTL_SRCS) $(SIM_SRCS) \
	  --Mdir $(OBJ_DIR)
endef

all: build

show-config:
	@echo "PROJECT_DIR=$(PROJECT_DIR)"
	@echo "RTL_DIR=$(PROJECT_DIR)/vsrc"
	@echo "SIM_ROOT=$(SIM_ROOT)"
	@echo "SOC=$(SOC) FST=$(FST) TRACE=$(TRACE) DIFFTEST=$(DIFFTEST)"
	@echo "PROG=$(PROG_ABS) ELF=$(ELF_ABS)"

lint:
	$(VERILATOR) --lint-only --top-module $(TOP) $(VERILATOR_FLAGS) $(RTL_SRCS)

test-clint:
	@mkdir -p $(BUILD_DIR)
	iverilog -g2012 -s clint_tb -o $(BUILD_DIR)/clint_tb \
	  $(PROJECT_DIR)/vsrc/CLINT.v $(PROJECT_DIR)/tests/clint_tb.v
	vvp $(BUILD_DIR)/clint_tb

$(BUILD_DIR)/clint_soc_smoke.bin: $(PROJECT_DIR)/tests/clint_soc_smoke.S
	@mkdir -p $(BUILD_DIR)
	riscv64-linux-gnu-gcc -march=rv32e_zicsr -mabi=ilp32e \
	  -nostdlib -nostartfiles -static -Wl,--build-id=none \
	  -Wl,-Ttext=0x30000000 -Wl,-e,_start \
	  -o $(BUILD_DIR)/clint_soc_smoke.elf $<
	riscv64-linux-gnu-objcopy --change-addresses=-0x30000000 \
	  -O binary $(@:.bin=.elf) $@

test-soc-clint: $(BUILD_DIR)/clint_soc_smoke.bin
	$(MAKE) build SOC=1
	@cd $(NPC_ROOT) && \
	  $(BUILD_DIR)/obj_dir_soc/VysyxSoCFull $< \
	  -l $(PROJECT_DIR)/clint_soc_smoke.log -b

build:
	@mkdir -p $(BUILD_DIR) $(WAVE_DIR)
	@echo "-- BUILD rtl-standalone [SOC=$(SOC) FST=$(FST) TRACE=$(TRACE)] --"
	$(VERILATE_CMD)

run: build
	@if [ ! -f "$(PROG_ABS)" ]; then \
	  echo "Error: program '$(PROG_ABS)' not found."; exit 1; \
	fi
	@if [ "$(DIFFTEST)" = "1" ] && [ ! -f "$(DIFFTEST_SO)" ]; then \
	  echo "Error: DiffTest REF '$(DIFFTEST_SO)' not found."; exit 1; \
	fi
	@echo "-- RUN rtl-standalone [SOC=$(SOC) DIFFTEST=$(DIFFTEST)] --"
	@cd $(NPC_ROOT) && \
	  $(OBJ_DIR)/$(TOP_CLASS) $(PROG_ABS) \
	  -l $(PROJECT_DIR)/npc.log $(ELF_ARG) $(DIFFTEST_ARG) $(BATCH)

clean:
	-rm -rf $(BUILD_DIR) $(WAVE_DIR) $(PROJECT_DIR)/npc.log \
	  $(PROJECT_DIR)/clint_soc_smoke.log

.PHONY: all show-config lint test-clint test-soc-clint build run clean
