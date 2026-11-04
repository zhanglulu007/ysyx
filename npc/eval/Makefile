# 用法:
#   make check                  # 只解析/elaborate 整个层次 (最快, 先验证可综合)
#   make synth                  # 综合出网表 + 面积报告
#   make sta                    # 综合 + 时序/功耗分析 (结束后更新 ../config/f_cpu)
#   make update-f               # 从最近时序报告更新 ../config/f_cpu
#   make report                 # 输出三份报告：eval / CI current / CI old
#   make all                    # 并行跑三套评估，然后输出三份报告
#
# 参数覆盖 (任意目标均可):
#   make sta CLK_FREQ_MHZ=800         # 换时钟约束
#   make sta PDK=nangate45            # 换工艺库
#   make sta RTL_FILES="..."          # 换 RTL 文件集
#   make sta SDC_FILE=/path/design.sdc
#
# 结果写入 result/NPCSynth-<频率>MHz/ ; 建议提交前记录 report 的输出。

PROJ_PATH := $(abspath $(CURDIR))
SHELL := /bin/bash

YOSYS_STA_HOME ?= $(HOME)/yosys-sta
YOSYS_BIN ?= $(YOSYS_STA_HOME)/oss-cad-suite/bin/yosys
IEDA_BIN ?= $(YOSYS_STA_HOME)/bin/iEDA

# 当前核 RTL 源目录 (npc/vsrc); 本评估项目不修改源 RTL
NPC_VSRC ?= $(PROJ_PATH)/../vsrc

DESIGN := NPCSynth
PDK ?= nangate45
CLK_FREQ_MHZ ?= 500
CLK_PORT_NAME ?= clk
# SYNTHESIS: 走 top.v 的合成用存储模型, 排除全部 DPI-C
DEFINES ?= SYNTHESIS

# 综合范围 = CPU + 总线仲裁 (PMEM.v 是仿真 DPI-C 内存模型, SYNTHESIS 下不被
# 实例化; ysyx_26020070.v 是 SOC_MODE 专用的 SoC 顶层, 均不纳入)
RTL_FILES := $(PROJ_PATH)/NPCSynth.v \
             $(NPC_VSRC)/top.v \
             $(NPC_VSRC)/Core.v \
             $(NPC_VSRC)/ICache.v \
             $(NPC_VSRC)/LSU.v \
             $(NPC_VSRC)/Arbiter.v \
             $(NPC_VSRC)/CSR.v \
             $(NPC_VSRC)/RegisterFile.v

SDC_FILE ?= $(YOSYS_STA_HOME)/scripts/default.sdc

RESULT_DIR := $(PROJ_PATH)/result/$(DESIGN)-$(CLK_FREQ_MHZ)MHz
NETLIST := $(RESULT_DIR)/$(DESIGN).netlist.v
TIMING_RPT := $(RESULT_DIR)/$(DESIGN).rpt
AREA_RPT := $(RESULT_DIR)/synth_stat.txt

# 评估完成后回写到 npc/config/f_cpu（单位 10MHz）
F_CONFIG ?= $(abspath $(PROJ_PATH)/../config/f_cpu)

# ---------------------------------------------------------------------------
# B 阶段 CI 的两套面积评估流程
#
# CI 使用 yosys-sta 的 ci 分支，并在同一 RTL 上再跑一次
#   git revert 97fa7fcb80de4966c6f390af8df1b37d6d4c42c8
# 的旧版流程，防止设计只在某一版综合器中“碰巧”通过面积检查。
#
# 使用前先准备一个 ci 分支的 yosys-sta：
#   git clone -b ci https://github.com/OSCPU/yosys-sta ~/yosys-sta-ci
#   make -C ~/yosys-sta-ci init      # 若 ~/yosys-sta 已有 bin/pdk，可省略
#
# 然后：
#   make ci-area
# 结果在 ci-result/current 和 ci-result/old 下，面积取自 yosys-fixed.log。
# ci-init 首次准备后会写 .ci-ready，之后不会重复 fetch/reset；
# 需要主动更新 yosys-sta ci 时运行 make ci-update。
# ---------------------------------------------------------------------------
WORKBENCH_ROOT := $(abspath $(PROJ_PATH)/../..)
STUID ?= $(shell sed -n 's/^STUID = //p' $(WORKBENCH_ROOT)/Makefile | head -1)

