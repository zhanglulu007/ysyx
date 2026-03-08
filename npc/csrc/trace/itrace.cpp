#include "itrace.h"
#include "../utils/log.h"
#include <stdio.h>
#include <string.h>
#include <dlfcn.h>
#include <capstone/capstone.h>

// Capstone函数指针
static size_t (*cs_disasm_dl)(csh handle, const uint8_t *code,
    size_t code_size, uint64_t address, size_t count, cs_insn **insn) = NULL;
static void (*cs_free_dl)(cs_insn *insn, size_t count) = NULL;
static csh cs_handle = 0;

// 指令环形缓冲区
#define IRINGBUF_SIZE 16

typedef struct {
  uint32_t pc;
  uint32_t inst;
  char logbuf[128];
} IringBufEntry;

static IringBufEntry iringbuf[IRINGBUF_SIZE];
static int iringbuf_idx = 0;
static bool iringbuf_full = false;

// 反汇编一条指令
static void disassemble(char *str, int size, uint32_t pc, uint8_t *code, int nbyte) {
  if (!cs_disasm_dl || !cs_free_dl || cs_handle == 0) {
    snprintf(str, size, "<disasm not available>");
    return;
  }
  
  cs_insn *insn;
  size_t count = cs_disasm_dl(cs_handle, code, nbyte, pc, 0, &insn);
  
  if (count == 0) {
    snprintf(str, size, "<invalid>");
    return;
  }
  
  int ret = snprintf(str, size, "%s", insn->mnemonic);
  if (insn->op_str[0] != '\0') {
    snprintf(str + ret, size - ret, "\t%s", insn->op_str);
  }
  
  cs_free_dl(insn, count);
}

// 初始化itrace
void init_itrace() {
  // 动态加载capstone库（使用相对于npc目录的路径）
  void *dl_handle = dlopen("../nemu/tools/capstone/repo/libcapstone.so.5", RTLD_LAZY);
  if (!dl_handle) {
    Log("Warning: Failed to load capstone library, itrace disassembly will not be available");
    Log("  Error: %s", dlerror());
    return;
  }
  
  // 获取函数指针
  cs_err (*cs_open_dl)(cs_arch arch, cs_mode mode, csh *handle) = NULL;
  cs_open_dl = (cs_err (*)(cs_arch, cs_mode, csh*))dlsym(dl_handle, "cs_open");
  if (!cs_open_dl) {
    Log("Warning: Failed to find cs_open in capstone library");
    return;
  }
  
  cs_disasm_dl = (size_t (*)(csh, const uint8_t*, size_t, uint64_t, size_t, cs_insn**))dlsym(dl_handle, "cs_disasm");
  if (!cs_disasm_dl) {
    Log("Warning: Failed to find cs_disasm in capstone library");
    return;
  }
  
  cs_free_dl = (void (*)(cs_insn*, size_t))dlsym(dl_handle, "cs_free");
  if (!cs_free_dl) {
    Log("Warning: Failed to find cs_free in capstone library");
    return;
  }
  
  // 初始化capstone（RISC-V 32位）
  cs_arch arch = CS_ARCH_RISCV;
  cs_mode mode = (cs_mode)(CS_MODE_RISCV32 | CS_MODE_RISCVC);
  
  int ret = cs_open_dl(arch, mode, &cs_handle);
  if (ret != CS_ERR_OK) {
    Log("Warning: Failed to initialize capstone (error code: %d)", ret);
    cs_handle = 0;
    return;
  }
  
  Log("itrace initialized successfully with capstone disassembler");
}

// 记录一条指令到环形缓冲区
static void iringbuf_write(uint32_t pc, uint32_t inst, const char *logbuf) {
  iringbuf[iringbuf_idx].pc = pc;
  iringbuf[iringbuf_idx].inst = inst;
  
  size_t len = strlen(logbuf);
  if (len >= sizeof(iringbuf[iringbuf_idx].logbuf)) {
    len = sizeof(iringbuf[iringbuf_idx].logbuf) - 1;
  }
  memcpy(iringbuf[iringbuf_idx].logbuf, logbuf, len);
  iringbuf[iringbuf_idx].logbuf[len] = '\0';
  
  iringbuf_idx = (iringbuf_idx + 1) % IRINGBUF_SIZE;
  if (iringbuf_idx == 0) {
    iringbuf_full = true;
  }
}

// 记录一条指令的执行
void itrace_log(uint32_t pc, uint32_t inst, bool print_to_console) {
  char logbuf[128];
  char *p = logbuf;
  
  // 格式化PC和指令编码
  p += snprintf(p, sizeof(logbuf), "0x%08x:", pc);
  
  // 打印指令字节（小端序）
  uint8_t *inst_bytes = (uint8_t *)&inst;
  for (int i = 3; i >= 0; i--) {
    p += snprintf(p, 4, " %02x", inst_bytes[i]);
  }
  
  // 添加空格对齐
  int space_len = 1;
  memset(p, ' ', space_len);
  p += space_len;
  
  // 反汇编
  disassemble(p, logbuf + sizeof(logbuf) - p, pc, (uint8_t *)&inst, 4);
  
  // 写入环形缓冲区
  iringbuf_write(pc, inst, logbuf);
  
  // 输出到日志文件（始终）
  log_write("%s\n", logbuf);
  
  // 输出到控制台（仅在si<=10时）
  if (print_to_console) {
    printf("%s\n", logbuf);
    fflush(stdout);  // 立即刷新，避免缓冲
  }
}

// 显示指令环形缓冲区
void display_iringbuf() {
  printf("\n" ANSI_FMT("Recent executed instructions (iringbuf):", ANSI_FG_CYAN) "\n");
  
  int start = iringbuf_full ? iringbuf_idx : 0;
  int count = iringbuf_full ? IRINGBUF_SIZE : iringbuf_idx;
  
  if (count == 0) {
    printf("  (empty)\n");
    return;
  }
  
  for (int i = 0; i < count; i++) {
    int idx = (start + i) % IRINGBUF_SIZE;
    
    // 标记最后一条指令（出错的指令）
    if (i == count - 1) {
      printf(ANSI_FMT("-->", ANSI_FG_RED) " %s\n", iringbuf[idx].logbuf);
    } else {
      printf("    %s\n", iringbuf[idx].logbuf);
    }
  }
  printf("\n");
}
