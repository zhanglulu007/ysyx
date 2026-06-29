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
  /* 轮询 UART 线路状态寄存器，等待发送保持寄存器为空 (THRE=1)
   * 确保 TX FIFO 有空闲位置后再写入, 避免字符丢失 */
  while ((*(volatile uint8_t *)(UART_BASE + UART_LSR) & UART_LSR_THRE) == 0);
  *(volatile uint8_t *)(UART_BASE + UART_TX) = ch;
}

void halt(int code) {
  // 使用ebreak指令通知NPC程序结束
  npc_trap(code);
  while (1);
}

/* 串口初始化: 设置除数寄存器, 使 UART 发送器开始工作.
 * 复位后除数 dl=0, UART 的 enable 信号为 0, 发送器不工作: 写入 TX FIFO 的字符
 * 不会被串行发送出去, FIFO 满后(16字节)后续字符丢失, 且 THRE 状态无法正确反映.
 * 设置一个非零除数后 enable=1, 发送器才能正常工作. 仿真环境中无电气特性概念,
 * 除数可随意设置(此处取较小值, 对应较高波特率). */
void uart_init() {
  volatile uint8_t *uart = (volatile uint8_t *)UART_BASE;
  /* 1. 打开 DLAB (LCR bit7), 使后续对偏移0/1的写访问除数锁存寄存器 */
  uart[UART_LCR] |= UART_LCR_DLAB;
  /* 2. 写入除数: 仿真环境随意取值, 这里设 dl=1 (低字节=1, 高字节=0) */
  uart[UART_DLL] = 0x01;
  uart[UART_DLM] = 0x00;
  /* 3. 关闭 DLAB, 恢复偏移0/1为 THR/IER; 同时设置 8N1 (8位字符, 无校验, 1停止位) */
  uart[UART_LCR] = UART_LCR_8N1;
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
  bootloader();
  uart_init();
  int ret = main(mainargs);
  halt(ret);
}