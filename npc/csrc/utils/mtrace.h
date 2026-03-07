#ifndef __MTRACE_H__
#define __MTRACE_H__

#include <stdint.h>
#include <stdbool.h>

// 初始化mtrace
void init_mtrace();

// 记录内存读操作
// addr: 内存地址
// len: 读取长度（字节）
// data: 读取的数据
// pc: 当前PC
// print_to_console: 是否输出到控制台（si<=10时为true）
void mtrace_read(uint32_t addr, int len, uint32_t data, uint32_t pc, bool print_to_console);

// 记录内存写操作
// addr: 内存地址
// len: 写入长度（字节）
// data: 写入的数据
// pc: 当前PC
// print_to_console: 是否输出到控制台（si<=10时为true）
void mtrace_write(uint32_t addr, int len, uint32_t data, uint32_t pc, bool print_to_console);

#endif
