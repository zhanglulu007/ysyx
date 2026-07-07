PROJ_PATH := $(shell pwd)
SHELL := /bin/bash

# yosys-sta 项目路径
YOSYS_STA_HOME ?= $(HOME)/yosys-sta
YOSYS_STA_MAKE ?= $(MAKE) -C $(YOSYS_STA_HOME)

# 评估目标频率: 设成一个难以达到的高值, 让综合器尽力拉满 (B4.md L247)
CLK_FREQ_MHZ ?= 5000
CLK_PORT_NAME ?= clk

# 评估项目目录布局
EVAL_DIR := $(PROJ_PATH)/result

# ===== 寄存器堆评估 =====
REG_DESIGN   := RegisterFile_Synth
REG_RTL_FILES := $(PROJ_PATH)/RegisterFile_Synth.v
REG_RESULT_DIR := $(EVAL_DIR)/$(REG_DESIGN)-$(CLK_FREQ_MHZ)MHz
REG_TIMING_RPT := $(REG_RESULT_DIR)/$(REG_DESIGN).rpt

# ===== EXU评估 =====
EXU_DESIGN   := EXU_Synth
EXU_RTL_FILES := $(PROJ_PATH)/EXU_Synth.v
EXU_RESULT_DIR := $(EVAL_DIR)/$(EXU_DESIGN)-$(CLK_FREQ_MHZ)MHz
EXU_TIMING_RPT := $(EXU_RESULT_DIR)/$(EXU_DESIGN).rpt

# 调用 yosys-sta 的 sta 目标 (命令行传参方式, 见 yosys-sta README "评估其他设计")
# 该目标会自动依次完成 yosys 综合 + iSTA 时序分析
sta-reg:
	@mkdir -p $(EVAL_DIR)
	$(YOSYS_STA_MAKE) sta \
	  DESIGN=$(REG_DESIGN) \
	  SDC_FILE=$(YOSYS_STA_HOME)/scripts/default.sdc \
	  CLK_FREQ_MHZ=$(CLK_FREQ_MHZ) \
	  CLK_PORT_NAME=$(CLK_PORT_NAME) \
	  RTL_FILES="$(REG_RTL_FILES)" \
	  O=$(EVAL_DIR)
	@echo "========== 寄存器堆评估完成 =========="
	@echo "查看时序报告: $(REG_TIMING_RPT)"

sta-exu:
	@mkdir -p $(EVAL_DIR)
	$(YOSYS_STA_MAKE) sta \
	  DESIGN=$(EXU_DESIGN) \
	  SDC_FILE=$(YOSYS_STA_HOME)/scripts/default.sdc \
	  CLK_FREQ_MHZ=$(CLK_FREQ_MHZ) \
	  CLK_PORT_NAME=$(CLK_PORT_NAME) \
	  RTL_FILES="$(EXU_RTL_FILES)" \
	  O=$(EVAL_DIR)
	@echo "========== EXU评估完成 =========="
	@echo "查看时序报告: $(EXU_TIMING_RPT)"

sta-all: sta-reg sta-exu
	@echo "========== 所有部件评估完成 =========="
	@echo "寄存器堆报告: $(REG_TIMING_RPT)"
	@echo "EXU报告:     $(EXU_TIMING_RPT)"

clean:
	-rm -rf $(EVAL_DIR)

.PHONY: sta-reg sta-exu sta-all clean
