# NPC 面积 / 频率 / IPC 优化报告

> 目标：在面积 < 25k（icsprout55，yosys-sta 同口径）的约束下，提升
> standalone 运行 microbench `train` 的 **IPC × Fmax**。
>
> 结论：最终三阶段流水线方案面积 **24,661**，Fmax **669.37 MHz**，
> IPC **0.5080**，**IPC×F = 340.0**，比基线（247.8）提升 **37.2%**。
> 所有改动只在 `test/` 下，未修改 `npc/` 及其它子项目的源码。
> 基线以 `test/baseline_rtl`（分析开始时的 `npc/vsrc` 快照）为准；
> `npc/` 下的其它未提交改动不参与本报告的统计。

---

## 1. 项目结构与子项目调用关系

`ysyx-workbench` 是"一生一芯"的完整工程，核心子项目与调用链如下：

```
abstract-machine (AM)
  ├─ scripts/riscv32e-npc.mk / riscv32e-ysyxsoc.mk   # 编译/链接/运行规则
  ├─ am/src/riscv/npc/{start.S,trm.c,ioe.c,timer.c,cte.c,trap.S}
  ├─ scripts/linker.ld: 代码/数据放在 0x8000_0000（standalone）
  └─ scripts/ysyxsoc.ld: flash 0x3000_0000 / SDRAM 0xa000_0000（SoC）
        │
        ├─ am-kernels/benchmarks/microbench   # train/test/ref/huge + mainargs
        │     └─ make ... ARCH=riscv32e-npc|riscv32e-ysyxsoc run
        │           └─ $(NPC_HOME)/Makefile run → Vtop <bin>
        │
nemu
  ├─ build/riscv32-nemu-interpreter-standalone-so   # DiffTest REF (.so)
  └─ difftest API: difftest_memcpy/regcpy/exec/raise_intr/init
        │
npc
  ├─ vsrc/top.v                # standalone 顶层（AXI4 + PMEM DPI 模型）
  ├─ vsrc/ysyx_26020070.v      # SoC 顶层，uart/spi/sdram/... 由 ysyxSoC 例化
  ├─ csrc/                     # Verilator harness: DPI-C / difftest / sdb / trace / perf
  ├─ eval/                     # yosys-sta 综合/STA（原多周期核）
  └─ cachesim/                 # 指令 cache 元数据模拟器（PC trace 回放）
        │
ysyxSoC
  ├─ build/ysyxSoCFull.v       # 例化 ysyx_26020070，接 flash/SDRAM/外设
  └─ perip/                    # uart16550/spi/sdram/psram/vga/ps2/gpio/flash...
        │
nvboard                        # 可选：FPGA 引脚绑定（NVBOARD=1）
```

### 1.1 standalone 运行路径（本报告的口径）

1. `microbench` 用 `ARCH=riscv32e-npc` 编译，链接到 `0x8000_0000`；
   `insert-arg.py` 把 `mainargs`（`train`）写入镜像。
2. `npc/Makefile` 用 Verilator 把 `vsrc/*.v` + `csrc/*.cpp` 编译成
   `build/obj_dir/Vtop`。
3. `main.cpp` 把 `.bin` 载入 `pmem[128MB]`；`cpu.cpp` 驱动 `clk` 半周期，
   `exec_once()` 循环到 DPI `commit_instruction` 增加一条指令。
4. RTL 通过 DPI-C 调用：
   - `pmem_read/pmem_write`：数据访存（`PMEM.v`）；
   - `commit_instruction/update_pc_value/update_reg_value`：退休/PC/寄存器；
   - `update_csr_values`、`ebreak_handler`、`mtrace_event`、ftrace；
   - `perf_event`：性能事件（`PERF=1`）。
5. `difftest_step()` 每条指令让 NEMU REF 执行一条，比较 PC + 16 个 GPR
   （RV32E 只有 x0–x15）。

### 1.2 SoC 运行路径

