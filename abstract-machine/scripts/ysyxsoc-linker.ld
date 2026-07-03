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
 * 不显式声明 PHDRS: 由 GNU ld 根据各输出节的 > region AT> region 自动生成 PT_LOAD 段.
 * 之前曾显式声明 PHDRS { boot/main/data }, 但当 .rodata 与 .data 之间存在额外输出节
 * (例如 RT-Thread 集成 AM 应用 fceux 时引入的 .srodata) 时, 多节共享同一 PHDR 且 LMA
 * 不连续会触发 GNU ld 的 "can't be allocated in segment" 警告, 使对应节丢失段分配,
 * LMA 退化为 VMA, 导致 objcopy -O binary 生成巨大的稀疏 bin (VMA 跨度 ~1.3GB).
 * 去掉 PHDRS 后, ld 会为每个 (region, AT-region) 组合自动建立正确的 PT_LOAD 段,
 * 所有节的 LMA 都能正确指向 Flash, objcopy 输出的 bin 仅覆盖 Flash 的 LMA 跨度. */

SECTIONS {
  /* ===== 必须在 Flash 中运行的代码（入口 + bootloader） ===== */
  . = ORIGIN(flash);

  .text.bootloader : {
    *(entry)
    *(.text.bootloader*)
  } > flash AT> flash

  etext = .;
  _etext = .;

  /* ===== 搬到 PSRAM 中执行（bootloader 负责从 Flash 复制） ===== */
  . = ORIGIN(psram);

  _text_lma = LOADADDR(.text);
  .text : {
    _text_start = .;
    *(.text*)
    _text_end = .;
  } > psram AT> flash

  _rodata_lma = LOADADDR(.rodata);
  .rodata : {
    _rodata_start = .;
    *(.rodata*)
    _rodata_end = .;
  } > psram AT> flash

  /* 已初始化全局变量 (.data, .sdata) 也搬到 PSRAM,
   * VMA=PSRAM, LMA=Flash, 由 bootloader 复制.
   * 同时收录 RT-Thread 的命令表/初始化表/集成 AM 应用的数据段:
   *   FSymTab/VSymTab - finsh shell 的命令符号表
   *   .rti_fn*        - RT-Thread 自动初始化函数表
   *   UtestTcTab      - utest 测试用例表
   *   __am_apps.*      - 被 integrate-am-apps.py 集成的 AM 应用数据
   * 这些都是携带 (函数)指针的 const 数据, 必须随 .data 一并由 bootloader
   * 从 Flash 复制到 PSRAM, 才能在运行时获得正确的重定位地址. */
  _data_lma = LOADADDR(.data);
  .data : {
    _data_start = .;

    /* small read-only data (GP-relative), 收录 am-apps (如 fceux) 的 .srodata.* 段.
     * 放在 .data 中随已初始化数据一并从 Flash 复制到 PSRAM (内容为只读查找表,
     * 运行时不被写入, 与 .data 同区无害), 避免其单独成节时被 ld 当作孤儿处理. */
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
  } > psram AT> flash

  edata = .;
  _data = .;

  /* 未初始化全局变量 (.bss, .sbss) 分配在 PSRAM 中, bootloader 负责清零.
   * 同时收录集成 AM 应用的 bss 段. 必须放在 .bss 输出节内部, 才能与主
   * bss 一起被 bootloader 清零, 且避免与 .bss 起始地址重叠. */
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