#ifndef __MTRACE_H__
#define __MTRACE_H__

#include <stdint.h>
#include <stdbool.h>

// 初始化mtrace
void init_mtrace();
void mtrace_read(uint32_t addr, int len, uint32_t data, uint32_t pc, uint64_t cycle);
void mtrace_write(uint32_t addr, int len, uint32_t data, uint32_t pc, uint64_t cycle);
void mtrace_flush(bool print_to_console);

extern "C" void mtrace_read_handler(int addr, int data, int pc);
extern "C" void mtrace_write_handler(int addr, int data, int wstrb, int pc);

#endif