`ysyxSoCFull.v` 例化 `ysyx_26020070`，把 `top` 的 AXI4 主机口接到
flash/SDRAM/外设；代码从 flash `0x3000_0000` 启动，`ssbl` 搬到 SDRAM
`0xa000_0000`。原 `ifu_cacheable` 只覆盖这两个区间，因此 SoC 模式下
ICache 生效。**standalone 的 PC 是 `0x8000_0000`，不在原 cacheable 区间，
所以基线在 standalone 下完全没有 I-Cache**——这是本报告最重要的起点。

---

## 2. 基线 NPC 分析

### 2.1 微架构

基线是一颗**多周期、无流水线**的 RV32E 核：

```
IFU 状态机: IDLE --AR--> WAIT --R--> 指令有效
             ↑                         │
             └──────── commit ←────────┘   (pc <= pc_next)
IDU/EXU/LSU/WBU/CSR 组合执行；LSU 与 IFU 并行发起 AXI
```

- IFU 每条指令发一次 AR，等一次 R；PC 只在 commit 时更新。
- `commit = ifu_valid && (!mem_valid || lsu_done)`。
- ICache 4 组 × 16B 直接映射，命中路径是 AR → RETURN（每字一次握手）；
  但 standalone 下被 `ifu_cacheable` 绕过，实际走 Arbiter 直连 PMEM。
- LSU 单 beat AR/R 或 AW/W/B；load/store 在完成时 commit。
- 寄存器堆 16×32（RV32E），读口带 `raddr==0 ? 0` mux；CSR 含 64-bit mcycle。
- IDU 用 ~40 根 one-hot `is_*`；EXU 用 `case(1'b1)` 优先级 mux；
  WBU 再一级写回 mux。

### 2.2 周期账本（standalone，microbench train）

实测（`npc/build/obj_dir/Vtop ... -b`）：

| 指标 | 数值 |
|---|---:|
| 退休指令 | 195,140,932 |
| 周期 | 413,017,098 |
| IPC | **0.4725** |
| CPI | 2.116 |

每条指令至少 2 拍（AR 1 拍 + R 1 拍）；load/store 再 +1 拍；IFU/LSU
在 Arbiter 上竞争、PMEM 的读状态机也会引入额外等待。没有 I-Cache，
取指带宽是硬上限。

### 2.3 基线 PPA（同口径）

`test/eval` 对 `test/baseline_rtl`（`npc/vsrc` 原样拷贝）综合：

| 指标 | 数值 |
|---|---:|
| 芯片面积 | **19,341.56** |
| 顺序单元面积 | 9,055.20（46.8%） |
| 约束 | 1200 MHz |
| Fmax | **524.432 MHz** |
| 关键路径 | `u_regfile.rf[7]_14:D`（RF 读 → ALU → WBU → RF 写） |

---

## 3. 优化方案 A：单周期退休 + FIFO + 流式 ICache

方案 A 位于 `test/rtl/`，目标是在不显著增加面积的前提下把 CPI 压到接近 1。

### 3.1 关键改动

1. **让 standalone 真正用上 ICache**
   - 新 ICache 为 8 组 × 16B = 128B 直接映射；
   - 命中后按 32-bit 字**连续流出整行**（4 条指令），不再每字一次 AR/R；
   - 行边界命中时在最后一字送出的同一拍完成下一行查表，无气泡；
   - 缺失时 4-beat 突发填充；`fence.i` 清空 valid。

   **ICache 容量/行大小选择**（`npc/cachesim` 回放 microbench train PC
   trace 的元数据结果）：

   | 容量 | 行大小 | 命中率 |
   |---:|---:|---:|
   | 64B | 16B | 90.50% |
   | 128B | 16B | 95.51% |
   | 256B | 16B | 98.02% |

   256B 需要多约 1.2k 个触发器（约 7k 面积），会突破 25k；128B 是
   面积/命中率的折中。实际 standalone train 的每指令 miss 为 18.28%
   （一行平均只被消费约 2 条指令），说明分支密集代码的行利用率是
   主要浪费，但增大行/容量都受面积限制。

2. **8 项指令 FIFO + ICache 旁路**
   - IFU 不再是"一条指令一次握手"，而是由 ICache 自主顺序预取；
   - FIFO 把取指与执行解耦，分支/跳转时清空；
   - FIFO 空时，ICache 输出直接旁路进译码级，避免"先入 FIFO 再读出"
     多耗一拍。

