PROJ_PATH := $(shell pwd)
SHELL := /bin/bash
YOSYS_STA_HOME ?= $(HOME)/yosys-sta
CLK_FREQ_MHZ ?= 1000
CLK_PORT_NAME ?= clk
VARIANT ?= assign

ifeq ($(VARIANT),assign)
  IDU_SRC := $(PROJ_PATH)/../../vsrc/IDU.v
  DEFINES := SYNTHESIS
else ifeq ($(VARIANT),grouped)
  IDU_SRC := $(PROJ_PATH)/../../vsrc/IDU_grouped.v
  DEFINES := SYNTHESIS IDU_IMPL_GROUPED
else ifeq ($(VARIANT),classified)
  IDU_SRC := $(PROJ_PATH)/../../vsrc/IDU_classified.v
  DEFINES := SYNTHESIS IDU_IMPL_CLASSIFIED
else ifeq ($(VARIANT),casez)
  IDU_SRC := $(PROJ_PATH)/../../vsrc/IDU_casez.v
  DEFINES := SYNTHESIS IDU_IMPL_CASEZ
else
  $(error Unknown VARIANT='$(VARIANT)'; use assign, classified, grouped, or casez)
endif

DESIGN := IDU_Eval
RESULT_DIR := $(PROJ_PATH)/result/$(VARIANT)/$(DESIGN)-$(CLK_FREQ_MHZ)MHz
TIMING_RPT := $(RESULT_DIR)/$(DESIGN).rpt
AREA_RPT := $(RESULT_DIR)/synth_stat.txt
RTL_FILES := $(PROJ_PATH)/IDU_Eval.v $(IDU_SRC)

sta:
	@mkdir -p $(PROJ_PATH)/result
	$(MAKE) -C $(YOSYS_STA_HOME) sta \
	  DESIGN=$(DESIGN) \
	  SDC_FILE=$(YOSYS_STA_HOME)/scripts/default.sdc \
	  CLK_FREQ_MHZ=$(CLK_FREQ_MHZ) \
	  CLK_PORT_NAME=$(CLK_PORT_NAME) \
	  RTL_FILES="$(RTL_FILES)" \
	  DEFINES="$(DEFINES)" \
	  O=$(PROJ_PATH)/result/$(VARIANT)

all:
#	$(MAKE) VARIANT=assign sta
	$(MAKE) VARIANT=classified sta
#	$(MAKE) VARIANT=grouped sta
#	$(MAKE) VARIANT=casez sta

test:
	iverilog -g2012 -s idu_tb -o /tmp/idu_tb.vvp \
	  $(PROJ_PATH)/idu_tb.v \
	  $(PROJ_PATH)/../../vsrc/IDU.v \
	  $(PROJ_PATH)/../../vsrc/IDU_classified.v \
	  $(PROJ_PATH)/../../vsrc/IDU_grouped.v \
	  $(PROJ_PATH)/../../vsrc/IDU_casez.v
	vvp /tmp/idu_tb.vvp

clean:
	-rm -rf $(PROJ_PATH)/result

.PHONY: sta all test clean
