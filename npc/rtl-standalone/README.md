# Copied-RTL standalone simulator

This project runs a copied RTL snapshot with the existing standalone Verilator
environment. Its memory path is direct DPI-C and has no modeled bus latency.

## Source layout

- `vsrc/`: copied from `/home/zhangshenlu/ysyx/ysyx-workbench/npc/vsrc`
- `../csrc_standalone/`: shared memory, devices, SDB, trace and DiffTest code
- `csrc/adapter/`: local compatibility code for this single-cycle RTL
- `build/`, `wave/`: project-local generated output

The RTL is copied into this project rather than referenced through an external
path. Later edits here do not modify the source checkout.

The source snapshot had a newer `IDU.v` but an older `top.v`: `ifu_valid` and
the added CSR/system outputs were left unconnected. This project's `top.v`
connects `ifu_valid` to `!rst` and explicitly terminates the added outputs so
the copied single-cycle datapath can execute normally. The untouched copied
top-level is retained as `vsrc/source-snapshot/top.v.bak` for comparison.

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

The default NEMU reference is
`../../nemu/build/riscv32-nemu-interpreter-standalone-so`.

## Integration boundary

The copied RTL is the historical single-cycle RV32E design. `IFU` and `LSU`
call `pmem_read()`/`pmem_write()` directly, so neither AXI nor ysyxSoC is part
of this project's execution path. Every rising edge is treated as one retired
instruction.

The main NPC project differs in two ways:

- SoC mode wraps `ysyx_26020070` in `ysyxSoCFull` and reaches Flash, SRAM,
  PSRAM, SDRAM, UART, GPIO, PS/2 and VGA through the SoC interconnect.
- Pipeline standalone mode wraps the AXI master in `top_pmem` and `pmem_axi`,
  then waits for the RTL `commit_instruction()` retirement event.

This project intentionally uses neither wrapper because the copied RTL already
contains direct DPI-C memory calls and has no AXI master interface.

## Synthesis interface

With `SYNTHESIS` defined, the DPI-C calls are removed and `top` uses an
explicit combinational instruction-memory port:

- instruction: `imem_addr`, `imem_rdata`

`PMEM.v` is simulation-only and is excluded from the synthesis source list.
The synthesis top has no data-memory connection and uses zero as load data.

The normal Verilator build does not define `SYNTHESIS`, so it continues to use
the direct DPI-C memory and trace handlers. The synthesis/STA project is in
`../eval/rtl-standalone/`.
