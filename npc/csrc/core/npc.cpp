/***************************************************************************************
* NPC Core
* NPC核心状态管理实现
***************************************************************************************/

#include "npc.h"

// NPC状态
static NPCState npc_state = { .state = NPC_STOP };

// 退出标志
static bool should_exit = false;
static uint32_t exit_code = 0;

// 周期计数器
static uint64_t g_cycle_cnt = 0;
static uint64_t g_commit_cnt = 0;

// 寄存器和指令缓存（在C++侧维护）
static uint32_t reg_cache[32] = {0};
static uint32_t pc_cache = 0;
static uint32_t inst_cache = 0;

// 获取NPC状态
NPCState* npc_get_state() {
    return &npc_state;
}

// 获取当前周期数
uint64_t npc_get_cycle() {
    return g_cycle_cnt;
}

uint64_t npc_get_commit_count() {
    return g_commit_cnt;
}

// 增加周期计数
void npc_inc_cycle() {
    g_cycle_cnt++;
}

// 获取当前PC
uint32_t npc_get_pc() {
    return pc_cache;
}

// 获取当前指令
uint32_t npc_get_inst() {
    return inst_cache;
}

// 获取寄存器值
uint32_t npc_get_reg(int idx) {
    if (idx == 0) return 0;  // x0恒为0
    if (idx < 0 || idx >= 32) return 0;
    return reg_cache[idx];
}

// 设置退出标志
void npc_set_exit(bool exit, uint32_t code) {
    should_exit = exit;
    exit_code = code;
}

// 检查是否应该退出
bool npc_should_exit() {
    return should_exit;
}

// 获取退出码
uint32_t npc_get_exit_code() {
    return exit_code;
}

// DPI-C函数：从Verilog接收寄存器更新
extern "C" void update_reg_value(int idx, int value) {
    if (idx >= 0 && idx < 32) {
        reg_cache[idx] = value;
    }
}

// DPI-C函数：从Verilog接收PC更新
extern "C" void update_pc_value(int pc_val) {
    pc_cache = pc_val;
}

// DPI-C函数：从Verilog接收指令更新
extern "C" void update_inst_value(int pc_val, int inst_val) {
    pc_cache = pc_val;
    inst_cache = inst_val;
}

extern "C" void commit_instruction(int pc_val, int inst_val, int next_pc_val) {
    (void)pc_val;
    pc_cache = next_pc_val;
    inst_cache = inst_val;
    g_commit_cnt++;
}
