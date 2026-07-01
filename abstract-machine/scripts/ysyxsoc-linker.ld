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

   /* 已初始化全局变量 (.data, .sdata) 分配在 PSRAM 中,
    * VMA=PSRAM, LMA=Flash, 由 bootloader 在 _trm_init 中复制. */
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

  /* 未初始化全局变量 (.bss, .sbss) 分配在 PSRAM 中, bootloader 负责清零. */
  .bss : {
    _bss_start = .;
    *(.bss*)
    *(.sbss*)
    *(.scommon)
    _bss_end = .;
  } > psram

  /* 栈区分配在 SRAM 末尾, 利用 SRAM 的单周期访问提升函数调用/局部变量效率. */
  . = ORIGIN(sram) + LENGTH(sram);
  _stack_pointer = .;

  /* 堆区紧跟在 .bss 之后 (PSRAM 中), 向上生长至 PSRAM 末尾. */
  _heap_start = _bss_end;
  _heap_end = ORIGIN(psram) + LENGTH(psram);

  end = .;
  _end = .;
}
