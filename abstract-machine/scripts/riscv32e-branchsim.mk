include $(AM_HOME)/scripts/isa/riscv.mk
include $(AM_HOME)/scripts/platform/ysyxsoc.mk

COMMON_CFLAGS += -march=rv32e_zicsr -mabi=ilp32e
LDFLAGS       += -melf32lriscv
AM_SRCS += riscv/npc/libgcc/div.S \
           riscv/npc/libgcc/muldi3.S \
           riscv/npc/libgcc/multi3.c \
           riscv/npc/libgcc/ashldi3.c \
           riscv/npc/libgcc/unused.c

BRANCHSIM_PREDICTOR          ?= all
BRANCHSIM_MISPREDICT_PENALTY ?= 2
BRANCHSIM_BTB_ENTRIES        ?= 8
BRANCHSIM_EXTRA_ARGS         ?=

NEMU_HOME ?= $(abspath $(AM_HOME)/../nemu)
NPC_HOME  ?= $(abspath $(AM_HOME)/../npc)

NEMU_BIN  := $(NEMU_HOME)/build/riscv32-nemu-interpreter
NEMU_LOG  := $(IMAGE).branchsim.log
BTRACE    := $(IMAGE).branchsim.btrace

run: insert-arg
	@echo "=================================================================="
	@echo " [branchsim] Step 1/2: generate a conditional-branch btrace"
	@echo "=================================================================="
	@$(MAKE) -s -C $(NEMU_HOME) riscv32-ysyxsoc_defconfig
	@$(MAKE) -s -C $(NEMU_HOME)
	@cd $(NEMU_HOME) && $(NEMU_BIN) -b -l $(NEMU_LOG) $(IMAGE).bin
	@test -f $(BTRACE)
	@echo "   btrace: $(BTRACE)"
	@echo ""
	@echo "=================================================================="
	@echo " [branchsim] Step 2/2: evaluate static branch predictors"
	@echo "=================================================================="
	@$(MAKE) -s -C $(NPC_HOME)/branchsim run \
	  BTRACE=$(BTRACE) \
	  ARGS="--predictor=$(BRANCHSIM_PREDICTOR) --mispredict-penalty=$(BRANCHSIM_MISPREDICT_PENALTY) --btb-entries=$(BRANCHSIM_BTB_ENTRIES) $(BRANCHSIM_EXTRA_ARGS)"
	@echo ""
	@echo " [branchsim] Done. Example:"
	@echo "   make ARCH=riscv32e-branchsim run BRANCHSIM_PREDICTOR=btfn BRANCHSIM_BTB_ENTRIES=8"
	@echo "=================================================================="

.PHONY: run
