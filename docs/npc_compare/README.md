# NPC 架构对比文档

对比两个 NPC 实现：

- `/home/zhangshenlu/ysyx-workbench/npc`：模块化多周期核
- `/home/zhangshenlu/npc_opt_lab_zsl/final_soc`：三级流水核

最终 PDF：`../NPC_architecture_comparison.pdf`

## 目录

```text
docs/npc_compare/
├── NPC_architecture_comparison.pdf   # 最终 PDF（45 页）
├── NPC_architecture_comparison.html  # 生成的 HTML 源
├── build_doc.py                      # HTML/PDF 生成脚本
├── make_figures.py                   # SVG 图表生成脚本
├── figures/                          # 生成的 SVG 图
├── figures_src/                      # Graphviz .dot 源
└── README.md
```

## 重新生成

```bash
cd docs/npc_compare
python3 make_figures.py        # 需要 matplotlib + graphviz dot
/usr/bin/python3 build_doc.py  # 需要 weasyprint + pygments
```

`build_doc.py` 使用 `/usr/bin/python3` 是因为当前环境的 `weasyprint` 安装在该解释器下；
`python3`（venv）可能没有 weasyprint。

## 数据口径

- 综合：`icsprout55`，1200 MHz 约束，`yosys-sta` + iEDA，顶层 `NPCSynth`，`-DSYNTHESIS`。
- 当前 npc 的面积/频率为本次在 `/tmp/npc_cmp` 副本中重跑的结果：19,341.56 / 524.432 MHz。
- final_soc 的面积/频率来自其 `eval/result/NPCSynth-1200MHz`：24,790.64 / 860.096 MHz。
- IPC 来自 README / `soc_train.log`；当前 npc standalone IPC 0.3877 引用 final_soc README 的原始 HEAD 基线，本文未重跑完整 train。
- 功耗两次报告差异过大（12.44 W vs 0.147 W），不作为结论。
