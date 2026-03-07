/***************************************************************************************
* NPC Instruction Trace (itrace)
* 指令追踪实现
***************************************************************************************/

#include "trace.h"
#include <cstring>
#include <cstdlib>

// 指令环形缓冲区
typedef struct {
  uint32_t pc;
  uint32_t inst;
  char logbuf[128];
} IringBufEntry;

static IringBufEntry iringbuf[IRINGBUF_SIZE];
static int iringbuf_idx = 0;
static bool iringbuf_full = false;

// 写入指令到环形缓冲区
void itrace_write(uint32_t pc, uint32_t inst) {
  iringbuf[iringbuf_idx].pc = pc;
  iringbuf[iringbuf_idx].inst = inst;
  
  // 反汇编指令
  char *p = iringbuf[iringbuf_idx].logbuf;
  p += snprintf(p, sizeof(iringbuf[iringbuf_idx].logbuf), "0x%08x:", pc);
  
  // 打印指令的十六进制
  uint8_t *inst_bytes = (uint8_t*)&inst;
  for (int i = 0; i < 4; i++) {
    p += snprintf(p, sizeof(iringbuf[iringbuf_idx].logbuf) - (p - iringbuf[iringbuf_idx].logbuf),
                  " %02x", inst_bytes[i]);
  }
  
  // 反汇编
  char disasm_buf[128];
  disassemble(disasm_buf, sizeof(disasm_buf), pc, (uint8_t*)&inst, 4);
  snprintf(p, sizeof(iringbuf[iringbuf_idx].logbuf) - (p - iringbuf[iringbuf_idx].logbuf),
           "   %s", disasm_buf);
  
  // 更新索引
  iringbuf_idx = (iringbuf_idx + 1) % IRINGBUF_SIZE;
  if (iringbuf_idx == 0) {
    iringbuf_full = true;
  }
  
  // 实时打印（可选）
  // printf("%s\n", iringbuf[(iringbuf_idx - 1 + IRINGBUF_SIZE) % IRINGBUF_SIZE].logbuf);
}

// 显示指令环形缓冲区
void display_iringbuf() {
  printf("\n\033[1;36mRecent executed instructions (iringbuf):\033[0m\n");
  
  int start = iringbuf_full ? iringbuf_idx : 0;
  int count = iringbuf_full ? IRINGBUF_SIZE : iringbuf_idx;
  
  if (count == 0) {
    printf("  (empty)\n");
    return;
  }
  
  for (int i = 0; i < count; i++) {
    int idx = (start + i) % IRINGBUF_SIZE;
    
    // 标记最后一条指令（当前执行的指令）
    if (i == count - 1) {
      printf("\033[1;31m-->\033[0m %s\n", iringbuf[idx].logbuf);
    } else {
      printf("    %s\n", iringbuf[idx].logbuf);
    }
  }
  printf("\n");
}
