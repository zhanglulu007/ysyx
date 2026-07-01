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

/* 读取 CSR 寄存器 (csrr 指令). csr_addr 为 12 位 CSR 地址. */
#define CSR_READ(csr_addr) ({ \
  uint32_t _v; \
  asm volatile ("csrr %0, " #csr_addr : "=r"(_v)); \
  _v; \
})

static void put_hex32(uint32_t v) {
  for (int i = 7; i >= 0; i--) {
    putch("0123456789abcdef"[(v >> (4 * i)) & 0xf]);
  }
}

static void print_student_id() {
  uint32_t vendor = CSR_READ(0xf11);   // mvendorid
  uint32_t arch   = CSR_READ(0xf12);   // marchid
  putstr("\nNPC student id: ysyx_");
  /* marchid 是学号十进制值, 按十进制打印 */
  char buf[12];
  int n = 0;
  if (arch == 0) buf[n++] = '0';
  for (uint32_t t = arch; t; t /= 10) buf[n++] = "0123456789"[t % 10];
  while (n > 0) putch(buf[--n]);
  putch('\n');
  putstr(" (mvendorid=0x"); put_hex32(vendor);
  putstr(", marchid=0x");   put_hex32(arch);
  putstr(")\n\n");
}

void _trm_init() {
  uart_init();
  bootloader();
  print_student_id();   // 进入 main() 前输出学号
  int ret = main(mainargs);
  halt(ret);
}