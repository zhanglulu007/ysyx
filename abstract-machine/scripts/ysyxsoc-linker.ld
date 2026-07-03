MEMORY {
  flash : ORIGIN = 0x30000000, LENGTH = 16M
  sram  : ORIGIN = 0x0f000000, LENGTH = 8K
  sdram : ORIGIN = 0xa0000000, LENGTH = 32M
}

SECTIONS {
  /* ===== FSBL: 在 Flash 中执行的入口 + 第一级 bootloader (VMA=LMA=Flash) ===== */
  . = ORIGIN(flash);

  .text.bootloader : {
    *(entry)
    *(.text.bootloader*)
  } > flash AT> flash

  etext = .;
  _etext = .;

  /* ===== SSBL: 第二级 bootloader, 存放在 Flash (LMA), 由 FSBL 复制到 SRAM (VMA) 执行. */
  .text.ssbl ORIGIN(sram) : {
    _ssbl_start = .;
    *(.text.ssbl)
    *(.text.ssbl*)
    _ssbl_end = .;
    . = ALIGN(4);
  } > sram AT> flash
  _ssbl_lma = LOADADDR(.text.ssbl);

  _text_lma = LOADADDR(.text);
  .text : {
    _text_start = .;
    *(.text*)
    _text_end = .;
  } > sdram AT> flash

  _rodata_lma = LOADADDR(.rodata);
  .rodata : {
    _rodata_start = .;
    *(.rodata*)
    _rodata_end = .;
  } > sdram AT> flash

  _data_lma = LOADADDR(.data);
  .data : {
    _data_start = .;

    *(.srodata*)
    . = ALIGN(8);

    /* RT-Thread finsh shell 命令符号表 */
    __fsymtab_start = .;
    KEEP(*(FSymTab))
    __fsymtab_end = .;
    . = ALIGN(8);
    __vsymtab_start = .;
    KEEP(*(VSymTab))
    __vsymtab_end = .;
    . = ALIGN(8);

    /* RT-Thread 自动初始化函数表 */
    __rt_init_start = .;
    KEEP(*(SORT(.rti_fn*)))
    __rt_init_end = .;
    . = ALIGN(8);

    /* RT-Thread utest 测试用例表 */
    __rt_utest_tc_tab_start = .;
    KEEP(*(UtestTcTab))
    __rt_utest_tc_tab_end = .;
    . = ALIGN(8);

    /* 集成的 AM 应用数据 (由 integrate-am-apps.py --prefix-alloc-sections 生成) */
    __am_apps_data_start = .;
    *(__am_apps.data*)
    *(__am_apps.sdata*)
    __am_apps_data_end = .;
    . = ALIGN(8);

    *(.data*)
    *(.sdata*)
    _data_end = .;
  } > sdram AT> flash

  edata = .;
  _data = .;

  .bss (NOLOAD) : {
    _bss_start = .;

    /* 集成的 AM 应用 bss (放在主 bss 之前, 由 bootloader 统一清零) */
    . = ALIGN(8);
    __am_apps_bss_start = .;
    *(__am_apps.bss*)
    *(__am_apps.sbss*)
    *(__am_apps.scommon*)
    __am_apps_bss_end = .;
    . = ALIGN(8);

    *(.bss*)
    *(.sbss*)
    *(.scommon)
    _bss_end = .;
  } > sdram

  /* 堆区紧跟 .bss 之后, 位于 SDRAM 中 (32MB 大容量可写). */
  . = ALIGN(8);
  _heap_start = .;
  _heap_end = ORIGIN(sdram) + LENGTH(sdram);

  /* 栈区分配在 SRAM 末尾, 利用 SRAM 的单周期访问提升函数调用/局部变量效率.
   * (SRAM 8KB 全部留给栈, 不放置任何程序数据) */
  _stack_pointer = ORIGIN(sram) + LENGTH(sram);

  end = .;
}

ENTRY(_start)