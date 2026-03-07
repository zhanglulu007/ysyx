/***************************************************************************************
* NPC Trace Support
* 指令追踪和内存追踪
***************************************************************************************/

#ifndef __TRACE_H__
#define __TRACE_H__

#include <cstdint>
#include <cstdio>

// 配置选项（由Makefile定义）
// #define CONFIG_ITRACE
// #define CONFIG_MTRACE
#define IRINGBUF_SIZE 16

// itrace - 指令追踪
void init_disasm();
void disassemble(char *str, int size, uint64_t pc, uint8_t *code, int nbyte);
void itrace_write(uint32_t pc, uint32_t inst);
void display_iringbuf();

// mtrace - 内存追踪
void mtrace_read(uint32_t addr, int len, uint32_t data, uint32_t pc);
void mtrace_write(uint32_t addr, int len, uint32_t data, uint32_t pc);

#endif
