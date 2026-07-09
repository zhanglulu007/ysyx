######################################################################################
# cachesim —— 简易 cache 功能模拟器 (B4.md "实现 cachesim")
#
# 用法:
#   make              # 编译 cachesim
#   make run          # 编译并对 $(ITRACE) 跑一次评估 (参数由 $(ARGS) 传入)
#   make clean
#
# 示例:
#   make run ITRACE=/tmp/microbench.itrace.txt
#   make run ITRACE=trace.bz2 ARGS="--bz2 --ways=2 --block=16 --total=64"
######################################################################################

CC      ?= gcc
CFLAGS  ?= -O2 -Wall -std=c99
TARGET  := cachesim

ITRACE  ?=
ARGS    ?=

$(TARGET): cachesim.c
	$(CC) $(CFLAGS) -o $(TARGET) cachesim.c

# 编译并对指定 itrace 跑评估
#   用法: make run ITRACE=<itrace文件> [ARGS="--ways=2 --block=16 ..."]
run: $(TARGET)
ifeq ($(ITRACE),)
	@echo "错误: 请指定 ITRACE 文件, 例如: make run ITRACE=/tmp/microbench.itrace.txt"
	@exit 1
endif
	./$(TARGET) $(ARGS) $(ITRACE)

clean:
	rm -f $(TARGET)

.PHONY: run clean
