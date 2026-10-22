# NPC 优化验证工程 (zc_eval)

本目录是 NPC 核优化的独立验证/评估工程。它只**读取**：

- `../../npc/vsrc`：当前优化 RTL
- `../../npc/csrc`：Verilator + DPI-C 仿真框架
- `../../am-kernels/benchmarks/microbench/build/microbench-riscv32e-npc.bin`：train 规模 microbench
- `~/yosys-sta`：yosys 综合 + iEDA STA

所有构建产物、日志、综合结果都落在本目录，不修改其它目录源码。
基线 RTL 冻结在 `rtl_baseline/`（对应 git `HEAD` 的 `npc/vsrc`）。

## 快速开始

```bash
cd test/zc_eval

make sim-opt      # Verilator 构建 npc/vsrc + 跑 microbench train -> result/sim-opt.log
make smoke-opt    # 跑自写 RV32E 冒烟测试 (ALU/load-store/分支/BTB/CSR/fence.i)
make synth-opt    # yosys 综合 + iEDA STA -> result/synth-opt/
make synth-base   # 基线 RTL 的综合/STA -> result/synth-base/
make report       # 汇总 IPC / 频率 / 面积 / 分数
```

依赖：`verilator` (>=5.0)、`riscv64-linux-gnu-*` 工具链、`sdl2-config`、
`~/yosys-sta/{oss-cad-suite/bin/yosys,bin/iEDA,scripts,PDK}`。

## 目录

```
zc_eval/
├── Makefile            # 顶层驱动
├── synth/              # 综合边界 + yosys-sta 调用
│   ├── NPCSynth.v      # 只暴露 clk/rst/imem_rdata/pc/inst/imem_addr
│   └── Makefile
├── scripts/
│   ├── report.py       # 基线/优化 IPC×频率 汇总
│   └── synth_report.py # 解析 synth_stat.txt + NPCSynth.rpt
├── tests/              # RV32E 冒烟测试 (smoke.S + link.ld)
├── rtl_baseline/       # 冻结的基线 RTL (git HEAD)
├── result/             # 日志与综合结果
└── REPORT.md           # 完整分析/优化报告
```

## 评估口径

- **IPC**：standalone 模式跑 `microbench` 的 `train` 规模，取
  `Executed ... instructions in ... cycles, IPC=...`。
- **频率**：`npc/vsrc` 全核用 `icsprout55` PDK、1200MHz 约束做 STA，
  取 `NPCSynth.rpt` 中所有 max 路径里最低的可达频率。
- **面积**：`NPCSynth` 的 `Chip area for module`（含 ICache、BTB、
  寄存器堆、总线仲裁；不含 PMEM 仿真模型）。
- **分数**：`IPC × 频率(MHz)`；面积要求 `< 25000`。

## 备注

- 综合使用 `-DSYNTHESIS`，此时 DPI-C/PMEM/perf/trace 全部排除，
  `top.v` 内部使用合成用存储模型。
- `rtl_baseline/` 是题目原始 RTL 的快照；`make sim-base`/`synth-base`
  用于同口径对照。
- 本工程与 `test/` 下另一套并发工程（`test/rtl`、`test/npc-opt` 等）
  相互独立，互不修改。

## 结果（standalone microbench train，2026-10-22）

| 指标 | 基线 | 优化后 |
|---|---:|---:|
| IPC | 0.4725 | **0.6653** |
| 最高频率 | 524.43 MHz | 516.89 MHz |
| 分数 IPC×MHz | 247.8 | **343.9 (1.39×)** |
| 面积 | 19341.56 | **24886.68（< 25000 ✓）** |
| 周期数 | 413,014,750 | 293,290,382 |

- microbench train：10/10 PASS（校验和正确）
- 冒烟测试：26 项检查 HIT GOOD TRAP
- 详细分析、逐项贡献与后续工作见 [REPORT.md](REPORT.md)
