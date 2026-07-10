#include <am.h>
#include <klib-macros.h>
#include "ysyxsoc.h"

extern char _heap_start, _heap_end;
extern char _text_start, _text_end, _text_lma;
extern char _rodata_start, _rodata_end, _rodata_lma;
extern char _data_start, _data_end, _data_lma;
extern char _bss_start, _bss_end;
extern char _ssbl_start, _ssbl_end, _ssbl_lma;
int main(const char *args);
void _trm_init(void);
void ssbl(void);
void fsbl(void);

/* 堆区: 紧跟 .bss 之后到 SDRAM 末尾, 由链接脚本决定区间
 * (程序主体在 SDRAM 中, 堆使用 SDRAM 剩余空间, 供 bench_alloc 等使用). */
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
  *(volatile uint8_t *)(UART_BASE + UART_LCR) = UART_LCR_DLAB;             // 进入除数访问模式 (DLAB=1)
  *(volatile uint8_t *)(UART_BASE + UART_TX)  = UART_DIVISOR & 0xff;       // 除数低字节
  *(volatile uint8_t *)(UART_BASE + UART_IE)  = (UART_DIVISOR >> 8) & 0xff;// 除数高字节
  *(volatile uint8_t *)(UART_BASE + UART_LCR) = UART_LCR_8N1;              // DLAB=0, 8N1
}

void halt(int code) {
  // 使用ebreak指令通知NPC程序结束
  npc_trap(code);
  while (1);
}

// SSBL
__attribute__((section(".text.ssbl")))
void ssbl(void) {
  uint32_t sz;
  uint8_t *dst, *src;

  /* ===== B4.md "在bootloader中复现加载器导致的缓存一致性问题" =====
   * 1. 在目标 SDRAM 位置放置 NOP 序列 + RET (充当"程序A")
   * 2. 函数调用跳转到 NOP 序列 → ICache 缓存了这些 NOP
   * 3. 复制真实程序到 SDRAM 覆盖 NOP (充当"程序B")
   * 4. 无 fence.i: ICache 仍有旧 NOP → 程序执行出错
   *    (后续讲义会添加 fence.i 修复) */

  /* 填充 NOP 序列: 16 条 NOP + 1 条 RET, 覆盖 ICache 全部 4 个块 */
  uintptr_t base = (uintptr_t)&_text_start;
  
  for (int i = 0; i < 16; i++) {
    *(volatile uint32_t *)(base + i * 4) = 0x00000013;
  }
  *(volatile uint32_t *)(base + 16 * 4) = 0x00008067;

  /* 通过函数调用执行 NOP 序列 (在 SDRAM 中, ICache 会缓存它们) */
  ((void (*)())(uintptr_t)base)();

  /* --- 以下为原有 bootloader 逻辑 --- */

  /* 复制 .text: Flash → SDRAM (覆盖上面的 NOP 序列!) */
  sz = (uint32_t)(uintptr_t)&_text_end - (uint32_t)(uintptr_t)&_text_start;
  dst = (uint8_t *)&_text_start;
  src = (uint8_t *)&_text_lma;
  for (uint32_t i = 0; i < sz; i++) dst[i] = src[i];

  /* 复制 .rodata: Flash → SDRAM */
  sz = (uint32_t)(uintptr_t)&_rodata_end - (uint32_t)(uintptr_t)&_rodata_start;
  dst = (uint8_t *)&_rodata_start;
  src = (uint8_t *)&_rodata_lma;
  for (uint32_t i = 0; i < sz; i++) dst[i] = src[i];

  /* 复制 .data: Flash → SDRAM */
  sz = (uint32_t)(uintptr_t)&_data_end - (uint32_t)(uintptr_t)&_data_start;
  dst = (uint8_t *)&_data_start;
  src = (uint8_t *)&_data_lma;
  for (uint32_t i = 0; i < sz; i++) dst[i] = src[i];

  /* 清零 .bss (SDRAM) */
  for (char *p = &_bss_start; p < &_bss_end; p++) *p = 0;

  /* 跳转到 SDRAM 中的 _trm_init (此时主程序已就位)
   * fence.i 冲刷 ICache, 确保后续取指看到被覆盖的真实程序,
   * 而非之前缓存的 NOP 序列 (B4.md "在bootloader中添加fence.i指令") */
  asm volatile("fence.i");
  _trm_init();
  while (1);
}

__attribute__((section(".text.bootloader")))
void fsbl(void) {
  uint32_t sz = (uint32_t)(uintptr_t)&_ssbl_end - (uint32_t)(uintptr_t)&_ssbl_start;
  uint8_t *dst = (uint8_t *)&_ssbl_start;
  uint8_t *src = (uint8_t *)&_ssbl_lma;
  for (uint32_t i = 0; i < sz; i++) dst[i] = src[i];
  /* 跳转到 SRAM 中的 ssbl() (此时 SSBL 代码已就位) */
  ssbl();
  while (1);
}

void _trm_init() {
  uart_init();
  int ret = main(mainargs);
  halt(ret);
}