3. **单周期退休**
   - ALU/分支/jal 每周期退休一条；
   - load/store 在 LSU 完成的那一拍退休（约 +1 周期）；
   - 分支 taken 在 EX 解析，重定向代价 1 拍。

4. **面积/时序优化**
   - IDU 从 ~40 根 one-hot 改成 `alu_op/a_sel/b_sel/wb_sel/mem_op/csr_op`
     编码，去掉大量 opcode/funct3/funct7 比较器与优先级 mux；
   - EXU 只保留一个 32-bit 主加法器，加法/减法/SLT/SLTU/分支比较/
     访存地址共用；逻辑与移位并行，结果 mux 选择；
   - RF 去掉读口 `raddr==0` 的 32-bit 零选择 mux，靠 rf[0] 复位为 0
     且永不写 x0；
   - Arbiter 去掉 `ar_grant` 锁存，改为 IFU 优先的组合仲裁；
   - 新增一个译码级寄存器（id_inst/id_pc/id_valid/id_miss），把
     FIFO 8:1 读 mux 挡在关键路径之外；配合 ICache 旁路，IPC 不下降。

5. **正确性修复（重要）**
   - **ICache 部分填充数据冒险**：缺失开始时先 `valid[req_index] <= 0`，
     否则旧 tag 仍命中而数据字已被新行覆盖，重定向会取到错误指令；
   - **SLTU 减法使能**：`sub` 必须覆盖 `ALU_SUB/SLT/SLTU`，否则
     `sltu` 变成加法进位；
   - 这些 bug 都是通过 32 个 cpu-tests 的逐指令 DiffTest 定位的。

### 3.2 方案 A 结果

| 指标 | 数值 |
|---|---:|
| 面积 | 21,907.48 |
| Fmax | 500.784 MHz |
| IPC | **0.5878** |
| IPC×F | **294.4** |
| 关键路径 | `u_regfile.rf[9]_8:D`（1.997 ns） |

IPC 从 0.4725 提升到 0.5878（+24.4%），但 Fmax 从 524.4 降到 500.8
（−4.5%），因此 IPC×F 只提升 18.8%。瓶颈仍然是**单周期执行路径**：
RF 读 mux → 操作数 mux → 32-bit 加法器 → ALU 结果 mux → 写回 mux → RF 写。

---

## 4. 优化方案 B：三阶段流水线（最终方案）

方案 B 位于 `test/rtl_pipe3/`，把方案 A 的单周期执行拆成 ID / EX / WB
三级，用流水线换频率。

### 4.1 结构

```
IFU FIFO/ICache
      │  (FIFO 空时 ICache 输出直接旁路)
      ▼
┌──────────── ID ────────────┐
│ 译码 (IDU)                 │
│ RF 读 + EX/WB 前递          │
│ 操作数选择 (rs1/pc/0,       │
│   rs2/imm_i/imm_s/imm_u)   │
│ 寄存: op_a/op_b/rs2/pc/    │
│   pc+4/pc_target/控制/rd   │
└────────────┬───────────────┘
             ▼
┌──────────── EX ────────────┐
│ ALU (加法/逻辑/移位/比较)   │
│ 分支解析 / 重定向           │
│ LSU 发起 / load-store 停顿  │
│ CSR 读 / CSR 写数据         │
│ 提交 commit (DPI/difftest)  │
│ 写回数据 mux → WB 寄存器    │
└────────────┬───────────────┘
             ▼
┌──────────── WB ────────────┐
│ 寄存器堆写回                │
│ CSR 写回                    │
└────────────────────────────┘
```

### 4.2 关键设计点

1. **前递**
   - ID 读 RF 后，先与 EX 级结果、WB 级结果比较 rd，做 3:1 前递；
   - EX 优先于 WB（EX 更年轻）；
   - 这样背靠背的 ALU 依赖不需要停顿。
