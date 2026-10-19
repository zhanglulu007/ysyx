# npc-trace - trace.npct 查看器 (M0 骨架)
#
# 复用仿真侧的事件模型/格式定义(csrc/trace/trace_event.cpp), 保证读写同一份
# 结构体布局。M0 只有 info/stats 可用, text/export/tui 为 M1/M2 占位。

CXX      ?= g++
CXXFLAGS ?= -std=c++14 -O2 -Wall -Wextra
CSRC     := ../../csrc

# capstone 头文件(供 text 离线反汇编); 用 NEMU_HOME 定位, 缺失也能编译
NEMU_HOME ?= ../../../nemu
CAPSTONE_INC := $(NEMU_HOME)/tools/capstone/repo/include
INCLUDES := -I$(CSRC) -I$(CAPSTONE_INC)

SRCS := main.cpp decode.cpp disasm.cpp text.cpp export_chrome.cpp tui.cpp $(CSRC)/trace/trace_event.cpp

TOOL := npc-trace

all: $(TOOL)

$(TOOL): $(SRCS) trace_file.h $(CSRC)/trace/trace_event.h
	$(CXX) $(CXXFLAGS) $(INCLUDES) $(SRCS) -o $@

clean:
	-rm -f $(TOOL)

.PHONY: all clean
