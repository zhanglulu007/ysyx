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

#ifndef __RISCV_REG_H__
#define __RISCV_REG_H__

#include <common.h>

static inline int check_reg_idx(int idx) {
  IFDEF(CONFIG_RT_CHECK, assert(idx >= 0 && idx < MUXDEF(CONFIG_RVE, 16, 32)));
  return idx;
}

#define gpr(idx) (cpu.gpr[check_reg_idx(idx)])

static inline const char* reg_name(int idx) {
  extern const char* regs[];
  return regs[check_reg_idx(idx)];
}

// CSR register access helper
// 注: csrr/csr 指令的 CSR 地址在指令 [31:20] 共 12 位, 经 I-type 立即数解码后
// 会被符号扩展为 32 位 (如 0xF11 -> 0xFFFFFF11), 故此处需 & 0xfff 取低 12 位.
#define csr(addr) (*({ \
  word_t __csr_addr = (addr) & 0xfff; \
  word_t *__csr_ptr = NULL; \
  switch (__csr_addr) { \
    case 0x300: __csr_ptr = &cpu.mstatus; break;  \
    case 0x305: __csr_ptr = &cpu.mtvec; break;    \
    case 0x341: __csr_ptr = &cpu.mepc; break;     \
    case 0x342: __csr_ptr = &cpu.mcause; break;   \
    case 0xF11: __csr_ptr = &cpu.mvendorid; break; \
    case 0xF12: __csr_ptr = &cpu.marchid; break;   \
    default: panic("Unknown CSR register: 0x%x", __csr_addr); \
  } \
  __csr_ptr; \
}))

#endif
