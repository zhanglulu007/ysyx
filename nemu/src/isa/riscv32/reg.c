/***************************************************************************************
* Copyright (c) 2014-2024 Zihao Yu, Nanjing University
*
* NEMU is licensed under Mulan PSL v2.
* You can use this software according to the terms and conditions of the Mulan PSL v2.
* You may obtain a copy of Mulan PSL v2 at:
*          http://license.coscl.org.cn/MulanPSL2
*
* THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
* EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
* MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
*
* See the Mulan PSL v2 for more details.
***************************************************************************************/

#include <isa.h>
#include "local-include/reg.h"

const char *regs[] = {
  "$0", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
  "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5",
  "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7",
  "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6"
};

void isa_reg_display() {
  // 打印32个通用寄存器
  int nr_regs = MUXDEF(CONFIG_RVE, 16, 32);
  for (int i = 0; i < nr_regs; i++) {
    printf("%-4s  0x%08x\n", regs[i], cpu.gpr[i]);
  }
  // 打印PC寄存器
  printf("%-4s  0x%08x\n", "pc", cpu.pc);
  // 打印CSR寄存器
  printf("%-8s  0x%08x\n", "mstatus", cpu.mstatus);
  printf("%-8s  0x%08x\n", "mtvec", cpu.mtvec);
  printf("%-8s  0x%08x\n", "mepc", cpu.mepc);
  printf("%-8s  0x%08x\n", "mcause", cpu.mcause);
}

word_t isa_reg_str2val(const char *s, bool *success) {
  *success = true;
  
  // 特殊寄存器：pc
  if (strcmp(s, "pc") == 0) {
    return cpu.pc;
  }
  
  // CSR寄存器
  if (strcmp(s, "mstatus") == 0) {
    return cpu.mstatus;
  }
  if (strcmp(s, "mtvec") == 0) {
    return cpu.mtvec;
  }
  if (strcmp(s, "mepc") == 0) {
    return cpu.mepc;
  }
  if (strcmp(s, "mcause") == 0) {
    return cpu.mcause;
  }
  
  // 通用寄存器：按名字匹配
  int nr_regs = MUXDEF(CONFIG_RVE, 16, 32);
  for (int i = 0; i < nr_regs; i++) {
    if (strcmp(s, regs[i]) == 0) {
      return cpu.gpr[i];
    }
    
    // 也支持 x0-x31 的形式
    char xname[8];
    sprintf(xname, "x%d", i);
    if (strcmp(s, xname) == 0) {
      return cpu.gpr[i];
    }
  }
  
  // 未找到寄存器
  *success = false;
  return 0;
}
