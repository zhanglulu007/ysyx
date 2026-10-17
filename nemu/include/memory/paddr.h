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

#ifndef __MEMORY_PADDR_H__
#define __MEMORY_PADDR_H__

#include <common.h>

#ifdef YSYXSOC_REF
/* ===== ysyxsoc REF 地址空间 (不存在 pmem, 与 ysyxSoC 一致) =====
 * FLASH 0x30000000 16MB: 复位向量/镜像入口 (XIP), 只读
 * SRAM  0x0f000000 8KB : FSBL/SSBL 运行区
 * SDRAM 0xa0000000 32MB: 主程序运行区 */
#define FLASH_LEFT  ((paddr_t)0x30000000)
#define FLASH_SIZE  0x1000000
#define FLASH_RIGHT (FLASH_LEFT + FLASH_SIZE - 1)
#define SRAM_LEFT   ((paddr_t)0x0f000000)
#define SRAM_SIZE   0x2000
#define SRAM_RIGHT  (SRAM_LEFT + SRAM_SIZE - 1)
#define SDRAM_LEFT  ((paddr_t)0xa0000000)
#define SDRAM_SIZE  0x2000000
#define SDRAM_RIGHT (SDRAM_LEFT + SDRAM_SIZE - 1)
#define RESET_VECTOR FLASH_LEFT

bool in_flash(paddr_t addr);
bool in_sram(paddr_t addr);
bool in_sdram(paddr_t addr);
uint8_t* flash_to_host(paddr_t paddr);
uint8_t* sram_to_host(paddr_t paddr);
uint8_t* sdram_to_host(paddr_t paddr);
#else
#define PMEM_LEFT  ((paddr_t)CONFIG_MBASE)
#define PMEM_RIGHT ((paddr_t)CONFIG_MBASE + CONFIG_MSIZE - 1)
#define RESET_VECTOR (PMEM_LEFT + CONFIG_PC_RESET_OFFSET)

static inline bool in_pmem(paddr_t addr) {
  return addr - CONFIG_MBASE < CONFIG_MSIZE;
}
#endif

/* convert the guest physical address in the guest program to host virtual address in NEMU
 * (ysyxsoc REF 中复位向量位于 FLASH, 该接口映射到 FLASH 窗口) */
uint8_t* guest_to_host(paddr_t paddr);
/* convert the host virtual address in NEMU to guest physical address in the guest program */
paddr_t host_to_guest(uint8_t *haddr);

word_t paddr_read(paddr_t addr, int len);
void paddr_write(paddr_t addr, int len, word_t data);

#endif
