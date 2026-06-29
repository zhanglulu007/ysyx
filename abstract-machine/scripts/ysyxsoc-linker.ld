MEMORY {
  mrom : ORIGIN = 0x20000000, LENGTH = 4K
  sram : ORIGIN = 0x0f000000, LENGTH = 8K
}

ENTRY(_start)
PHDRS { text PT_LOAD; data PT_LOAD; }

SECTIONS {
  . = ORIGIN(mrom);

  .text : {
    *(entry)
    *(.text*)
  } > mrom AT> mrom : text

  etext = .;
  _etext = .;

  .rodata : {
    *(.rodata*)
  } > mrom AT> mrom

  /* 数据段：VMA在SRAM（运行时访问），LMA在MROM（烧录位置）
   * bootloader 将在启动时将其从 MROM 复制到 SRAM
   * 注意: RISC-V 把小的已初始化全局变量放入 .sdata 段, 必须一并包含,
   *       否则 bootloader 不会复制它们, 运行时读到的是 SRAM 中的无效数据 */
  .data : {
    _data_start = .;
    *(.data*)
    *(.sdata*)
    _data_end = .;
  } > sram AT> mrom : data
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
  } > sram

  _stack_top = ALIGN(0x1000);
  . = _stack_top + 0x800;
  _stack_pointer = .;
  end = .;
  _end = .;
  _heap_start = ALIGN(0x1000);
}