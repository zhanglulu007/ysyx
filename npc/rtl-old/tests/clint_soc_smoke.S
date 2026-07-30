  .section .text
  .globl _start

_start:
  lui t0, 0x0200c
  lw t1, -8(t0)
  li t2, 64

1:
  addi t2, t2, -1
  bnez t2, 1b

  lw t2, -8(t0)
  sltu a0, t1, t2
  xori a0, a0, 1
  ebreak
