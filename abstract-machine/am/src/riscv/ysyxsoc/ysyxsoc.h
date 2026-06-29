#ifndef YSYXSOC_H__
#define YSYXSOC_H__

#include <klib-macros.h>
#include <riscv/riscv.h>

// ysyxSoC 设备地址空间
#define UART_BASE     0x10000000   // UART16550 基地址
#define UART_TX       0x0          // 发送保持寄存器 (THR) 偏移 (DLAB=0 时)
#define UART_LSR      0x5          // 线路状态寄存器 (LSR) 偏移
#define UART_LSR_THRE 0x20         // 发送保持寄存器空 (THRE, bit 5)

// UART16550 寄存器偏移与位定义 (用于串口初始化)
#define UART_IER      0x1          // 中断使能寄存器 / 除数高字节 (DLAB=1 时)
#define UART_FCR      0x2          // FIFO 控制寄存器
#define UART_LCR      0x3          // 线路控制寄存器
#define UART_LSR_OFFS 0x5
#define UART_LCR_DLAB 0x80         // 除数访问位 (LCR bit7): 置1时访问除数锁存寄存器
#define UART_LCR_8N1  0x03         // 8 位字符, 无校验, 1 停止位 (LCR[1:0]=11, 其余0)
#define UART_DLL      0x0          // 除数低字节 (DLAB=1 时, 偏移0)
#define UART_DLM      0x1          // 除数高字节 (DLAB=1 时, 偏移1)

#define SRAM_BASE     0x0f000000
#define SRAM_SIZE     0x2000       // 8KB

#define MROM_BASE     0x20000000
#define MROM_SIZE     0x1000       // 4KB

#define npc_trap(code) asm volatile("mv a0, %0; ebreak" : :"r"(code))

#endif