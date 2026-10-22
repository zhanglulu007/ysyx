# test/ —— NPC 优化与验证项目集合

本目录包含两套**独立**的 NPC 优化/验证工作。两套工作都只读取
`npc/`、`nemu/`、`am-kernels/`、`abstract-machine/` 等目录，不修改它们；
所有构建产物、RTL 副本、日志和报告都落在 `test/` 下。

---

## A. npc-opt（本次新增，推荐从这里开始）

入口：

- 设计说明：`npc-opt/README.md`
- **详细报告：`report/npc-opt-report.md`**
- 一键验证：`npc-opt/run_verify.sh --diff`
- 一键综合/STA：`npc-opt/run_synth.sh`

核心思路：3 级顺序流水线（IF | ID | EX）+ 128B 8×16B 组合读/流式填充
ICache + BTB8/BHT8 + EX 级共享 adder + 数据侧优先 AXI 仲裁。

最终结果（standalone microbench train，icsprout55，yosys-sta）：

| 指标 | 基线 | npc-opt | 变化 |
|---|---|---|---|
| IPC | 0.4725 | **0.7114** | +50.6% |
| 最高频率 | 524.432 MHz | **790.143 MHz** | +50.7% |
| **IPC × fmax** | **247.8** | **562.1** | **2.27×** |
| 面积 | 19,341.56 | **23,012.08** | +19.0%（< 25k） |
| 关键路径 | regfile D（1.9068 ns） | `idex_alu_b`（1.2656 ns） | −33.6% |

验证：33/33 cpu-tests、microbench test + DiffTest、microbench train、
`fence.i` 自修改代码、SoC 模式 `add` 均通过。

目录：

```
npc-opt/        # 优化版 NPC（RTL + csrc + Makefile + 脚本）
npc-baseline/   # 原始 npc 的冻结副本（A/B 基线）
eval-opt/       # npc-opt 的 yosys-sta 评估
eval-baseline/  # 基线的 yosys-sta 评估
prog/           # microbench test/ref/huge + fence.i 测试
tools/          # PC trace 分析、反汇编分类、面积分解
report/         # npc-opt-report.md + 证据日志
```

---

## B. 既有的三阶段流水线评估工程

入口：

- 顶层 Makefile：`Makefile`
- **报告：`REPORT.md`**
- RTL：`rtl/`、`rtl_pipe3/`
- 评估：`eval/`、`zc_eval/`
- 基线快照：`baseline_rtl/`
- 测试/脚本：`bench/`、`tests/`、`scripts/`

该工程的报告结论（摘自 `REPORT.md`）：三阶段流水线方案面积 **24,661**，
Fmax **669.37 MHz**，IPC **0.5080**，IPC×F = **340.0**，相对基线 247.8
提升 **37.2%**。

常用入口：

```bash
cd /home/zhangshenlu/ysyx-workbench/test
make build IMPL=rtl_pipe3
make run
make difftest
make bench
make eval VARIANT=pipe3
```

---

## 说明

- 两套工作使用不同的 RTL 目录和评估目录，互不覆盖；
- 基线以各自目录中的 `npc-baseline/` 或 `baseline_rtl/` 快照为准；
- 综合口径：`yosys-sta` + `icsprout55` + 1200MHz 约束，报告中的频率为
  STA 解析出的 max 路径等效频率；
- `npc/` 等目录未做任何修改。
