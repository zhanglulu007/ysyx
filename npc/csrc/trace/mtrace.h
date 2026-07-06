#ifndef __MTRACE_H__
#define __MTRACE_H__

#include <stdint.h>
#include <stdbool.h>

// 初始化mtrace
void init_mtrace();

// 记录内存读操作（延迟输出）
// addr: 内存地址
// len: 读取长度（字节）
// data: 读取的数据
// pc: 当前PC
// cycle: 当前仿真周期数
void mtrace_read(uint32_t addr, int len, uint32_t data, uint32_t pc, uint64_t cycle);

// 记录内存写操作（延迟输出）
// addr: 内存地址
// len: 写入长度（字节）
// data: 写入的数据
// pc: 当前PC
// cycle: 当前仿真周期数
void mtrace_write(uint32_t addr, int len, uint32_t data, uint32_t pc, uint64_t cycle);

// 刷新mtrace缓冲区（在时钟周期结束后调用）
// print_to_console: 是否输出到控制台（si<=10时为true）
void mtrace_flush(bool print_to_console);

// ========== DPI-C 接口 (由 LSU 在 AXI 访存事务完成时调用) ==========
// 接入 ysyxSoC 后, 内存访问发生在 AXI 总线上 (SDRAM/flash/外设), 原先位于
// pmem_read/pmem_write 的 mtrace 钩子已失效. 正确的观测点是 LSU 完成一次访存事务的
// 握手时刻:
//   - load  完成 (L_WAIT_R 态 R 通道握手) -> mtrace_read_handler
//   - store 完成 (L_WAIT_B 态 B 通道握手) -> mtrace_write_handler
// 周期数由 C++ 侧通过 npc_get_cycle() 获取, 与仿真时间对齐.

// DPI-C接口: 记录一次 load 访存 (LSU R 通道握手完成时由 LSU.v 调用)
//   addr : 访存地址
//   data : 读到的数据
//   pc   : 引发本次访存的指令 PC
extern "C" void mtrace_read_handler(int addr, int data, int pc);

// DPI-C接口: 记录一次 store 访存 (LSU B 通道握手完成时由 LSU.v 调用)
//   addr  : 访存地址
//   data  : 写入的数据
//   wstrb : 字节写掩码 (每位对应一字节, 1=写), 由此推算写入字节数
//   pc    : 引发本次访存的指令 PC
extern "C" void mtrace_write_handler(int addr, int data, int wstrb, int pc);

#endif
