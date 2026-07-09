include $(AM_HOME)/scripts/isa/riscv.mk
include $(AM_HOME)/scripts/platform/ysyxsoc.mk

# 与 riscv32e-ysyxsoc 一致: 真实 SoC 无 M 扩展, 用 libgcc 软件乘除法
COMMON_CFLAGS += -march=rv32e_zicsr -mabi=ilp32e
LDFLAGS       += -melf32lriscv
AM_SRCS += riscv/npc/libgcc/div.S \
           riscv/npc/libgcc/muldi3.S \
           riscv/npc/libgcc/multi3.c \
           riscv/npc/libgcc/ashldi3.c \
           riscv/npc/libgcc/unused.c

# ---------------------------------------------------------------------------- #
# cachesim 评估参数 (可由命令行覆盖, 便于设计空间探索批量评估)
# ---------------------------------------------------------------------------- #
CACHESIM_WAYS         ?= 1        # 组相联路数 (1=直接映射)
CACHESIM_BLOCK        ?= 4        # 块大小 (字节)
CACHESIM_TOTAL        ?= 16       # cache 块总数
CACHESIM_REPLACE      ?= lru      # 替换算法: lru | random
CACHESIM_MISS_PENALTY ?= 100      # 单次缺失代价 (周期)
CACHESIM_ACCESS_TIME  ?= 1        # 命中访问时间 (周期)

# ---------------------------------------------------------------------------- #
# NEMU_HOME / NPC_HOME 默认推导 (若环境未导出, 则从 AM_HOME 推断, 保证可运行)
# ---------------------------------------------------------------------------- #
NEMU_HOME ?= $(abspath $(AM_HOME)/../nemu)
NPC_HOME  ?= $(abspath $(AM_HOME)/../npc)

NEMU_BIN  := $(NEMU_HOME)/build/riscv32-nemu-interpreter
NEMU_LOG  := $(IMAGE).itrace.log
ITRACE    := $(IMAGE).itrace.bin

run: insert-arg
	@echo "=================================================================="
	@echo " [cachesim] 步骤 1/3: 用 ysyxsoc 配置的 NEMU 生成二进制 RLE itrace"
	@echo "=================================================================="
	@echo ">> 配置 NEMU 为 riscv32-ysyxsoc (复位PC=0x30000000, CLINT/UART16550)"
	@$(MAKE) -s -C $(NEMU_HOME) riscv32-ysyxsoc_defconfig
	@echo ">> 编译 NEMU"
	@$(MAKE) -s -C $(NEMU_HOME)
	@echo ">> NEMU 运行镜像, 生成二进制 RLE itrace: $(ITRACE)"
	@echo "   镜像: $(IMAGE).bin  (文本日志: $(NEMU_LOG))"
	@# 在 NEMU_HOME 下运行: NEMU 用相对路径 dlopen("tools/capstone/repo/libcapstone.so.5")
	@cd $(NEMU_HOME) && $(NEMU_BIN) -b -l $(NEMU_LOG) $(IMAGE).bin
	@echo "   二进制 RLE trace 大小:" $$(ls -lh $(ITRACE) | awk '{print $$5}')
	@echo ""
	@echo "=================================================================="
	@echo " [cachesim] 步骤 2/3: cachesim 评估 (配置: ways=$(CACHESIM_WAYS) block=$(CACHESIM_BLOCK)B total=$(CACHESIM_TOTAL) replace=$(CACHESIM_REPLACE))"
	@echo "=================================================================="
	@$(MAKE) -s -C $(NPC_HOME)/cachesim run \
	  ITRACE=$(ITRACE) \
	  ARGS="--ways=$(CACHESIM_WAYS) --block=$(CACHESIM_BLOCK) --total=$(CACHESIM_TOTAL) --replace=$(CACHESIM_REPLACE) --miss-penalty=$(CACHESIM_MISS_PENALTY) --access-time=$(CACHESIM_ACCESS_TIME)"
	@echo ""
	@echo " [cachesim] 完成. 欲探索其他参数组合, 例如:"
	@echo "   make ARCH=riscv32e-cachesim run CACHESIM_WAYS=2 CACHESIM_BLOCK=16 CACHESIM_TOTAL=64"
	@echo "=================================================================="

.PHONY: run
