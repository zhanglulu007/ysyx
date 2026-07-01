MEMORY {
  flash : ORIGIN = 0x30000000, LENGTH = 16M
  sram  : ORIGIN = 0x0f000000, LENGTH = 8K
}

ENTRY(_start)
PHDRS { text PT_LOAD; data PT_LOAD; }

SECTIONS {
  . = ORIGIN(flash);

  .text : {
    *(entry)
    *(.text*)
  } > flash AT> flash : text

  etext = .;
  _etext = .;

  .rodata : {
    *(.rodata*)
  } > flash AT> flash

   /* 注意: RISC-V 把小的已初始化全局变量放入 .sdata 段, 必须一并包含,
   *       否则 bootloader 不会复制它们, 运行时读到的是 SRAM 中的无效数据 */
  .data : {
    _data_start = .;
    *(.data*)
    *(.sdata*)
    _data_end = .;
  } > sram AT> flash : data
  _data_lma = LOADADDR(.data);
  _data_size = _data_end - _data_start;

  edata = .;
  _data = .;

  .bss : {
    _bss_start = .;
    *(.bss*)
    *(.sbss*)
    *(.scommon)
    _bss_end = .;
  } > sram AT> flash : data

  /* 栈区与堆区布局 (按 B2.md 内存访问测试要求):
   *   栈区位于 SRAM 末尾, 从栈顶 (SRAM_BASE + SRAM_SIZE) 向低地址生长;
   *   堆区从 SRAM 起始处开始, 其结束地址即栈顶初值.
   * 这样 mem-test 可以把 [SRAM_BASE, 栈顶) 作为可写测试范围, 并在运行时绕开
   * 自身栈帧所占据的字节. */
  . = ORIGIN(sram) + LENGTH(sram);   /* 移到 SRAM 末尾 */
  _stack_pointer = .;                /* 栈顶 = SRAM_BASE + SRAM_SIZE, sp 向下生长 */
  end = .;
  _end = .;
  _heap_start = ORIGIN(sram);        /* 堆起始 = SRAM_BASE */
}