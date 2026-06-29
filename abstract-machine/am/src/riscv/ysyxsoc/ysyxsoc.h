#ifndef YSYXSOC_H__
#define YSYXSOC_H__

#include <klib-macros.h>
#include <riscv/riscv.h>

// ysyxSoC 设备地址空间
#define UART_BASE     0x10000000   // UART16550 基地址
#define UART_TX       0x0          // 发送保持寄存器 (THR) 偏移
#define UART_LSR      0x5          // 线路状态寄存器 (LSR) 偏移
#define UART_LSR_THRE 0x20         // 发送保持寄存器空 (THRE, bit 5)

#define SRAM_BASE     0x0f000000
#define SRAM_SIZE     0x2000       // 8KB

#define MROM_BASE     0x20000000
#define MROM_SIZE     0x1000       // 4KB

#define npc_trap(code) asm volatile("mv a0, %0; ebreak" : :"r"(code))

#endif