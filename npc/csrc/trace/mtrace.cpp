#include "mtrace.h"
#include "trace_manager.h"
#include "../utils/log.h"
#include "../core/npc.h"
#include <stdio.h>
#include <vector>
#include <string>

// mtrace缓冲区（用于延迟输出到 npc.log 的 legacy 文本）
static std::vector<std::string> mtrace_buffer;

// 初始化mtrace
void init_mtrace() {
  Log("mtrace initialized");
}

// 统一访存事件入口
//   legacy 文本: 保持 [MTRACE] READ/WRITE 格式(与现有 grep/脚本兼容)
//   二进制事件: 按 (is_write, is_fetch) 区分 MTRACE_IFETCH/LOAD/STORE
//
// 注: M1 的 len 对 load 固定为 4 —— pmem_read DPI 只返回对齐的 32 位数据,
//     真实访存宽度需要 LSU 的 is_lb/is_lh/is_lw 信息(见计划 §5 的 M2 RTL 探针)。
void mtrace_access(bool is_write, bool is_fetch, uint32_t addr, int len,
                   uint32_t data, uint32_t pc, uint64_t cycle) {
#ifdef ENABLE_TRACE
  // ── legacy 文本(延迟到 flush) ──
  char logbuf[256];
  snprintf(logbuf, sizeof(logbuf),
           "[MTRACE] cyc=%llu %s at 0x%08x len=%d data=0x%08x pc=0x%08x",
           (unsigned long long)cycle, is_write ? "WRITE" : "READ ",
           addr, len, data, pc);
  mtrace_buffer.push_back(std::string(logbuf));

  // ── 二进制事件 ──
  npctrace::TraceEvent ev{};
  ev.cycle = cycle;
  ev.commit_id = npctrace::TraceManager::instance().inflight_commit();
  ev.pc = pc;
  ev.addr = addr;
  ev.data = data;
  ev.len = (uint16_t)len;
  ev.region = npctrace::RG_PMEM;   // memory.cpp 只对 PMEM 范围记录 mtrace
  if (is_write) {
    ev.type = npctrace::TT_MTRACE_STORE;
    ev.flags = npctrace::TF_WRITE;
    ev.channel = npctrace::CH_LSU;
  } else if (is_fetch) {
    ev.type = npctrace::TT_MTRACE_IFETCH;
    ev.flags = npctrace::TF_READ | npctrace::TF_FETCH;
    ev.channel = npctrace::CH_IFU;
  } else {
    ev.type = npctrace::TT_MTRACE_LOAD;
    ev.flags = npctrace::TF_READ;
    ev.channel = npctrace::CH_LSU;
  }
  npctrace::TraceManager::instance().emit(ev);
#else
  (void)is_write; (void)is_fetch; (void)addr; (void)len;
  (void)data; (void)pc; (void)cycle;
#endif
}

// 兼容旧接口(默认非取指)
void mtrace_read(uint32_t addr, int len, uint32_t data, uint32_t pc, uint64_t cycle) {
  mtrace_access(false, false, addr, len, data, pc, cycle);
}

void mtrace_write(uint32_t addr, int len, uint32_t data, uint32_t pc, uint64_t cycle) {
  mtrace_access(true, false, addr, len, data, pc, cycle);
}

// 刷新mtrace缓冲区(仅 legacy 文本; 二进制事件是即时的)
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

// ========== DPI-C 接口实现: 由 LSU 在 AXI 访存事务完成时调用(M2 RTL 探针接入) ==========

// 记录一次 load 访存 (R 通道握手完成)
extern "C" void mtrace_read_handler(int addr, int data, int pc) {
#ifdef ENABLE_TRACE
  mtrace_access(false, false, (uint32_t)addr, 4, (uint32_t)data,
                (uint32_t)pc, npc_get_cycle());
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
  mtrace_access(true, false, (uint32_t)addr, len, (uint32_t)data,
                (uint32_t)pc, npc_get_cycle());
#else
  (void)addr; (void)data; (void)wstrb; (void)pc;
#endif
}