CI_YOSYS_STA     ?= $(HOME)/yosys-sta-ci
CI_YOSYS_STA_BIN ?= $(HOME)/yosys-sta/bin
CI_YOSYS_STA_PDK ?= $(HOME)/yosys-sta/pdk
CI_RESULT        ?= $(PROJ_PATH)/ci-result
CI_VFILE         ?= $(WORKBENCH_ROOT)/npc/build/$(STUID).v
CI_OLD_COMMIT    := 97fa7fcb80de4966c6f390af8df1b37d6d4c42c8
CI_AREA_BUDGET   := 16500
CI_AREA_OLD_BUDGET := 25000
CI_CLK_FREQ_MHZ  := 500

# yosys.tcl / sta.tcl 从环境变量读取时钟与宏定义
export CLK_FREQ_MHZ CLK_PORT_NAME DEFINES

# 解析 + elaborate 整个层次, 不映射
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
	  $(IEDA_BIN) -script \
	  $(YOSYS_STA_HOME)/scripts/sta.tcl \
	  $(SDC_FILE) $(NETLIST) $(DESIGN) $(PDK) 2>&1 | tee sta.log
	@$(MAKE) --no-print-directory update-f

# 从时序报告解析最高可达频率，向下取整到 10MHz 后写入 npc/config/f_cpu
update-f:
	@if [ ! -f "$(TIMING_RPT)" ]; then \
	  echo "[F] $(TIMING_RPT) not found; keep $(F_CONFIG)"; \
	  exit 0; \
	fi; \
	freq=$$(awk -F'|' ' \
	  /core_clock/ && /\| max / { \
	    gsub(/ /,"",$$5); gsub(/ /,"",$$8); gsub(/ /,"",$$9); \
	    if ($$9 ~ /^[0-9.]+$$/ && (min=="" || $$9+0<min)) min=$$9+0; \
	  } \
	  END { if (min=="") exit 1; printf "%.3f", min }' "$(TIMING_RPT)" 2>/dev/null); \
	if [ -z "$$freq" ]; then \
	  echo "[F] cannot parse max frequency from $(TIMING_RPT); keep $(F_CONFIG)"; \
	  exit 0; \
	fi; \
	new_f=$$(awk -v f="$$freq" 'BEGIN { if (f <= 0) exit 1; printf "%d", f / 10 }') || { \
	  echo "[F] invalid frequency '$$freq'; keep $(F_CONFIG)"; exit 0; \
	}; \
	mkdir -p "$$(dirname "$(F_CONFIG)")"; \
	old=$$(cat "$(F_CONFIG)" 2>/dev/null || true); \
	printf '%s\n' "$$new_f" > "$(F_CONFIG)"; \
	if [ "$$old" = "$$new_f" ]; then \
	  echo "[F] $(F_CONFIG) = $$new_f (unchanged, from $$freq MHz)"; \
	else \
	  echo "[F] $(F_CONFIG): $${old:-<empty>} -> $$new_f (from $$freq MHz)"; \
	fi

