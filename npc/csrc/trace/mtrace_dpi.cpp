/***************************************************************************************
* NPC MTRACE DPI-C Interface Implementation
* 由 LSU 在 AXI 访存事务完成时通过 DPI-C 调用, 转入 mtrace 记录.
***************************************************************************************/

#include "mtrace_dpi.h"
#include "mtrace.h"

// 记录一次 load 访存 (R 通道握手完成)
extern "C" void mtrace_read_handler(int addr, int data, int pc) {
#ifdef ENABLE_TRACE
    fprintf(stderr, "[DBG-mtrace-read] addr=0x%x data=0x%x pc=0x%x\n", addr, data, pc);
    // load 默认按字访问 (lsu 已按 funct3 选择传输粒度), 这里以 4 字节记录;
    // 真正的有效字节由后续字节/半字选择决定, trace 只关心访存事务本身.
    mtrace_read((uint32_t)addr, 4, (uint32_t)data, (uint32_t)pc);
#else
    (void)addr; (void)data; (void)pc;  // TRACE 未开启时空操作
#endif
}

// 记录一次 store 访存 (B 通道握手完成)
extern "C" void mtrace_write_handler(int addr, int data, int wstrb, int pc) {
#ifdef ENABLE_TRACE
    fprintf(stderr, "[DBG-mtrace-write] addr=0x%x data=0x%x wstrb=0x%x pc=0x%x\n", addr, data, wstrb, pc);
    // 由字节写掩码的 popcount 得到实际写入字节数
    int len = __builtin_popcount((unsigned)(wstrb & 0xF));
    if (len == 0) len = 4;  // 容错
    mtrace_write((uint32_t)addr, len, (uint32_t)data, (uint32_t)pc);
#else
    (void)addr; (void)data; (void)wstrb; (void)pc;
#endif
}
