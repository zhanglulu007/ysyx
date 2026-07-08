######################################################################################
# ARCH=riscv32e-cachesim
#
# 构建与 riscv32e-ysyxsoc 完全相同的镜像 (同样的链接脚本/源码/-march), 但 run 目标
# 不跑 NPC, 而是:
#   1. 用 riscv32-ysyxsoc 配置的 NEMU 跑该镜像, 生成完整 itrace (PC 序列)
#   2. 调用 npc/cachesim 对该 itrace 评估 icache 缺失次数 / AMAT / TMT
#
# 设计依据: B4.md "实现 cachesim" (讲义 768-793 行):
#   - 给定 PC 序列, cache 的缺失次数与访存内容无关, 只需维护元数据即可统计.
#   - NEMU 生成 PC 序列的速度远高于 ysyxSoC 仿真, 适合设计空间探索.
#
# 可配置参数 (覆盖默认值即可, 便于批量评估):
#   CACHESIM_WAYS, CACHESIM_BLOCK, CACHESIM_TOTAL, CACHESIM_REPLACE,
#   CACHESIM_MISS_PENALTY, CACHESIM_ACCESS_TIME
#
# 用法:
#   make ARCH=riscv32e-cachesim run mainargs=test
#   make ARCH=riscv32e-cachesim run mainargs=test \
#       CACHESIM_WAYS=2 CACHESIM_BLOCK=16 CACHESIM_TOTAL=64
######################################################################################

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

NEMU_BIN := $(NEMU_HOME)/build/riscv32-nemu-interpreter
ITRACE   := $(IMAGE).itrace.txt

# ---------------------------------------------------------------------------- #
# run 目标: NEMU 生成 itrace -> cachesim 评估
#
# 覆盖 ysyxsoc.mk 中的 run 目标 (它原本是跑 NPC). 这里改为:
#   1. 确保 NEMU 用 riscv32-ysyxsoc 配置编译 (复位PC=0x30000000, 启用 CLINT/UART16550)
#   2. NEMU 以 batch 模式运行镜像, -l 输出完整 itrace 到 $(ITRACE)
#   3. npc/cachesim 对 itrace 评估
# ---------------------------------------------------------------------------- #
run: insert-arg
	@echo "=================================================================="
	@echo " [cachesim] 步骤 1/3: 用 ysyxsoc 配置的 NEMU 生成 itrace"
	@echo "=================================================================="
	@echo ">> 配置 NEMU 为 riscv32-ysyxsoc (复位PC=0x30000000, CLINT/UART16550)"
	@$(MAKE) -s -C $(NEMU_HOME) riscv32-ysyxsoc_defconfig
	@echo ">> 编译 NEMU"
	@$(MAKE) -s -C $(NEMU_HOME)
	@echo ">> NEMU 运行镜像并输出 itrace 到 $(ITRACE)"
	@echo "   镜像: $(IMAGE).bin"
	@$(NEMU_BIN) -b -l $(ITRACE) $(IMAGE).bin
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
