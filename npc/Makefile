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

# ── TRACE: ENABLE_TRACE 必须同时进入 C++(-CFLAGS) 与 RTL(-D) 两个编译单元 ──
ifeq ($(TRACE),1)
  EXTRA_CFLAGS += -DENABLE_TRACE
  VERILATOR_FLAGS += -DENABLE_TRACE
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

# 把当前 git commit 注入 meta.json(经 shell 双引号转义, 到 gcc 即 -DNPC_GIT_COMMIT="abc")
GIT_COMMIT := $(shell git -C $(PROJECT_DIR) rev-parse --short HEAD 2>/dev/null)
EXTRA_CFLAGS += -DNPC_GIT_COMMIT=\"$(GIT_COMMIT)\"

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

# ── npc-trace 离线工具(转写/导出) ───────────────────────────────────────────
NPC_TRACE      := $(PROJECT_DIR)/tools/npc-trace/npc-trace
TRACE_OUT      ?= trace.npct
TRACE_TEXT_OUT ?= npc.trace.log
TRACE_JSON_OUT ?= trace.json

$(NPC_TRACE): $(wildcard $(PROJECT_DIR)/tools/npc-trace/*.cpp) \
              $(wildcard $(PROJECT_DIR)/tools/npc-trace/*.h) \
              $(SRC_ROOT)/trace/trace_event.cpp
	@$(MAKE) -s -C $(PROJECT_DIR)/tools/npc-trace

build-npc-trace: $(NPC_TRACE)

build: $(NVBOARD_PREREQ) $(MODE_PREREQUISITE) $(if $(filter 1,$(DIFFTEST)),$(DIFFTEST_SO))
	@mkdir -p $(BUILD_DIR) $(WAVE_DIR)
	@echo "-- BUILD NPC [MODE=$(MODE) FST=$(FST) TRACE=$(TRACE) FFLASH=$(FFLASH)] --"
	$(VERILATE_CMD)

# 结束后自动转写文本视图与 Chrome 时间轴。失败路径(exit != 0)也转写,
# 且转写失败不影响仿真退出码(用 `|| true` 兜住)。
run: build $(if $(filter 1,$(TRACE)),$(NPC_TRACE))
	@if [ ! -r "$(PROG_ABS)" ]; then \
	  echo "Error: program '$(PROG_ABS)' not found."; exit 1; \
	fi
	@if [ "$(DIFFTEST)" = "1" ] && [ ! -f "$(DIFFTEST_SO)" ]; then \
	  echo "Error: DiffTest REF '$(DIFFTEST_SO)' not found."; exit 1; \
	fi
	$(call git_commit, "sim RTL") # DO NOT REMOVE THIS LINE!!!
	@echo "-- RUN NPC [MODE=$(MODE) DIFFTEST=$(DIFFTEST)] --"
	@set +e; \
	  cd $(PROJECT_DIR) && \
	  $(OBJ_DIR)/$(TOP_CLASS) $(PROG_ABS) \
	    -l $(PROJECT_DIR)/npc.log $(ELF_ARG) $(DIFFTEST_ARG) $(BATCH); \
	  status=$$?; \
	  if [ "$(TRACE)" = "1" ] && [ -f "$(TRACE_OUT)" ]; then \
	    echo "-- TRANSCRIBE $(TRACE_OUT) -> $(TRACE_TEXT_OUT) ($(TRACE_JSON_OUT)) --"; \
	    $(NPC_TRACE) text $(TRACE_OUT) -o $(TRACE_TEXT_OUT) --format=legacy \
	      $(if $(ELF),--elf $(ELF_ABS)) || true; \
	    $(NPC_TRACE) export $(TRACE_OUT) --format=chrome -o $(TRACE_JSON_OUT) || true; \
	  fi; \
	  exit $$status

clean:
	-rm -rf $(BUILD_DIR) $(WAVE_DIR) $(PROJECT_DIR)/npc.log
	-rm -f $(PROJECT_DIR)/$(TRACE_OUT) $(PROJECT_DIR)/$(TRACE_TEXT_OUT) \
	       $(PROJECT_DIR)/$(TRACE_JSON_OUT)
	-$(MAKE) -s -C $(PROJECT_DIR)/tools/npc-trace clean

.PHONY: all show-config check-soc lint build run build-npc-trace \
	build-standalone run-standalone build-soc run-soc clean