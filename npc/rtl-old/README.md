# rtl-old standalone simulator

This project preserves the NPC RTL from Git commit
`3af90a428bc25436f7be5992ed78bcf21d582184` and runs it with the current
`npc/csrc_standalone` Verilator environment.

This revision includes the commit's CSR implementation and its
`ecall`/`mret` exception path, including `mtvec`, `mepc`, and `mcause`.

The functional RTL is copied into `vsrc/`. The original top-level source is
also retained as `vsrc/source-snapshot/top.v.bak`. Local changes are limited to
the integration boundary:

- expose `pc` and `inst` to the current C++ simulation adapter;
- use direct DPI-C instruction and data memory during simulation;
- expose only `imem_addr` and `imem_rdata` when `SYNTHESIS` is defined;
- remove DPI-C calls and tie load data to zero during synthesis.

There is no synthesized `PMEM` instance and no `dmem_*` top-level interface.

## Commands

```bash
make show-config
make lint
make build
make run PROG=/absolute/path/to/program.bin
make run PROG=/absolute/path/to/program.bin ELF=/absolute/path/to/program.elf TRACE=1
make run PROG=/absolute/path/to/program.bin DIFFTEST=1
make run PROG=/absolute/path/to/program.bin FST=1
```

The corresponding synthesis and STA project is in `../eval/rtl-old/`.
