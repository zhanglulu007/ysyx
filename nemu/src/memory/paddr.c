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

#define CONFIG_MROM_SIZE 0x1000   /* 4KB, 与 ysyxSoC 的 MROM 一致 */
#define CONFIG_SRAM_SIZE 0x2000   /* 8KB, 与 ysyxSoC 的 SRAM 一致 */
#define CONFIG_FLASH_SIZE 0x1000000  /* 16MB, 与 ysyxSoC 的 flash 颗粒(W25Q128JV)一致 */
#define CONFIG_PSRAM_SIZE 0x400000  /* 4MB, 与 ysyxSoC 的 PSRAM 颗粒(IS66WVS4M8ALL)一致 */
#define CONFIG_SDRAM_SIZE 0x2000000 /* 32MB, 与 ysyxSoC 的 SDRAM 颗粒(W9825G6KH)一致 */

#define MROM_LEFT  ((paddr_t)0x20000000)
#define MROM_RIGHT (MROM_LEFT + CONFIG_MROM_SIZE - 1)
#define SRAM_LEFT  ((paddr_t)0x0f000000)
#define SRAM_RIGHT (SRAM_LEFT + CONFIG_SRAM_SIZE - 1)
#define FLASH_LEFT  ((paddr_t)0x30000000)
#define FLASH_RIGHT (FLASH_LEFT + CONFIG_FLASH_SIZE - 1)
#define PSRAM_LEFT  ((paddr_t)0x80000000)
#define PSRAM_RIGHT (PSRAM_LEFT + CONFIG_PSRAM_SIZE - 1)
#define SDRAM_LEFT  ((paddr_t)0xa0000000)
#define SDRAM_RIGHT (SDRAM_LEFT + CONFIG_SDRAM_SIZE - 1)

static uint8_t mrom[CONFIG_MROM_SIZE] PG_ALIGN = {};  /* MROM 镜像 (只读) */
static uint8_t sram[CONFIG_SRAM_SIZE] PG_ALIGN = {};  /* SRAM 镜像 (可读写) */
static uint8_t flash[CONFIG_FLASH_SIZE] PG_ALIGN = {};/* Flash 镜像 (只读) */
static uint8_t psram[CONFIG_PSRAM_SIZE] PG_ALIGN = {};/* PSRAM 镜像 (可读写) */
static uint8_t sdram[CONFIG_SDRAM_SIZE] PG_ALIGN = {};/* SDRAM 镜像 (可读写, riscv32e-ysyxsoc 主程序运行区) */

bool in_mrom(paddr_t addr) { return addr - MROM_LEFT < CONFIG_MROM_SIZE; }
bool in_sram(paddr_t addr) { return addr - SRAM_LEFT < CONFIG_SRAM_SIZE; }
bool in_flash(paddr_t addr) { return addr - FLASH_LEFT < CONFIG_FLASH_SIZE; }
bool in_psram(paddr_t addr) { return addr - PSRAM_LEFT < CONFIG_PSRAM_SIZE; }
bool in_sdram(paddr_t addr) { return addr - SDRAM_LEFT < CONFIG_SDRAM_SIZE; }
uint8_t* mrom_to_host(paddr_t paddr) { return mrom + (paddr - MROM_LEFT); }
uint8_t* sram_to_host(paddr_t paddr) { return sram + (paddr - SRAM_LEFT); }
uint8_t* flash_to_host(paddr_t paddr) { return flash + (paddr - FLASH_LEFT); }
uint8_t* psram_to_host(paddr_t paddr) { return psram + (paddr - PSRAM_LEFT); }
uint8_t* sdram_to_host(paddr_t paddr) { return sdram + (paddr - SDRAM_LEFT); }

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
  if (likely(in_pmem(addr))) {
    word_t ret = pmem_read(addr, len);
    IFDEF(CONFIG_MTRACE, mtrace_read(addr, len, ret));
    return ret;
  }
  /* ysyxSoC: MROM 与 SRAM 是物理内存 (不走 MMIO, 避免 difftest_skip_ref) */
  if (in_mrom(addr)) {
    word_t ret = host_read(mrom_to_host(addr), len);
    IFDEF(CONFIG_MTRACE, mtrace_read(addr, len, ret));
    return ret;
  }
  if (in_sram(addr)) {
    word_t ret = host_read(sram_to_host(addr), len);
    IFDEF(CONFIG_MTRACE, mtrace_read(addr, len, ret));
    return ret;
  }
  if (in_flash(addr)) {
    word_t ret = host_read(flash_to_host(addr), len);
    IFDEF(CONFIG_MTRACE, mtrace_read(addr, len, ret));
    return ret;
  }
  if (in_psram(addr)) {
    word_t ret = host_read(psram_to_host(addr), len);
    IFDEF(CONFIG_MTRACE, mtrace_read(addr, len, ret));
    return ret;
  }
  /* SDRAM 仅 riscv32e-ysyxsoc 使用; nemu 模式下 0xa0000000 段是设备 MMIO,
   * 必须落到 mmio_read, 故此处用 CONFIG_YSYXSOC 守护, 避免劫持设备访问. */
  IFDEF(CONFIG_YSYXSOC,
    if (in_sdram(addr)) {
      word_t ret = host_read(sdram_to_host(addr), len);
      IFDEF(CONFIG_MTRACE, mtrace_read(addr, len, ret));
      return ret;
    }
  )
  IFDEF(CONFIG_DEVICE, return mmio_read(addr, len));
  out_of_bound(addr);
  return 0;
}

void paddr_write(paddr_t addr, int len, word_t data) {
  IFDEF(CONFIG_MTRACE, mtrace_write(addr, len, data));
  if (likely(in_pmem(addr))) { pmem_write(addr, len, data); return; }
  /* ysyxSoC: SRAM/PSRAM 可写; MROM/Flash 只读, 静默丢弃写 (与只读介质一致).
   * SDRAM 仅 ysyxsoc 使用 (见 paddr_read 注释), 用 CONFIG_YSYXSOC 守护. */
  if (in_sram(addr)) { host_write(sram_to_host(addr), len, data); return; }
  if (in_psram(addr)) { host_write(psram_to_host(addr), len, data); return; }
  IFDEF(CONFIG_YSYXSOC,
    if (in_sdram(addr)) { host_write(sdram_to_host(addr), len, data); return; }
  )
  if (in_mrom(addr)) { return; }
  if (in_flash(addr)) { return; }
  IFDEF(CONFIG_DEVICE, mmio_write(addr, len, data); return);
  out_of_bound(addr);
}
