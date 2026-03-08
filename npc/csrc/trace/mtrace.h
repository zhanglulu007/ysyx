#ifndef __MTRACE_H__
#define __MTRACE_H__

#include <stdint.h>
#include <stdbool.h>

// 初始化mtrace
void init_mtrace();

// 记录内存读操作（延迟输出）
// addr: 内存地址
// len: 读取长度（字节）
// data: 读取的数据
// pc: 当前PC
void mtrace_read(uint32_t addr, int len, uint32_t data, uint32_t pc);

// 记录内存写操作（延迟输出）
// addr: 内存地址
// len: 写入长度（字节）
// data: 写入的数据
// pc: 当前PC
void mtrace_write(uint32_t addr, int len, uint32_t data, uint32_t pc);

// 刷新mtrace缓冲区（在时钟周期结束后调用）
// print_to_console: 是否输出到控制台（si<=10时为true）
void mtrace_flush(bool print_to_console);

#endif