2. **load/store 停顿**
   - EX 级是 load/store 且 `lsu_done=0` 时，`ex_stall=1`，ID/EX 保持，
     FIFO 不弹出；
   - `lsu_done` 当拍 load 数据可用，前递到 ID，下一条继续。
3. **CSR 读写分离**
   - CSR 模块拆成 `csr_raddr`（EX 读）与 `csr_waddr`（WB 写）；
   - WB 的 CSR 写与 EX 的 CSR 读同拍时做前递；`mret/ecall` 的
     mepc/mtvec 也走前递，避免 CSR 指令停顿；
   - ecall 在 EX 提交时写 mepc/mcause，mret 在 EX 读 mepc 重定向。
4. **提交与写回分离**
   - 指令在 EX 级提交（`commit_instruction`、`ebreak`、ftrace/mtrace、
     `update_reg_value`），RF/CSR 实际写在 WB 级；
   - `update_reg_value` 改在 EX 提交时调用，WB 级 RF 不再挂 DPI hook，
     避免 WB 的旧值覆盖 difftest 的寄存器 cache（这是调试中发现的
     一个真实时序 bug）。
5. **取指侧保持方案 A**
   - 8 项 FIFO、128B 流式 ICache、FIFO 空旁路、`fence.i` flush、
     缺失/重定向时的 DRAIN，全部复用。

### 4.3 设计空间探索（同口径综合）

| 变体 | 面积 | Fmax | 说明 |
|---|---:|---:|---|
| A: 两阶段 | 21,907.48 | 500.78 | 方案 A |
| B1: 三阶段，pc_target 在 ID，CSR 前递 | **24,661.00** | **669.37** | **最终选择** |
| B2: pc_target 移到 EX | 24,640.28 | 661.45 | 关键路径转到 ICache `cur_word` |
| B3: B2 + 去掉 CSR 前递、CSR 停顿 | ≈24.1k | 602.31 | 关键路径转到 ICache `valid` |
| B4: B1 + `ex_pc_plus4` 在 EX 计算 | 24,534.16 | 647.61 | 省 32 个触发器，但 F 下降 |
| A2: 方案 A + one-hot 写回 mux | ≈22.2k | 487.97 | 在方案 A 上试验；宽 OR 树反而更慢，已回退 |

最终选 B1：Fmax 最高，面积 24,661 < 25k。A2 的 one-hot AND-OR 在 ABC
映射下面积/时序都变差，说明"减少逻辑级数"不能只看 RTL 层数，必须实测。

### 4.4 方案 B 结果

| 指标 | 数值 |
|---|---:|
| 面积 | **24,661.00**（余量 339） |
| 顺序单元面积 | 12,085.92（49.01%） |
| 标准单元数 | 7,362 |
| Fmax | **669.368 MHz** |
| IPC | **0.5080** |
| CPI | 1.9686 |
| IPC×F | **340.0** |
| 关键路径 | `u_top.ex_pc_target_30:D`（1.4939 ns） |

---

## 5. 验证

### 5.1 验证工程

`test/` 是独立工程，**只读取** `npc/csrc` 的仿真框架，RTL 全部在
`test/rtl` 与 `test/rtl_pipe3`：

```bash
make build IMPL=rtl_pipe3          # Verilator + npc/csrc + DPI
make difftest IMPL=rtl_pipe3       # 32 个 cpu-tests + CSR 定向测试 + DiffTest
make bench IMPL=rtl_pipe3          # microbench train, 输出 IPC
make -C eval all VARIANT=pipe3     # yosys-sta 综合/STA/面积
./scripts/summarize.sh             # 汇总
```

`test/eval` 的 `VARIANT` 支持 `base`（npc/vsrc 拷贝）、`opt`（方案 A）、
`pipe3`（方案 B），三者使用同一个 `NPCSynth.v` 边界、同一 PDK/约束，
因此面积和频率可直接比较。

### 5.2 DiffTest 回归

对 `am-kernels/tests/cpu-tests/build/*-riscv32e-npc.bin` 运行 32 个
测试，每个都带 `-d nemu/build/riscv32-nemu-interpreter-standalone-so`：

- 方案 A：**32/32 pass**
- 方案 B：**32/32 pass**

