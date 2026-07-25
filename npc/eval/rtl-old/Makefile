PROJ_PATH := $(abspath $(CURDIR))
SHELL := /bin/bash

YOSYS_STA_HOME ?= $(HOME)/yosys-sta
RTL_DIR := $(PROJ_PATH)/../../rtl-old/vsrc
DESIGN := RTLOld_Synth
PDK := icsprout55
CLK_FREQ_MHZ ?= 1200
override CLK_PORT_NAME := clk
override DEFINES := SYNTHESIS

RTL_FILES := $(PROJ_PATH)/RTLOld_Synth.v \
             $(PROJ_PATH)/IFU_Synth.v \
             $(RTL_DIR)/IDU.v \
             $(PROJ_PATH)/RegisterFile_Synth.v \
             $(RTL_DIR)/EXU.v \
             $(RTL_DIR)/CSR.v \
             $(RTL_DIR)/LSU.v \
             $(RTL_DIR)/WBU.v \
             $(RTL_DIR)/AXIArbiter.v

SDC_FILE ?= $(YOSYS_STA_HOME)/scripts/default.sdc
RESULT_DIR := $(PROJ_PATH)/result/$(DESIGN)-$(CLK_FREQ_MHZ)MHz
NETLIST := $(RESULT_DIR)/$(DESIGN).netlist.v
TIMING_RPT := $(RESULT_DIR)/$(DESIGN).rpt
YOSYS_BIN ?= $(YOSYS_STA_HOME)/oss-cad-suite/bin/yosys

export CLK_FREQ_MHZ CLK_PORT_NAME DEFINES

check:
	$(YOSYS_BIN) -p 'read_verilog -sv -DSYNTHESIS $(RTL_FILES); hierarchy -check -top $(DESIGN); check'

synth: $(NETLIST)

$(NETLIST): $(RTL_FILES) $(YOSYS_STA_HOME)/scripts/yosys.tcl
	@mkdir -p $(RESULT_DIR)
	echo tcl $(YOSYS_STA_HOME)/scripts/yosys.tcl $(DESIGN) $(PDK) \"$(RTL_FILES)\" $@ | \
	  $(YOSYS_BIN) -g -l $(RESULT_DIR)/yosys.log -s -

sta: synth
	@cd $(RESULT_DIR) && set -o pipefail && \
	  $(YOSYS_STA_HOME)/bin/iEDA -script \
	  $(YOSYS_STA_HOME)/scripts/sta.tcl \
	  $(SDC_FILE) $(NETLIST) $(DESIGN) $(PDK) 2>&1 | tee sta.log
	@echo "Timing report: $(TIMING_RPT)"

clean:
	-rm -rf $(PROJ_PATH)/result

.PHONY: check synth sta clean
