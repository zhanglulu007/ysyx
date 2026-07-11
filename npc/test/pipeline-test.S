  .section .text
  .globl _start
_start:
  li    t0, 5
  addi  t1, t0, 7
  la    t2, test_data
  sw    t1, 0(t2)
  lw    a0, 0(t2)
  addi  a0, a0, -12
  bnez  a0, bad
  j     good
bad:
  li    a0, 1
good:
  ebreak

  .section .data
  .align 2
test_data:
  .word 0
