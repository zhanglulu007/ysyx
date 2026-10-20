# cachesim

NPC 指令 cache 的元数据模拟器。它只回放 PC 序列，不保存 cache 数据，因此可以快速评估
不同 cache 参数下的缺失次数和 TMT（Total Miss Time）。

## 1. 编译

```bash
make -C nemu/tools/cachesim
```

## 2. 生成 PC 序列

NEMU 新增了 `-c/--cache-trace=FILE` 选项，输出紧凑的二进制 PC 序列：

```bash
make -C nemu cachesim-nemu
nemu/build/riscv32-nemu-interpreter-ysyxsoc -b -c build/cachesim.trace \
  am-kernels/benchmarks/microbench/build/microbench-riscv32e-ysyxsoc.bin
```

`cachesim-nemu` 会临时切换到 `riscv32-ysyxsoc_defconfig` 并以 `YSYXSOC_REF=1`
构建，结束后自动恢复原来的 NEMU 配置。

NEMU 在该模式下只建模 FLASH/SRAM/SDRAM，SoC 的 UART/VGA 等 MMIO 写入会被丢弃，
UART LSR 返回 `THRE=1`，因此 AM 的 `putch()` 不会死等。

## 3. 单组参数

```bash
nemu/tools/cachesim/cachesim --trace build/cachesim.trace \
  --size 4K --block 16 --ways 2 --miss-penalty 41.4
```

默认只把 FLASH `[0x30000000,0x31000000)` 和 SDRAM `[0xa0000000,0xa2000000)`
视为可缓存，与 `npc/vsrc/ICache.v` 一致；其他取指计入 `bypass`。
用 `--cache-all` 可以取消这个限制。

输出中的关键指标：

- `accesses/hits/misses`：可缓存取指数、命中数、缺失数
- `bypass`：不可缓存取指数
- `compulsory/replace`：首次填充 / 替换造成的缺失
- `tmt = misses * miss_penalty`

`--csv` 只输出一行，便于脚本收集。

## 4. 一键 DSE

```bash
nemu/tools/cachesim/run-dse.sh --check
```

脚本会：

1. 编译 cachesim；
2. 如果没有 ysyxsoc 版 NEMU，自动执行 `make -C nemu cachesim-nemu`；
3. 用 NEMU 生成 `nemu/build/cachesim.trace`；
4. 从 `npc/build/perf-microbench.log` 读取 NPC 实测的平均缺失代价（找不到则用 30）；
5. 扫描 size/block/ways 组合，按 TMT 排序，结果写入 `dse.csv`；
6. `--check` 额外把 `64B / 4B / 1-way` 的 cachesim 结果与 NPC 的
   `icache_miss` 对比，作为性能 DiffTest（TMT 只由缺失次数决定）。
   默认允许 `CHECK_TOL=0.001` 的相对误差；`CHECK_TOL=0` 可做严格比较。

> NEMU 的 SoC MMIO sink 不模拟 UART THRE 的真实时序，所以带 `putch` 轮询的程序
> 在 NEMU 中会少执行一些“全命中”的等待指令，`access/hit` 可能略小于 NPC；
> 缺失次数仍然可以对齐（hello 实测 381 vs 381，microbench train 51140840 vs 51141501）。

可用环境变量覆盖默认值：

```bash
SIZES="512 1024 2048" BLOCKS="4 16" WAYS="1 2" PENALTY=41.4 \
  nemu/tools/cachesim/run-dse.sh path/to/image.bin path/to/trace
```

## 5. trace 格式

二进制 RLE：

```text
uint32 magic   = 0x43535431 ("CST1")
uint32 version = 1
{ uint32 pc, uint32 run_len } ...
```

`run_len` 表示从 `pc` 开始连续执行 `run_len` 条 4 字节指令。
cachesim 也兼容 NEMU 的文本 itrace（每行以 `0x...` 开头，或含 `pc=0x...`）
以及裸 `uint32_t` PC 数组。
