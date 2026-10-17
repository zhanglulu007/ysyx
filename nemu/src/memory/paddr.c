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

#include <memory/host.h>
#include <memory/paddr.h>
#include <device/mmio.h>
#include <isa.h>

#if   defined(CONFIG_PMEM_MALLOC)
static uint8_t *pmem = NULL;
#else // CONFIG_PMEM_GARRAY
static uint8_t pmem[CONFIG_MSIZE] PG_ALIGN = {};
#endif

uint8_t* guest_to_host(paddr_t paddr) { return pmem + paddr - CONFIG_MBASE; }
paddr_t host_to_guest(uint8_t *haddr) { return haddr - pmem + CONFIG_MBASE; }

/* ===== 地址空间定义 =====
 * pmem 由 CONFIG_MBASE/CONFIG_MSIZE 决定:
 *   - standalone REF (riscv32e-npc):     0x80000000
 *   - ysyxsoc REF    (riscv32e-ysyxsoc): 0x30000000 (Flash 窗口, 取指也从这里开始)
 * YSYXSOC_REF 由 Makefile 的 difftest-so-ysyxsoc 目标注入 (非 Kconfig 选项):
 * 只有 ysyxsoc REF 需要额外的 SRAM/SDRAM 区域, 其余构建仅使用 pmem.
 */
#ifdef YSYXSOC_REF
#define SRAM_SIZE  0x2000
#define SDRAM_SIZE 0x2000000
#define SRAM_LEFT  ((paddr_t)0x0f000000)
#define SDRAM_LEFT ((paddr_t)0xa0000000)

static uint8_t sram[SRAM_SIZE] PG_ALIGN = {};
static uint8_t sdram[SDRAM_SIZE] PG_ALIGN = {};

bool in_sram(paddr_t addr) { return addr - SRAM_LEFT < SRAM_SIZE; }
bool in_sdram(paddr_t addr) { return addr - SDRAM_LEFT < SDRAM_SIZE; }
uint8_t* sram_to_host(paddr_t paddr) { return sram + (paddr - SRAM_LEFT); }
uint8_t* sdram_to_host(paddr_t paddr) { return sdram + (paddr - SDRAM_LEFT); }
#endif

#ifdef CONFIG_MTRACE
static void mtrace_read(paddr_t addr, int len, word_t data) {
#ifdef CONFIG_MTRACE_COND
  if (MTRACE_COND) {
    log_write("[MTRACE] READ  at " FMT_PADDR " len=%d data=" FMT_WORD " pc=" FMT_WORD "\n", 
              addr, len, data, cpu.pc);
  }
#endif
}

static void mtrace_write(paddr_t addr, int len, word_t data) {
#ifdef CONFIG_MTRACE_COND
  if (MTRACE_COND) {
    log_write("[MTRACE] WRITE at " FMT_PADDR " len=%d data=" FMT_WORD " pc=" FMT_WORD "\n", 
              addr, len, data, cpu.pc);
  }
#endif
}
#endif

static word_t pmem_read(paddr_t addr, int len) {
  word_t ret = host_read(guest_to_host(addr), len);
  return ret;
}

static void pmem_write(paddr_t addr, int len, word_t data) {
  host_write(guest_to_host(addr), len, data);
}

static void out_of_bound(paddr_t addr) {
  panic("address = " FMT_PADDR " is out of bound of pmem [" FMT_PADDR ", " FMT_PADDR "] at pc = " FMT_WORD,
      addr, PMEM_LEFT, PMEM_RIGHT, cpu.pc);
}

void init_mem() {
#if   defined(CONFIG_PMEM_MALLOC)
  pmem = malloc(CONFIG_MSIZE);
  assert(pmem);
#endif
  IFDEF(CONFIG_MEM_RANDOM, memset(pmem, rand(), CONFIG_MSIZE));
  Log("physical memory area [" FMT_PADDR ", " FMT_PADDR "]", PMEM_LEFT, PMEM_RIGHT);
}

word_t paddr_read(paddr_t addr, int len) {
  if (in_pmem(addr)) {
    word_t ret = pmem_read(addr, len);
    IFDEF(CONFIG_MTRACE, mtrace_read(addr, len, ret));
    return ret;
  }
#ifdef YSYXSOC_REF
  if (in_sram(addr)) {
    word_t ret = host_read(sram_to_host(addr), len);
    IFDEF(CONFIG_MTRACE, mtrace_read(addr, len, ret));
    return ret;
  }
  if (in_sdram(addr)) {
    word_t ret = host_read(sdram_to_host(addr), len);
    IFDEF(CONFIG_MTRACE, mtrace_read(addr, len, ret));
    return ret;
  }
#endif
  IFDEF(CONFIG_DEVICE, return mmio_read(addr, len));
  out_of_bound(addr);
  return 0;
}

void paddr_write(paddr_t addr, int len, word_t data) {
  IFDEF(CONFIG_MTRACE, mtrace_write(addr, len, data));
  if (in_pmem(addr)) { pmem_write(addr, len, data); return; }
#ifdef YSYXSOC_REF
  if (in_sram(addr)) { host_write(sram_to_host(addr), len, data); return; }
  if (in_sdram(addr)) { host_write(sdram_to_host(addr), len, data); return; }
#endif
  IFDEF(CONFIG_DEVICE, mmio_write(addr, len, data); return);
  out_of_bound(addr);
}
