# ============================================================================
#  csr_test.S - CSR / ecall / mret / fence.i 定向测试
#
#  覆盖:
#    * csrw mtvec / csrw mepc / csrr / csrrs / csrrw
#    * csrw 后紧跟 csrr (WB->EX CSR 前递)
#    * ecall -> trap -> csrr mcause/mepc -> csrw mepc -> mret (背靠背)
#    * fence.i (ICache flush)
#    * ebreak, a0=0 表示通过
#
#  编译: riscv64-linux-gnu-gcc -march=rv32e_zicsr_zifencei -mabi=ilp32e \
#          -nostdlib -nostartfiles -Wl,-Ttext=0x80000000 -Wl,--entry=_start
# ============================================================================
.section .text
.globl _start
_start:
  la   t0, trap
  csrw mtvec, t0

  # csrw + 背靠背 csrr (测试 CSR 写后读前递)
  li   t0, 0x1234
  csrw mepc, t0
  csrr a0, mepc
  li   t1, 0x1234
  bne  a0, t1, fail

  # csrrs: 读旧值, 写新值
  li   t0, 1
  csrrs a1, mstatus, t0
  csrr a2, mstatus
  andi a3, a2, 1
  li   t1, 1
  bne  a3, t1, fail

  # ecall / mret
  li   a4, 0
  ecall
  li   t1, 1
  bne  a4, t1, fail

  # fence.i: a4 应保持 trap 中写入的 1
  fence.i
  li   t1, 1
  bne  a4, t1, fail

  li   a0, 0
  ebreak
  j    fail

trap:
  csrr t0, mcause
  li   t2, 11
  bne  t0, t2, fail_trap

  csrr t1, mepc
  addi t1, t1, 4
  csrw mepc, t1
  li   a4, 1
  mret

fail_trap:
  li   a0, 1
  ebreak

fail:
  li   a0, 1
  ebreak
