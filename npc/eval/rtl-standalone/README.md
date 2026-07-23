# rtl-standalone synthesis evaluation

This project synthesizes the copied single-cycle RV32E core in
`../../rtl-standalone/vsrc` with the repository's existing `yosys-sta` flow.
`RTLStandalone_Synth.v` is the evaluation wrapper. Instruction memory is an
external interface and is not counted in the core area.
The DPI-C `PMEM` module is not read or instantiated by the synthesis flow;
the synthesis top has no data-memory interface and ties load data to zero.

```bash
make check
make synth
make sta
make sta CLK_FREQ_MHZ=800
```

`check` only parses and elaborates the RTL. `synth` performs technology-mapped
synthesis and produces the area report. `sta` additionally runs timing and
power analysis. Results are written under
`result/RTLStandalone_Synth-<frequency>MHz/`.

The local `rtl-standalone.sdc` constrains the external instruction-memory ports
with input and output delays equal to 20% of the clock period. Override
it with `SDC_FILE=/path/to/design.sdc` when evaluating a concrete memory
interface.