覆盖 add/sub/bit/shift/div/mul-longlong/load-store/unalign/bubble-sort/
quick-sort/matrix-mul/mersenne 等。

另外，`bench/csr_test.S` 是专门补的 CSR/异常定向测试（`make csrtest`），
覆盖：

- `csrw mtvec/mepc`、`csrr`、`csrrs`；
- `csrw mepc` 后**背靠背** `csrr`（WB→EX CSR 前递）；
- `ecall → trap → csrr mcause/mepc → csrw mepc → mret`（背靠背
  `csrw mepc; mret`，验证 mepc 前递）；
- `fence.i`（ICache flush）。

方案 A 和方案 B 均通过该测试（`HIT GOOD TRAP`）。

### 5.3 Microbench train

两个方案都跑完 `MicroBench PASS`，`train` 规模：

| 方案 | 指令 | 周期 | IPC |
|---|---:|---:|---:|
| 基线 | 195,140,932 | 413,017,098 | 0.4725 |
| A | 195,138,903 | 331,986,044 | 0.5878 |
| B | 195,139,818 | 384,151,085 | 0.5080 |

### 5.4 性能计数器（方案 B，PERF=1）

`test/result/microbench-rtl_pipe3-perf.log` 的关键数据：

```
[Instruction mix]
  alu      114,274,150  58.56%
  load      15,587,961   7.99%
  store      7,147,249   3.66%
  branch    52,591,079  26.95%
  jump       3,961,591   2.03%
  upper      1,577,787   0.81%
[Control flow]
  taken / not taken: 38,685,728 / 13,905,351 (73.56% taken)
  control transfer : 28.98% of committed instructions
[ICache]
  access / hit / miss: 195,139,818 / 159,460,260 / 35,679,558
  hit rate / miss rate: 81.72% / 18.28%
  refill AR: 18,272,635
[LSU]
  load / store done: 15,587,961 / 7,147,249
  avg load latency : 1.9268 cycles
  avg store latency: 1.0000 cycles
```

这组数据解释了 IPC 的构成：

- **分支占比 26.95%，其中 73.56% taken**。三阶段的分支重定向要清空
  ID/EX 两级，taken 分支代价约 2 拍；这是方案 B 相对方案 A IPC 下降
  （0.588 → 0.508）的主要原因。
- **ICache 每条指令 miss 率 18.28%**，平均每 10.7 条指令一次 refill；
  128B 容量对 microbench 的分支密集代码偏小，refill 是第二大成本。
- load/store 占比 11.65%，平均 load 1.93 拍、store 1.0 拍，合计约
  0.2 CPI。

---

## 6. 最终对比

| 设计 | 面积 | Fmax | IPC | IPC×F | 相对基线 |
|---|---:|---:|---:|---:|---:|
| 基线 | 19,341.56 | 524.43 MHz | 0.4725 | 247.8 | 1.00× |
| 方案 A | 21,907.48 | 500.78 MHz | 0.5878 | 294.4 | 1.19× |
| **方案 B** | **24,661.00** | **669.37 MHz** | **0.5080** | **340.0** | **1.37×** |

- 面积：24,661 < 25k，满足约束（余量 339）。
- IPC：方案 B 比基线 +7.5%，比方案 A −13.6%；
- Fmax：方案 B 比基线 +27.6%，比方案 A +33.7%；
- **IPC×F：方案 B 比基线 +37.2%，比方案 A +15.5%。**

---

## 7. 瓶颈分析与后续方向

### 7.1 当前瓶颈

1. **频率**
   - 关键路径 `id_pc + (is_jal ? imm_j : imm_b) → ex_pc_target` 1.494 ns；
   - ICache 的 `cur_word/cur_index` 更新路径约 1.47–1.51 ns，与 PC 目标
     路径接近；
   - 两条路径都受 8:1 tag mux + 25-bit 比较 + 32-bit 加法器的限制。
2. **面积**
   - 24,661，仅余 339；三阶段流水线寄存器（约 330 个触发器）和
     128B ICache（1024 个数据触发器）是主要开销；
   - 顺序单元占 49%，面积已经很难再压缩。
