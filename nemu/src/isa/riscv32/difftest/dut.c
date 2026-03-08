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
#include <cpu/difftest.h>
#include "../local-include/reg.h"

#ifdef CONFIG_DIFFTEST
// External reference to difftest functions
extern void (*ref_difftest_regcpy)(void *dut, bool direction);
#endif

bool isa_difftest_checkregs(CPU_state *ref_r, vaddr_t pc) {
  // 检查PC寄存器
  if (!difftest_check_reg("pc", pc, ref_r->pc, cpu.pc)) {
    return false;
  }
  
  // 检查32个通用寄存器
  for (int i = 0; i < MUXDEF(CONFIG_RVE, 16, 32); i++) {
    if (!difftest_check_reg(reg_name(i), pc, ref_r->gpr[i], cpu.gpr[i])) {
      return false;
    }
  }
  
  // 检查CSR寄存器
  if (!difftest_check_reg("mstatus", pc, ref_r->mstatus, cpu.mstatus)) {
    return false;
  }
  if (!difftest_check_reg("mcause", pc, ref_r->mcause, cpu.mcause)) {
    return false;
  }
  if (!difftest_check_reg("mepc", pc, ref_r->mepc, cpu.mepc)) {
    return false;
  }
  if (!difftest_check_reg("mtvec", pc, ref_r->mtvec, cpu.mtvec)) {
    return false;
  }
  
  return true;
}

void isa_difftest_attach() {
#ifdef CONFIG_DIFFTEST
  // Sync CSR registers from reference (Spike) to DUT (NEMU)
  // This is called after difftest initialization to get the correct initial CSR values
  Log("isa_difftest_attach() called");
  
  if (ref_difftest_regcpy == NULL) {
    Log("Warning: ref_difftest_regcpy is NULL, cannot sync CSR registers");
    return;
  }
  
  CPU_state ref_r;
  ref_difftest_regcpy(&ref_r, DIFFTEST_TO_DUT);
  
  Log("Syncing CSR registers from Spike: mstatus=0x%08x, mtvec=0x%08x, mepc=0x%08x, mcause=0x%08x",
      ref_r.mstatus, ref_r.mtvec, ref_r.mepc, ref_r.mcause);
  
  // Copy CSR registers from reference
  cpu.mstatus = ref_r.mstatus;
  cpu.mtvec = ref_r.mtvec;
  cpu.mepc = ref_r.mepc;
  cpu.mcause = ref_r.mcause;
  
  Log("NEMU CSR registers after sync: mstatus=0x%08x, mtvec=0x%08x, mepc=0x%08x, mcause=0x%08x",
      cpu.mstatus, cpu.mtvec, cpu.mepc, cpu.mcause);
#endif
}
