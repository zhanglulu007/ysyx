#include <am.h>
#include <klib-macros.h>
#include "ysyxsoc.h"

extern char _heap_start;
extern char _data_start, _data_end;
extern char _data_lma, _data_size;
int main(const char *args);

Area heap = RANGE(&_heap_start, SRAM_BASE + SRAM_SIZE);
static const char mainargs[MAINARGS_MAX_LEN] = TOSTRING(MAINARGS_PLACEHOLDER);

void putch(char ch) {
  /* 轮询 UART 线路状态寄存器，等待发送保持寄存器为空 */
  while ((*(volatile uint8_t *)(UART_BASE + UART_LSR) & UART_LSR_THRE) == 0);
  *(volatile uint8_t *)(UART_BASE + UART_TX) = ch;
}

void halt(int code) {
  /* 在 mv a0,code 和 ebreak 之间插入多条 nop，
   * 确保 NPC 流水线在 ebreak 检测 a0 时已完成写回。
   * 这是为了弥补 NPC 流水线中 mv 到 ebreak 之间
   * 缺少 RAW hazard 转发的问题。 */
  asm volatile(

    "ebreak"
    : : "r"(code) : "a0", "memory");
  while (1);
}

/* bootloader: 将 .data 段从 MROM (LMA) 搬移到 SRAM (VMA)，并清零 .bss */
static void bootloader() {
  extern char _bss_start, _bss_end;

  uint8_t *dst = (uint8_t *)&_data_start;
  uint8_t *src = (uint8_t *)&_data_lma;
  uint32_t  sz = (uint32_t)(uintptr_t)&_data_size;

  for (uint32_t i = 0; i < sz; i++) {
    dst[i] = src[i];
  }

  for (uint8_t *p = (uint8_t *)&_bss_start; p < (uint8_t *)&_bss_end; p++) {
    *p = 0;
  }
}

void _trm_init() {
  bootloader();
  int ret = main(mainargs);
  halt(ret);
}