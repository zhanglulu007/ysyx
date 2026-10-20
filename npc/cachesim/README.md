# cachesim

指令 cache 的**元数据**模拟器：读取 NEMU 导出的 PC 序列，回放并统计 ICache 的
命中/缺失次数与总缺失时间 TMT。

对应《B4：存储层次结构和局部性原理》的「实现 cachesim」与「使用 cachesim 进行设计空间探索」。
核心观察是：给定程序的取指地址序列固定，且缺失次数与访存内容无关，因此只需维护
valid/tag/LRU 元数据即可，无需 RTL 仿真、无需指令内容、无需处理器驱动。

## 输入：NEMU 导出的 PC 序列

由 NEMU 的 `-c/--cachesim-trace=FILE` 生成，格式为**裸二进制小端 u32 序列**，
每条提交指令一个 PC（不含反汇编，不依赖 `CONFIG_TRACE`）。

```bash
# 在 nemu/ 下：先切到 ysyxsoc 运行配置并编译
make riscv32-ysyxsoc_defconfig
make YSYXSOC_REF=1 NAME=riscv32-nemu-interpreter-ysyxsoc -j

# 导出 microbench train 的 PC 序列（-c 必须在镜像位置参数之前）
./build/riscv32-nemu-interpreter-ysyxsoc -b \
    -c ../npc/cachesim/build/microbench-train.pc \
    ../am-kernels/benchmarks/microbench/build/microbench-riscv32e-ysyxsoc.bin
```

注意 `YSYXSOC_REF=1` 是必需的：它让 NEMU 的内存模型从单块 `pmem` 切换为
FLASH + SRAM + SDRAM，复位向量指向 `0x30000000`，从而能直接运行
`riscv32e-ysyxsoc` 的镜像。

## 用法

```bash
make                       # 产物 build/cachesim
./build/cachesim --trace build/microbench-train.pc \
                 --sets 16 --ways 1 --block 4 --miss-penalty 30
```

| 参数 | 含义 |
| --- | --- |
| `--trace FILE` | NEMU 导出的 u32 PC 序列（必填） |
| `--sets N` | 组数，2 的幂，默认 16 |
| `--block BYTES` | 块大小，2 的幂且 ≥ 4，默认 4 |
| `--ways N` | 相联度，2 的幂，默认 1 |
| `--miss-penalty N` | 每次缺失折算的周期数，默认 30 |

默认值 `sets=16 ways=1 block=4` 与当前 `npc/vsrc/ICache.v` 完全一致
（16 块直接映射，每块 4 字节），因此可直接作为 NPC 性能计数器的参考。

## 一键评估（推荐）

```bash
make -C npc/cachesim eval
```

cachesim 自带完整流程，`npc/Makefile` 不参与；全部产物落在本目录 `build/` 下。

一次完成三件事：

1. **隔离并自动恢复 NEMU 配置**：导出 trace 前把 `nemu/.config`、`.config.old`、
   `include/config`、`include/generated` 备份到 `npc/cachesim/build/.nemu-cfg-bak`，
   切到 `riscv32-ysyxsoc_defconfig` 编译并导出 trace；结束后（**包括 Ctrl-C 或中途失败**）
   由 `trap EXIT` 无条件还原，因此不会污染你原本的 NEMU 配置。
2. **多进程并行探索**：按 `block × ways × sets` 网格以 `JOBS`（默认 CPU 核数）
   并行调用 cachesim，每组结果落盘到 `npc/cachesim/build/sweep/*.csv`。
3. **打印报告**：输出环境信息、当前实现的基线、**全部组合**的完整结果表（按 TMT 升序）、
   最优组合及其相对基线的改善，以及与 NPC perf 的参考对照。

可调参数（均可在命令行覆盖）：

| 变量 | 默认 | 含义 |
| --- | --- | --- |
| `JOBS` | CPU 核数 | 并行进程数 |
| `SWEEP_BLOCKS` | `4 8 16 32` | 块大小网格 |
| `SWEEP_WAYS` | `1 2 4` | 相联度网格 |
| `SWEEP_SETS` | `4 8 16 32` | 组数网格 |
| `PENALTY` | `30` | 每次缺失的周期数 |
| `FORCE` | 空 | 设为 `1` 强制重建 trace |

拆开用的子目标：`make trace`（只导 trace）、`make sweep`（扫描并打印全表）、
`make report`（只按已有 CSV 重打印完整报告）、`make run`（单组评估）。

例：`make eval SWEEP_WAYS="1 2 4 8" PENALTY=34`

报告不截断结果，组合数较多时输出会较长；只想看全表可单独跑 `make sweep`。

## 输出

```text
[ICache behavior]
  access / hit / miss: 195141500 / 144000660 / 51140840
  hit rate / miss rate: 73.79% / 26.21%
  compulsory / replace: 16 / 51140824 (OK)

[Fetch traffic]
  cacheable (access)  : 195141500
  bypass (uncached)   : 154571
  total fetched       : 195296071

[Miss cost]
  miss penalty        : 30 cycles
  TMT                 : 1534225200 cycles
```

- `access` 只统计落在可缓存区间的取指；区间外计入 `bypass`。区间判定
  （`0x3000_0000~0x3100_0000` 与 `0xa000_0000~0xa200_0000`）照抄
  `npc/vsrc/top.v` 的 `ifu_cacheable`，这是能与 NPC 对上的前提。
- `compulsory` = 组内有无效路的缺失；`replace` = 组内全有效时的替换。
- `TMT = miss × miss_penalty`，按讲义用常数缺失代价估算。

## 与 NPC 性能计数器的对照（仅供参考）

用 `microbench train`（`mainarch=train`）实测，cachesim 在 `16/1/4` 下与
`npc/build/perf-microbench.log` 的 `[ICache behavior]` 段对比：

| 指标 | NPC perf | cachesim | 差异 |
| --- | --- | --- | --- |
| bypass | 154571 | 154571 | **0** |
| compulsory | 16 | 16 | **0** |
| access | 195334923 | 195141500 | −193423 |
| hit | 144193422 | 144000660 | −192762 |
| miss | 51141501 | 51140840 | −661 |
| misses per 1k inst | 261.61 | 261.86 | +0.25 |

`bypass` 与 `compulsory` 完全一致，说明区间判定与缺失分类正确。
其余差异恰好等于两侧**指令总数之差**（NPC commit 195489494 vs NEMU 195296071，
差 193423，正好等于 access 之差），即算法一致，差异来自两次运行的指令流长度不同。
若要严格逐项对齐，应让 NPC 与 NEMU 跑同一份镜像并核对 commit 计数。

## 局限

- trace 为未压缩的 u32 裸序列（train 规模约 780 MB）。讲义提到的 bzip2 + 差分压缩未实现。
- 缺失代价取常数，未区分块大小 > 总线位宽时的多次总线事务开销。
- 不模拟写回、预取、多端口等特性；块大小 > 4 时按「块内一次缺失、后续命中」处理。
