#ifndef __MTRACE_H__
#define __MTRACE_H__

#include <stdint.h>
#include <stdbool.h>

// 初始化mtrace
void init_mtrace();

// legacy 实时文本行生成: 保持 [MTRACE] READ/WRITE 格式, 与现有 grep/脚本兼容。
// 二进制事件由 RTL 探针(csrc/trace/trace_probe.cpp)提供(带真实宽度);
// 本函数只负责 npc.log 的实时文本视图。
//   is_write: false=READ, true=WRITE
//   is_fetch: true 表示取指(IFU)
void mtrace_legacy(bool is_write, bool is_fetch, uint32_t addr, int len,
                   uint32_t data, uint32_t pc, uint64_t cycle);

void mtrace_flush(bool print_to_console);

#endif
