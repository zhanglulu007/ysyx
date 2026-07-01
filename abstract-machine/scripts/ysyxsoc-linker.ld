MEMORY {
  flash : ORIGIN = 0x30000000, LENGTH = 16M
  sram  : ORIGIN = 0x0f000000, LENGTH = 8K
  psram : ORIGIN = 0x80000000, LENGTH = 4M
}

ENTRY(_start)
PHDRS { flash_text PT_LOAD; sram_text PT_LOAD; data PT_LOAD; }

SECTIONS {
  /* ===== 必须在 Flash 中运行的代码（入口 + bootloader） ===== */
  . = ORIGIN(flash);

  .text.bootloader : {
    *(entry)
    *(.text.bootloader*)
  } > flash AT> flash : flash_text

  etext = .;
  _etext = .;

  /* ===== 搬到 SRAM 中执行（bootloader 负责从 Flash 复制） ===== */
  . = ORIGIN(sram);

  _text_lma = LOADADDR(.text);
  .text : {
    _text_start = .;
    *(.text*)
    _text_end = .;
  } > sram AT> flash : sram_text

  _rodata_lma = LOADADDR(.rodata);
  .rodata : {
    _rodata_start = .;
    *(.rodata*)
    _rodata_end = .;
  } > sram AT> flash : sram_text

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
  _end = .;
}
