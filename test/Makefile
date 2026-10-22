# ============================================================================
#  test - 优化 NPC 核的独立验证 / 评估工程
#
#  本工程只读取 ../npc/csrc 的仿真框架 (Verilator + DPI-C + Difftest),
#  RTL 位于 ./rtl (两阶段) 或 ./rtl_pipe3 (三阶段), 不修改 npc/ 或其它目录.
#
#  常用目标:
#    make build IMPL=rtl_pipe3     # Verilator 生成仿真器
#    make run             # 运行 microbench (train)
#    make difftest        # CPU-tests + NEMU DiffTest 回归
#    make bench           # 运行 microbench 并生成 IPC 摘要
#    make eval VARIANT=pipe3       # yosys-sta 综合/时序/面积
#    make all             # build + difftest + bench + eval
# ============================================================================
PROJ       := $(abspath $(CURDIR))
ROOT       := $(abspath $(PROJ)/..)
IMPL       ?= rtl_pipe3
RTL_DIR    := $(PROJ)/$(IMPL)
SRC_ROOT   := $(ROOT)/npc/csrc
NEMU_HOME  ?= $(ROOT)/nemu
NVBOARD_HOME ?= $(ROOT)/nvboard
VERILATOR  ?= verilator

PERF       ?= 0
VARIANT    ?= pipe3
JOBS       ?= 4

