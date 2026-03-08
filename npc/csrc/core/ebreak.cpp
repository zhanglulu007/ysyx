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
