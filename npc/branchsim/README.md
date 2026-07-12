# branchsim

`branchsim` is a C99 functional reference for the static RISC-V conditional
branch predictors in `讲义/B5.md`: always-not-taken (ANT), always-taken (AT),
and BTFN (Backward Taken, Forward Not-taken). Like `npc/cachesim`, it consumes
an NEMU trace rather than RTL simulation, so it can quickly evaluate a design
choice before that choice is implemented in hardware.

This version models the finite Branch Target Buffer (BTB) required by the
lecture. A direction prediction alone is not enough for IFU: on a predicted
taken branch, IFU also needs the branch target. A BTB miss therefore predicts
`PC + 4`, even when AT or BTFN would otherwise predict taken.

## Build and run

```sh
cd npc/branchsim
make
make run BTRACE=/path/to/program.btrace
make run BTRACE=/path/to/program.btrace ARGS="--predictor=btfn --btb-entries=8"
make run BTRACE=/path/to/program.btrace ARGS="--btb-entries=0"
make test
```

The default predictor is `all`, which prints all three static strategies.
Choose one with `--predictor=always-not-taken`, `--predictor=always-taken`,
or `--predictor=btfn`; `--predict=<name>` is an equivalent integration alias.
The short aliases `ant` and `at` are accepted too.

## BTB model

`--btb-entries=N` selects a direct-mapped BTB with `N` entries. `N` must be a
power of two; the RTL-matched default is `8`. Each
entry holds a valid bit, the full branch PC (tag), target PC, and a saved
backward bit for BTFN. Its index is:

```text
index = (PC >> 2) & (N - 1)
```

The table starts invalid. For every valid conditional B instruction,
branchsim performs `lookup -> predict -> update`: a hit uses the entry's
target and stored direction bit; a miss predicts `PC + 4`; then the decoded
branch refreshes the entry. This includes actually not-taken branches. A valid
entry with another PC is overwritten and counted as a replacement.

The report gives conditional-branch-trace lookup, hit, cold-miss, conflict
miss, fill, replacement, and stale-target statistics. It also prints an
ideal-target-availability result beside the BTB-calibrated result.

`--btb-entries=0` is an ideal-target-availability comparison baseline, not a
hardware configuration with no BTB. It preserves pure static predictor
behavior so cold-start and conflict costs can be measured directly. The
default `8` entries match the current RTL `BranchTargetBuffer` default. The
RTL configuration point is its `ENTRY_NUM` parameter; after changing it, rerun
branchsim with the same `--btb-entries` value.

## RTL selection

The 8-entry `MicroBench train` evaluation selects always-taken (AT) for the
current RTL: its BTB-calibrated Next-PC accuracy is `73.50%`, ahead of BTFN
(`69.97%`) and always-not-taken (`26.43%`). Accordingly, IFU follows `target`
on every BTB hit. The RTL table stores only valid, full PC tag, and target;
branchsim retains BTFN state solely to evaluate its alternative policy.

### MicroBench train result

Measured with the direct-mapped 8-entry BTB and a 2-cycle EX-stage
mispredict penalty:

| Predictor | Calibrated Next-PC accuracy | Estimated IPC | Speedup vs ANT |
| --- | ---: | ---: | ---: |
| Always not taken | 26.43% | 0.716080 | 1.000000x |
| Always taken | **73.50%** | **0.875055** | **1.222008x** |
| BTFN | 69.97% | 0.860719 | 1.201987x |

The trace contains 195,301,237 dynamic instructions and 52,624,413 valid
conditional branches. It was generated and evaluated with:

```sh
cd am-kernels/benchmarks/microbench
make ARCH=riscv32e-branchsim run mainargs=train BRANCHSIM_BTB_ENTRIES=8
```

## Generate a btrace

The RISC-V NEMU build writes a sibling `.btrace` whenever instruction tracing
is enabled and NEMU is given `-l <log-file>`. For example, with the ysyxSoC
configuration:

```sh
make -C nemu riscv32-ysyxsoc_defconfig
make -C nemu
cd nemu
./build/riscv32-nemu-interpreter -b -l /tmp/program.log /path/to/program.bin
../npc/branchsim/branchsim --btb-entries=8 /tmp/program.btrace
```

For an AM workload, the same flow is wrapped by
`ARCH=riscv32e-branchsim`, for example:

```sh
make ARCH=riscv32e-branchsim run mainargs=test BRANCHSIM_BTB_ENTRIES=8
```

## btrace format

The NEMU producer format is supported directly:

```text
# branchsim-btrace v1
0x30000000 0xfe000ce3 1
0x30000004 0x00008463 0
# total-instructions=123456
```

Each non-comment record is `pc inst taken`: a 32-bit program counter, a
32-bit RISC-V instruction, and an observed branch outcome (`0` for not taken,
`1` for taken). Integer fields accept `0x` hexadecimal or decimal notation.
Lines beginning with `#` are ignored. `# total-instructions=N` provides the
program's dynamic instruction count; whitespace and `total_instructions` are
also accepted. Use `--total-insts=N` to override trace metadata.

Only legal base conditional branch instructions are counted: opcode `0x63`
and `funct3` other than reserved values `010` and `011`. Malformed records and
invalid instructions are skipped and reported. The B-type immediate
reconstructs the target, so no trace format change is required for the BTB.
This task intentionally does not add JAL/JALR prediction to the trace or BTB
model.

## Performance model

The report keeps two accuracy definitions. `Direction` compares taken/not
taken with NEMU's semantic branch condition. `Next-PC` compares the predicted
fetch target with the architectural next PC, including whether a taken target
was available. This is the BTB-relevant metric and is used for performance.

For dynamic instruction count `N`, the report uses an ideal single-issue
baseline and adds the selected penalty for every BTB-calibrated Next-PC miss:

```text
cycles  = N + calibrated_next_pc_mispredictions * mispredict_penalty
IPC     = N / cycles
speedup = always-not-taken_cycles / predictor_cycles
```

`--mispredict-penalty=N` defaults to `2` cycles. If no total instruction
count is available, branchsim falls back to the valid branch count and emits a
warning; accuracy remains exact, but the cycle and IPC estimate is then only a
branch-only approximation.

## Model boundary

The btrace contains retired conditional branches from the architecturally
correct path, not all IFU PC lookups. BTB lookup counters therefore describe
only those conditional-branch trace records. The model is a committed-path
`lookup -> predict -> update` functional reference; it does not model
wrong-path fetches, speculative BTB pollution, or JAL/JALR. A future RTL BTB
should use its matching organization and entry count for comparison, while its
speculative timing may legitimately prevent every internal counter from being
bit-for-bit identical.
