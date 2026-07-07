PROJ_PATH := $(shell pwd)
SHELL := /bin/bash

# yosys-sta 项目路径
YOSYS_STA_HOME ?= $(HOME)/yosys-sta

# NPC 源码目录 (vsrc)
NPC_VSRC ?= $(PROJ_PATH)/../../vsrc

# 评估目标频率 (B4.md L898: B 阶段流片面积限制 25000, 推荐此时不超过 23000)
CLK_FREQ_MHZ ?= 1200
# ysyx_26020070 的时钟端口名为 clock (ysyxSoC 接口规范)
CLK_PORT_NAME ?= clock

# 综合时需定义的宏: SYNTHESIS 屏蔽所有 DPI-C, 使 vsrc 可被直接综合
DEFINES ?= SYNTHESIS

# 顶层设计与 RTL 文件列表 (完整 AXI4 版本, 共 10 个模块)
DESIGN := ysyx_26020070
RTL_FILES := $(NPC_VSRC)/ysyx_26020070.v \
             $(NPC_VSRC)/IFU.v \
             $(NPC_VSRC)/IDU.v \
             $(NPC_VSRC)/EXU.v \
             $(NPC_VSRC)/LSU.v \
             $(NPC_VSRC)/WBU.v \
             $(NPC_VSRC)/RegisterFile.v \
             $(NPC_VSRC)/CSR.v \
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
