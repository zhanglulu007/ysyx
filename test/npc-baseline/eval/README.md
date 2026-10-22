# NPCSynth — 当前 NPC 多周期核整体综合评估

用仓库既有的 `yosys-sta` 流程（yosys 综合 + iEDA 时序/功耗分析）评估
`../vsrc` 下的当前多周期核，产出**面积、最高频率、时序违例、功耗**四项指标。

与 `npc/` 下的仿真评估（IPC、周期、停顿）互补：仿真回答"跑得多快"，
本评估回答"能不能跑到这个频率、要多少面积"。

## 评估范围

`NPCSynth.v` 是综合边界，例化 `top`，覆盖整颗核：

```
top
├── IFU          LSU
├── ICache       WBU
├── IDU          CSR
├── EXU          RegisterFile
└── Arbiter (ICache/LSU 的 AXI AR 仲裁)
```

读取 RTL 时定义 `SYNTHESIS`，此时：

- `top.v` 走内部**合成用**存储模型（`synth_rvalid` / `synth_rdata`），
  不含仿真行为；
- 全部 `DPI-C`（`PMEM`、itrace/mtrace/ftrace、difftest、perf）被排除；
- **总线请求/响应逻辑（AXI AR/R/AW/W/B 通道与 Arbiter 仲裁）保留**在
  面积与时序范围内。

端口对齐核的指令存储器接口（`imem_rdata` / `pc` / `inst` / `imem_addr`），
与 `/home/zhangshenlu/ysyx-workbench/npc/eval` 下的 `rtl-standalone` 评估项
同口径，便于跨版本对比。

未纳入：`PMEM.v`（仿真 DPI-C 内存模型，`SYNTHESIS` 下不被实例化）、
`ysyx_26020070.v`（`SOC_MODE` 专用的 SoC 顶层）。

## 用法

```bash
make check          # 解析/elaborate 整个层次（秒级，先确认可综合）
make synth          # 综合 -> 网表 + 面积报告
make sta            # 综合 + 时序/功耗分析（结束后自动更新 ../config/f_cpu）
make update-f       # 仅从最近时序报告更新 ../config/f_cpu
make report         # 从最近结果提取面积/频率/违例摘要
make all            # sta + report
make clean          # 清除 result/

# 覆盖参数
make sta CLK_FREQ_MHZ=800      # 换时钟约束
make sta PDK=nangate45         # 换工艺库
make sta SDC_FILE=/path/design.sdc
```

## F 参数自动更新

`npc/config/f_cpu` 保存 CPU 频率参数 `F`（单位 10MHz，`F=55` 对应 550MHz）。
`make sta` / `make all` 完成后，会从 `NPCSynth.rpt` 解析最高可达频率，
向下取整到 10MHz 并写回该文件；也可以单独执行 `make update-f`。

```bash
make all
cat ../config/f_cpu
```

`npc/Makefile` 读取 `F` 的优先级：

1. 命令行/环境变量：`make ... F=55`
2. `npc/config/f_cpu`
3. `F_DEFAULT`（默认 `0`，表示不定义 `-DF`）

结果写入 `result/NPCSynth-<频率>MHz/`（已 gitignore）。关键文件：

| 文件 | 内容 |
|---|---|
| `synth_stat.txt` | 面积报告（Chip area、标准单元数、顺序单元占比） |
| `NPCSynth.rpt` | 时序表（各路径 slack / 等效频率 / TNS） |
| `NPCSynth.pwr`、`*_instance.csv` | 功耗报告 |
| `yosys.log`、`sta.log` | 综合与时序分析完整日志 |

## 依赖

- `~/yosys-sta`：`YOSYS_STA_HOME` 可覆盖，提供 `oss-cad-suite/bin/yosys`、
  `bin/iEDA`、`scripts/{yosys,sta}.tcl`、`pdk/{icsprout55,nangate45}`。
- 默认 `PDK=icsprout55`、`CLK_FREQ_MHZ=1200`，与 workbench 的评估口径一致。

## 基线结果（2026-10-20 实测，含 ICache）

`make all PDK=icsprout55 CLK_FREQ_MHZ=1200`：

| 指标 | 数值 |
|---|---|
| 芯片面积 | **21530.60** |
| 　标准单元数 | 6439 |
| 　顺序单元面积 | 11057.20（占 51.36%） |
| 时序约束 | 1200 MHz（周期预算 0.8333 ns） |
| **最高可达频率** | **527.588 MHz** |
| WNS（最差 slack） | −1.062 ns |
| 关键路径终点 | `u_top.u_regfile.rf[8]_25__reg_p:D`（寄存器堆） |
| 总功耗（toggle 0.1） | 2.647 W |

结论：加入 16 块 × 58-bit 的触发器 ICache 后，综合上限约 528 MHz，
瓶颈仍在**寄存器堆的读选通 → 写回**路径；顺序单元占比从 36% 升到
51%，面积增加约 7.8k。

## 注意

- 跨工艺/跨工具链的面积与频率数字**不可直接比较**。历史记录（如
  `15766.8` / `549.6MHz`）来自不同 PDK 与口径，只能作为量级参考。
  本项目的价值在于**同口径、可重复**：固定 PDK、约束与 RTL 边界后，
  每次改动的 PPA 变化都可归因。
- `sta` 的功耗使用固定翻转率 0.1（iPA 默认），不是真实负载功耗，
  只用于版本间相对比较。
- `synth` 后会检查 `yosys.log` 中的 `multiple conflicting drivers`：
  一旦出现多个 always 块驱动同一寄存器，综合会直接失败，避免生成
  “只剩几个 TIE cell”的空网表。
- 本评估项目不修改 `../vsrc` 的源 RTL，只读取。
