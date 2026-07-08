# cachesim - 简易 cache 功能模拟器 (独立 C 程序, 不依赖 NEMU/Verilator)
#
# 用法:
#   make            # 编译生成 ./cachesim
#   make run        # 用示例 pc.bin 运行 (需先用 NEMU --dump-pc 生成)
#   make clean

CC      ?= gcc
CFLAGS  ?= -O2 -std=c11 -Wall -Wextra
TARGET  := cachesim
SRC     := cachesim.c

.PHONY: all clean run

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $@ $(SRC)

run: $(TARGET)
	./$(TARGET) -h

clean:
	rm -f $(TARGET)
