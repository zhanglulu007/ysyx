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
   *   .data/.bss/堆区位于 PSRAM (4MB, 0x8000_0000), 提供大容量可写空间;
   *   栈区仍位于 SRAM 末尾 (8KB, 0x0f00_2000), 利用 SRAM 的低延迟提升
   *   函数调用与局部变量访问效率. 堆区从 PSRAM 起始处延伸至 PSRAM 末尾. */
  _heap_start = ORIGIN(psram);                 /* 堆起始 = PSRAM_BASE */
  _heap_end   = ORIGIN(psram) + LENGTH(psram); /* 堆结束 = PSRAM_BASE + PSRAM_SIZE */
  . = ORIGIN(sram) + LENGTH(sram);             /* 移到 SRAM 末尾 */
  _stack_pointer = .;                /* 栈顶 = SRAM_BASE + SRAM_SIZE, sp 向下生长 */
  end = .;
  _end = .;
}