/***************************************************************************************
* NPC Memory Trace (mtrace)
* 内存追踪实现
***************************************************************************************/

#include "trace.h"
#include <cstdio>

// 内存读取追踪
void mtrace_read(uint32_t addr, int len, uint32_t data, uint32_t pc) {
  printf("[MTRACE] READ  at 0x%08x len=%d data=0x%08x pc=0x%08x\n", 
         addr, len, data, pc);
}

// 内存写入追踪
void mtrace_write(uint32_t addr, int len, uint32_t data, uint32_t pc) {
  printf("[MTRACE] WRITE at 0x%08x len=%d data=0x%08x pc=0x%08x\n", 
         addr, len, data, pc);
}
