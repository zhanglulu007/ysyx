PROJ_PATH := $(shell pwd)
SHELL := /bin/bash

YOSYS_STA_HOME ?= $(HOME)/yosys-sta

NPC_VSRC ?= $(PROJ_PATH)/../../vsrc

CLK_FREQ_MHZ ?= 1200

CLK_PORT_NAME ?= clock

DEFINES ?= SYNTHESIS

DESIGN := ysyx_26020070
RTL_FILES := $(NPC_VSRC)/ysyx_26020070.v \
             $(NPC_VSRC)/PipelineCore.v \
             $(NPC_VSRC)/RegisterFile.v \
             $(NPC_VSRC)/CSR.v \
             $(NPC_VSRC)/LSU.v \
             $(NPC_VSRC)/ICache.v \
             $(NPC_VSRC)/CLINT.v \
             $(NPC_VSRC)/AXIArbiter.v

RESULT_DIR := $(PROJ_PATH)/result/$(DESIGN)-$(CLK_FREQ_MHZ)MHz
TIMING_RPT := $(RESULT_DIR)/$(DESIGN).rpt
AREA_RPT   := $(RESULT_DIR)/synth_stat.txt

# 调用 yosys-sta 的 sta 目标 (yosys 综合 + iSTA 时序分析 + iPA 功耗分析)
sta:
	@mkdir -p $(PROJ_PATH)/result
	$(MAKE) -C $(YOSYS_STA_HOME) sta \
	  DESIGN=$(DESIGN) \
	  SDC_FILE=$(YOSYS_STA_HOME)/scripts/default.sdc \
	  CLK_FREQ_MHZ=$(CLK_FREQ_MHZ) \
	  CLK_PORT_NAME=$(CLK_PORT_NAME) \
	  RTL_FILES="$(RTL_FILES)" \
	  DEFINES="$(DEFINES)" \
	  O=$(PROJ_PATH)/result
	@echo "========== NPC 整体综合评估完成 =========="
	@echo "时序报告: $(TIMING_RPT)"
	@echo "面积报告: $(AREA_RPT)"
	@echo "综合日志: $(RESULT_DIR)/yosys.log"

clean:
	-rm -rf $(PROJ_PATH)/result

.PHONY: sta clean
