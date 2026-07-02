MEMORY {
  flash : ORIGIN = 0x30000000, LENGTH = 16M
  sram  : ORIGIN = 0x0f000000, LENGTH = 8K
  psram : ORIGIN = 0x80000000, LENGTH = 4M
}

/* 内存布局 (B2.md '通过bootloader将程序加载到PSRAM中执行'):
 *   - 程序主体 (.text/.rodata/.data/.bss) 加载到 PSRAM 执行: VMA=PSRAM, LMA=Flash.
 *     PSRAM 有 4MB, 足够装下 microbench 等大程序; 取指/数据访问虽慢于 SRAM, 但容量大.
 *   - 栈分配在 SRAM 末尾, 利用 SRAM 单周期访问提升函数调用/局部变量效率.
 *   - 堆区紧跟 .bss 之后, 位于 PSRAM 中, 提供大容量可写空间 (bench_alloc 等).
 *
 * 三个 PT_LOAD 段:
 *   boot - Flash 中执行的入口 + bootloader (VMA=LMA=Flash)
 *   main - VMA=PSRAM / LMA=Flash 的 .text/.rodata (bootloader 复制到 PSRAM 后执行)
 *   data - VMA=PSRAM / LMA=Flash 的 .data (bootloader 复制)
 * 关键点: VMA=PSRAM 的节必须放在独立的 PHDR 中, 否则与 VMA=Flash 的 .text.bootloader
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

  /* ===== 搬到 PSRAM 中执行（bootloader 负责从 Flash 复制） ===== */
  . = ORIGIN(psram);

  _text_lma = LOADADDR(.text);
  .text : {
    _text_start = .;
    *(.text*)
    _text_end = .;
  } > psram AT> flash : main

  _rodata_lma = LOADADDR(.rodata);
  .rodata : {
    _rodata_start = .;
    *(.rodata*)
    _rodata_end = .;
  } > psram AT> flash : main

  /* 已初始化全局变量 (.data, .sdata) 也搬到 PSRAM,
   * VMA=PSRAM, LMA=Flash, 由 bootloader 复制. */
  _data_lma = LOADADDR(.data);
  .data : {
    _data_start = .;
    *(.data*)
    *(.sdata*)
    _data_end = .;
  } > psram AT> flash : data

  edata = .;
  _data = .;

  /* 未初始化全局变量 (.bss, .sbss) 分配在 PSRAM 中, bootloader 负责清零. */
  .bss (NOLOAD) : {
    _bss_start = .;
    *(.bss*)
    *(.sbss*)
    *(.scommon)
    _bss_end = .;
  } > psram

  /* 堆区紧跟 .bss 之后, 位于 PSRAM 中 (大容量可写, 供 bench_alloc 等使用). */
  . = ALIGN(8);
  _heap_start = .;
  _heap_end = ORIGIN(psram) + LENGTH(psram);

  /* 栈区分配在 SRAM 末尾, 利用 SRAM 的单周期访问提升函数调用/局部变量效率.
   * (SRAM 8KB 全部留给栈, 不放置任何程序数据) */
  _stack_pointer = ORIGIN(sram) + LENGTH(sram);

  end = .;
}

ENTRY(_start)