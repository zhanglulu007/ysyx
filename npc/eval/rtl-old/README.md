# rtl-old synthesis evaluation

This project evaluates the AXI4-Lite multi-cycle NPC restored from commit
`7e02b8139d72d16b2edb135dbabba19b4a646c80`.

The synthesis scope is deliberately limited to the CPU and `AXIArbiter`, so it
is comparable with the `rtl-standalone` core evaluation. `Xbar`, `MEM`, `UART`,
`LFSR`, DPI-C callbacks, and all random-delay test logic are excluded.

`RTLOld_Synth.v` exposes the arbiter's downstream AXI4-Lite interface directly.
`IFU_Synth.v` and `RegisterFile_Synth.v` preserve the restored hardware logic
while removing simulation-only DPI-C notifications. The source RTL under
`../../rtl-old/vsrc` is not modified by this evaluation project.

```bash
make check
make synth
make sta
make sta CLK_FREQ_MHZ=800
```

Results are written to `result/RTLOld_Synth-<frequency>MHz/`. The evaluation
uses the same default clock constraint as `../rtl-standalone`.
