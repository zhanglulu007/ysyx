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
