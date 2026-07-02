.section entry, "ax"
.globl _start
.type _start, @function

_start:
  mv s0, zero
  la sp, _stack_pointer
  /* bootloader 将 .text / .rodata / .data 从 Flash 复制到 PSRAM，并清零 .bss */
  call bootloader
  /* 此时代码已在 PSRAM 中，跳转 _trm_init (VMA=PSRAM) */
  call _trm_init

.size _start, . - _start