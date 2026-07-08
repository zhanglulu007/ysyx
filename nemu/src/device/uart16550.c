/***************************************************************************************
* UART16550 设备模型 —— 供 riscv32e-ysyxsoc 镜像在 NEMU 上运行
*
* 背景: ysyxSoC 的 AM 程序通过 UART16550 (基地址 0x10000000) 输出字符:
*   trm.c putch():  while ((*(UART_BASE + LSR) & THRE) == 0);  // 轮询 THRE
*                   *(UART_BASE + TX) = ch;                     // 写入发送寄存器
*   trm.c uart_init(): 写 LCR/IER 配置除数 (否则 THRE 被永久屏蔽, putch 死锁)
* 若 NEMU 不提供 UART, putch 会因读到 0 而 THRE 永不置位, 陷入死循环.
*
* 实现策略 (功能级最小模型, 不仿真 SoC 细节):
*   - 读 LSR (offset 0x5) 恒返回 THRE|TEMT 置位 (0x60), 使 putch 立即返回不阻塞.
*   - 写 TX (offset 0x0) 输出字符到 stderr (与 NEMU serial.c 一致).
*   - 其余寄存器 (LCR/IER/FCR 等) 的读返回 0, 写静默接收 (配合 uart_init 配置流程).
*   - DR 位 (offset 0x5, bit0) 不置位, 表示无输入数据 (ioe.c 的 UART_RX 读到 0xFF).
***************************************************************************************/

#include <device/map.h>
#include <utils.h>

/* UART16550 寄存器窗口: 0x1000_0000 ~ 0x1000_0007 (8 字节), 与 ysyxSoC SoC.scala 一致 */
#define UART16550_BASE_ADDR  0x10000000
#define UART16550_WINDOW_SZ  8

/* 寄存器偏移 (与 AM ysyxsoc.h 一致) */
#define UART_TX_OFFSET   0x0   /* THR / 除数低字节 (DLAB=1) */
#define UART_IE_OFFSET   0x1   /* IER / 除数高字节 (DLAB=1) */
#define UART_FCR_OFFSET  0x2   /* FIFO 控制寄存器 */
#define UART_LCR_OFFSET  0x3   /* 线路控制寄存器 */
#define UART_LSR_OFFSET  0x5   /* 线路状态寄存器 */

/* LSR 位定义 */
#define UART_LSR_THRE    0x20  /* 发送保持寄存器空 (bit 5) */
#define UART_LSR_TEMT    0x40  /* 发送器空 (bit 6) */

static uint8_t *uart_base = NULL;

static void uart16550_io_handler(uint32_t offset, int len, bool is_write) {
  switch (offset) {
    case UART_TX_OFFSET:
      /* 写 THR: 输出字符到 stderr (与 NEMU 内置 serial 行为一致) */
      if (is_write) {
        putc(uart_base[UART_TX_OFFSET], stderr);
      }
      break;
    case UART_LSR_OFFSET:
      /* 读 LSR: 恒置 THRE|TEMT, 使 putch() 轮询立即通过, 不阻塞 */
      if (!is_write) {
        uart_base[UART_LSR_OFFSET] = UART_LSR_THRE | UART_LSR_TEMT;
      }
      break;
    default:
      /* LCR/IER/FCR 等: 读返回 0 (复位值), 写静默接收 (配合 uart_init 除数配置) */
      break;
  }
}

void init_uart16550() {
  uart_base = new_space(UART16550_WINDOW_SZ);
  add_mmio_map("uart16550", UART16550_BASE_ADDR, uart_base, UART16550_WINDOW_SZ, uart16550_io_handler);
}
