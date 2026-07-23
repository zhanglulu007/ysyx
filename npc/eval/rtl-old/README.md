# rtl-old synthesis evaluation

This project synthesizes the NPC RTL preserved from commit
`3af90a428bc25436f7be5992ed78bcf21d582184` in `../../rtl-old/vsrc`, including
the commit's CSR and `ecall`/`mret` exception support.

`RTLOld_Synth.v` is the synthesis top. Its only memory interface is the
combinational instruction-memory pair `imem_addr`/`imem_rdata`. Data-memory
DPI calls are disabled under `SYNTHESIS`, load data is tied to zero, and no
`PMEM` or `dmem_*` interface is included in the netlist.

```bash
make check
make synth
make sta
make sta CLK_FREQ_MHZ=800
```

Results are written to `result/RTLOld_Synth-<frequency>MHz/`. The local SDC
constrains `clk` and applies a 20% clock-period delay to each instruction-memory
port bit.
