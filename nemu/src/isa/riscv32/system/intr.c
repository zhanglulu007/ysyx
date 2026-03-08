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
#include <utils.h>

#ifdef CONFIG_ETRACE
// Exception names for RISC-V
static const char *exception_names[] = {
  [0]  = "Instruction address misaligned",
  [1]  = "Instruction access fault",
  [2]  = "Illegal instruction",
  [3]  = "Breakpoint",
  [4]  = "Load address misaligned",
  [5]  = "Load access fault",
  [6]  = "Store/AMO address misaligned",
  [7]  = "Store/AMO access fault",
  [8]  = "Environment call from U-mode",
  [9]  = "Environment call from S-mode",
  [10] = "Reserved",
  [11] = "Environment call from M-mode",
  [12] = "Instruction page fault",
  [13] = "Load page fault",
  [14] = "Reserved",
  [15] = "Store/AMO page fault",
};

static const char* get_exception_name(word_t NO) {
  if (NO < sizeof(exception_names) / sizeof(exception_names[0]) && exception_names[NO] != NULL) {
    return exception_names[NO];
  }
  return "Unknown exception";
}
#endif

word_t isa_raise_intr(word_t NO, vaddr_t epc) {
  /* TODO: Trigger an interrupt/exception with ``NO''.
   * Then return the address of the interrupt/exception vector.
   */
  
#ifdef CONFIG_ETRACE
  Log("Exception #%d (%s) raised at PC = " FMT_WORD ", jumping to " FMT_WORD,
      NO, get_exception_name(NO), epc, cpu.mtvec);
#endif
  
  // 保存触发异常时的PC到mepc
  cpu.mepc = epc;
  
  // 设置异常号到mcause
  cpu.mcause = NO;
  
  // 返回异常入口地址（从mtvec寄存器读取）
  return cpu.mtvec;
}

word_t isa_query_intr() {
  return INTR_EMPTY;
}
