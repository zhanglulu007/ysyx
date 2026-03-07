/***************************************************************************************
* NPC Disassembler
* 反汇编器实现（使用capstone库）
***************************************************************************************/

#include "trace.h"
#include <dlfcn.h>
#include <cassert>
#include <cstdio>

// 尝试包含capstone头文件，如果不存在则定义必要的类型
#ifdef __has_include
#  if __has_include(<capstone/capstone.h>)
#    include <capstone/capstone.h>
#    define HAS_CAPSTONE 1
#  endif
#endif

#ifndef HAS_CAPSTONE
// 如果没有capstone头文件，定义必要的类型
typedef size_t csh;
typedef enum cs_arch {
  CS_ARCH_RISCV = 9,
} cs_arch;
typedef enum cs_mode {
  CS_MODE_RISCV32 = 1 << 2,
  CS_MODE_RISCVC = 1 << 3,
} cs_mode;
typedef enum cs_err {
  CS_ERR_OK = 0,
} cs_err;
typedef struct cs_insn {
  unsigned int id;
  uint64_t address;
  uint16_t size;
  uint8_t bytes[24];
  char mnemonic[32];
  char op_str[160];
} cs_insn;
#endif

static size_t (*cs_disasm_dl)(csh handle, const uint8_t *code,
    size_t code_size, uint64_t address, size_t count, cs_insn **insn) = NULL;
static void (*cs_free_dl)(cs_insn *insn, size_t count) = NULL;

static csh handle;
static bool disasm_initialized = false;

void init_disasm() {
  if (disasm_initialized) return;
  
  void *dl_handle;
  
  // 尝试不同的capstone库路径
  const char* lib_paths[] = {
    "libcapstone.so.5",
    "libcapstone.so.4",
    "libcapstone.so",
    "/usr/lib/libcapstone.so.5",
    "/usr/lib/libcapstone.so.4",
    "/usr/lib/x86_64-linux-gnu/libcapstone.so.5",
    "/usr/lib/x86_64-linux-gnu/libcapstone.so.4",
    "/usr/local/lib/libcapstone.so.5",
    "/usr/local/lib/libcapstone.so.4",
    NULL
  };
  
  for (int i = 0; lib_paths[i] != NULL; i++) {
    dl_handle = dlopen(lib_paths[i], RTLD_LAZY);
    if (dl_handle) {
      printf("Loaded capstone library: %s\n", lib_paths[i]);
      break;
    }
  }
  
  if (!dl_handle) {
    printf("Warning: Failed to load capstone library. Disassembly will be disabled.\n");
    printf("Install capstone: sudo apt-get install libcapstone-dev\n");
    return;
  }

  cs_err (*cs_open_dl)(cs_arch arch, cs_mode mode, csh *handle) = NULL;
  cs_open_dl = (cs_err (*)(cs_arch, cs_mode, csh*))dlsym(dl_handle, "cs_open");
  if (!cs_open_dl) {
    printf("Warning: Failed to find cs_open symbol\n");
    return;
  }

  cs_disasm_dl = (size_t (*)(csh, const uint8_t*, size_t, uint64_t, size_t, cs_insn**))
                 dlsym(dl_handle, "cs_disasm");
  if (!cs_disasm_dl) {
    printf("Warning: Failed to find cs_disasm symbol\n");
    return;
  }

  cs_free_dl = (void (*)(cs_insn*, size_t))dlsym(dl_handle, "cs_free");
  if (!cs_free_dl) {
    printf("Warning: Failed to find cs_free symbol\n");
    return;
  }

  // 初始化RISC-V 32位反汇编器
  cs_arch arch = CS_ARCH_RISCV;
  cs_mode mode = (cs_mode)(CS_MODE_RISCV32 | CS_MODE_RISCVC);
  
  int ret = cs_open_dl(arch, mode, &handle);
  if (ret != CS_ERR_OK) {
    printf("Warning: Failed to initialize capstone (error %d)\n", ret);
    return;
  }

  disasm_initialized = true;
  printf("Disassembler initialized successfully\n");
}

void disassemble(char *str, int size, uint64_t pc, uint8_t *code, int nbyte) {
  if (!disasm_initialized) {
    // 如果反汇编器未初始化，显示原始字节
    snprintf(str, size, "<raw: ");
    int offset = 6;
    for (int i = 0; i < nbyte && i < 4; i++) {
      offset += snprintf(str + offset, size - offset, "%02x ", code[i]);
    }
    snprintf(str + offset, size - offset, ">");
    return;
  }
  
  cs_insn *insn;
  size_t count = cs_disasm_dl(handle, code, nbyte, pc, 0, &insn);
  
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
