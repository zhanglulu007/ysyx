#include "core/cpu.h"
#include "core/device.h"
#include "core/ebreak.h"
#include "core/npc.h"
#include "sdb/sdb.h"
#include "utils/difftest.h"
#include "utils/log.h"

#include <cstdio>
#include <verilated.h>
#include "Vtop.h"

#ifdef ENABLE_FST
#include <verilated_fst_c.h>
#endif

#ifdef ENABLE_TRACE
#include "trace/ftrace.h"
#include "trace/itrace.h"
#include "trace/mtrace.h"
#endif

static Vtop* top = nullptr;
static VerilatedContext* contextp = nullptr;
static bool print_itrace = false;

#ifdef ENABLE_FST
static VerilatedFstC* tfp = nullptr;
#endif

static void eval_half_cycle(int clock_value) {
    top->clk = clock_value;
    top->eval();
#ifdef ENABLE_FST
    if (tfp) tfp->dump(contextp->time());
#endif
    contextp->timeInc(1);
}

bool init_cpu(int argc, char** argv) {
    contextp = new VerilatedContext;
    contextp->commandArgs(argc, argv);
    top = new Vtop{contextp};

#ifdef ENABLE_FST
    Verilated::traceEverOn(true);
    tfp = new VerilatedFstC;
    top->trace(tfp, 99);
    tfp->open("rtl-old/wave/dump.fst");
    printf("FST: ON  -> rtl-old/wave/dump.fst\n");
#else
    printf("FST: OFF\n");
#endif

#ifdef ENABLE_TRACE
    printf("Trace: ON\n");
#else
    printf("Trace: OFF\n");
#endif
    printf("Mode: direct DPI-C memory, one instruction per cycle\n");
    return true;
}

void reset_cpu() {
    Log("Resetting single-cycle NPC...");
    top->rst = 1;
    for (int i = 0; i < 10; i++) {
        eval_half_cycle(0);
        eval_half_cycle(1);
    }
    top->rst = 0;
    Log("Reset complete");
}

void exec_once() {
    const uint32_t current_pc = npc_get_pc();

    eval_half_cycle(0);
    eval_half_cycle(1);
    npc_inc_cycle();
    device_update();

#ifdef ENABLE_TRACE
    if (top->insdone_out) {
        ftrace_flush(print_itrace);
        itrace_log(npc_get_pc(), npc_get_inst(), print_itrace);
        mtrace_flush(print_itrace);
    }
#endif

    if (top->insdone_out) {
        difftest_step(current_pc, npc_get_pc());
    }
}

void set_itrace_print(bool enable) {
    print_itrace = enable;
}

void cpu_exec(uint64_t n) {
    NPCState* state = npc_get_state();
    if (state->state == NPC_END || state->state == NPC_ABORT) {
        printf("Program has already exited. Use 'q' to quit.\n");
        return;
    }

    state->state = NPC_RUNNING;
    set_itrace_print(n <= 10);
    uint64_t instructions = 0;

    while (instructions < n || n == static_cast<uint64_t>(-1)) {
        exec_once();
        instructions++;

        if (npc_should_exit() || state->state != NPC_RUNNING) break;

        if (check_watchpoints()) {
            state->state = NPC_STOP;
            printf("Program stopped due to watchpoint.\n");
            break;
        }
    }

    if (state->state == NPC_RUNNING) state->state = NPC_STOP;
    Log("Executed %lu instructions in %lu cycles, IPC=%.4f",
        instructions, npc_get_cycle(),
        npc_get_cycle() ? static_cast<double>(instructions) / npc_get_cycle() : 0.0);
}

void cleanup_cpu() {
    top->final();
#ifdef ENABLE_FST
    if (tfp) {
        tfp->close();
        delete tfp;
        tfp = nullptr;
    }
#endif
    delete top;
    delete contextp;
    top = nullptr;
    contextp = nullptr;
    device_cleanup();
}
