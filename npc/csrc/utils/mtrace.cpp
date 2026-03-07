#include "mtrace.h"
#include "log.h"
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
void mtrace_read(uint32_t addr, int len, uint32_t data, uint32_t pc) {
  char logbuf[256];
  snprintf(logbuf, sizeof(logbuf), 
           "[MTRACE] READ  at 0x%08x len=%d data=0x%08x pc=0x%08x",
           addr, len, data, pc);
  
  // 添加到缓冲区，延迟输出
  mtrace_buffer.push_back(std::string(logbuf));
}

// 记录内存写操作（延迟输出）
void mtrace_write(uint32_t addr, int len, uint32_t data, uint32_t pc) {
  char logbuf[256];
  snprintf(logbuf, sizeof(logbuf), 
           "[MTRACE] WRITE at 0x%08x len=%d data=0x%08x pc=0x%08x",
           addr, len, data, pc);
  
  // 添加到缓冲区，延迟输出
  mtrace_buffer.push_back(std::string(logbuf));
}

// 刷新mtrace缓冲区
void mtrace_flush(bool print_to_console) {
  for (const auto& line : mtrace_buffer) {
    // 输出到日志文件（始终）
    log_write("%s\n", line.c_str());
    
    // 输出到控制台（仅在si<=10时）
    if (print_to_console) {
      printf("%s\n", line.c_str());
    }
  }
  
  mtrace_buffer.clear();
}
