/***************************************************************************************
* NPC Performance Counter
* 性能计数器实现: 汇总 RTL 通过 DPI-C 上报的性能事件, 并在仿真结束时打印报告.
***************************************************************************************/

#include "core/perf.h"
#include "core/npc.h"
#include "../utils/log.h"

#include <cinttypes>
#include <cstdio>

static uint64_t perf_count[PERF_EVENT_COUNT] = {};

extern "C" void perf_event(int event_id) {
    if (event_id >= 0 && event_id < PERF_EVENT_COUNT) {
        perf_count[event_id]++;
    }
}

extern "C" int perf_delay_acc_step() {
    static const int M = 8;                 // 放大系数 s = 2^M
    static const int S = 1 << M;
    static const int F_DEV_MHZ = 100;       // 外设频率

#ifdef F
    const int f_cpu_mhz = F * 10;           
#else
    const int f_cpu_mhz = F_DEV_MHZ;        // 未指定 F: r = 1
#endif

    if (f_cpu_mhz <= F_DEV_MHZ) return 0;
    const double r = static_cast<double>(f_cpu_mhz) / F_DEV_MHZ;
    return static_cast<int>((r - 1.0) * S + 0.5);   // 四舍五入
}

static double ratio(uint64_t num, uint64_t den) {
    return den ? static_cast<double>(num) / static_cast<double>(den) : 0.0;
}

void perf_report() {
    const uint64_t cycle  = npc_get_cycle();
    const uint64_t commit = perf_count[PERF_COMMIT];

    const uint64_t ic_access    = perf_count[PERF_IC_ACCESS];
    const uint64_t ic_hit       = perf_count[PERF_IC_HIT];
    const uint64_t ic_miss      = perf_count[PERF_IC_MISS];
    const uint64_t ic_miss_wait = perf_count[PERF_IC_MISS_AR] + perf_count[PERF_IC_MISS_R];

    // 各指令类别计数之和, 用于与动态指令数做一致性检查
    const uint64_t class_sum =
        perf_count[PERF_ALU]    + perf_count[PERF_LOAD]   + perf_count[PERF_STORE] +
        perf_count[PERF_BRANCH] + perf_count[PERF_JUMP]   + perf_count[PERF_UPPER] +
        perf_count[PERF_CSR]    + perf_count[PERF_ECALL]  + perf_count[PERF_MRET]  +
        perf_count[PERF_EBREAK];

    printf("\n=================== Performance Report ===================\n");
    printf("Cycles           : %" PRIu64 "\n",  cycle);
    printf("Instructions     : %" PRIu64 "\n", commit);
    printf("IPC              : %.4f\n", ratio(commit, cycle));

    printf("\n[Instruction mix]\n");
    printf("  alu   load  store branch jump  upper csr   ecall mret  ebreak\n");
    printf("  %-5" PRIu64 " %-5" PRIu64 " %-5" PRIu64 " %-6" PRIu64 " %-5" PRIu64
           " %-5" PRIu64 " %-5" PRIu64 " %-5" PRIu64 " %-5" PRIu64 " %" PRIu64 "\n",
           perf_count[PERF_ALU],    perf_count[PERF_LOAD],   perf_count[PERF_STORE],
           perf_count[PERF_BRANCH], perf_count[PERF_JUMP],   perf_count[PERF_UPPER],
           perf_count[PERF_CSR],    perf_count[PERF_ECALL],  perf_count[PERF_MRET],
           perf_count[PERF_EBREAK]);
    printf("  class sum        : %" PRIu64 " (consistency vs instructions: %s)\n",
           class_sum, class_sum == commit ? "OK" : "MISMATCH");

    printf("\n[IFU behavior]\n");
    printf("  fetched          : %" PRIu64 "\n", perf_count[PERF_IF_FETCH]);
    printf("  stall (busy AR)  : %" PRIu64 " cycles\n", perf_count[PERF_IF_STALL_BUS]);
    printf("  stall (wait R)   : %" PRIu64 " cycles\n", perf_count[PERF_IF_STALL_MEM]);
    printf("  stall ratio      : %.4f\n",
           ratio(perf_count[PERF_IF_STALL_BUS] + perf_count[PERF_IF_STALL_MEM], cycle));

    printf("\n[LSU behavior]\n");
    printf("  load done        : %" PRIu64 "\n", perf_count[PERF_LD_DONE]);
    printf("  store done       : %" PRIu64 "\n", perf_count[PERF_ST_DONE]);
    printf("  load wait cycles : %" PRIu64 "\n", perf_count[PERF_LD_WAIT]);
    printf("  avg load latency : %.4f cycles\n",
           ratio(perf_count[PERF_LD_WAIT], perf_count[PERF_LD_DONE]));

    printf("\n[ICache behavior]\n");
    printf("  access           : %" PRIu64 "\n", ic_access);
    printf("  hit              : %" PRIu64 "\n", ic_hit);
    printf("  miss             : %" PRIu64 "\n", ic_miss);
    printf("  hit rate         : %.2f%%\n", ratio(ic_hit, ic_access) * 100.0);
    printf("  miss rate        : %.2f%%\n", ratio(ic_miss, ic_access) * 100.0);
    printf("  refill AR        : %" PRIu64 "\n", perf_count[PERF_IC_REFILL]);
    printf("  miss AR wait     : %" PRIu64 " cycles\n", perf_count[PERF_IC_MISS_AR]);
    printf("  miss R wait      : %" PRIu64 " cycles\n", perf_count[PERF_IC_MISS_R]);
    printf("  avg miss latency : %.4f cycles\n", ratio(ic_miss_wait, ic_miss));
    printf("==========================================================\n");

    Log("Perf summary: cycles=%llu inst=%llu ipc=%.4f icache_access=%llu icache_hit=%llu icache_hit_rate=%.4f",
        (unsigned long long)cycle, (unsigned long long)commit, ratio(commit, cycle),
        (unsigned long long)ic_access, (unsigned long long)ic_hit,
        ratio(ic_hit, ic_access));
}
