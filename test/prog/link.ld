ENTRY(_start)
SECTIONS {
  . = 0x80000000;
  .text : { *(.text*) }
  . = ALIGN(4);
  /DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) *(.riscv.attributes) *(.got*) *(.plt*) }
}
