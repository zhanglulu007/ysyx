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

static double percent(uint64_t num, uint64_t den) {
    return ratio(num, den) * 100.0;
}

static void print_mix(const char *name, uint64_t count, uint64_t total) {
    printf("  %-14s %10" PRIu64 "  %7.2f%%\n", name, count, percent(count, total));
}

void perf_report() {
    const uint64_t cycle  = npc_get_cycle();
    const uint64_t commit = perf_count[PERF_COMMIT];
    const uint64_t state_commit = npc_get_commit_count();

    const uint64_t if_fetch     = perf_count[PERF_IF_FETCH];
    const uint64_t if_bypass    = perf_count[PERF_IF_BYPASS];
    const uint64_t if_stall_bus = perf_count[PERF_IF_STALL_BUS];
    const uint64_t if_stall_mem = perf_count[PERF_IF_STALL_MEM];

    const uint64_t ic_access     = perf_count[PERF_IC_ACCESS];
    const uint64_t ic_hit        = perf_count[PERF_IC_HIT];
    const uint64_t ic_miss       = perf_count[PERF_IC_MISS];
    const uint64_t ic_compulsory = perf_count[PERF_IC_COMPULSORY];
    const uint64_t ic_replace    = perf_count[PERF_IC_REPLACE];
    const uint64_t ic_refill     = perf_count[PERF_IC_REFILL];
    const uint64_t ic_miss_ar    = perf_count[PERF_IC_MISS_AR];
    const uint64_t ic_miss_r     = perf_count[PERF_IC_MISS_R];

    const uint64_t alu     = perf_count[PERF_ALU];
    const uint64_t alu_r   = perf_count[PERF_ALU_R];
    const uint64_t alu_i   = perf_count[PERF_ALU_I];
    const uint64_t load    = perf_count[PERF_LOAD];
    const uint64_t store   = perf_count[PERF_STORE];
    const uint64_t branch  = perf_count[PERF_BRANCH];
    const uint64_t jump    = perf_count[PERF_JUMP];
    const uint64_t upper   = perf_count[PERF_UPPER];
    const uint64_t csr     = perf_count[PERF_CSR];
    const uint64_t ecall   = perf_count[PERF_ECALL];
    const uint64_t mret    = perf_count[PERF_MRET];
    const uint64_t ebreak  = perf_count[PERF_EBREAK];

    const uint64_t branch_taken     = perf_count[PERF_BRANCH_TAKEN];
    const uint64_t branch_not_taken = perf_count[PERF_BRANCH_NOT_TAKEN];
    const uint64_t jal              = perf_count[PERF_JAL];
    const uint64_t jalr             = perf_count[PERF_JALR];

    const uint64_t ld_byte    = perf_count[PERF_LD_BYTE];
    const uint64_t ld_half    = perf_count[PERF_LD_HALF];
    const uint64_t ld_word    = perf_count[PERF_LD_WORD];
    const uint64_t st_byte    = perf_count[PERF_ST_BYTE];
    const uint64_t st_half    = perf_count[PERF_ST_HALF];
    const uint64_t st_word    = perf_count[PERF_ST_WORD];
    const uint64_t ld_done    = perf_count[PERF_LD_DONE];
    const uint64_t st_done    = perf_count[PERF_ST_DONE];
    const uint64_t ld_wait    = perf_count[PERF_LD_WAIT];
    const uint64_t st_wait    = perf_count[PERF_ST_WAIT];

    const uint64_t bus_ar       = perf_count[PERF_BUS_AR];
    const uint64_t bus_r        = perf_count[PERF_BUS_R];
    const uint64_t bus_aw       = perf_count[PERF_BUS_AW];
    const uint64_t bus_w        = perf_count[PERF_BUS_W];
    const uint64_t bus_b        = perf_count[PERF_BUS_B];
    const uint64_t bus_ar_stall = perf_count[PERF_BUS_AR_STALL];

    const uint64_t csrrw = perf_count[PERF_CSRRW];
    const uint64_t csrrs = perf_count[PERF_CSRRS];

    // 各指令类别计数之和, 用于与动态指令数做一致性检查
    const uint64_t class_sum =
        alu + load + store + branch + jump + upper + csr + ecall + mret + ebreak;

    printf("\n=================== Performance Report ===================\n");
    printf("Cycles           : %" PRIu64 "\n", cycle);
    printf("Instructions     : %" PRIu64 "\n", commit);
    printf("IPC              : %.4f\n", ratio(commit, cycle));
    printf("CPI              : %.4f\n", ratio(cycle, commit));
#ifdef F
    printf("Clock estimate   : %d MHz (F=%d)\n", F * 10, F);
#endif
    printf("Commit (state)   : %" PRIu64 " (%s)\n", state_commit,
           state_commit == commit ? "OK" : "MISMATCH");
    printf("Fetch / commit   : %" PRIu64 " / %" PRIu64 " (%s)\n", if_fetch, commit,
           if_fetch == commit ? "OK" : "MISMATCH");

    printf("\n[Instruction mix]\n");
    printf("  %-14s %10s  %7s\n", "category", "count", "share");
    printf("  %-14s %10s  %7s\n", "--------------", "----------", "-------");
    print_mix("alu", alu, commit);
    print_mix("load", load, commit);
    print_mix("store", store, commit);
    print_mix("branch", branch, commit);
    print_mix("jump", jump, commit);
    print_mix("upper", upper, commit);
    print_mix("csr", csr, commit);
    print_mix("ecall", ecall, commit);
    print_mix("mret", mret, commit);
    print_mix("ebreak", ebreak, commit);
    printf("  %-14s %10" PRIu64 "  %s\n", "class sum", class_sum,
           class_sum == commit ? "OK" : "MISMATCH");

    printf("  ALU breakdown  : R=%" PRIu64 ", I=%" PRIu64 " (%s)\n",
           alu_r, alu_i, alu_r + alu_i == alu ? "OK" : "MISMATCH");
    printf("  Load width     : byte=%" PRIu64 ", half=%" PRIu64 ", word=%" PRIu64 " (%s)\n",
           ld_byte, ld_half, ld_word,
           ld_byte + ld_half + ld_word == load ? "OK" : "MISMATCH");
    printf("  Store width    : byte=%" PRIu64 ", half=%" PRIu64 ", word=%" PRIu64 " (%s)\n",
           st_byte, st_half, st_word,
           st_byte + st_half + st_word == store ? "OK" : "MISMATCH");

    printf("\n[Control flow]\n");
    printf("  conditional branch : %" PRIu64 "\n", branch);
    printf("  taken / not taken  : %" PRIu64 " / %" PRIu64 " (%.2f%% taken)\n",
           branch_taken, branch_not_taken, percent(branch_taken, branch));
    printf("  jal / jalr         : %" PRIu64 " / %" PRIu64 " (%s)\n",
           jal, jalr, jal + jalr == jump ? "OK" : "MISMATCH");
    printf("  control transfer   : %.2f%% of committed instructions\n",
           percent(branch + jump, commit));

    printf("\n[IFU behavior]\n");
    printf("  fetched            : %" PRIu64 "\n", if_fetch);
    printf("  uncached bypass    : %" PRIu64 " requests\n", if_bypass);
    printf("  stall (busy AR)    : %" PRIu64 " cycles\n", if_stall_bus);
    printf("  stall (wait R)     : %" PRIu64 " cycles\n", if_stall_mem);
    printf("  stall ratio        : %.2f%% of cycles\n",
           percent(if_stall_bus + if_stall_mem, cycle));
    printf("  avg R wait / fetch : %.4f cycles\n", ratio(if_stall_mem, if_fetch));
    printf("  fetch path check   : hit+miss+bypass = %" PRIu64 " (%s)\n",
           ic_hit + ic_miss + if_bypass,
           ic_hit + ic_miss + if_bypass == if_fetch ? "OK" : "MISMATCH");

    printf("\n[ICache behavior]\n");
    printf("  access / hit / miss: %" PRIu64 " / %" PRIu64 " / %" PRIu64 "\n",
           ic_access, ic_hit, ic_miss);
    printf("  hit rate / miss rate: %.2f%% / %.2f%%\n",
           percent(ic_hit, ic_access), percent(ic_miss, ic_access));
    printf("  compulsory / replace: %" PRIu64 " / %" PRIu64 " (%s)\n",
           ic_compulsory, ic_replace,
           ic_compulsory + ic_replace == ic_miss ? "OK" : "MISMATCH");
    printf("  refill AR          : %" PRIu64 " (%s)\n", ic_refill,
           ic_refill == ic_miss ? "OK" : "MISMATCH");
    printf("  miss AR wait       : %" PRIu64 " cycles\n", ic_miss_ar);
    printf("  miss R wait        : %" PRIu64 " cycles\n", ic_miss_r);
    printf("  avg miss latency   : %.4f cycles\n", ratio(ic_miss_ar + ic_miss_r, ic_miss));
    printf("  misses per 1k inst : %.2f\n", ratio(ic_miss, commit) * 1000.0);

    printf("\n[LSU behavior]\n");
    printf("  load / store done  : %" PRIu64 " / %" PRIu64 "\n", ld_done, st_done);
    printf("  load width         : byte=%" PRIu64 ", half=%" PRIu64 ", word=%" PRIu64 "\n",
           ld_byte, ld_half, ld_word);
    printf("  store width        : byte=%" PRIu64 ", half=%" PRIu64 ", word=%" PRIu64 "\n",
           st_byte, st_half, st_word);
    printf("  load wait cycles   : %" PRIu64 "\n", ld_wait);
    printf("  avg load latency   : %.4f cycles\n", ratio(ld_wait, ld_done));
    printf("  store wait cycles  : %" PRIu64 "\n", st_wait);
    printf("  avg store latency  : %.4f cycles\n", ratio(st_wait, st_done));
    printf("  load / store share : %.2f%% / %.2f%%\n",
           percent(load, commit), percent(store, commit));
    printf("  LSU vs commit      : load=%s, store=%s\n",
           ld_done == load ? "OK" : "MISMATCH",
           st_done == store ? "OK" : "MISMATCH");

    printf("\n[Bus behavior]\n");
    printf("  AR / R             : %" PRIu64 " / %" PRIu64 "\n", bus_ar, bus_r);
    printf("  AW / W / B         : %" PRIu64 " / %" PRIu64 " / %" PRIu64 "\n",
           bus_aw, bus_w, bus_b);
    printf("  AR stall cycles    : %" PRIu64 " (%.2f%% of cycles)\n",
           bus_ar_stall, percent(bus_ar_stall, cycle));
    printf("  beats per read     : %.2f\n", ratio(bus_r, bus_ar));
    printf("  beats per write    : %.2f\n", ratio(bus_w, bus_aw));
    printf("  AR source check    : refill+bypass+load = %" PRIu64 " vs AR = %" PRIu64 " (%s)\n",
           ic_refill + if_bypass + load, bus_ar,
           ic_refill + if_bypass + load == bus_ar ? "OK" : "MISMATCH");
    printf("  write source check : store=%" PRIu64 ", AW=%" PRIu64 ", W=%" PRIu64 ", B=%" PRIu64 " (%s)\n",
           store, bus_aw, bus_w, bus_b,
           (store == bus_aw && store == bus_w && store == bus_b) ? "OK" : "MISMATCH");

    printf("\n[System / CSR]\n");
    printf("  CSR total          : %" PRIu64 "\n", csr);
    printf("  csrrw / csrrs      : %" PRIu64 " / %" PRIu64 " (%s)\n",
           csrrw, csrrs, csrrw + csrrs == csr ? "OK" : "MISMATCH");
    printf("  ecall / mret / ebreak: %" PRIu64 " / %" PRIu64 " / %" PRIu64 "\n",
           ecall, mret, ebreak);

    printf("\n[Observation]\n");
    bool any = false;
    if (ic_access && ratio(ic_miss, ic_access) > 0.10) {
        printf("  - ICache miss rate %.2f%%; cache capacity/locality may be limiting fetch.\n",
               percent(ic_miss, ic_access));
        any = true;
    }
    if (ratio(if_stall_bus + if_stall_mem, cycle) > 0.10) {
        printf("  - IFU stall ratio %.2f%%; fetch wait is a significant fraction of cycles.\n",
               percent(if_stall_bus + if_stall_mem, cycle));
        any = true;
    }
    if (ratio(ld_wait, cycle) > 0.10) {
        printf("  - load wait %.2f%% of cycles; data-side memory latency is significant.\n",
               percent(ld_wait, cycle));
        any = true;
    }
    if (ratio(bus_ar_stall, cycle) > 0.05) {
        printf("  - bus AR stall %.2f%% of cycles; arbitration/memory backpressure is visible.\n",
               percent(bus_ar_stall, cycle));
        any = true;
    }
    if (branch && ratio(branch_taken, branch) > 0.50) {
        printf("  - taken branch ratio %.2f%%; without a branch predictor, fetch redirects are frequent.\n",
               percent(branch_taken, branch));
        any = true;
    }
    if (!any) {
        printf("  - no single dominant stall above current thresholds.\n");
    }
    printf("==========================================================\n");

    Log("Perf summary: cycles=%llu inst=%llu ipc=%.4f cpi=%.4f icache_access=%llu icache_hit=%llu icache_miss=%llu icache_hit_rate=%.4f if_bypass=%llu",
        (unsigned long long)cycle, (unsigned long long)commit, ratio(commit, cycle),
        ratio(cycle, commit), (unsigned long long)ic_access, (unsigned long long)ic_hit,
        (unsigned long long)ic_miss, ratio(ic_hit, ic_access),
        (unsigned long long)if_bypass);
    Log("Perf memory: load=%llu store=%llu load_latency=%.4f store_latency=%.4f bus_ar=%llu bus_aw=%llu bus_ar_stall=%llu branch_taken_rate=%.4f",
        (unsigned long long)load, (unsigned long long)store,
        ratio(ld_wait, ld_done), ratio(st_wait, st_done),
        (unsigned long long)bus_ar, (unsigned long long)bus_aw,
        (unsigned long long)bus_ar_stall, ratio(branch_taken, branch));
}
