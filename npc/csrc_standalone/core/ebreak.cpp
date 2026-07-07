/***************************************************************************************
* NPC EBREAK Handler
* EBREAK指令处理实现
***************************************************************************************/

#include "ebreak.h"
#include "npc.h"
#include "../utils/difftest.h"
#include <cstdio>

// DPI-C函数：ebreak处理
extern "C" void ebreak_handler(int code) {
    // code是a0寄存器的值，0表示成功，非0表示失败

    // ebreak是特殊指令，需要跳过DiffTest
    difftest_skip_ref();

    if (code == 0) {
        printf("\n*** HIT GOOD TRAP ***\n");
    } else {
        printf("\n*** HIT BAD TRAP (code=%d) ***\n", code);
    }

    npc_set_exit(true, code);
    NPCState* state = npc_get_state();
    state->state = NPC_END;
    state->halt_ret = code;
}

// DPI-C函数：Access Fault处理
// 当 AXI resp 返回错误(取指/load/store访问了未分配地址或设备错误)时, NPC 跳转到地址0.
// 这里仅打印告警信息, 不停止仿真 (跳转地址0后程序会异常, 让你察觉系统运行不正常).
extern "C" void access_fault_handler(int pc_val, int is_store) {
    printf("\n*** ACCESS FAULT at PC=0x%08x (%s), jumping to address 0 ***\n",
           pc_val, is_store ? "store" : "fetch/load");
    // Access Fault 跳转不在 NEMU 中模拟, 跳过 DiffTest 以避免误报
    difftest_skip_ref();
}
