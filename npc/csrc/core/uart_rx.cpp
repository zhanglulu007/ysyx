/***************************************************************************************
* NPC UART Receiver (仿真侧) 实现
* 详见 uart_rx.h
***************************************************************************************/

#include "uart_rx.h"
#include <cstdio>

/* 状态:
 *   IDLE      - 等待起始位 (uart_tx 由 1 变 0)
 *   MEASURE   - 测量起始位持续的低电平周期数, 以确定一个比特的宽度
 *   DATA      - 在每个比特的中心位置采样 8 个数据位
 *   STOP      - 等待停止位
 */
enum { S_IDLE, S_MEASURE, S_DATA, S_STOP };

static int    rx_state    = S_IDLE;
static uint32_t bit_period = 0;   // 一个比特持续的时钟周期数 (= 16 * divisor)
static uint32_t counter    = 0;   // 通用计数器
static uint32_t shift      = 0;   // 移位寄存器 (LSB first)
static int     bit_idx     = 0;   // 已接收的数据位数

void uart_rx_sample(uint8_t uart_tx_pin) {
    switch (rx_state) {
    case S_IDLE:
        /* 空闲时 uart_tx=1; 检测到下降沿即起始位开始 */
        if (uart_tx_pin == 0) {
            rx_state = S_MEASURE;
            counter  = 0;
        }
        break;

    case S_MEASURE:
        /* 计数起始位 (低电平) 持续的周期数, 直至其结束 (回到高电平) */
        counter++;
        if (uart_tx_pin != 0) {
            /* 起始位结束, counter 即为一个比特的宽度 (近似) */
            bit_period = counter;
            shift   = 0;
            bit_idx = 0;
            /* 起始位刚结束, 此处位于数据位0的开始; 等待 0.5 比特到达位中心 */
            counter   = 0;
            rx_state  = (bit_period > 0) ? S_DATA : S_IDLE;
        }
        break;

    case S_DATA:
        /* 在位中心采样: 等待 bit_period/2 个周期后采样, 然后每 bit_period 周期采一位 */
        counter++;
        if (counter >= bit_period / 2) {
            /* 到达当前数据位的中心, 采样 */
            shift |= (uart_tx_pin ? 1u : 0u) << bit_idx;
            bit_idx++;
            counter = 0;
            if (bit_idx >= 8) {
                rx_state = S_STOP;
                counter  = 0;
            }
        }
        break;

    case S_STOP:
        /* 等待停止位 (高电平) 持续约一个比特后结束 */
        counter++;
        if (counter >= bit_period) {
            /* 一个完整字节接收完成, 输出到终端 */
            putchar((int)(shift & 0xFF));
            fflush(stdout);
            rx_state = S_IDLE;
        }
        break;
    }
}
