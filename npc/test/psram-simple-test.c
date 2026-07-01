/* Simple PSRAM test: write a byte, read it back, verify */
#define UART_BASE 0x10000000L
#define UART_TX   0x0
#define UART_LSR  0x5
#define UART_LSR_THRE 0x20
#define UART_LCR  0x3
#define UART_LCR_DLAB 0x80
#define UART_IE   0x1

#define PSRAM_BASE 0x80000000

static void putch(char ch) {
  while ((*(volatile unsigned char *)(UART_BASE + UART_LSR) & UART_LSR_THRE) == 0);
  *(volatile unsigned char *)(UART_BASE + UART_TX) = ch;
}

static void put_hex8(unsigned char v) {
  putch("0123456789abcdef"[v >> 4]);
  putch("0123456789abcdef"[v & 0xf]);
}

void _start() {
  /* UART init: set divisor so tx works */
  *(volatile unsigned char *)(UART_BASE + UART_LCR) = UART_LCR_DLAB;
  *(volatile unsigned char *)(UART_BASE + UART_TX) = 0x08;
  *(volatile unsigned char *)(UART_BASE + UART_IE) = 0x00;
  *(volatile unsigned char *)(UART_BASE + UART_LCR) = 0x03; /* 8N1 */

  /* Test 1: write 0xA5 to PSRAM offset 0, read back */
  volatile unsigned char *p = (volatile unsigned char *)PSRAM_BASE;
  putch('T'); putch('1'); putch(':');
  putch('w'); putch('r'); putch('i'); putch('t'); putch('e'); putch(' ');
  *p = 0xA5;
  putch('r'); putch('e'); putch('a'); putch('d'); putch(' ');
  unsigned char r = *p;
  putch('g'); putch('o'); putch('t'); putch('=');
  put_hex8(r);
  putch(' ');
  putch('e'); putch('x'); putch('p'); putch('=');
  put_hex8(0xA5);
  putch('\n');

  /* Test 2: write 0x5A to PSRAM offset 4, read back */
  volatile unsigned char *p2 = (volatile unsigned char *)(PSRAM_BASE + 4);
  putch('T'); putch('2'); putch(':');
  putch(' ');
  *p2 = 0x5A;
  r = *p2;
  putch('g'); putch('o'); putch('t'); putch('=');
  put_hex8(r);
  putch(' ');
  putch('e'); putch('x'); putch('p'); putch('=');
  put_hex8(0x5A);
  putch('\n');

  /* Test 3: read without prior write (should see written value 0xA5 from test 1) */
  putch('T'); putch('3'); putch(':');
  putch('r'); putch('e'); putch('-'); putch('r'); putch('e'); putch('a'); putch('d'); putch(' ');
  r = *p;
  putch('g'); putch('o'); putch('t'); putch('=');
  put_hex8(r);
  putch(' ');
  putch('e'); putch('x'); putch('p'); putch('=');
  put_hex8(0xA5);
  putch('\n');

  /* Done */
  putch('D'); putch('O'); putch('N'); putch('E'); putch('\n');
  while (1);
}