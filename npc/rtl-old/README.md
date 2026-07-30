# rtl-old multi-cycle simulator

This project preserves the NPC RTL from Git commit
`7e02b8139d72d16b2edb135dbabba19b4a646c80` and runs it with the current
`npc/csrc_standalone` Verilator environment.

This revision is the historical AXI4-Lite multi-cycle NPC with IFU/LSU
arbitration. It supports both its original local Xbar/UART/MEM path and
ysyxSoC through an AXI4 boundary bridge.

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
make build SOC=1
make run SOC=1 PROG=/absolute/path/to/ysyxsoc-program.bin
make -C .. compare-rtl-soc PROG=/absolute/path/to/ysyxsoc-program.bin
```

The corresponding synthesis and STA project is in `../eval/rtl-old/`.

In `SOC=1` mode, the original core state machines are unchanged. The
post-arbiter AXI4-Lite request is expanded to a single-beat AXI4 transaction,
CLINT accesses are handled locally, and all other addresses are sent to the
ysyxSoC interconnect. The reset vector is `0x30000000` in SoC mode and remains
`0x80000000` in local mode.

For comparable measurements, use the same ysyxSoC binary and keep `FST`,
`TRACE`, `FFLASH` and `DIFFTEST` settings identical. The simulator reports
retired instruction count, cycle count and IPC at the good trap.
