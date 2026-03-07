#ifndef __FTRACE_H__
#define __FTRACE_H__

#include <stdint.h>
#include <stdbool.h>

// 初始化ftrace（需要ELF文件来解析符号表）
void init_ftrace(const char *elf_file);

// 记录函数调用
// pc: 当前PC
// target: 跳转目标地址
// print_to_console: 是否输出到控制台（si<=10时为true）
void ftrace_call(uint32_t pc, uint32_t target, bool print_to_console);

// 记录函数返回
// pc: 当前PC
// print_to_console: 是否输出到控制台（si<=10时为true）
void ftrace_ret(uint32_t pc, bool print_to_console);

#endif
