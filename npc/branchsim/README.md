# branchsim

`branchsim` is a small C99 functional simulator for the static RISC-V branch
predictors introduced in `讲义/B5.md`: always-not-taken, always-taken, and
BTFN (Backward Taken, Forward Not-taken). It is separate from the RTL model,
like `npc/cachesim`, so a NEMU-generated dynamic trace can be the reference
for branch-predictor performance counters.

## Build and run

```sh
cd npc/branchsim
make
make run BTRACE=/path/to/program.btrace
make run BTRACE=/path/to/program.btrace ARGS="--predictor=btfn --mispredict-penalty=2"
make test
```

The default predictor is `all`, which prints all three static strategies.
Choose one with `--predictor=always-not-taken`, `--predictor=always-taken`,
or `--predictor=btfn`; `--predict=<name>` is an equivalent integration alias.
The short aliases `ant` and `at` are accepted too.

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
invalid instructions are skipped and reported. BTFN uses the B-type immediate
sign bit, `inst[31]`: one means backward and is predicted taken.

## Performance model

For dynamic instruction count `N`, the report uses an ideal single-issue
baseline and adds the selected penalty for every wrong branch:

```text
cycles  = N + incorrect_predictions * mispredict_penalty
IPC     = N / cycles
speedup = always-not-taken_cycles / predictor_cycles
```

`--mispredict-penalty=N` defaults to `2` cycles. If no total instruction
count is available, branchsim falls back to the valid branch count and emits a
warning; accuracy remains exact, but the cycle and IPC estimate is then only a
branch-only approximation.
