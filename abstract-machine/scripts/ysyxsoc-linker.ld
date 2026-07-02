MEMORY {
  flash : ORIGIN = 0x30000000, LENGTH = 16M
  sram  : ORIGIN = 0x0f000000, LENGTH = 8K
  psram : ORIGIN = 0x80000000, LENGTH = 4M
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
    *       否则 bootloader 不会复制它们, 运行时读到的是 PSRAM 中的无效数据 */
  .data : {
    _data_start = .;
    *(.data*)
    *(.sdata*)
    _data_end = .;
  } > psram AT> flash : data
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
  } > psram AT> flash : data

  /* 内存布局 (B2.md "在ysyxSoC上运行microbench"):
   *   .data/.bss 位于 PSRAM (4MB, 0x8000_0000) 起始;
   *   堆区紧跟 .bss 结束位置 (_end) 起, 延伸至 PSRAM 末尾 —— 注意堆区必须从
   *   数据段之后开始, 否则 bench_alloc 会覆盖 benchmarks[] 等全局变量!
   *   栈区位于 SRAM 末尾 (8KB, 0x0f00_2000), 利用 SRAM 低延迟提升调用效率. */
  . = ALIGN(8);
  _heap_start = .;                             /* 堆起始 = .bss 结束处 (8字节对齐) */
  end = .;                                     /* 程序数据结束 = 堆起始 (传统语义) */
  _end = .;
  _heap_end   = ORIGIN(psram) + LENGTH(psram); /* 堆结束 = PSRAM_BASE + PSRAM_SIZE */
  _stack_pointer = ORIGIN(sram) + LENGTH(sram);/* 栈顶 = SRAM 末尾, sp 向下生长 */
}