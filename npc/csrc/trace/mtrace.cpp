/***************************************************************************************
* NPC Memory Trace (mtrace)
* 内存追踪实现
***************************************************************************************/

#include "trace.h"
#include <cstdio>

// 内存读取追踪 - 只记录到日志，不打印到stdout
void mtrace_read(uint32_t addr, int len, uint32_t data, uint32_t pc) {
  // 使用log_write记录到日志文件，不打印到stdout
#ifdef CONFIG_LOG
  extern void log_write_internal(const char* format, ...);
  log_write_internal("[MTRACE] READ  at 0x%08x len=%d data=0x%08x pc=0x%08x\n", 
                     addr, len, data, pc);
#endif
}

// 内存写入追踪 - 只记录到日志，不打印到stdout
void mtrace_write(uint32_t addr, int len, uint32_t data, uint32_t pc) {
  // 使用log_write记录到日志文件，不打印到stdout
#ifdef CONFIG_LOG
  extern void log_write_internal(const char* format, ...);
  log_write_internal("[MTRACE] WRITE at 0x%08x len=%d data=0x%08x pc=0x%08x\n", 
                     addr, len, data, pc);
#endif
}
