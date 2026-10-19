/***************************************************************************************
* NPC TRACE - RTL 探针的 C++ 接入层 (M2)
*
* RTL(top.v) 在关键事件处通过 DPI-C 调用本层, 本层只做两件事:
*   1. 把裸信号转换成 TraceEvent(判地址区域、定 channel/flags/len);
*   2. 交给 TraceManager 统一过滤/写盘。
*
* 探针覆盖(替代 M1 在 memory.cpp 里的“addr==pc 猜取指”启发式):
*   - IFETCH / LOAD / STORE: 带真实访存宽度(来自 LSU 的 is_lb/lh/lw/sb/sh/sw)
*   - AXI AR/R/AW/W/B: standalone 与 SoC 通用(直接挂在 top.v 的 mem_* 上)
*   - CSR 读/写, ecall/mret/ebreak, 分支
*
* 未启用 TRACE(ENABLE_TRACE 未定义)时全部为空实现, 不产生任何开销。
***************************************************************************************/
#ifndef __NPC_TRACE_PROBE_H__
#define __NPC_TRACE_PROBE_H__

#include <cstdint>

namespace npctrace {

// 地址 -> 区域(PMEM/FLASH/SRAM/SDRAM/PSRAM/MROM/MMIO/FB), 区分 standalone/SoC
uint8_t addr_region(uint32_t addr);

}  // namespace npctrace

extern "C" {
// IFU 取到一条指令 (R 通道握手完成)
void trace_probe_ifetch(int addr, int data, int pc);

// LSU 完成一次 load/store; width 为真实字节数(1/2/4)
void trace_probe_mem(int is_write, int width, int addr, int data, int pc);

// AXI 通道事务。channel: 3=AR 4=R 5=AW 6=W 7=B(与 TraceChannel 对齐)
void trace_probe_axi(int channel, int id, int addr, int len, int size, int data);

// CSR 读/写。is_write: 0=读 1=写
void trace_probe_csr(int is_write, int csr_addr, int wdata, int rdata, int pc);

// 异常/中断/返回。kind: 0=exception 1=mret 2=ebreak
void trace_probe_trap(int kind, int cause, int epc, int tvec, int pc);

// 分支指令提交。taken: 是否跳转, target: 目标地址
void trace_probe_branch(int pc, int taken, int target);
}

#endif  // __NPC_TRACE_PROBE_H__
