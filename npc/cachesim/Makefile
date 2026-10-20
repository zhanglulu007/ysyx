# cachesim —— 指令 cache 元数据模拟器
#
# 只依赖标准库, 产物在 build/cachesim.
# 输入 trace 由 NEMU 的 -c/--cachesim-trace 生成, 见 npc/Makefile 的 cachesim-trace 目标.

CXX      ?= g++
CXXFLAGS ?= -O2 -std=c++17 -Wall -Wextra
BUILD_DIR := build
TARGET    := $(BUILD_DIR)/cachesim

all: $(TARGET)

$(TARGET): cachesim.cpp
	@mkdir -p $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) -o $@ $<

# 默认跑当前 ICache 配置(sets=16 ways=1 block=4), trace 由上层 Makefile 生成
run: $(TARGET)
	./$(TARGET) --trace ../build/microbench-train.pc

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all run clean
