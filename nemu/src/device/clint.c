/***************************************************************************************
* CLINT - Core Local Interrupt controller (ysyxSoC mtime 计时器模型)
*
* 对应 NPC 内部的 CLINT 模块 (npc/vsrc/CLINT.v), 地址空间 0x0200_0000 ~ 0x0200_ffff.
* AM-ysyxsoc 程序 (timer.c) 读取 mtime 来计时 (microbench 等基准依赖):
*   CLINT_MTIME_LO = 0x0200_bff8  (mtime 低 32 位)
*   CLINT_MTIME_HI = 0x0200_bffc  (mtime 高 32 位)
*
* NPC 中 mtime 为每时钟周期 +1 的 64 位计数器. NEMU 无统一时钟概念, 这里用
* host 时间 (get_time, 微秒) 近似 mtime: 数值不与 NPC 严格相等, 但 microbench
* 的相对计时逻辑 (uptime = now - boot_time) 仍正确可用, 且不影响 cachesim PC 流.
***************************************************************************************/

#include <device/map.h>
#include <device/alarm.h>
#include <utils.h>
#include <memory/paddr.h>

/* CLINT 地址: 与 NPC CLINT.v / AM ysyxsoc.h 一致 */
#define CLINT_MTIME_BASE  0x0200bff8UL
#define CLINT_MTIME_SIZE  8            /* mtime_lo(4B) + mtime_hi(4B) */

static uint32_t *clint_mtime_base = NULL;

static void clint_io_handler(uint32_t offset, int len, bool is_write) {
  assert(offset == 0 || offset == 4);
  if (!is_write) {
    /* 读 mtime: 用 host 微秒时间近似每周期递增的 mtime, 保证单调递增 */
    uint64_t mtime = get_time();
    clint_mtime_base[0] = (uint32_t)mtime;        /* offset 0: mtime[31:0]  */
    clint_mtime_base[1] = (uint32_t)(mtime >> 32);/* offset 4: mtime[63:32] */
  }
  /* mtime 为只读, 写入静默忽略 (与硬件 CLINT 不支持写一致) */
}

void init_clint() {
  clint_mtime_base = (uint32_t *)new_space(CLINT_MTIME_SIZE);
  clint_mtime_base[0] = 0;
  clint_mtime_base[1] = 0;
  add_mmio_map("clint-mtime", CLINT_MTIME_BASE, clint_mtime_base, CLINT_MTIME_SIZE, clint_io_handler);
}
