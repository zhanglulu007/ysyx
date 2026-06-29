#include <am.h>
#include <klib-macros.h>
#include "ysyxsoc.h"

extern char _heap_start;
extern char _data_start, _data_end;
extern char _data_lma, _data_size;
int main(const char *args);

/* 堆区: 从 SRAM 起始到栈顶 (SRAM 末尾), 栈顶即栈指针初值 */
Area heap = RANGE(&_heap_start, SRAM_BASE + SRAM_SIZE);
static const char mainargs[MAINARGS_MAX_LEN] = TOSTRING(MAINARGS_PLACEHOLDER);

void putch(char ch) {
  /* 轮询 UART 线路状态寄存器，等待发送保持寄存器为空 */
  while ((*(volatile uint8_t *)(UART_BASE + UART_LSR) & UART_LSR_THRE) == 0);
  *(volatile uint8_t *)(UART_BASE + UART_TX) = ch;
}

/* 串口初始化: 设置除数寄存器, 否则 block_cnt 无法归零, THRE 位被永久屏蔽,
 * putch() 轮询 THRE 时会陷入死循环. 仿真环境无接收端/电气特性, 除数可任意取值. */
static void uart_init() {
  *(volatile uint8_t *)(UART_BASE + UART_LCR) = UART_LCR_DLAB;          // 进入除数访问模式 (DLAB=1)
  *(volatile uint8_t *)(UART_BASE + UART_TX)  = UART_DIVISOR & 0xff;    // 除数低字节
  *(volatile uint8_t *)(UART_BASE + UART_IE)  = (UART_DIVISOR >> 8) & 0xff; // 除数高字节
  *(volatile uint8_t *)(UART_BASE + UART_LCR) = UART_LCR_8N1;           // DLAB=0, 8N1
}

void halt(int code) {
  // 使用ebreak指令通知NPC程序结束
  npc_trap(code);
  while (1);
}
 //bootloader: 将 .data 段从 MROM (LMA) 搬移到 SRAM (VMA)，并清零 .bss */
void bootloader() {
  extern char _data_start, _data_end, _data_lma;
  uint32_t sz = (uint32_t)(uintptr_t)&_data_end - (uint32_t)(uintptr_t)&_data_start;
  uint8_t *dst = (uint8_t *)&_data_start;
  uint8_t *src = (uint8_t *)&_data_lma;   // MROM 中的加载地址
  for (uint32_t i = 0; i < sz; i++) dst[i] = src[i];
  extern char _bss_start, _bss_end;
  for (char *p = &_bss_start; p < &_bss_end; p++) *p = 0;
}

void _trm_init() {
  uart_init();
  bootloader();
  int ret = main(mainargs);
  halt(ret);
}