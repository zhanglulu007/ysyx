#include <am.h>
#include <klib-macros.h>
#include "ysyxsoc.h"

extern char _heap_start, _heap_end;
extern char _text_start, _text_end, _text_lma;
extern char _rodata_start, _rodata_end, _rodata_lma;
extern char _data_start, _data_end, _data_lma;
extern char _bss_start, _bss_end;
int main(const char *args);

/* 堆区: 紧跟 .bss 之后到 PSRAM 末尾, 由链接脚本决定区间
 * (程序主体在 PSRAM 中, 堆使用 PSRAM 剩余空间, 供 bench_alloc 等使用). */
Area heap = RANGE(&_heap_start, &_heap_end);
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
 /*bootloader: 将 .text/.rodata/.data 从 flash (LMA) 搬移到 PSRAM (VMA)，并清零 .bss */
__attribute__((section(".text.bootloader")))
void bootloader() {
  uint32_t sz;
  uint8_t *dst, *src;

  /* 复制 .text: Flash → PSRAM */
  sz = (uint32_t)(uintptr_t)&_text_end - (uint32_t)(uintptr_t)&_text_start;
  dst = (uint8_t *)&_text_start;
  src = (uint8_t *)&_text_lma;
  for (uint32_t i = 0; i < sz; i++) dst[i] = src[i];
  sz = (uint32_t)(uintptr_t)&_rodata_end - (uint32_t)(uintptr_t)&_rodata_start;
  dst = (uint8_t *)&_rodata_start;
  src = (uint8_t *)&_rodata_lma;
  for (uint32_t i = 0; i < sz; i++) dst[i] = src[i];

  /* 复制 .data: Flash → PSRAM */
  sz = (uint32_t)(uintptr_t)&_data_end - (uint32_t)(uintptr_t)&_data_start;
  dst = (uint8_t *)&_data_start;
  src = (uint8_t *)&_data_lma;
  for (uint32_t i = 0; i < sz; i++) dst[i] = src[i];
  for (char *p = &_bss_start; p < &_bss_end; p++) *p = 0;
}

/* 读取 CSR 寄存器 (csrr 指令). csr_addr 为 12 位 CSR 地址. */
#define CSR_READ(csr_addr) ({ \
  uint32_t _v; \
  asm volatile ("csrr %0, " #csr_addr : "=r"(_v)); \
  _v; \
})

// static void put_hex32(uint32_t v) {
//   for (int i = 7; i >= 0; i--) {
//     putch("0123456789abcdef"[(v >> (4 * i)) & 0xf]);
//   }
// }

// static void print_student_id() {
//   uint32_t vendor = CSR_READ(0xf11);   // mvendorid
//   uint32_t arch   = CSR_READ(0xf12);   // marchid
//   putstr("\nNPC student id: ysyx_");
//   /* marchid 是学号十进制值, 按十进制打印 */
//   char buf[12];
//   int n = 0;
//   if (arch == 0) buf[n++] = '0';
//   for (uint32_t t = arch; t; t /= 10) buf[n++] = "0123456789"[t % 10];
//   while (n > 0) putch(buf[--n]);
//   putch('\n');
//   putstr(" (mvendorid=0x"); put_hex32(vendor);
//   putstr(", marchid=0x");   put_hex32(arch);
//   putstr(")\n\n");
// }

void _trm_init() {
  uart_init();
  //bootloader();
  //print_student_id();   // 进入 main() 前输出学号
  int ret = main(mainargs);
  halt(ret);
}