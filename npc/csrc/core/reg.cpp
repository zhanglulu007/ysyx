/***************************************************************************************
* NPC Register Interface
* 寄存器访问接口实现
***************************************************************************************/

#include "reg.h"
#include "npc.h"
#include "../utils/log.h"
#include <cstdio>
#include <cstring>

// RISC-V寄存器名称
static const char *regs[] = {
    "$0", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
    "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5",
};

static const char *csr_names[] = {
    "mstatus", "mtvec", "mepc", "mcause", "mcycle", "mcycleh",
};

// 寄存器名称转换为值
word_t npc_reg_str2val(const char *s, bool *success) {
    *success = true;
    
    if (strcmp(s, "pc") == 0) {
        return npc_get_pc();
    }
    
    for (int i = 0; i < 16; i++) {
        if (strcmp(s, regs[i]) == 0) {
            return npc_get_reg(i);
        }
        
        char xname[8];
        sprintf(xname, "x%d", i);
        if (strcmp(s, xname) == 0) {
            return npc_get_reg(i);
        }
    }

    for (int i = 0; i < 6; i++) {
        if (strcmp(s, csr_names[i]) == 0) {
            return npc_get_csr(i);
        }
    }
    
    *success = false;
    return 0;
}

// 打印所有寄存器和 CSR；同时写入日志，便于失败快照回溯
void npc_reg_display() {
    for (int i = 0; i < 16; i++) {
        printf("%-7s 0x%08x\n", regs[i], npc_get_reg(i));
        log_write("%-7s 0x%08x\n", regs[i], npc_get_reg(i));
    }
    printf("%-7s 0x%08x\n", "pc", npc_get_pc());
    log_write("%-7s 0x%08x\n", "pc", npc_get_pc());

    for (int i = 0; i < 6; i++) {
        printf("%-7s 0x%08x\n", csr_names[i], npc_get_csr(i));
        log_write("%-7s 0x%08x\n", csr_names[i], npc_get_csr(i));
    }
}
