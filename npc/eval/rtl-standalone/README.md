# rtl-standalone synthesis evaluation

This project evaluates the current multi-cycle AXI4 core in
`../../rtl-standalone/vsrc` with the repository's existing `yosys-sta` flow.
`RTLStandalone_Synth.v` is the synthesis boundary. The current `top` is read
with `SYNTHESIS`, so the simulation-only DPI-C `PMEM` and trace callbacks are
excluded while the internal AXI request/response logic remains in the area
and timing scope.

```bash
make check
make synth
make sta
make sta CLK_FREQ_MHZ=800
```

`check` parses and elaborates the complete current hierarchy. `synth` performs
technology-mapped synthesis and produces the area report. `sta` additionally
runs timing and power analysis. Results are written under
`result/RTLStandalone_Synth-<frequency>MHz/`.

The default clock constraint is supplied by `yosys-sta`. Override it with
`SDC_FILE=/path/to/design.sdc` when evaluating a concrete interface.
