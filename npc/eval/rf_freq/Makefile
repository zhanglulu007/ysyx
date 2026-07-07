PROJ_PATH := $(shell pwd)
SHELL := /bin/bash

# yosys-sta 项目路径
YOSYS_STA_HOME ?= $(HOME)/yosys-sta

# 评估目标频率: 设成难以达到的高值 (B4.md L247)
CLK_FREQ_MHZ ?= 5000
CLK_PORT_NAME ?= clk

DESIGN   := RegisterFile_Synth
RTL_FILES := $(PROJ_PATH)/RegisterFile_Synth.v
RESULT_DIR := $(PROJ_PATH)/result/$(DESIGN)-$(CLK_FREQ_MHZ)MHz
TIMING_RPT := $(RESULT_DIR)/$(DESIGN).rpt

# 调用 yosys-sta 的 sta 目标 (yosys 综合 + iSTA 时序分析)
sta:
	@mkdir -p $(PROJ_PATH)/result
	$(MAKE) -C $(YOSYS_STA_HOME) sta \
	  DESIGN=$(DESIGN) \
	  SDC_FILE=$(YOSYS_STA_HOME)/scripts/default.sdc \
	  CLK_FREQ_MHZ=$(CLK_FREQ_MHZ) \
	  CLK_PORT_NAME=$(CLK_PORT_NAME) \
	  RTL_FILES="$(RTL_FILES)" \
	  O=$(PROJ_PATH)/result
	@echo "========== 寄存器堆评估完成 =========="
	@echo "时序报告: $(TIMING_RPT)"

clean:
	-rm -rf $(PROJ_PATH)/result

.PHONY: sta clean
