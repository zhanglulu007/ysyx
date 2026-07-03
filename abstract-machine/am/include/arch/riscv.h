#ifndef ARCH_H__
#define ARCH_H__

#ifdef __riscv_e
#define NR_REGS 16
#else
#define NR_REGS 32
#endif

struct Context {
  // TODO: fix the order of these members to match trap.S
  // Order: gpr[0-31], mcause, mstatus, mepc (matching trap.S)
  uintptr_t gpr[NR_REGS], mcause, mstatus, mepc;
  void *pdir;
};

#ifdef __riscv_e
#define GPR1 gpr[15] // a5
#else
#define GPR1 gpr[17] // a7
#endif

#define GPR2 gpr[0]
#define GPR3 gpr[0]
#define GPR4 gpr[0]
/* kcontext(entry, arg) 创建的上下文 mret 后进入 entry(void *arg),
 * arg 须通过 a0 (x10) 传递. trap.S 用 PUSH/POP(n) 保存恢复 x_n 到 gpr[n],
 * 故 GPRx 必须是 gpr[10] (a0), 而非 gpr[0] (x0 不可写, arg 会丢失). */
#define GPRx gpr[10] // a0

#endif
