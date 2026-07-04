#ifndef YSYXSOC_H__
#define YSYXSOC_H__

#include <klib-macros.h>
#include <riscv/riscv.h>

// ysyxSoC 设备地址空间
#define UART_BASE     0x10000000   // UART16550 基地址
#define UART_TX       0x0          // 发送保持寄存器 (THR) / 除数低字节 (DLAB=1)
#define UART_IE       0x1          // 中断使能寄存器 (IER) / 除数高字节 (DLAB=1)
#define UART_FCR      0x2          // FIFO 控制寄存器 (FCR)
#define UART_LCR      0x3          // 线路控制寄存器 (LCR)
#define UART_LSR      0x5          // 线路状态寄存器 (LSR) 偏移
#define UART_LSR_THRE 0x20         // 发送保持寄存器空 (THRE, bit 5)
#define UART_LSR_DR   0x01         // 数据就绪 (DR, bit 0)
#define UART_LCR_DLAB 0x80         // 除数访问位 (LCR bit 7)
#define UART_LCR_8N1  0x03         // 8 数据位, 无校验, 1 停止位
#define UART_DIVISOR  0x08         // 波特率除数 (必须非零: dl=0 时 enable 永远为 0, block_cnt 无法递减, THRE 锁死)

#define SRAM_BASE     0x0f000000
#define SRAM_SIZE     0x2000       // 8KB

#define MROM_BASE     0x20000000
#define MROM_SIZE     0x1000       // 4KB

#define PSRAM_BASE    0x80000000
#define PSRAM_SIZE    0x400000     // 4MB

#define SDRAM_BASE    0xa0000000
#define SDRAM_SIZE    0x2000000    // 32MB

#define npc_trap(code) asm volatile("mv a0, %0; ebreak" : :"r"(code))

#endif