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
  // 使用ebreak指令通知NPC程序结束
  npc_trap(code);
  while (1);
}

/* bootloader: 将 .data 段从 MROM (LMA) 搬移到 SRAM (VMA)，并清零 .bss */
// static void bootloader() {
//   extern char _bss_start, _bss_end;

//   uint8_t *dst = (uint8_t *)&_data_start;
//   uint8_t *src = (uint8_t *)&_data_lma;
//   uint32_t  sz = (uint32_t)(uintptr_t)&_data_size;

//   /* 注意: 不能直接写 for(i=0;i<sz;i++) 循环. 在 -O2 下编译器会把它优化成
//    * 先复制再判断终止地址的 do-while 形式, 当 sz==0 (本程序 .data 段为空) 时,
//    * 终止地址等于起始地址, do-while 至少执行一次后 a5 != a2 恒成立, 陷入死循环.
//    * 此处显式判断 sz>0, 阻止编译器做该优化. */
//   if (sz > 0) {
//     for (uint32_t i = 0; i < sz; i++) {
//       dst[i] = src[i];
//     }
//   }

//   for (uint8_t *p = (uint8_t *)&_bss_start; p < (uint8_t *)&_bss_end; p++) {
//     *p = 0;
//   }
// }

void _trm_init() {
  //bootloader();
  int ret = main(mainargs);
  halt(ret);
}