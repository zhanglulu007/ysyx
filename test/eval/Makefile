SHELL := /bin/bash
# ============================================================================
#  test/eval - 优化前后 NPC 的同口径综合/时序/面积评估
#
#  用法:
#    make check                     # 只 elaborate
#    make all VARIANT=opt            # 优化版综合+STA+摘要
#    make all VARIANT=base           # 基线 (npc/vsrc 拷贝) 综合+STA+摘要
#    make sta VARIANT=opt PDK=icsprout55 CLK_FREQ_MHZ=1200
#    make report VARIANT=opt
#
#  与 npc/eval 的区别: 结果写到 test/eval/result, 不回写 npc/config.
# ============================================================================
PROJ_PATH := $(abspath $(CURDIR))
TEST_ROOT := $(abspath $(PROJ_PATH)/..)

YOSYS_STA_HOME ?= $(HOME)/yosys-sta
YOSYS_BIN ?= $(YOSYS_STA_HOME)/oss-cad-suite/bin/yosys
IEDA_BIN  ?= $(YOSYS_STA_HOME)/bin/iEDA

VARIANT ?= opt
ifeq ($(VARIANT),base)
  RTL_DIR := $(TEST_ROOT)/baseline_rtl
  RTL_FILES := $(PROJ_PATH)/NPCSynth.v \
               $(RTL_DIR)/top.v $(RTL_DIR)/Arbiter.v $(RTL_DIR)/CSR.v \
               $(RTL_DIR)/EXU.v $(RTL_DIR)/ICache.v $(RTL_DIR)/IDU.v \
               $(RTL_DIR)/IFU.v $(RTL_DIR)/LSU.v $(RTL_DIR)/RegisterFile.v \
               $(RTL_DIR)/WBU.v
else ifeq ($(VARIANT),pipe3)
  RTL_DIR := $(TEST_ROOT)/rtl_pipe3
  RTL_FILES := $(PROJ_PATH)/NPCSynth.v \
               $(RTL_DIR)/top.v $(RTL_DIR)/alu.v $(RTL_DIR)/arbiter.v \
               $(RTL_DIR)/csr.v $(RTL_DIR)/icache.v $(RTL_DIR)/idu.v \
               $(RTL_DIR)/ifu.v $(RTL_DIR)/lsu.v $(RTL_DIR)/register_file.v
else
  RTL_DIR := $(TEST_ROOT)/rtl
  RTL_FILES := $(PROJ_PATH)/NPCSynth.v \
               $(RTL_DIR)/top.v $(RTL_DIR)/arbiter.v $(RTL_DIR)/csr.v \
               $(RTL_DIR)/exu.v $(RTL_DIR)/icache.v $(RTL_DIR)/idu.v \
               $(RTL_DIR)/ifu.v $(RTL_DIR)/lsu.v $(RTL_DIR)/register_file.v
endif

DESIGN := NPCSynth
PDK ?= icsprout55
CLK_FREQ_MHZ ?= 1200
CLK_PORT_NAME ?= clk
DEFINES ?= SYNTHESIS

SDC_FILE ?= $(YOSYS_STA_HOME)/scripts/default.sdc

RESULT_DIR := $(PROJ_PATH)/result/$(DESIGN)-$(VARIANT)-$(CLK_FREQ_MHZ)MHz
NETLIST    := $(RESULT_DIR)/$(DESIGN).netlist.v
TIMING_RPT := $(RESULT_DIR)/$(DESIGN).rpt
AREA_RPT   := $(RESULT_DIR)/synth_stat.txt

export CLK_FREQ_MHZ CLK_PORT_NAME DEFINES

check:
	$(YOSYS_BIN) -p 'read_verilog -sv $(addprefix -D,$(DEFINES)) $(RTL_FILES); hierarchy -check -top $(DESIGN); check'

synth: $(NETLIST)

$(NETLIST): $(RTL_FILES) $(YOSYS_STA_HOME)/scripts/yosys.tcl
	@mkdir -p $(RESULT_DIR)
	echo tcl $(YOSYS_STA_HOME)/scripts/yosys.tcl $(DESIGN) $(PDK) \"$(RTL_FILES)\" $@ | \
	  $(YOSYS_BIN) -g -l $(RESULT_DIR)/yosys.log -s -
	@if grep -q 'multiple conflicting drivers' $(RESULT_DIR)/yosys.log; then \
	  echo "Error: multiple conflicting drivers detected; see $(RESULT_DIR)/yosys.log"; \
	  exit 1; \
	fi

sta: synth
	@cd $(RESULT_DIR) && set -o pipefail && \
	  $(IEDA_BIN) -script $(YOSYS_STA_HOME)/scripts/sta.tcl \
	  $(SDC_FILE) $(NETLIST) $(DESIGN) $(PDK) 2>&1 | tee sta.log

report:
	@echo "========== NPCSynth $(VARIANT) (PDK=$(PDK), 约束=$(CLK_FREQ_MHZ)MHz) =========="
	@if [ -f "$(AREA_RPT)" ]; then \
	  echo "[面积]"; \
	  grep -E "Chip area for module|used for sequential elements" "$(AREA_RPT)" | sed 's/^[[:space:]]*/  /'; \
	  grep -E "^ +[0-9]+ +[0-9.E+-]+ +cells$$" "$(AREA_RPT)" | awk '{printf "  标准单元: %s 个, 单元面积合计 %s\n", $$1, $$2}'; \
	else echo "[面积] 未找到 $(AREA_RPT)"; fi
	@if [ -f "$(TIMING_RPT)" ]; then \
	  echo "[时序]"; \
	  awk -F'|' ' \
	    /core_clock/ && /\| max / { \
	      gsub(/ /,"",$$5); gsub(/ /,"",$$8); gsub(/ /,"",$$9); \
	      if ($$9 ~ /^[0-9.]+$$/ && (min=="" || $$9+0<min)) { min=$$9+0; wns=$$8; ep=$$2 } \
	    } \
	    END { \
	      if (min=="") print "  未解析到 max 路径"; \
	      else { gsub(/^ +| +$$/,"",ep); printf "  最高可达频率: %.3f MHz\n", min; printf "  WNS: %s (周期 %.4f ns)\n", wns, 1000/min; printf "  关键路径终点: %s\n", ep } \
	    }' "$(TIMING_RPT)"; \
	else echo "[时序] 未找到 $(TIMING_RPT)"; fi
	@echo "=========================================================="

all: sta report

clean:
	rm -rf $(PROJ_PATH)/result

.PHONY: check synth sta report all clean
