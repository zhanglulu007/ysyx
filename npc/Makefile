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

F_CONFIG_FILE ?= $(PROJECT_DIR)/config/f_cpu
F_DEFAULT     ?= 0
ifeq ($(origin F),undefined)
  ifneq ($(wildcard $(F_CONFIG_FILE)),)
    F_FROM_FILE := $(strip $(shell head -n1 $(F_CONFIG_FILE) 2>/dev/null))
    ifneq ($(F_FROM_FILE),)
      ifeq ($(shell printf '%s' '$(F_FROM_FILE)' | grep -Eq '^[0-9]+$$' && echo ok),ok)
        F := $(F_FROM_FILE)
      else
        $(warning NPC: invalid F value '$(F_FROM_FILE)' in $(F_CONFIG_FILE); using default $(F_DEFAULT))
      endif
    endif
  endif
endif
ifeq ($(origin F),undefined)
  F := $(F_DEFAULT)
endif

BUILD_DIR := $(PROJECT_DIR)/build
WAVE_DIR := $(PROJECT_DIR)/wave
EVAL_DIR ?= $(PROJECT_DIR)/eval
MICROBENCH_DIR ?= $(WORKBENCH_ROOT)/am-kernels/benchmarks/microbench
PERF_EVAL_LOG := $(BUILD_DIR)/perf-eval.log
PERF_MICROBENCH_LOG := $(BUILD_DIR)/perf-microbench.log
$(shell mkdir -p $(BUILD_DIR) $(WAVE_DIR))

# ---- cachesim: 基于 NEMU PC 序列的 ICache 快速评估 ----
# 只回放 PC 序列统计缺失次数, 不跑 Verilator, 因此比 RTL 仿真快 2~3 个数量级.
CACHESIM_DIR     ?= $(PROJECT_DIR)/cachesim
CACHESIM_BIN     := $(CACHESIM_DIR)/build/cachesim
CACHESIM_TRACE   ?= $(BUILD_DIR)/microbench-train.pc
CACHESIM_CSETS   ?= 16
CACHESIM_CWAYS   ?= 1
CACHESIM_CBLOCK  ?= 4
CACHESIM_PENALTY ?= 30
CACHESIM_SWEEP_BLOCKS ?= 4 8 16 32
CACHESIM_SWEEP_WAYS   ?= 1 2 4
CACHESIM_SWEEP_SETS   ?= 4 8 16 32
JOBS ?= $(shell nproc 2>/dev/null || echo 4)
NEMU_TRACE_BIN   ?= $(NEMU_HOME)/build/riscv32-nemu-interpreter-ysyxsoc
MICROBENCH_BIN   ?= $(MICROBENCH_DIR)/build/microbench-riscv32e-ysyxsoc.bin
CACHESIM_NEMU_LOG := $(BUILD_DIR)/cachesim-nemu.log

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

ifneq ($(strip $(F)),)
  ifneq ($(strip $(F)),0)
    EXTRA_CFLAGS += -DF=$(strip $(F))
  endif
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

# 一键性能评估：清理 NPC -> eval 综合 -> microbench train -> 打印报告
perf:
	@set -e; \
	echo "[perf] 1/3 clean NPC build"; \
	$(MAKE) --no-print-directory -C $(PROJECT_DIR) clean; \
	mkdir -p $(BUILD_DIR) $(WAVE_DIR); \
	echo "[perf] 2/3 eval: $(EVAL_DIR)"; \
	if ! $(MAKE) --no-print-directory -C $(EVAL_DIR) all > $(PERF_EVAL_LOG) 2>&1; then \
	  echo "[perf] eval failed; tail of $(PERF_EVAL_LOG):"; \
	  tail -n 80 $(PERF_EVAL_LOG); \
	  exit 1; \
	fi; \
	echo "[perf] 3/3 microbench train: $(MICROBENCH_DIR)"; \
	if ! $(MAKE) --no-print-directory -C $(MICROBENCH_DIR) \
	      AM_HOME=$(WORKBENCH_ROOT)/abstract-machine \
	      NPC_HOME=$(PROJECT_DIR) \
	      ARCH=riscv32e-ysyxsoc SOC=1 FFLASH=0 PERF=1 \
	      TRACE=0 FST=0 DIFFTEST=0 NVBOARD=0 mainargs=train run \
	      > $(PERF_MICROBENCH_LOG) 2>&1; then \
	  echo "[perf] microbench failed; tail of $(PERF_MICROBENCH_LOG):"; \
	  tail -n 80 $(PERF_MICROBENCH_LOG); \
	  exit 1; \
	fi; \
	echo ""; \
	echo "==================== PERF REPORT ===================="; \
	if grep -q "Performance Report" $(PERF_MICROBENCH_LOG); then \
	  awk '/Performance Report/ {show=1} show {print} show && /^=+$$/ {exit}' $(PERF_MICROBENCH_LOG); \
	else \
	  echo "(未找到 NPC Performance Report，完整日志: $(PERF_MICROBENCH_LOG))"; \
	fi; \
	echo ""; \
	echo "==================== EVAL REPORT ===================="; \
	$(MAKE) --no-print-directory -C $(EVAL_DIR) report; \
	echo ""; \
	echo "[perf] logs: $(PERF_EVAL_LOG), $(PERF_MICROBENCH_LOG)"

# ==================== cachesim 快速评估 ====================
# 流程: 编译 microbench(train) -> NEMU 导出 PC 序列 -> cachesim 回放统计

$(CACHESIM_BIN): $(CACHESIM_DIR)/cachesim.cpp
	@$(MAKE) --no-print-directory -C $(CACHESIM_DIR)