RTL_SRCS   := $(wildcard $(RTL_DIR)/*.v)
SIM_SRCS   := \
  $(SRC_ROOT)/main.cpp \
  $(wildcard $(SRC_ROOT)/core/*.cpp) \
  $(wildcard $(SRC_ROOT)/sdb/*.cpp) \
  $(wildcard $(SRC_ROOT)/utils/*.cpp) \
  $(wildcard $(SRC_ROOT)/trace/*.cpp)

BUILD_DIR  := $(PROJ)/build
OBJ_DIR    := $(BUILD_DIR)/obj_$(IMPL)$(if $(filter 1,$(PERF)),_perf,)
TOP        := top
TOP_CLASS  := Vtop
TARGET     := $(OBJ_DIR)/$(TOP_CLASS)
RESULT_DIR := $(PROJ)/result
BENCH_LOG  := $(RESULT_DIR)/microbench-$(IMPL)$(if $(filter 1,$(PERF)),-perf,).log

PROG       ?= $(PROJ)/bench/microbench-train.bin
REF_SO     ?= $(NEMU_HOME)/build/riscv32-nemu-interpreter-standalone-so
CPU_TESTS  ?= $(ROOT)/am-kernels/tests/cpu-tests/build

CSR_SRC    := $(PROJ)/bench/csr_test.S
CSR_LD     := $(PROJ)/bench/csr_test.ld
CSR_ELF    := $(PROJ)/bench/csr_test.elf
CSR_BIN    := $(PROJ)/bench/csr_test.bin
CSR_CC     ?= riscv64-linux-gnu-gcc
CSR_OCPY   ?= riscv64-linux-gnu-objcopy

# ---- SoC + ICachesim 参数化评估 (使用 baseline_rtl 快照, 不修改 npc/) ----
YSYXSOC_ROOT  ?= $(ROOT)/ysyxSoC
YSYXSOC_BUILD := $(YSYXSOC_ROOT)/build
YSYXSOC_PERIP := $(YSYXSOC_ROOT)/perip
SOC_BIN       ?= $(ROOT)/am-kernels/benchmarks/microbench/build/microbench-riscv32e-ysyxsoc.bin
SOC_OBJ       := $(BUILD_DIR)/obj_soc_cachesim$(if $(filter 1,$(PERF)),_perf,)
SOC_TARGET    := $(SOC_OBJ)/VysyxSoCFull
SOC_LOG       := $(RESULT_DIR)/soc-cachesim$(if $(filter 1,$(PERF)),-perf,).out
SOC_RUNLOG    := $(RESULT_DIR)/soc-cachesim$(if $(filter 1,$(PERF)),-perf,).log
SOC_RTL       := $(wildcard $(PROJ)/baseline_rtl/*.v)
SOC_PERIP_RTL := \
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
SOC_RTL_SRCS  := $(YSYXSOC_BUILD)/ysyxSoCFull.v $(SOC_PERIP_RTL) $(SOC_RTL)
SOC_INC       := -I$(YSYXSOC_PERIP)/uart16550/rtl -I$(YSYXSOC_PERIP)/spi/rtl
SOC_DEFINES   := -DSOC_MODE -DICACHE_SIM -DIC_BLOCK=128 -DIC_SETS=4 -DIC_WAYS=4 -DIC_BURST=1
SOC_CFLAGS    := -std=c++14 -O3 -I$(SRC_ROOT) \
                 -I$(NEMU_HOME)/tools/capstone/repo/include -I$(NEMU_HOME)/include \
                 -I$(NVBOARD_HOME)/usr/include $(SDL_CFLAGS) -DSOC_MODE $(if $(filter 1,$(PERF)),-DENABLE_PERF,)

SDL_CFLAGS := $(shell sdl2-config --cflags)
SDL_LIBS   := $(shell sdl2-config --libs) -lSDL2_image -lSDL2_ttf

EXTRA_CFLAGS :=
ifeq ($(PERF),1)
  EXTRA_CFLAGS += -DENABLE_PERF
  VERILATOR_FLAGS += -DENABLE_PERF
endif

VERILATOR_FLAGS += --top-module $(TOP) --x-assign fast --x-initial fast \
                   --timescale "1ns/1ns" --no-timing

SIM_CFLAGS := -std=c++14 -O3 \
  -I$(SRC_ROOT) \
  -I$(NEMU_HOME)/tools/capstone/repo/include \
  -I$(NEMU_HOME)/include \
  -I$(NVBOARD_HOME)/usr/include \
  $(SDL_CFLAGS) $(EXTRA_CFLAGS)

LDFLAGS_SIM := -lreadline -ldl $(SDL_LIBS)

.PHONY: all build run bench bench-perf difftest csrtest soc-cachesim soc-run eval eval-check report clean help

all: build difftest bench eval report

help:
	@echo "targets: build run bench difftest csrtest soc-cachesim soc-run eval eval-check report clean"

build: $(TARGET)

$(TARGET): $(RTL_SRCS) $(SIM_SRCS)
	@mkdir -p $(BUILD_DIR) $(RESULT_DIR)
	$(VERILATOR) $(VERILATOR_FLAGS) -cc --exe --build -j $(JOBS) \
	  -CFLAGS "$(SIM_CFLAGS)" \
	  -LDFLAGS "$(LDFLAGS_SIM)" \
	  $(RTL_SRCS) $(SIM_SRCS) \
	  --Mdir $(OBJ_DIR)

run: build
	@mkdir -p $(RESULT_DIR)
	@cd $(PROJ) && $(TARGET) $(PROG) -l $(RESULT_DIR)/npc.log $(if $(ELF),-e $(ELF)) -b

bench: build
	@mkdir -p $(RESULT_DIR)
	@echo "[bench] microbench train (PERF=$(PERF))"
	@cd $(PROJ) && $(TARGET) $(PROG) -l $(RESULT_DIR)/bench.log -b \
	  > $(BENCH_LOG) 2>&1; \
	status=$$?; \
	tail -n 20 $(BENCH_LOG); \
	echo "--- IPC ---"; \
	grep -E "Executed .* instructions in .* cycles, IPC=" $(BENCH_LOG) | tail -1; \
	exit $$status

# 带性能计数器的构建/运行 (独立 obj_dir, 不拖慢基准测试)
bench-perf:
	@$(MAKE) --no-print-directory PERF=1 build
	@$(MAKE) --no-print-directory PERF=1 bench

# CPU-tests 回归: 与 NEMU 逐指令 DiffTest
difftest: build
	@mkdir -p $(RESULT_DIR)/cputest
	@fail=0; \
	for t in add add-longlong bit bubble-sort crc32 div fact fib goldbach if-else \
	         leap-year load-store matrix-mul max mersenne min3 mov-c movsx \
	         mul-longlong pascal prime quick-sort recursion select-sort shift \
	         shuixianhua sub-longlong sum switch to-lower-case unalign wanshu; do \
	  bin="$(CPU_TESTS)/$$t-riscv32e-npc.bin"; \
	  [ -f "$$bin" ] || { echo "  [skip] $$t"; continue; }; \
	  if cd $(PROJ) && $(TARGET) "$$bin" -b -d $(REF_SO) -l $(RESULT_DIR)/cputest/$$t.log \
	        > $(RESULT_DIR)/cputest/$$t.out 2>&1 && \
	     grep -q "HIT GOOD TRAP" $(RESULT_DIR)/cputest/$$t.out; then \
	    echo "  [pass] $$t"; \
	  else \
	    echo "  [FAIL] $$t  (see $(RESULT_DIR)/cputest/$$t.out)"; fail=1; \
	  fi; \
	done; \
	exit $$fail
	@$(MAKE) --no-print-directory csrtest IMPL=$(IMPL)

# CSR / ecall / mret / fence.i 定向测试
$(CSR_BIN): $(CSR_SRC) $(CSR_LD)
	$(CSR_CC) -march=rv32e_zicsr_zifencei -mabi=ilp32e -mcmodel=medany \
	  -fno-pic -no-pie -nostdlib -nostartfiles -Wl,--build-id=none \
	  -Wl,-T,$(CSR_LD) -Wl,--entry=_start -o $(CSR_ELF) $(CSR_SRC)
	$(CSR_OCPY) -O binary $(CSR_ELF) $@

csrtest: build $(CSR_BIN)
	@mkdir -p $(RESULT_DIR)
	@cd $(PROJ) && $(TARGET) $(CSR_BIN) -b -d $(REF_SO) \
	  -l $(RESULT_DIR)/csrtest-$(IMPL).log > $(RESULT_DIR)/csrtest-$(IMPL).out 2>&1; \
	status=$$?; \
	if [ $$status -eq 0 ] && grep -q "HIT GOOD TRAP" $(RESULT_DIR)/csrtest-$(IMPL).out; then \
	  echo "  [pass] csr/ecall/mret/fence.i"; \
	else \
	  echo "  [FAIL] csr/ecall/mret/fence.i (see $(RESULT_DIR)/csrtest-$(IMPL).out)"; \
	  exit 1; \
	fi


# SoC + ICachesim 构建/运行 (IC_BLOCK=128 IC_SETS=4 IC_WAYS=4 IC_BURST=1, F=0)
soc-cachesim: $(SOC_TARGET)

$(SOC_TARGET): $(SOC_RTL_SRCS) $(SIM_SRCS)
	@mkdir -p $(BUILD_DIR) $(RESULT_DIR)
	$(VERILATOR) --top-module ysyxSoCFull -DSOC_MODE \
	  --x-assign fast --x-initial fast --timescale "1ns/1ns" --no-timing \
	  -DICACHE_SIM -DIC_BLOCK=128 -DIC_SETS=4 -DIC_WAYS=4 -DIC_BURST=1 \
	  $(if $(filter 1,$(PERF)),-DENABLE_PERF,) \
	  $(SOC_INC) --autoflush \
	  -cc --exe --build -j $(JOBS) \
	  -CFLAGS "$(SOC_CFLAGS)" \
	  -LDFLAGS "$(LDFLAGS_SIM)" \
	  $(SOC_RTL_SRCS) $(SIM_SRCS) \
	  --Mdir $(SOC_OBJ)

soc-run: soc-cachesim
	@test -f "$(SOC_BIN)" || { echo "missing $(SOC_BIN)"; exit 1; }
	@mkdir -p $(RESULT_DIR)
	@echo "[soc] IC_BLOCK=128 IC_SETS=4 IC_WAYS=4 IC_BURST=1 ICACHE_SIM=1 F=0"
	@cd $(PROJ) && $(SOC_TARGET) $(SOC_BIN) -b -l $(SOC_RUNLOG) \
	  > $(SOC_LOG) 2>&1; \
	status=$$?; \
	tail -n 30 $(SOC_LOG); \
	grep -E "HIT GOOD TRAP|HIT BAD TRAP|DiffTest failed" $(SOC_LOG) | tail -3; \
	exit $$status


eval:
	$(MAKE) -C $(PROJ)/eval all VARIANT=$(VARIANT)

eval-check:
	$(MAKE) -C $(PROJ)/eval check VARIANT=$(VARIANT)

report:
	@echo "================ NPC TEST SUMMARY ================"
	@for f in $(RESULT_DIR)/microbench-*.log; do [ -f "$$f" ] || continue; echo "-- $$f"; grep -E "Executed .* instructions in .* cycles, IPC=" "$$f" | tail -1; grep -E "MicroBench (PASS|FAIL)" "$$f" | tail -1; done
	@echo "see $(PROJ)/REPORT.md"

clean:
	rm -rf $(BUILD_DIR) $(RESULT_DIR)/cputest $(RESULT_DIR)/*.log
