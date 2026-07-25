# Multi-cycle RTL simulator

This project contains the rewritten RV32E multi-cycle core with a full AXI4
master interface. It supports both a local PMEM backend and ysyxSoC.

## Source layout

- `vsrc/`: multi-cycle core, AXI4 arbiter, CLINT and SoC wrapper
- `../csrc_standalone/`: shared memory, devices, SDB, trace and DiffTest code
- `csrc/adapter/`: local compatibility code for this single-cycle RTL
- `build/`, `wave/`: project-local generated output

## Commands

```bash
make show-config
make lint
make build
make run PROG=/absolute/path/to/program.bin
make run PROG=/absolute/path/to/program.bin ELF=/absolute/path/to/program.elf TRACE=1
make run PROG=/absolute/path/to/program.bin DIFFTEST=1
make run PROG=/absolute/path/to/program.bin FST=1
make test-clint
make test-soc-clint
make build SOC=1
make run SOC=1 PROG=/absolute/path/to/ysyxsoc-program.bin
```

The default NEMU reference is
`../../nemu/build/riscv32-nemu-interpreter-standalone-so`.

## Integration boundary

In local mode, `top` connects the AXI4 master to `PMEM`. In SoC mode,
`ysyx_26020070` exposes the same AXI4 master interface used by the main
pipeline implementation and is instantiated by `ysyxSoCFull`.

The local CLINT occupies `0x0200_0000` through `0x0200_ffff`. Reads from
`0x0200_bff8` and `0x0200_bffc` return the low and high halves of the 64-bit
cycle counter. All other accesses continue through the ysyxSoC interconnect.

## Synthesis interface

With `SYNTHESIS` defined in local mode, the DPI-C calls are removed and `top`
uses an explicit combinational instruction-memory port:

- instruction: `imem_addr`, `imem_rdata`

`PMEM.v` is simulation-only and is excluded from the synthesis source list.
The synthesis top has no data-memory connection and uses zero as load data.

The synthesis/STA project is in `../eval/rtl-standalone/`.
