# rtl-old standalone simulator

This project preserves the NPC RTL from Git commit
`7e02b8139d72d16b2edb135dbabba19b4a646c80` and runs it with the current
`npc/csrc_standalone` Verilator environment.

This revision is the AXI4-Lite multi-cycle NPC with IFU/LSU arbitration,
address routing through Xbar, and the UART and MEM slave modules.

The functional RTL is copied into `vsrc/`. The original top-level source is
also retained as `vsrc/source-snapshot/top.v.bak`. Local changes are limited to
the integration boundary:

- use the RTL's `insdone_out` signal to advance trace and difftest;
- read PC and instruction values from the RTL's DPI-C update callbacks;
- match the commit's two-argument ftrace return hook.

The restored `MEM` keeps the original AXI4-Lite handshake state machine, but
its LFSR-based random request and response delays are removed so simulation is
deterministic.

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
