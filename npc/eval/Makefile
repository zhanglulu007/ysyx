# NPC 综合评估统一入口
# 子目录说明:
#   rf_freq/  - 寄存器堆最大频率评估 (B4.md "寻找最高的综合频率")
#   exu_freq/ - EXU/ALU 加法器关键路径最大频率评估
#   npc/      - NPC 处理器整体综合评估 (直接引用 vsrc, B4.md "记录性能数据")
#
# 使用方法:
#   make rf          # 评估寄存器堆
#   make exu         # 评估 EXU
#   make npc         # 评估整体 NPC (默认 1200MHz)
#   make all         # 评估全部
#   make npc CLK_FREQ_MHZ=1500   # 指定频率

PROJ_PATH := $(shell pwd)

rf:
	$(MAKE) -C $(PROJ_PATH)/rf_freq sta

exu:
	$(MAKE) -C $(PROJ_PATH)/exu_freq sta

npc:
	$(MAKE) -C $(PROJ_PATH)/npc sta

all: rf exu npc
	@echo "========== 所有评估完成 =========="

clean:
	$(MAKE) -C $(PROJ_PATH)/rf_freq clean
	$(MAKE) -C $(PROJ_PATH)/exu_freq clean
	$(MAKE) -C $(PROJ_PATH)/npc clean

.PHONY: rf exu npc all clean
