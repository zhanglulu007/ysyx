# ============================================================================
# NPC 优化验证工程 (独立于 test/ 下另一套并发工程)
#
# 只读取 ../../npc 的 RTL/csrc 与 ../../am-kernels 的 microbench 产物；
# 所有构建、日志、综合结果都落在本目录，不改动其它目录源码。
#
#   make sim-opt      用 npc/vsrc 跑 standalone microbench (train) -> IPC
#   make sim-base     用 rtl_baseline/ 跑同一程序，作为基线对照
#   make smoke-opt    跑自写 RV32E 冒烟测试 (ALU/load-store/分支/BTB/fence.i/CSR)
#   make synth-opt    综合 + STA 当前 npc/vsrc -> 面积/频率
#   make synth-base   综合 + STA 基线 RTL
#   make report       汇总 IPC / 频率 / 面积 / 分数
# ============================================================================

HERE       := $(abspath $(CURDIR))
ROOT       := $(abspath $(HERE)/../..)
NPC        := $(ROOT)/npc
MICRO_BIN  := $(ROOT)/am-kernels/benchmarks/microbench/build/microbench-riscv32e-npc.bin
MICRO_ELF  := $(ROOT)/am-kernels/benchmarks/microbench/build/microbench-riscv32e-npc.elf
BUILD      := $(HERE)/build
RESULT     := $(HERE)/result

VERILATOR  ?= verilator
F_CONF     := $(shell cat $(NPC)/config/f_cpu 2>/dev/null)
F_VAL      := $(if $(F_CONF),$(F_CONF),0)

SIM_CPP := \
  $(NPC)/csrc/main.cpp \
  $(wildcard $(NPC)/csrc/core/*.cpp) \
  $(wildcard $(NPC)/csrc/sdb/*.cpp) \
  $(wildcard $(NPC)/csrc/utils/*.cpp) \
  $(wildcard $(NPC)/csrc/trace/*.cpp)

SIM_INC := \
  -I$(NPC)/csrc \
  -I$(ROOT)/nemu/tools/capstone/repo/include \
  -I$(ROOT)/nemu/include \
  $(shell sdl2-config --cflags)

SIM_LDFLAGS := -lreadline -ldl $(shell sdl2-config --libs) -lSDL2_image -lSDL2_ttf

VFLAGS := --top-module top --x-assign fast --x-initial fast \
          --timescale "1ns/1ns" --no-timing -DENABLE_PERF

OPT_RTL  := $(wildcard $(NPC)/vsrc/*.v)
BASE_RTL := $(wildcard $(HERE)/rtl_baseline/*.v)

define VERILATE
	$(VERILATOR) $(VFLAGS) -cc --exe --build -j \
	  -CFLAGS "-std=c++14 -O3 $(SIM_INC) -DENABLE_PERF -DF=$(F_VAL)" \
	  -LDFLAGS "$(SIM_LDFLAGS)" \
	  $(1) $(SIM_CPP) --Mdir $(2)
endef

$(BUILD)/opt/Vtop: $(OPT_RTL) $(SIM_CPP) Makefile
	@mkdir -p $(BUILD)/opt
	$(call VERILATE,$(OPT_RTL),$(BUILD)/opt)

$(BUILD)/base/Vtop: $(BASE_RTL) $(SIM_CPP) Makefile
	@mkdir -p $(BUILD)/base
	$(call VERILATE,$(BASE_RTL),$(BUILD)/base)

.PHONY: all sim-opt sim-base smoke-opt smoke-base synth-opt synth-base report clean help

all: sim-opt smoke-opt synth-opt report

help:
	@sed -n '2,20p' Makefile

sim-opt: $(BUILD)/opt/Vtop
	@mkdir -p $(RESULT)
	@$(BUILD)/opt/Vtop $(MICRO_BIN) -l $(RESULT)/sim-opt.log -e $(MICRO_ELF) -b \
	  > $(RESULT)/sim-opt.stdout 2>&1
	@echo "== sim-opt =="; grep -E "IPC=|HIT GOOD TRAP" $(RESULT)/sim-opt.stdout | tail -2

sim-base: $(BUILD)/base/Vtop
	@mkdir -p $(RESULT)
	@$(BUILD)/base/Vtop $(MICRO_BIN) -l $(RESULT)/sim-base.log -e $(MICRO_ELF) -b \
	  > $(RESULT)/sim-base.stdout 2>&1
	@echo "== sim-base =="; grep -E "IPC=|HIT GOOD TRAP" $(RESULT)/sim-base.stdout | tail -2

smoke-opt: $(BUILD)/opt/Vtop
	@$(MAKE) -C tests smoke
	@$(BUILD)/opt/Vtop tests/smoke.bin -b > $(RESULT)/smoke-opt.stdout 2>&1 || true
	@echo "== smoke-opt =="; grep -E "HIT|BAD|EBREAK" $(RESULT)/smoke-opt.stdout | tail -3

smoke-base: $(BUILD)/base/Vtop
	@$(MAKE) -C tests smoke
	@$(BUILD)/base/Vtop tests/smoke.bin -b > $(RESULT)/smoke-base.stdout 2>&1 || true
	@echo "== smoke-base =="; grep -E "HIT|BAD|EBREAK" $(RESULT)/smoke-base.stdout | tail -3

synth-opt:
	@$(MAKE) -C synth TAG=opt RTL_DIR=$(NPC)/vsrc

synth-base:
	@$(MAKE) -C synth TAG=base RTL_DIR=$(HERE)/rtl_baseline

report:
	@python3 scripts/report.py

clean:
	-rm -rf $(BUILD) $(RESULT) tests/smoke.elf tests/smoke.bin tests/smoke.o
