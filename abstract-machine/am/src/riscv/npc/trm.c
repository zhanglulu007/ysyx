#include <am.h>
#include <klib-macros.h>

extern char _heap_start;
int main(const char *args);

extern char _pmem_start;
#define PMEM_SIZE (128 * 1024 * 1024)
#define PMEM_END  ((uintptr_t)&_pmem_start + PMEM_SIZE)

Area heap = RANGE(&_heap_start, PMEM_END);
static const char mainargs[MAINARGS_MAX_LEN] = TOSTRING(MAINARGS_PLACEHOLDER); // defined in CFLAGS

void putch(char ch) {
}

void halt(int code) {
  // 使用ebreak指令通知NPC程序结束
  // ebreak指令的机器码是0x00100073
  asm volatile("ebreak");
  while (1);  // 防止继续执行
}

void _trm_init() {
  int ret = main(mainargs);
  halt(ret);
}
