/***************************************************************************************
* NPC CPU Execution
* CPU执行控制模块实现
***************************************************************************************/

#include "cpu.h"
#include "npc.h"
#include "memory.h"
#include "../utils/log.h"
#include "../trace/itrace.h"
#include "../trace/mtrace.h"
#include "../trace/ftrace.h"
#include "../utils/difftest.h"
#include "../sdb/sdb.h"
#include <verilated.h>
#include <verilated_fst_c.h>
#include "Vtop.h"

// 全局变量：顶层模块指针和仿真上下文
Vtop* g_top = NULL;
static VerilatedContext* g_contextp = NULL;
static VerilatedFstC* g_tfp = NULL;

// itrace控制：是否输出到控制台
static bool g_print_itrace = false;

// 初始化CPU
bool init_cpu(int argc, char** argv) {
    // 初始化Verilator上下文
    g_contextp = new VerilatedContext;
    g_contextp->commandArgs(argc, argv);
    
    // 创建顶层模块
    g_top = new Vtop{g_contextp};
    
    // 启用波形追踪（可选）
    // Verilated::traceEverOn(true);
    // g_tfp = new VerilatedFstC;
    // g_top->trace(g_tfp, 99);
    // g_tfp->open("wave/dump.fst");
    
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
    // 保存当前PC用于DiffTest
    uint32_t current_pc = npc_get_pc();
    
    // 下降沿
    g_top->clk = 0;
    g_top->eval();
    if (g_tfp) g_tfp->dump(g_contextp->time());
    
    g_contextp->timeInc(1);
    
    // 上升沿
    g_top->clk = 1;
    g_top->eval();
    if (g_tfp) g_tfp->dump(g_contextp->time());
    
    g_contextp->timeInc(1);
    
    // 增加周期计数
    npc_inc_cycle();
    
    // 统一输出trace（按顺序：ftrace -> itrace -> mtrace）
    ftrace_flush(g_print_itrace);
    itrace_log(npc_get_pc(), npc_get_inst(), g_print_itrace);
    mtrace_flush(g_print_itrace);
    
    // DiffTest：对比执行结果
    uint32_t next_pc = npc_get_pc();
    difftest_step(current_pc, next_pc);
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
    
    // 设置itrace输出模式：si命令且n<=10时输出到控制台
    set_itrace_print(n <= 10);
    
    uint64_t cycles = 0;
    bool hit_watchpoint = false;
    
    Log("Starting execution of %lu instructions", n == (uint64_t)-1 ? 0 : n);
    
    // 对于长时间运行（c命令或si>10），启用日志缓冲区
    if (n > 10) {
        enable_log_buffer();
    }
    
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
        
        // 避免无限循环
        if (cycles % 1000000 == 0 && n == (uint64_t)-1) {
            Log("Executed %lu cycles...", cycles);
            printf("Executed %lu cycles...\n", cycles);
        }
    }
    
    // 刷新日志缓冲区到文件
    if (n > 10) {
        flush_log_buffer();
    }
    
    if (state->state == NPC_RUNNING) {
        state->state = NPC_STOP;
    }
    
    if (!hit_watchpoint && state->state == NPC_STOP) {
        Log("Executed %lu cycles", cycles);
        printf("Executed %lu cycles.\n", cycles);
    }
}

// 清理CPU资源
void cleanup_cpu() {
    g_top->final();
    if (g_tfp) {
        g_tfp->close();
        delete g_tfp;
    }
    delete g_top;
    delete g_contextp;
}
