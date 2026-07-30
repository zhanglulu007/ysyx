PROJ_PATH := $(abspath $(CURDIR))
SHELL := /bin/bash

YOSYS_STA_HOME ?= $(HOME)/yosys-sta
YOSYS_BIN ?= $(YOSYS_STA_HOME)/oss-cad-suite/bin/yosys
NPC_VSRC ?= $(PROJ_PATH)/../../rtl-standalone/vsrc

DESIGN := RTLStandalone_Synth
PDK ?= icsprout55
CLK_FREQ_MHZ ?= 1200
CLK_PORT_NAME ?= clk
DEFINES ?= SYNTHESIS

RTL_FILES := $(PROJ_PATH)/RTLStandalone_Synth.v \
             $(NPC_VSRC)/top.v \
             $(NPC_VSRC)/Arbiter.v \
             $(NPC_VSRC)/CLINT.v \
             $(NPC_VSRC)/CSR.v \
             $(NPC_VSRC)/EXU.v \
             $(NPC_VSRC)/IFU.v \
             $(NPC_VSRC)/IDU.v \
             $(NPC_VSRC)/LSU.v \
             $(NPC_VSRC)/RegisterFile.v \
             $(NPC_VSRC)/WBU.v

SDC_FILE ?= $(YOSYS_STA_HOME)/scripts/default.sdc
RESULT_DIR := $(PROJ_PATH)/result/$(DESIGN)-$(CLK_FREQ_MHZ)MHz
NETLIST := $(RESULT_DIR)/$(DESIGN).netlist.v
TIMING_RPT := $(RESULT_DIR)/$(DESIGN).rpt
AREA_RPT := $(RESULT_DIR)/synth_stat.txt

export CLK_FREQ_MHZ CLK_PORT_NAME DEFINES

check:
	$(YOSYS_BIN) -p 'read_verilog -sv -D$(DEFINES) $(RTL_FILES); hierarchy -check -top $(DESIGN); check'

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
	@echo "Area report: $(AREA_RPT)"

clean:
	-rm -rf $(PROJ_PATH)/result

.PHONY: check synth sta clean
