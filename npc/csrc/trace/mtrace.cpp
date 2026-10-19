#include "mtrace.h"
#include "../utils/log.h"
#include <stdio.h>
#include <vector>
#include <string>

// mtrace缓冲区（用于延迟输出到 npc.log 的 legacy 文本）
static std::vector<std::string> mtrace_buffer;

// 初始化mtrace
void init_mtrace() {
  Log("mtrace initialized");
}

// legacy 实时文本行。二进制事件不在这里产生——由 RTL 探针(trace_probe.cpp)
// 在 AXI 握手点发出, 携带真实访存宽度, 且 standalone/SoC 通用。
void mtrace_legacy(bool is_write, bool is_fetch, uint32_t addr, int len,
                   uint32_t data, uint32_t pc, uint64_t cycle) {
#ifndef ENABLE_TRACE
  (void)is_write; (void)is_fetch; (void)addr; (void)len;
  (void)data; (void)pc; (void)cycle;
  return;
#endif
  char logbuf[256];
  snprintf(logbuf, sizeof(logbuf),
           "[MTRACE] cyc=%llu %s at 0x%08x len=%d data=0x%08x pc=0x%08x",
           (unsigned long long)cycle, is_write ? "WRITE" : "READ ",
           addr, len, data, pc);
  mtrace_buffer.push_back(std::string(logbuf));
}

// 刷新mtrace缓冲区（仅 legacy 文本；二进制事件是即时的）
void mtrace_flush(bool print_to_console) {
  if (mtrace_buffer.empty()) return;

  // 先收集所有输出到一个字符串，确保原子性
  std::string output;
  for (const auto& line : mtrace_buffer) {
    output += line + "\n";
  }

  // 一次性输出到日志文件
  log_write("%s", output.c_str());

  // 一次性输出到控制台
  if (print_to_console) {
    printf("%s", output.c_str());
    fflush(stdout);  // 立即刷新，避免缓冲
  }

  mtrace_buffer.clear();
}
