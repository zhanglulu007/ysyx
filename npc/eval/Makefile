# NPC 综合评估统一入口
# 子目录说明:
#   rf_freq/  - 寄存器堆最大频率评估 (B4.md "寻找最高的综合频率")
#   exu_freq/ - EXU/ALU 加法器关键路径最大频率评估
#   idu_freq/ - IDU 四种 RTL 写法的独立综合与时序对比
#   npc/      - NPC 处理器整体综合评估 (直接引用 vsrc, B4.md "记录性能数据")
#   rtl-standalone/ - 单周期 rtl-standalone 整体综合评估
#   rtl-old/ - commit 2cb3c80 的旧版单周期 RTL 综合评估
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

idu:
	$(MAKE) -C $(PROJ_PATH)/idu_freq all

npc:
	$(MAKE) -C $(PROJ_PATH)/npc sta

rtl-standalone:
	$(MAKE) -C $(PROJ_PATH)/rtl-standalone sta

rtl-old:
	$(MAKE) -C $(PROJ_PATH)/rtl-old sta

all: rf exu idu npc rtl-standalone rtl-old
	@echo "========== 所有评估完成 =========="

clean:
	$(MAKE) -C $(PROJ_PATH)/rf_freq clean
	$(MAKE) -C $(PROJ_PATH)/exu_freq clean
	$(MAKE) -C $(PROJ_PATH)/idu_freq clean
	$(MAKE) -C $(PROJ_PATH)/npc clean
	$(MAKE) -C $(PROJ_PATH)/rtl-standalone clean
	$(MAKE) -C $(PROJ_PATH)/rtl-old clean

.PHONY: rf exu idu npc rtl-standalone rtl-old all clean
