# NPC 微架构图解

当前工作区（预译码 + stateless ICache hit）与上一版 HEAD `ae80eb8` 的对比。

## 文件

- `npc-microarch.pdf`：8 页 A4 横向图解 PDF（推荐直接打开）
- `png/page-1.png` ~ `png/page-8.png`：逐页 PNG，方便插入文档或聊天
- `npc-microarch.html`：可编辑的 HTML/SVG 源文件

## 页面内容

| 页 | 内容 |
|---|---|
| 1 | 一页速览：2 段式、命中 2 拍、1036 MHz；上一版 vs 当前命中路径 |
| 2 | 三个概念：多周期、关键路径、预译码；为什么切长链能提高频率 |
| 3 | 当前微架构全景：Stage A / 寄存器边界 / Stage B |
| 4 | 一条指令的旅程与周期账：命中 3→2，miss/bypass 不变 |
| 5 | 上一版 vs 当前：关键路径被切开；四个关键改动与代价 |
| 6 | IFU 三状态 + ICache 命中/缺失时间线；关键信号 |
| 7 | ICache tag 26→20 位、写回旁路、x0 保护 |
| 8 | 性能账本、瓶颈、优化优先级、严格 A/B 建议 |

## 重新生成

```bash
cd docs/microarch
~/.local/bin/weasyprint npc-microarch.html npc-microarch.pdf
pdftoppm -png -r 130 npc-microarch.pdf png/page
```

## 口径说明

- “上一版”指 HEAD `ae80eb8`；“当前”指工作区未提交改动。
- 1036 MHz / 19939 面积 / 0.2142 W 来自当前工作区最新一次 `npc/eval` 记录。
- `npc/eval/README.md` 中的 527 MHz / 2.647 W 是更早基线，不是 HEAD 的直接对照；
  严格 A/B 建议在 HEAD 的独立 worktree 上跑同一套 eval。
