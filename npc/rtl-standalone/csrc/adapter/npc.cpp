#include "core/npc.h"

static NPCState npc_state = { .state = NPC_STOP };
static bool should_exit = false;
static uint32_t exit_code = 0;
static uint64_t cycle_count = 0;
static uint64_t commit_count = 0;
static uint32_t reg_cache[32] = {};
static uint32_t pc_cache = 0;
static uint32_t inst_cache = 0;

NPCState* npc_get_state() {
    return &npc_state;
}

uint64_t npc_get_cycle() {
    return cycle_count;
}

uint64_t npc_get_commit_count() {
    return commit_count;
}

void npc_inc_cycle() {
    cycle_count++;
}

uint32_t npc_get_pc() {
    return pc_cache;
}

uint32_t npc_get_inst() {
    return inst_cache;
}

uint32_t npc_get_reg(int idx) {
    if (idx <= 0 || idx >= 32) return 0;
    return reg_cache[idx];
}

void npc_set_exit(bool exit, uint32_t code) {
    should_exit = exit;
    exit_code = code;
}

bool npc_should_exit() {
    return should_exit;
}

uint32_t npc_get_exit_code() {
    return exit_code;
}

extern "C" void update_reg_value(int idx, int value) {
    if (idx > 0 && idx < 32) {
        reg_cache[idx] = static_cast<uint32_t>(value);
    }
}

extern "C" void update_pc_value(int pc_val) {
    pc_cache = static_cast<uint32_t>(pc_val);
}

extern "C" void update_inst_value(int pc_val, int inst_val) {
    (void)pc_val;
    inst_cache = static_cast<uint32_t>(inst_val);
    commit_count++;
}

extern "C" void commit_instruction(int pc_val, int inst_val, int next_pc_val) {
    (void)pc_val;
    inst_cache = static_cast<uint32_t>(inst_val);
    pc_cache = static_cast<uint32_t>(next_pc_val);
    commit_count++;
}