# 从最近一次结果提取关键指标: 面积 / 可达频率 / WNS / 关键路径端点
report-eval:
	@echo "========== NPCSynth 评估摘要 (PDK=$(PDK), 约束=$(CLK_FREQ_MHZ)MHz) =========="
	@if [ -f "$(AREA_RPT)" ]; then \
	  echo "[面积]"; \
	  grep -E "Chip area for module|used for sequential elements" "$(AREA_RPT)" | sed 's/^[[:space:]]*/  /'; \
	  grep -E "^ +[0-9]+ +[0-9.E+-]+ +cells$$" "$(AREA_RPT)" | awk '{printf "  标准单元: %s 个, 单元面积合计 %s\n", $$1, $$2}'; \
	else \
	  echo "[面积] 未找到 $(AREA_RPT), 请先运行 make synth"; \
	fi
	@if [ -f "$(TIMING_RPT)" ]; then \
	  echo "[时序] 约束周期预算: $$(awk "BEGIN{printf \"%.4f\", 1000/$(CLK_FREQ_MHZ)}") ns"; \
	  awk -F'|' ' \
	    /core_clock/ && /\| max / { \
	      gsub(/ /,"",$$5); gsub(/ /,"",$$8); gsub(/ /,"",$$9); \
	      if ($$9 ~ /^[0-9.]+$$/ && (min=="" || $$9+0<min)) { min=$$9+0; wns=$$8; ep=$$2 } \
	    } \
	    END { \
	      if (min=="") { print "  未解析到 max 路径" } \
	      else { gsub(/^ +| +$$/,"",ep); printf "  最高可达频率: %.3f MHz\n", min; printf "  WNS(最差 slack): %s (等效周期 %.4f ns)\n", wns, 1000/min; printf "  关键路径终点: %s\n", ep } \
	    }' "$(TIMING_RPT)"; \
	  echo "  (完整时序表: $(TIMING_RPT))"; \
	else \
	  echo "[时序] 未找到 $(TIMING_RPT), 请先运行 make sta"; \
	fi
	@if [ -f "$(RESULT_DIR)/$(DESIGN).pwr" ]; then \
	  echo "[功耗]"; grep -E "Total|total" "$(RESULT_DIR)/$(DESIGN).pwr" | grep -iE "power|mW" | sed 's/^/  /'; \
	fi
	@echo "[F] config: $(F_CONFIG) = $$(cat "$(F_CONFIG)" 2>/dev/null || echo '<unset>')"
	@echo "=========================================================="

# 三份报告：eval / CI current / CI old
report: report-eval report-ci-current report-ci-old
	@echo "========== ALL THREE REPORTS DONE =========="

report-ci-current:
	@$(MAKE) --no-print-directory report-ci-dir \
	  CI_REPORT_DIR="$(CI_RESULT)/current" \
	  CI_REPORT_LABEL="CI current: yosys-sta ci, nangate45, 500MHz"

report-ci-old:
	@$(MAKE) --no-print-directory report-ci-dir \
	  CI_REPORT_DIR="$(CI_RESULT)/old" \
	  CI_REPORT_LABEL="CI old: yosys-sta ci + revert 97fa7fc, nangate45, 500MHz"

# 通用 CI 报告；CI_REPORT_DIR/CI_REPORT_LABEL 由上面的 target 传入
CI_REPORT_DIR ?= $(CI_RESULT)/current
CI_REPORT_LABEL ?= CI report

report-ci-dir:
	@echo "========== $(CI_REPORT_LABEL) =========="
	@log="$(CI_REPORT_DIR)/$(STUID)-$(CI_CLK_FREQ_MHZ)MHz/yosys-fixed.log"; \
	stat="$(CI_REPORT_DIR)/$(STUID)-$(CI_CLK_FREQ_MHZ)MHz/synth_stat_fixed.txt"; \
	rpt="$(CI_REPORT_DIR)/$(STUID)-$(CI_CLK_FREQ_MHZ)MHz/$(STUID).rpt"; \
	if [ -f "$$log" ]; then \
	  echo "[面积]"; \
	  grep -E "Chip area for module|used for sequential elements" "$$log" | sed 's/^[[:space:]]*/  /'; \
	elif [ -f "$$stat" ]; then \
	  echo "[面积]"; \
	  grep -E "Chip area for module|used for sequential elements" "$$stat" | sed 's/^[[:space:]]*/  /'; \
	else \
	  echo "[面积] 未找到 $$log / $$stat，请先运行对应 ci-sta 目标"; \
	fi; \
	if [ -f "$$rpt" ]; then \
	  echo "[时序]"; \
	  awk -F'|' ' \
	    /core_clock/ && /\| max / { \
	      gsub(/ /,"",$$5); gsub(/ /,"",$$8); gsub(/ /,"",$$9); \
	      if ($$9 ~ /^[0-9.]+$$/ && (min=="" || $$9+0<min)) { min=$$9+0; wns=$$8; ep=$$2 } \
	    } \
	    END { \
	      if (min=="") { print "  未解析到 max 路径" } \
	      else { gsub(/^ +| +$$/,"",ep); printf "  最高可达频率: %.3f MHz\n", min; printf "  WNS(最差 slack): %s (等效周期 %.4f ns)\n", wns, 1000/min; printf "  关键路径终点: %s\n", ep } \
	    }' "$$rpt"; \
	  echo "  (完整时序表: $$rpt)"; \
	else \
	  echo "[时序] 未找到 $$rpt"; \
	fi; \
	if [ -f "$$stat" ]; then \
	  echo "[单元统计]"; \
	  grep -E "Chip area for module|used for sequential elements" "$$stat" | sed 's/^[[:space:]]*/  /'; \
	fi
	@echo "=========================================================="