3. **IPC**
   - 分支占 27%，taken 73.6%，三阶段重定向 2 拍；
   - ICache 每指令 miss 18.3%，128B 容量不足；
   - load/store 各 +1 拍。

### 7.2 可行的后续优化

| 方向 | 预期收益 | 代价/风险 |
|---|---|---|
| 16 组 × 16B（256B）ICache | miss 率显著下降 | +~7k 面积，超 25k |
| 2 路组相联（同 128B） | 冲突 miss 可能下降 | +tag/LRU 逻辑，面积余量不足；cachesim 显示 train 上收益很小 |
| 分支目标缓冲 / ID 级分支解析 | 降低 taken 分支代价 | 与单提交口冲突，需要提交队列；面积/复杂度高 |
| Store buffer | store 提前退休 | store 仅 3.66%，收益小 |
| 寄存器化 tag 查找 / 下一行命中预判 | 缩短 ICache 关键路径 | +~30 触发器，需仔细处理重定向 |
| 数据 cache | 降低 load 延迟 | 128B 数据 cache +~6k 面积，不可行 |

在面积 < 25k 的硬约束下，当前方案 B 已经接近"频率-面积-IPC"的折中上限：
再增加 cache 或流水级都会突破面积；而降低分支代价需要更复杂的提交/
预测结构。

---

## 8. 复现命令

```bash
cd /home/zhangshenlu/ysyx-workbench/test

# 方案 B 仿真器
make build IMPL=rtl_pipe3
make difftest IMPL=rtl_pipe3
make bench IMPL=rtl_pipe3

# 方案 B 综合/STA/面积
make -C eval all VARIANT=pipe3

# 方案 A / 基线
make build IMPL=rtl
make bench IMPL=rtl
make -C eval all VARIANT=opt
make -C eval all VARIANT=base

# 汇总
./scripts/summarize.sh
```

依赖：

- `verilator`、`yosys`、`iEDA`（`~/yosys-sta`）；
- `riscv64-linux-gnu-gcc`（AM 工具链）；
- `nemu/build/riscv32-nemu-interpreter-standalone-so`（DiffTest REF）；
- `am-kernels/benchmarks/microbench/build/microbench-riscv32e-npc.bin`
  （已复制到 `test/bench/`）。

### 8.1 迁移到 `npc/vsrc`

由于题目要求不修改其它目录，本工程没有直接改 `npc/vsrc`。最终 RTL 位于
`test/rtl_pipe3/`，`top` 的端口与 `npc/vsrc/top.v` 完全一致
（`clk/rst/imem_rdata/pc/inst/imem_addr` + standalone AXI），可以整体
覆盖到 `npc/vsrc/` 并复用 `npc/Makefile`。迁移时注意：

- `register_file.v` 去掉了 DPI `update_reg_value` hook（pipe3 top 在 EX
  提交时调用）；
- `csr.v` 拆成 `csr_raddr` / `csr_waddr`；
- `exu.v` 被 `alu.v` 取代；
- `PMEM.v` 与接口保持不变。

如果只想要较小的改动量，方案 A（`test/rtl/`）与 `npc/vsrc` 的模块划分
更接近，面积余量也更大（21.9k），但 IPC×F 低于方案 B。

---

## 9. 结论

- 基线在 standalone 下**没有 I-Cache**，每条指令至少 2 拍，IPC 0.4725；
  这是最大的结构性浪费。
- 方案 A 用"单周期退休 + FIFO + 128B 流式 ICache"把 IPC 提升到 0.5878，
  但单周期执行路径把 Fmax 限制在 500.8 MHz。
- 方案 B 把执行拆成 ID/EX/WB 三级，在面积 24,661（< 25k）下把
  Fmax 提升到 669.4 MHz，IPC 0.5080，**IPC×F = 340.0，较基线 +37.2%**。
- 32 个 cpu-tests + CSR/ecall/mret/fence.i 定向测试的逐指令 DiffTest
  与 microbench train 全部通过；所有新增 RTL、验证脚本和评估流程均
  位于 `test/`，未修改其它目录。
