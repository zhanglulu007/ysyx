#ifndef ARCH_H__
#define ARCH_H__

#ifdef __riscv_e
#define NR_REGS 16
#else
#define NR_REGS 32
#endif

struct Context {
  // TODO: fix the order of these members to match trap.S
  // Order must match trap.S:
  // 1. General purpose registers (x0 is at offset 0, but not saved/restored)
  // 2. mcause at OFFSET_CAUSE = (NR_REGS + 0) * XLEN
  // 3. mstatus at OFFSET_STATUS = (NR_REGS + 1) * XLEN  
  // 4. mepc at OFFSET_EPC = (NR_REGS + 2) * XLEN
  // 5. pdir (address space) shares space with x0
  uintptr_t gpr[NR_REGS];
  uintptr_t mcause;
  uintptr_t mstatus;
  uintptr_t mepc;
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
#define GPRx gpr[0]

#endif
