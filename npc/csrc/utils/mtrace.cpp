#include "mtrace.h"
#include "log.h"
#include <stdio.h>

// 初始化mtrace
void init_mtrace() {
  Log("mtrace initialized");
}

// 记录内存读操作
void mtrace_read(uint32_t addr, int len, uint32_t data, uint32_t pc, bool print_to_console) {
  char logbuf[256];
  snprintf(logbuf, sizeof(logbuf), 
           "[MTRACE] READ  at 0x%08x len=%d data=0x%08x pc=0x%08x",
           addr, len, data, pc);
  
  // 输出到日志文件（始终）
  log_write("%s\n", logbuf);
  
  // 输出到控制台（仅在si<=10时）
  if (print_to_console) {
    printf("%s\n", logbuf);
  }
}

// 记录内存写操作
void mtrace_write(uint32_t addr, int len, uint32_t data, uint32_t pc, bool print_to_console) {
  char logbuf[256];
  snprintf(logbuf, sizeof(logbuf), 
           "[MTRACE] WRITE at 0x%08x len=%d data=0x%08x pc=0x%08x",
           addr, len, data, pc);
  
  // 输出到日志文件（始终）
  log_write("%s\n", logbuf);
  
  // 输出到控制台（仅在si<=10时）
  if (print_to_console) {
    printf("%s\n", logbuf);
  }
}
