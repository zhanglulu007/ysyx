/***************************************************************************************
* Copyright (c) 2014-2024 Zihao Yu, Nanjing University
*
* NEMU is licensed under Mulan PSL v2.
* You can use this software according to the terms and conditions of the Mulan PSL v2.
* You may obtain a copy of Mulan PSL v2 at:
*          http://license.coscl.org.cn/MulanPSL2
*
* THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
* EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
* MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
*
* See the Mulan PSL v2 for more details.
***************************************************************************************/

#include <utils.h>
#include <device/map.h>
#include <memory/paddr.h>

/* http://en.wikibooks.org/wiki/Serial_Programming/8250_UART_Programming */
// NOTE: this is compatible to 16550

#define CH_OFFSET 0

static uint8_t *serial_base = NULL;

/* ysyxSoC UART16550 初始化 (0x10000000), 前向声明, 定义见文件末尾 */
void init_uart16550();


static void serial_putc(char ch) {
  MUXDEF(CONFIG_TARGET_AM, putch(ch), putc(ch, stderr));
}

static void serial_io_handler(uint32_t offset, int len, bool is_write) {
  assert(len == 1);
  switch (offset) {
    /* We bind the serial port with the host stderr in NEMU. */
    case CH_OFFSET:
      if (is_write) serial_putc(serial_base[0]);
      else panic("do not support read");
      break;
    default: panic("do not support offset = %d", offset);
  }
}

void init_serial() {
  serial_base = new_space(8);
#ifdef CONFIG_HAS_PORT_IO
  add_pio_map ("serial", CONFIG_SERIAL_PORT, serial_base, 8, serial_io_handler);
#else
  add_mmio_map("serial", CONFIG_SERIAL_MMIO, serial_base, 8, serial_io_handler);
#endif

  /* ysyxSoC 模式: 额外映射一个最小 UART16550 @0x10000000, 供 ysyxsoc AM 程序使用.
   * 真实 SoC 的串口在 0x10000000, 与 NEMU 默认的 0xa00003f8 不同. */
  if (nemu_soc_mode) {
    init_uart16550();
  }
}

/* ==================== ysyxSoC UART16550 (0x10000000) ==================== */
/* AM-ysyxsoc 程序 (trm.c) 访问的 UART16550 寄存器:
 *   uart_init(): 写 LCR(DLAB)/除数(THR,IER)/LCR(8N1)  -> 写入静默接受
 *   putch():     轮询 LSR(THRE), 写 THR 输出字符
 *   __am_uart_rx(): 读 LSR(DR), 读 RBR(THR offset)
 * 最小模型: LSR 始终 THRE=1(可发送)/DR=0(无输入), 写 THR 输出字符, 其余寄存器静默. */
#define UART16550_BASE   0x10000000UL
#define UART16550_SIZE   8
#define UART_REG_THR     0   /* Transmit Holding / Divisor Low / RBR */
#define UART_REG_IER     1   /* Interrupt Enable / Divisor High */
#define UART_REG_FCR     2   /* FIFO Control */
#define UART_REG_LCR     3   /* Line Control */
#define UART_REG_LSR     5   /* Line Status */
#define UART_LSR_THRE    0x20 /* Transmit Holding Register Empty */
#define UART_LSR_DR      0x01 /* Data Ready */

static uint8_t *uart16550_base = NULL;

static void uart16550_io_handler(uint32_t offset, int len, bool is_write) {
  assert(len == 1);
  switch (offset) {
    case UART_REG_THR:  /* offset 0 */
      if (is_write) {
        /* 写发送保持寄存器: 输出字符到 stderr (DLAB=1 时为除数低字节, 静默忽略) */
        putc(uart16550_base[0], stderr);
      }
      /* 读: RBR, 无输入返回 0 (uart16550_base[0] 初值 0) */
      break;
    case UART_REG_LSR:  /* offset 5: 读线路状态 */
      if (!is_write) {
        /* 始终报告 THRE=1(可发送) + DR=0(无数据), 避免轮询卡死 */
        uart16550_base[UART_REG_LSR] = UART_LSR_THRE;
      }
      break;
    case UART_REG_IER:  /* offset 1: IER / 除数高字节 */
    case UART_REG_FCR:  /* offset 2: FCR */
    case UART_REG_LCR:  /* offset 3: LCR (含 DLAB 位) */
      /* 静默接受写入 (uart_init 设置除数/8N1 用); 读返回 0 */
      break;
    default: break;     /* 其余 offset 静默 */
  }
}

void init_uart16550() {
  uart16550_base = new_space(UART16550_SIZE);
  /* LSR 预置 THRE=1, DR=0 */
  uart16550_base[UART_REG_LSR] = UART_LSR_THRE;
  add_mmio_map("uart16550", UART16550_BASE, uart16550_base, UART16550_SIZE, uart16550_io_handler);
}
