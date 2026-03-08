/***************************************************************************************
* NPC Register Interface
* 寄存器访问接口实现
***************************************************************************************/

#include "reg.h"
#include "npc.h"
#include <cstdio>
#include <cstring>

// RISC-V寄存器名称
static const char *regs[] = {
    "$0", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
    "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5",
    "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7",
    "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6"
};

// 寄存器名称转换为值
word_t npc_reg_str2val(const char *s, bool *success) {
    *success = true;
    
    if (strcmp(s, "pc") == 0) {
        return npc_get_pc();
    }
    
    for (int i = 0; i < 32; i++) {
        if (strcmp(s, regs[i]) == 0) {
            return npc_get_reg(i);
        }
        
        char xname[8];
        sprintf(xname, "x%d", i);
        if (strcmp(s, xname) == 0) {
            return npc_get_reg(i);
        }
    }
    
    *success = false;
    return 0;
}

// 打印所有寄存器
void npc_reg_display() {
    for (int i = 0; i < 32; i++) {
        printf("%-4s  0x%08x\n", regs[i], npc_get_reg(i));
    }
    printf("%-4s  0x%08x\n", "pc", npc_get_pc());
}
