  .section .text
  .globl _start
_start:
  # The final x5 must come from the younger ADDI, not an older LS/WB writer.
  addi x5, x0, 1
  addi x5, x5, 2
  add  x6, x5, x5

  # Exercise forwarded store address/data, then a load-use branch dependency.
  auipc x7, 0
  addi  x7, x7, 128
  sw    x6, 0(x7)
  lw    x10, 0(x7)
  addi  x10, x10, -6
  bne   x10, x0, fail
  ebreak

fail:
  addi x10, x0, 1
  ebreak
