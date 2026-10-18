/***************************************************************************************
* NPC Performance Counter
* 性能计数器: 接收 RTL 通过 DPI-C 上报的性能事件, 在仿真结束时打印性能报告.
***************************************************************************************/

#ifndef __PERF_H__
#define __PERF_H__

#include <cstdint>

enum PerfEventId {
    PERF_COMMIT       = 0,   // 提交(动态)指令数
    PERF_IF_FETCH     = 1,   // IFU 取到指令
    PERF_IF_STALL_BUS = 2,   // IFU 等 AR 握手 (总线/仲裁忙)
    PERF_IF_STALL_MEM = 3,   // IFU 已发请求, 等 R 数据 (访存延迟)
    PERF_LD_DONE      = 4,   // LSU 取到数据 (load 完成)
    PERF_ST_DONE      = 5,   // LSU 完成 store
    PERF_LD_WAIT      = 6,   // load 等待数据周期数 (统计平均访存延迟)
    PERF_ALU          = 7,   // 计算类指令 (R型/I型算术逻辑)
    PERF_LOAD         = 8,   // load 类指令
    PERF_STORE        = 9,   // store 类指令
    PERF_BRANCH       = 10,  // 分支指令
    PERF_JUMP         = 11,  // 跳转指令
    PERF_UPPER        = 12,  // lui/auipc
    PERF_CSR          = 13,  // CSR 指令
    PERF_ECALL        = 14,  // ecall
    PERF_MRET         = 15,  // mret
    PERF_EBREAK       = 16,  // ebreak
    PERF_EVENT_COUNT
};

void perf_report();

#ifdef __cplusplus
extern "C" {
#endif
int perf_delay_acc_step();
#ifdef __cplusplus
}
#endif

#endif
