/***************************************************************************************
* NPC CPU Execution
* CPU执行控制模块实现
***************************************************************************************/

#include "cpu.h"
#include "npc.h"
#include "memory.h"
#include "device.h"
#include "../utils/log.h"
#include "../utils/difftest.h"
#include "../sdb/sdb.h"
#include <verilated.h>
#include "Vtop.h"

#ifdef ENABLE_FST
#include <verilated_fst_c.h>
#endif

#ifdef ENABLE_TRACE
#include "../trace/itrace.h"
#include "../trace/mtrace.h"
#include "../trace/ftrace.h"
#endif

// 全局变量：顶层模块指针和仿真上下文
Vtop* g_top = NULL;
static VerilatedContext* g_contextp = NULL;

#ifdef ENABLE_FST
static VerilatedFstC* g_tfp = NULL;
#endif

// itrace控制：是否输出到控制台
static bool g_print_itrace = false;

// 初始化CPU
bool init_cpu(int argc, char** argv) {
    g_contextp = new VerilatedContext;
    g_contextp->commandArgs(argc, argv);
    g_top = new Vtop{g_contextp};

#ifdef ENABLE_FST
    Verilated::traceEverOn(true);
    g_tfp = new VerilatedFstC;
    g_top->trace(g_tfp, 99);
    g_tfp->open("wave/dump.fst");
    Log("FST wave tracing enabled: wave/dump.fst");
    printf("FST: ON  -> wave/dump.fst\n");
#else
    printf("FST: OFF\n");
#endif

#ifdef ENABLE_TRACE
    printf("Trace: ON\n");
#else
    printf("Trace: OFF\n");
#endif

    return true;
}

// 复位CPU
void reset_cpu() {
    Log("Resetting NPC...");
    g_top->rst = 1;
    g_top->clk = 0;
    g_top->eval();
    
    g_contextp->timeInc(1);
    g_top->clk = 1;
    g_top->eval();
    
    g_contextp->timeInc(1);
    g_top->rst = 0;
    Log("Reset complete");
}

// 单步执行
void exec_once() {
    uint32_t current_pc = npc_get_pc();

    // 下降沿
    g_top->clk = 0;
    g_top->eval();
#ifdef ENABLE_FST
    if (g_tfp) g_tfp->dump(g_contextp->time());
#endif
    g_contextp->timeInc(1);

    // 上升沿
    g_top->clk = 1;
    g_top->eval();
#ifdef ENABLE_FST
    if (g_tfp) g_tfp->dump(g_contextp->time());
#endif
    g_contextp->timeInc(1);

    npc_inc_cycle();
    device_update();

#ifdef ENABLE_TRACE
    ftrace_flush(g_print_itrace);
    itrace_log(npc_get_pc(), npc_get_inst(), g_print_itrace);
    mtrace_flush(g_print_itrace);
#endif

    difftest_step(current_pc, npc_get_pc());
}

// 设置itrace输出模式
void set_itrace_print(bool enable) {
    g_print_itrace = enable;
}

// CPU执行n条指令
void cpu_exec(uint64_t n) {
    NPCState* state = npc_get_state();
    
    if (state->state == NPC_END || state->state == NPC_ABORT) {
        Log("Program has already exited. Use 'q' to quit.");
        printf("Program has already exited. Use 'q' to quit.\n");
        return;
    }
    
    state->state = NPC_RUNNING;

    // si命令且n<=10时输出到控制台
    set_itrace_print(n <= 10);

    uint64_t cycles = 0;
    bool hit_watchpoint = false;

    Log("Starting execution of %lu instructions", n == (uint64_t)-1 ? 0 : n);

#ifdef ENABLE_TRACE
    if (n > 10) enable_log_buffer();
#endif
    
    while (cycles < n || n == (uint64_t)-1) {
        exec_once();
        cycles++;
        
        // 检查是否遇到ebreak
        if (npc_should_exit() || state->state != NPC_RUNNING) {
            Log("Execution stopped at cycle %lu due to EBREAK", cycles);
            break;
        }
        
        // 检查监视点
        if (check_watchpoints()) {
            hit_watchpoint = true;
            state->state = NPC_STOP;
            Log("Execution stopped at cycle %lu due to watchpoint", cycles);
            printf("Program stopped due to watchpoint.\n");
            break;
        }
        
        // 避免无限循环（仅 TRACE 开启时打印进度，避免频繁 I/O）
#ifdef ENABLE_TRACE
        if (cycles % 1000000 == 0 && n == (uint64_t)-1) {
            Log("Executed %lu cycles...", cycles);
            printf("Executed %lu cycles...\n", cycles);
        }
#endif
    }

#ifdef ENABLE_TRACE
    if (n > 10) flush_log_buffer();
#endif
    
    if (state->state == NPC_RUNNING) {
        state->state = NPC_STOP;
    }
    
    if (!hit_watchpoint && state->state == NPC_STOP) {
#ifdef ENABLE_TRACE
        Log("Executed %lu cycles", cycles);
        printf("Executed %lu cycles.\n", cycles);
#endif
    }
}

// 清理CPU资源
void cleanup_cpu() {
    g_top->final();
#ifdef ENABLE_FST
    if (g_tfp) {
        g_tfp->close();
        delete g_tfp;
    }
#endif
    delete g_top;
    delete g_contextp;
    device_cleanup();
}