# microbench 的 train 镜像; bin 已存在则跳过, FORCE=1 可强制重编
$(MICROBENCH_BIN):
	@echo "[cachesim] 编译 microbench (mainargs=train) ..."
	@$(MAKE) --no-print-directory -C $(MICROBENCH_DIR) \
	  AM_HOME=$(WORKBENCH_ROOT)/abstract-machine \
	  ARCH=riscv32e-ysyxsoc mainargs=train insert-arg > /dev/null

cachesim-trace: $(MICROBENCH_BIN)
	@if [ -f "$(CACHESIM_TRACE)" ] && [ "$(FORCE)" != "1" ]; then \
	  echo "[cachesim] 复用已有 PC 序列: $(CACHESIM_TRACE)  (FORCE=1 可强制重建)"; \
	else \
	  echo "[cachesim] 构建 NEMU (riscv32-ysyxsoc 配置) ..."; \
	  $(MAKE) --no-print-directory -C $(NEMU_HOME) riscv32-ysyxsoc_defconfig > /dev/null; \
	  $(MAKE) --no-print-directory -C $(NEMU_HOME) YSYXSOC_REF=1 \
	    NAME=riscv32-nemu-interpreter-ysyxsoc -j > /dev/null; \
	  echo "[cachesim] 导出 PC 序列 -> $(CACHESIM_TRACE)"; \
	  $(NEMU_TRACE_BIN) -b -c $(CACHESIM_TRACE) $(MICROBENCH_BIN) \
	    > $(CACHESIM_NEMU_LOG) 2>&1; \
	  echo "[cachesim] trace 大小: $$(du -h $(CACHESIM_TRACE) | cut -f1)  (NEMU 日志: $(CACHESIM_NEMU_LOG))"; \
	fi

cachesim: $(CACHESIM_BIN) cachesim-trace
	@echo "=== cachesim 评估 [sets=$(CACHESIM_CSETS) ways=$(CACHESIM_CWAYS) block=$(CACHESIM_CBLOCK)B penalty=$(CACHESIM_PENALTY)] ==="
	@$(CACHESIM_BIN) --trace $(CACHESIM_TRACE) \
	  --sets $(CACHESIM_CSETS) --ways $(CACHESIM_CWAYS) \
	  --block $(CACHESIM_CBLOCK) --miss-penalty $(CACHESIM_PENALTY)

cachesim-sweep: $(CACHESIM_BIN) cachesim-trace
	@mkdir -p $(BUILD_DIR)/cachesim-sweep
	@rm -f $(BUILD_DIR)/cachesim-sweep/*.csv
	@echo "[cachesim] 参数扫描 blocks={$(CACHESIM_SWEEP_BLOCKS)} ways={$(CACHESIM_SWEEP_WAYS)} sets={$(CACHESIM_SWEEP_SETS)} (并行 $(JOBS) 路)"
	@for b in $(CACHESIM_SWEEP_BLOCKS); do \
	  for w in $(CACHESIM_SWEEP_WAYS); do \
	    for s in $(CACHESIM_SWEEP_SETS); do echo "$$b $$w $$s"; done; \
	  done; \
	done | xargs -P $(JOBS) -n 3 sh -c '\
	  $(CACHESIM_BIN) --csv --trace $(CACHESIM_TRACE) \
	    --block $$0 --ways $$1 --sets $$2 --miss-penalty $(CACHESIM_PENALTY) \
	    > $(BUILD_DIR)/cachesim-sweep/$${0}_$${1}_$${2}.csv'
	@echo ""
	@printf "%-6s %-5s %-5s %9s %12s %14s\n" block ways sets hit-rate miss TMT
	@printf "%-6s %-5s %-5s %9s %12s %14s\n" ------ ----- ----- --------- ------------ --------------
	@cat $(BUILD_DIR)/cachesim-sweep/*.csv | sort -t, -k1,1n -k2,2n -k3,3n | \
	  awk -F, '{ printf "%-6s %-5s %-5s %8s%% %12s %14s\n", $$1, $$2, $$3, $$4, $$5, $$6 }'

cachesim-report: $(CACHESIM_BIN) cachesim-trace
	@echo "============ cachesim vs NPC perf (仅供参考, 不自动断言) ============"
	@echo "--- NPC perf [ICache behavior]  ($(PERF_MICROBENCH_LOG)) ---"
	@if [ -f "$(PERF_MICROBENCH_LOG)" ]; then \
	  awk '/\[ICache behavior\]/{show=1} show{print} show&&/^\[LSU behavior\]/{exit}' $(PERF_MICROBENCH_LOG); \
	else \
	  echo "  (未找到 perf 日志, 请先运行 make perf)"; \
	fi
	@echo ""
	@echo "--- cachesim (sets=16 ways=1 block=4, 与当前 ICache 一致) ---"
	@$(CACHESIM_BIN) --trace $(CACHESIM_TRACE) --sets 16 --ways 1 --block 4 \
	  --miss-penalty $(CACHESIM_PENALTY)
	@echo "======================================================================"

cachesim-clean:
	-rm -rf $(CACHESIM_DIR)/build $(BUILD_DIR)/cachesim-sweep $(CACHESIM_TRACE)

clean:
	-rm -rf $(BUILD_DIR) $(WAVE_DIR) $(PROJECT_DIR)/npc.log

.PHONY: all show-config check-soc lint build run \
	build-standalone run-standalone build-soc run-soc perf clean \
	cachesim cachesim-trace cachesim-sweep cachesim-report cachesim-clean