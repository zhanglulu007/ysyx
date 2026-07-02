MEMORY {
  flash : ORIGIN = 0x30000000, LENGTH = 16M
  sram  : ORIGIN = 0x0f000000, LENGTH = 8K
  psram : ORIGIN = 0x80000000, LENGTH = 4M
}

/* 三个 PT_LOAD 段:
 *   boot - Flash 中执行的入口 + bootloader (VMA=LMA=Flash)
 *   main - VMA=SRAM / LMA=Flash 的 .text/.rodata (bootloader 复制到 SRAM 后执行)
 *   data - VMA=SRAM / LMA=Flash 的 .data (bootloader 复制)
 * 关键点: VMA=SRAM 的节必须放在独立的 PHDR 中, 否则与 VMA=Flash 的 .text.bootloader
 * 同处一个 PHDR 时, ld 会因两段 VMA 不连续而报 "can't be allocated in segment",
 * 并把这些节丢弃到空段, 导致 objcopy 生成巨大的稀疏 bin 且 _text_lma 等符号失效. */
PHDRS { boot PT_LOAD; main PT_LOAD; data PT_LOAD; }

SECTIONS {
  /* ===== 必须在 Flash 中运行的代码（入口 + bootloader） ===== */
  . = ORIGIN(flash);

  .text.bootloader : {
    *(entry)
    *(.text.bootloader*)
  } > flash AT> flash : boot

  etext = .;
  _etext = .;

  /* ===== 搬到 SRAM 中执行（bootloader 负责从 Flash 复制） ===== */
  . = ORIGIN(sram);

  _text_lma = LOADADDR(.text);
  .text : {
    _text_start = .;
    *(.text*)
    _text_end = .;
  } > sram AT> flash : main

  _rodata_lma = LOADADDR(.rodata);
  .rodata : {
    _rodata_start = .;
    *(.rodata*)
    _rodata_end = .;
  } > sram AT> flash : main

  /* 已初始化全局变量 (.data, .sdata) 也搬到 SRAM,
   * VMA=SRAM, LMA=Flash, 由 bootloader 在 _trm_init 中复制. */
  _data_lma = LOADADDR(.data);
  .data : {
    _data_start = .;
    *(.data*)
    *(.sdata*)
    _data_end = .;
  } > sram AT> flash : data
 
  edata = .;
  _data = .;
 
  /* 未初始化全局变量 (.bss, .sbss) 分配在 SRAM 中, bootloader 负责清零. */
  .bss : {
    _bss_start = .;
    *(.bss*)
    *(.sbss*)
    *(.scommon)
    _bss_end = .;
  } > sram
 
  /* 栈区分配在 SRAM 末尾, 利用 SRAM 的单周期访问提升函数调用/局部变量效率. */
  . = ORIGIN(sram) + LENGTH(sram);
  _stack_pointer = .;
 
  /* 堆区在 PSRAM 中 (供需要大量堆空间的程序使用). */
  _heap_start = ORIGIN(psram);
  _heap_end = ORIGIN(psram) + LENGTH(psram);
 
  end = .;
}

ENTRY(_start)