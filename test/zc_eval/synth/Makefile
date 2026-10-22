# ============================================================================
# 综合/STA 子工程: 读取 RTL_DIR, 产出 area / freq
#
#   make -C synth TAG=opt  RTL_DIR=/path/to/rtl
#   make -C synth TAG=base RTL_DIR=/path/to/baseline
# ============================================================================
PROJ := $(abspath $(CURDIR))
SHELL := /bin/bash

YOSYS_STA_HOME ?= $(HOME)/yosys-sta
YOSYS_BIN ?= $(YOSYS_STA_HOME)/oss-cad-suite/bin/yosys
IEDA_BIN ?= $(YOSYS_STA_HOME)/bin/iEDA

TAG ?= opt
RTL_DIR ?= $(abspath $(PROJ)/../../../npc/vsrc)
DESIGN := NPCSynth
PDK ?= icsprout55
CLK_FREQ_MHZ ?= 1200
CLK_PORT_NAME ?= clk
DEFINES ?= SYNTHESIS

RTL_FILES := $(PROJ)/NPCSynth.v \
             $(RTL_DIR)/top.v \
             $(RTL_DIR)/Arbiter.v \
             $(RTL_DIR)/CSR.v \
             $(RTL_DIR)/EXU.v \
             $(RTL_DIR)/ICache.v \
             $(RTL_DIR)/IDU.v \
             $(RTL_DIR)/IFU.v \
             $(RTL_DIR)/LSU.v \
             $(RTL_DIR)/RegisterFile.v \
             $(RTL_DIR)/WBU.v

SDC_FILE ?= $(YOSYS_STA_HOME)/scripts/default.sdc

RESULT_DIR := $(PROJ)/../result/synth-$(TAG)
NETLIST := $(RESULT_DIR)/$(DESIGN).netlist.v
TIMING_RPT := $(RESULT_DIR)/$(DESIGN).rpt
AREA_RPT := $(RESULT_DIR)/synth_stat.txt

export CLK_FREQ_MHZ CLK_PORT_NAME DEFINES

.PHONY: all synth sta report clean

all: sta report

synth: $(NETLIST)

$(NETLIST): $(RTL_FILES) $(YOSYS_STA_HOME)/scripts/yosys.tcl
	@mkdir -p $(RESULT_DIR)
	echo tcl $(YOSYS_STA_HOME)/scripts/yosys.tcl $(DESIGN) $(PDK) \"$(RTL_FILES)\" $@ | \
	  $(YOSYS_BIN) -g -l $(RESULT_DIR)/yosys.log -s -
	@if grep -q 'multiple conflicting drivers' $(RESULT_DIR)/yosys.log; then \
	  echo "Error: multiple conflicting drivers"; exit 1; fi

sta: synth
	@cd $(RESULT_DIR) && set -o pipefail && \
	  $(IEDA_BIN) -script \
	  $(YOSYS_STA_HOME)/scripts/sta.tcl \
	  $(SDC_FILE) $(NETLIST) $(DESIGN) $(PDK) 2>&1 | tee sta.log

report:
	@python3 $(PROJ)/../scripts/synth_report.py $(TAG) $(RESULT_DIR)

clean:
	-rm -rf $(RESULT_DIR)
