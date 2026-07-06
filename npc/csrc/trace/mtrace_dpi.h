/***************************************************************************************
* NPC MTRACE DPI-C Interface
* MTRACE的DPI-C接口: 由 LSU 在 AXI 访存事务完成时调用, 适配 ysyxSoC 总线访存模型.
*
* 设计说明:
*   接入 ysyxSoC 后, 内存访问发生在 AXI 总线上 (SDRAM/flash/外设), 原先位于
*   pmem_read/pmem_write 的 mtrace 钩子已失效 (被注释). 正确的观测点是 LSU
*   完成一次访存事务的握手时刻:
*     - load  完成 (L_WAIT_R 态 R 通道握手) -> mtrace_read_handler
*     - store 完成 (L_WAIT_B 态 B 通道握手) -> mtrace_write_handler
*   仅在编译时传入 ENABLE_TRACE 宏时, LSU 才实例化这些 DPI 调用 (见 LSU.v).
***************************************************************************************/

#ifndef __MTRACE_DPI_H__
#define __MTRACE_DPI_H__

#include <stdint.h>

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
