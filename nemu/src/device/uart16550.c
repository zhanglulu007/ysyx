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
