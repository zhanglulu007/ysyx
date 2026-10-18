#include "mtrace.h"
#include "../utils/log.h"
#include "../core/npc.h"
#include <stdio.h>
#include <vector>
#include <string>

// mtrace缓冲区（用于延迟输出）
static std::vector<std::string> mtrace_buffer;

// 初始化mtrace
void init_mtrace() {
  Log("mtrace initialized");
}

// 记录内存读操作（延迟输出）
void mtrace_read(uint32_t addr, int len, uint32_t data, uint32_t pc, uint64_t cycle) {
#ifndef ENABLE_TRACE
  return;
#endif
  char logbuf[256];
  snprintf(logbuf, sizeof(logbuf),
           "[MTRACE] cyc=%llu READ  at 0x%08x len=%d data=0x%08x pc=0x%08x",
           (unsigned long long)cycle, addr, len, data, pc);
  mtrace_buffer.push_back(std::string(logbuf));
}

// 记录内存写操作（延迟输出）
void mtrace_write(uint32_t addr, int len, uint32_t data, uint32_t pc, uint64_t cycle) {
#ifndef ENABLE_TRACE
  return;
#endif
  char logbuf[256];
  snprintf(logbuf, sizeof(logbuf),
           "[MTRACE] cyc=%llu WRITE at 0x%08x len=%d data=0x%08x pc=0x%08x",
           (unsigned long long)cycle, addr, len, data, pc);
  mtrace_buffer.push_back(std::string(logbuf));
}

// 刷新mtrace缓冲区
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

// ========== DPI-C 接口实现: 由 LSU 在 AXI 访存事务完成时调用 ==========

// 记录一次 load 访存 (R 通道握手完成)
extern "C" void mtrace_read_handler(int addr, int data, int pc) {
#ifdef ENABLE_TRACE
  mtrace_read((uint32_t)addr, 4, (uint32_t)data, (uint32_t)pc, npc_get_cycle());
#else
  (void)addr; (void)data; (void)pc;  // TRACE 未开启时空操作
#endif
}

// 记录一次 store 访存 (B 通道握手完成)
extern "C" void mtrace_write_handler(int addr, int data, int wstrb, int pc) {
#ifdef ENABLE_TRACE
  // 由字节写掩码的 popcount 得到实际写入字节数
  int len = __builtin_popcount((unsigned)(wstrb & 0xF));
  if (len == 0) len = 4;  // 容错
  mtrace_write((uint32_t)addr, len, (uint32_t)data, (uint32_t)pc, npc_get_cycle());
#else
  (void)addr; (void)data; (void)wstrb; (void)pc;
#endif
}
