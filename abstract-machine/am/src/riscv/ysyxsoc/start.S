.section entry, "ax"
.globl _start
.type _start, @function

_start:
  mv s0, zero
  la sp, _stack_pointer
  /* FSBL: 调用 fsbl() 将 SSBL 从 Flash 复制到 SRAM,
   * 然后 fsbl() 跳转到 SRAM 中的 ssbl() 继续执行. */
  call fsbl
  /* 不应到达这里: fsbl() 会跳转到 SRAM 中的 ssbl(), 不返回 */
1: j 1b

.size _start, . - _start