# 并行跑三套评估，再串行输出三份报告。
# CI 的 ci-init / ci-verilog / ci-old-src 必须先生成；之后
# sta（icsprout55 eval）、ci-sta-only、ci-sta-old-only 互不依赖，可以 -j3。
all:
	@$(MAKE) --no-print-directory clean
	@$(MAKE) --no-print-directory ci-clean
	@$(MAKE) --no-print-directory ci-prepare
	@$(MAKE) --no-print-directory -j3 sta ci-sta-only ci-sta-old-only
	@$(MAKE) --no-print-directory report

# ---------------------------------------------------------------------------
# CI 面积流程：当前 yosys-sta ci + 旧版（revert 97fa7fc）
# ---------------------------------------------------------------------------
# ci-init 只在第一次准备 yosys-sta ci 时执行；之后用 $(CI_READY) 跳过。
# 需要主动更新 yosys-sta ci 时运行：make ci-update
CI_READY := $(CI_YOSYS_STA)/.ci-ready

$(CI_READY):
	@if [ ! -d "$(CI_YOSYS_STA)/.git" ]; then \
	  echo "[ci] clone yosys-sta ci -> $(CI_YOSYS_STA)"; \
	  git clone -b ci https://github.com/OSCPU/yosys-sta "$(CI_YOSYS_STA)"; \
	fi
	@if [ "$$(git -C "$(CI_YOSYS_STA)" rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]; then \
	  echo "[ci] unshallow $(CI_YOSYS_STA)"; \
	  git -C "$(CI_YOSYS_STA)" fetch --unshallow; \
	fi
	@git -C "$(CI_YOSYS_STA)" fetch -q origin ci
	@git -C "$(CI_YOSYS_STA)" checkout -f -q ci
	@git -C "$(CI_YOSYS_STA)" reset --hard -q origin/ci
	@if [ ! -x "$(CI_YOSYS_STA)/bin/iEDA" ]; then \
	  if [ -x "$(CI_YOSYS_STA_BIN)/iEDA" ]; then \
	    rm -rf "$(CI_YOSYS_STA)/bin"; \
	    ln -s "$(CI_YOSYS_STA_BIN)" "$(CI_YOSYS_STA)/bin"; \
	  else \
	    $(MAKE) -C "$(CI_YOSYS_STA)" init; \
	  fi; \
	fi
	@if [ ! -d "$(CI_YOSYS_STA)/pdk/nangate45" ]; then \
	  if [ -d "$(CI_YOSYS_STA_PDK)/nangate45" ]; then \
	    rm -rf "$(CI_YOSYS_STA)/pdk"; \
	    ln -s "$(CI_YOSYS_STA_PDK)" "$(CI_YOSYS_STA)/pdk"; \
	  else \
	    $(MAKE) -C "$(CI_YOSYS_STA)" init; \
	  fi; \
	fi
	@test -x "$(CI_YOSYS_STA)/bin/iEDA" || { echo "missing $(CI_YOSYS_STA)/bin/iEDA"; exit 1; }
	@test -d "$(CI_YOSYS_STA)/pdk/nangate45" || { echo "missing $(CI_YOSYS_STA)/pdk/nangate45"; exit 1; }
	@touch "$(CI_READY)"
	@echo "[ci] yosys-sta ci is ready (skip next time)"

ci-init: $(CI_READY)
	@test -x "$(CI_YOSYS_STA)/bin/iEDA" && test -d "$(CI_YOSYS_STA)/pdk/nangate45" || { \
	  echo "[ci] ci tool incomplete, rebuilding"; \
	  rm -f "$(CI_READY)"; \
	  $(MAKE) --no-print-directory "$(CI_READY)"; \
	}

ci-update:
	@rm -f "$(CI_READY)"
	@$(MAKE) --no-print-directory "$(CI_READY)"

ci-verilog:
	$(MAKE) -C $(WORKBENCH_ROOT)/npc verilog

ci-prepare: ci-init ci-verilog ci-old-src

ci-sta-only:
	@mkdir -p $(CI_RESULT)/current
	$(MAKE) --no-print-directory -C $(CI_YOSYS_STA) sta \
	  DESIGN=$(STUID) CLK_FREQ_MHZ=$(CI_CLK_FREQ_MHZ) CLK_PORT_NAME=clock \
	  RTL_FILES=$(CI_VFILE) O=$(CI_RESULT)/current

ci-sta: ci-prepare
	@$(MAKE) --no-print-directory ci-sta-only

ci-old-src: ci-init
	@rm -rf $(CI_RESULT)/old-src
	-@git -C $(CI_YOSYS_STA) worktree remove --force $(CI_RESULT)/old-src >/dev/null 2>&1 || true
	@mkdir -p $(CI_RESULT)
	@git -C $(CI_YOSYS_STA) worktree add --detach $(CI_RESULT)/old-src origin/ci
	@ln -sfn $(CI_YOSYS_STA)/bin $(CI_RESULT)/old-src/bin
	@ln -sfn $(CI_YOSYS_STA)/pdk $(CI_RESULT)/old-src/pdk
	@git -C $(CI_RESULT)/old-src -c user.name=ysyx-ci -c user.email=ci@ysyx.org \
	  revert --no-edit $(CI_OLD_COMMIT)

ci-sta-old-only:
	@mkdir -p $(CI_RESULT)/old
	$(MAKE) --no-print-directory -C $(CI_RESULT)/old-src sta \
	  DESIGN=$(STUID) CLK_FREQ_MHZ=$(CI_CLK_FREQ_MHZ) CLK_PORT_NAME=clock \
	  RTL_FILES=$(CI_VFILE) O=$(CI_RESULT)/old

ci-sta-old: ci-prepare
	@$(MAKE) --no-print-directory ci-sta-old-only

ci-area: ci-sta ci-sta-old
	@set -e; \
	cur_log="$(CI_RESULT)/current/$(STUID)-$(CI_CLK_FREQ_MHZ)MHz/yosys-fixed.log"; \
	old_log="$(CI_RESULT)/old/$(STUID)-$(CI_CLK_FREQ_MHZ)MHz/yosys-fixed.log"; \
	cur=$$(grep -o "Chip area for module .*: [0-9.]*" "$$cur_log" | sed 's/.*: //' | tail -1); \
	old=$$(grep -o "Chip area for module .*: [0-9.]*" "$$old_log" | sed 's/.*: //' | tail -1); \
	if [ -z "$$cur" ] || [ -z "$$old" ]; then \
	  echo "cannot parse area: current='$$cur' old='$$old'"; exit 1; \
	fi; \
	echo "========== B-stage CI area check =========="; \
	echo "  current yosys-sta ci : $$cur"; \
	echo "  old  (revert 97fa7fc): $$old"; \
	echo "  budgets              : current $(CI_AREA_BUDGET), old $(CI_AREA_OLD_BUDGET)"; \
	if [ $$(awk "BEGIN {print ($$cur > $(CI_AREA_BUDGET))}") -eq 1 ] && \
	   [ $$(awk "BEGIN {print ($$old > $(CI_AREA_OLD_BUDGET))}") -eq 1 ]; then \
	  echo "  CI AREA CHECK: FAIL"; exit 1; \
	else \
	  echo "  CI AREA CHECK: PASS"; \
	fi

ci-clean:
	-rm -rf $(CI_RESULT)
	-@git -C $(CI_YOSYS_STA) worktree prune >/dev/null 2>&1 || true

clean:
	-rm -rf $(PROJ_PATH)/result

.PHONY: check synth sta update-f report report-eval report-ci-current report-ci-old report-ci-dir all clean \
	ci-init ci-update ci-verilog ci-prepare ci-sta-only ci-sta ci-old-src ci-sta-old-only ci-sta-old ci-area ci-clean
