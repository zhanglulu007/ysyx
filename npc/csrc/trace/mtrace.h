#ifndef __MTRACE_H__
#define __MTRACE_H__

#include <stdint.h>
#include <stdbool.h>

// 初始化mtrace
void init_mtrace();

// 统一访存事件入口: legacy 文本 + 二进制事件。
//   is_write: false=READ, true=WRITE
//   is_fetch: true 表示取指(IFU), 仅在 !is_write 时有意义
// 事件类型按 (is_write, is_fetch) 分为 IFETCH / LOAD / STORE。
void mtrace_access(bool is_write, bool is_fetch, uint32_t addr, int len,
                   uint32_t data, uint32_t pc, uint64_t cycle);

// 兼容旧接口(默认非取指)
void mtrace_read(uint32_t addr, int len, uint32_t data, uint32_t pc, uint64_t cycle);
void mtrace_write(uint32_t addr, int len, uint32_t data, uint32_t pc, uint64_t cycle);
void mtrace_flush(bool print_to_console);

extern "C" void mtrace_read_handler(int addr, int data, int pc);
extern "C" void mtrace_write_handler(int addr, int data, int wstrb, int pc);

#endif
