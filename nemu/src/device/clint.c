/***************************************************************************************
* CLINT (Core Local Interruptor) 设备模型 —— 供 riscv32e-ysyxsoc 镜像在 NEMU 上运行
*
* 背景: ysyxSoC 的 AM 程序 (如 microbench) 通过 CLINT 的 mtime 寄存器计时:
*   timer.c: __am_timer_uptime() 读取 CLINT_BASE + 0xBFF8 (mtime[31:0]) 和
*            CLINT_BASE + 0xBFFC (mtime[63:32]).
* 若 NEMU 不提供 CLINT, 该读取会触发 out_of_bound, 程序无法运行.
*
* 实现策略 (功能级最小模型, 不仿真 SoC 细节):
*   - 对应 NPC 的 vsrc/CLINT.v: mtime 是每周期 +1 的 64 位自由计数器.
*   - NEMU 无"周期"概念, 用 g_nr_guest_inst (每条指令 +1) 近似驱动 mtime,
*     对 cachesim 所需的 PC 序列一致性无影响 (仅影响 microbench 报告的时间数值).
*   - 地址解码与 NPC CLINT.v 一致: 仅 offset 0xBFF8 / 0xBFFC 有效, 其余读 0.
*   - mtimecmp (offset 0x4000) 在 NPC 中未实现 (写返回 SLVERR 但无效果),
*     此处同样静默忽略写入, 不产生中断 (NPC 亦不靠 mtimecmp 触发 MTI).
***************************************************************************************/

#include <device/map.h>

/* g_nr_guest_inst: cpu-exec.c 中每执行一条指令递增一次的全局计数器 */
extern uint64_t g_nr_guest_inst;

/* CLINT 寄存器窗口: 0x0200_0000 ~ 0x0200_ffff (64KB), 与 NPC AXIArbiter 译码一致 */
#define CLINT_BASE_ADDR  0x02000000
#define CLINT_WINDOW_SZ  0x10000

/* mtime 寄存器偏移 (与 NPC CLINT.v / RISC-V CLINT 规范一致) */
#define MTIME_LO_OFFSET  0xBFF8   /* mtime[31:0]  */
#define MTIME_HI_OFFSET  0xBFFC   /* mtime[63:32] */

static uint32_t *clint_base = NULL;

static void clint_io_handler(uint32_t offset, int len, bool is_write) {
  /* 读 mtime 时用当前已执行指令数刷新对应槽位, 其余读保持 0 (复位初值) */
  if (!is_write) {
    uint64_t t = g_nr_guest_inst;
    if (offset == MTIME_LO_OFFSET) {
      clint_base[MTIME_LO_OFFSET / sizeof(uint32_t)] = (uint32_t)t;
    } else if (offset == MTIME_HI_OFFSET) {
      clint_base[MTIME_HI_OFFSET / sizeof(uint32_t)] = (uint32_t)(t >> 32);
    }
  }
  /* 写入 (如 mtimecmp): 静默忽略, 与 NPC 行为一致 */
}

void init_clint() {
  clint_base = (uint32_t *)new_space(CLINT_WINDOW_SZ);
  add_mmio_map("clint", CLINT_BASE_ADDR, clint_base, CLINT_WINDOW_SZ, clint_io_handler);
}
