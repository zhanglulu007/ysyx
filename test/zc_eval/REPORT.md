# NPC 核优化报告

> 评估口径：standalone 运行 `microbench` 的 `train` 规模；分数 = IPC × 最高频率；
> 面积要求 < 25000（`icsprout55`，yosys + iEDA STA，1200MHz 约束）。
>
> 验证工程：`test/zc_eval`。基线 RTL 冻结在 `test/zc_eval/rtl_baseline`
> （git `HEAD` 的 `npc/vsrc`）。

---

## 1. 结论

| 指标 | 基线 | 优化后 | 变化 |
|---|---:|---:|---:|
| IPC | 0.4725 | **0.6653** | **+40.8%** |
| 最高频率 | 524.43 MHz | 516.89 MHz | −1.4% |
| 分数 (IPC×MHz) | 247.8 | **343.9** | **1.39×** |
| 面积 | 19341.56 | **24886.68** | +28.7%（< 25000 ✓） |
| 周期数 | 413,014,750 | **293,290,382** | −29.0% |
| 指令数 | 195,139,784 | 195,139,535 | — |

功能验证：microbench train 全部 10 个 benchmark **PASS**；自写 RV32E
冒烟测试 26 项检查 **HIT GOOD TRAP**；SoC 模式 Verilator lint 通过。

**一句话总结**：原核的瓶颈是取指——standalone 下 `0x8000_0000` 不在
ICache 范围内，每条指令都要走 2 拍总线，IPC 上限只有 0.5。优化把取指
变成"命中 1 拍/条 + 缺失行内流式填充"，并加入 8 项 BTB 消除 taken
分支的取指断流，IPC 从 0.4725 提升到 0.6653（+40.8%）；面积控制在
24.89k。频率受 E 段 ALU+写回组合路径限制，本次流水线拆分没有带来
频率收益（516.9 vs 524.4），这是一项明确的后续工作。

---

## 2. 项目结构与调用关系

```
ysyx-workbench
├── abstract-machine/        AM 运行时；riscv32e-npc / ysyxsoc 构建脚本
├── am-kernels/              microbench 等负载；产出 riscv32e-*.bin/.elf
├── nemu/                    NEMU 参考模型；build/*-so 供 DiffTest
├── npc/                     ★ 本项目的 RTL + Verilator 仿真 + 综合评估
│   ├── vsrc/                RTL（top/IFU/ICache/IDU/EXU/LSU/WBU/CSR/...）
│   ├── csrc/                仿真框架：main、cpu、memory(PMEM)、device、
│   │                        perf、difftest、trace、sdb
│   ├── eval/                yosys-sta 项目（面积/频率/功耗），回写 config/f_cpu
│   ├── config/f_cpu         频率参数 F（单位 10MHz）
│   └── Makefile             standalone / SOC 两种构建，Verilator + DPI-C
├── ysyxSoC/                 SoC 集成（ysyxSoCFull，例化 ysyx_26020070）
├── nvboard/                 FPGA 板级外设（可选）
└── rt-thread-am/            RT-Thread + AM 运行环境
```

**仿真调用链**（standalone）：

1. AM 以 `-march=rv32e_zicsr_zifencei -mabi=ilp32e` 编译 microbench，
   生成 `microbench-riscv32e-npc.bin`（链接在 `0x8000_0000`）。
2. `npc/Makefile` 用 Verilator 把 `vsrc` + `csrc` 编成 `Vtop`；
   `main.cpp` 把 bin 装入 PMEM，`cpu.cpp` 逐拍 `eval()`，等待
   `commit_instruction` 使累计指令数变化；可选 NEMU DiffTest。
3. `PMEM.v` 是 AXI4 从设备模型，通过 DPI-C 调 `pmem_read/pmem_write`；
   `Arbiter.v` 仲裁 ICache 与 LSU 的 AR。
4. `core/perf.cpp` 汇总 `top.v` 通过 DPI-C 上报的性能事件，结束时打印报告。
5. `eval/` 用 `-DSYNTHESIS` 读同一套 RTL（排除 DPI-C/PMEM/trace），
   综合出 `NPCSynth` 并做 STA，频率写回 `config/f_cpu`。

**SoC 模式**：`ysyx_26020070.v` 把 `top` 的 AXI 主口接到 `ysyxSoCFull`，
从 flash（`0x3000_0000`）启动、搬代码到 DDR（`0xa000_0000`）后执行。
本报告的主指标是 standalone；SoC 路径保留了原有 AXI 接口和
`difftest_skip_ref` 逻辑，并通过 lint。

---

## 3. 基线测量与瓶颈

### 3.1 基线数字

- cycles 413,014,750；inst 195,139,784；**IPC 0.4725**（CPI 2.1165）
- 面积 19341.56（顺序单元 9055.20），最高频率 **524.43 MHz**，
  WNS −1.074ns；关键路径 `u_regfile.rf[*][14]:D`，等效 1.9ns
- 分数 247.8

### 3.2 指令组成（基线 PERF）

| 类别 | 占比 | 说明 |
|---|---:|---|
| ALU | 58.56% | R 型 26.0M，I 型 88.3M |
| load | 7.99% | word 84.5%，byte 10.1%，half 5.3% |
| store | 3.66% | word 88.3% |
| branch | 26.95% | **taken 73.56%**（38.7M / 52.6M） |
| jump | 2.03% | jal 1.93M，jalr 2.03M |
| upper | 0.81% | lui/auipc |

### 3.3 根因

1. **每条指令至少 2 拍**：standalone 代码在 `0x8000_0000`，但原
   `ifu_cacheable` 只覆盖 `0x3000_0000-0x3100_0000` 与
   `0xa000_0000-0xa200_0000`，因此 **195M 次取指全部 bypass ICache**
   （基线 PERF 中 `icache_access=0`，`if_bypass=195M`）。IFU 的
   IDLE→WAIT 状态机 + 总线往返使 ALU 指令也只能 2 拍一条，理论
   IPC 上限 0.5。
2. **分支多且 taken 比例高**：26.95% 的分支、73.56% taken。没有预测时
   每个 taken 分支都要冲刷取指，微基准的分支密度使流水线几乎无法
   连续。
3. **单周期执行路径过长**：基线关键路径 = ICache 读 → 译码 → RF 读
   → ALU/分支 → 写回 mux → RF 写，1.9ns → 524MHz。取指、译码、RF
   读、ALU、写回全部串在一拍。
4. **load/store 串行**：LSU 必须等 R/B 才 commit，load 至少多 1 拍。

---

## 4. 优化设计

### 4.1 总体微架构：3 级流水 F / D / E

```
F: PC + BTB -> ICache(流式) -> IFID           （取指）
D: IDU 译码 + RegisterFile 读 -> IDEX          （译码/读寄存器）
E: 旁路 -> EXU(ALU/分支) -> WBU(纯 mux) -> RF 写
   + LSU 发起/等待 + CSR + 重定向
```

- **F**：命中时每个周期取一条；IFID 只有 1 项，D 前进时 F 才能再取。
- **D**：IDU 从 `ifid_inst` 译码，控制包（ALU op、branch type、jump/
  load/store/CSR 标志等约 23 位）与 `rs1/rs2/pc/inst` 一起锁进 IDEX。
- **E**：从 IDEX 寄存器出发，经 **EX→EX 旁路**（上一条已提交指令的
  `last_result`）直接进 ALU；分支在 E 段解决；load/store 在 E 段发起，
  等 `lsu_done` 才 commit；jal/jalr 的 link 值由 `ex_pc_plus4` 提供。
- 分支预测由 BTB 完成；E 段用"下一条指令 PC 是否正确"校验预测：
  `next_pc_ok = ifid_valid ? (ifid_pc == correct_next_pc)
                           : (pc_f == correct_next_pc)`。
  预测只影响性能，不影响正确性；重定向固定 2 拍代价（冲刷 IFID +
  重取目标）。
- load-use 依赖由 `last_result` 旁路解决（距离 1）；距离 2 由 RF 写回
  可见性解决（D 在 E 写回后的下一拍读 RF）。

### 4.2 ICache：4×16B 直接映射 + 行内流式填充

这是 IPC 提升的最大来源。设计演进：

| 版本 | 取指行为 | 微基准 IPC |
|---|---|---:|
| 基线 | 全部 bypass，2 拍/条 | 0.4725 |
| 直接映射 + 阻塞填充 + 早发 AR | 命中 1 拍；缺失 AR+4beat+服务 ≈ 9 拍/行 | 0.5797 |
| **行内流式填充（最终）** | 缺失时目标字所在 beat 一到就送出，后续 beat 后台填本行 | **0.6653** |

关键点：

- **命中 1 拍/条**：`fetch_inst_valid` 在 `state==IDLE && hit` 同拍给出，
  没有旧的 RETURN/SERVE 状态往返。
- **早发 AR**：缺失检测的同一拍就拉高 `arvalid`，省 1 拍。
- **行内流式填充**：`beat_is_word` 用总线 `rdata` 直接服务当前字；
  已填入的字（`word_in < beat_cnt`）从数组部分命中。顺序流中
  4 条指令与 4 拍填充完全重叠，实测把 IFU stall 从 34.7% 降到 12.6%。
- **不允许填充期间命中其它行**：这是与第一版流式实现的关键区别。
  允许其它行命中会让 F 跑超前、重定向取消正在填的行，miss 数从
  19.5M 涨到 28.8M，IPC 反而降到 0.516。
- **取消/重定向的处理**：已写 beat 的行必须作废（数据被部分覆盖）；
  未写 beat 的保留原行；`rlast` 同拍取消时数据已完整，写入最后一拍
  并提交该行。冒烟测试曾在这里抓到一个 bug：最后拍取消只置 valid
  没写数据，导致该行 word3 保留旧行指令；修复后通过。
- 缺失行号/标签/字偏移与填充计数（`beat_cnt`）都是小寄存器，
  没有额外 SRAM。

### 4.3 BTB：8 项 taken cache

- 8 项，索引 `pc[4:2]`，标签 `pc[23:5]`（19 位），目标 `[14:0]`，
  预测目标 = `{pc[31:15], target[14:0]}`（32KB 代码窗口）。
- 只在实际 taken 且预测失败时写表；正确预测不写，避免同索引分支
  互相覆盖。
- **标签截断必须配 opcode 门控**：只有取到的指令是 B/J 时才使用
  预测；否则标签别名可能让非分支跳到错误目标而 E 段无法纠正。
  对 B/J 的误预测是安全的——E 段的 `next_pc_ok` 会重定向到真实目标。
- 实验：只给 **4 项** BTB 时，预测数从 49.7M 跌到 16.9M，重定向从
  13.6M 涨到 33M，IPC 回落到 0.4713。8 项是必要的。

### 4.4 其它面积/频率优化

- **AUIPC 复用分支加法器**：`pc_imm = pc + (is_jal?imm_j :
  (is_auipc?imm_u:imm_b))`；WBU 不再有独立的 `pc+imm_u`/`pc+4`
  32-bit 加法器，写回路径退化为纯 mux。`pc_plus4` 由 E 段现有加法器
  提供。
- **load/store 地址复用 ALU 加法器**：EXU 对 load/store 计算
  `rs1+imm_i/imm_s`，删掉 top 里独立的地址加法器。
- **译码移到 D**：E 段不再包含 opcode/funct 译码；控制包寄存。
  实测这一项对频率没有明显收益（关键路径仍在 ALU+写回），但让
  E 段控制与 opcode 解耦，便于压缩 BTB/ALU 控制。
- **BTB 位宽裁剪 + mcycle 32 位**：面积从 25.7k 降到 24.89k。
  mcycle 在 32 位仿真规模内不溢出；`mcycleh` 读 0。代码 >32KB 时
  BTB 目标可能跨窗口，只会多一次重定向，不影响正确性。

---

## 5. 验证方法（`test/zc_eval`）

### 5.1 冒烟测试 `tests/smoke.S`

手写 RV32E 汇编，26 项检查，覆盖：

- x0 恒零；ALU 连续 RAW 依赖（add/addi/sub/xor/sll/srl/sra/slt/sltu）
- lui/auipc
- lw/sw、lb/lbu、lh/lhu（符号/零扩展，off=4/6/8 的非对齐字内偏移）
- load-use 立即进 ALU / 进分支
- 后向 taken 循环、嵌套循环（两个后向分支争用 BTB）
- 前向 not-taken / taken 分支
- jal/jalr 函数调用与返回（BTB taken cache + 返回地址）
- csrw/csrs/csrr（mstatus）
- `fence.i`（冲刷 ICache+BTB 后继续）
- 失败时 `a0=用例号` 并 `ebreak`；成功 `a0=0`。

该测试在开发中抓到了流式填充最后拍取消的脏行 bug（见 4.2），
修复后 `HIT GOOD TRAP`。

### 5.2 microbench train

同一份 `microbench-riscv32e-npc.bin`，standalone 模式，10 个 benchmark
全部 PASS（校验和正确），共 195,140,113 条指令，`HIT GOOD TRAP`。

### 5.3 综合/STA

`test/zc_eval/synth` 的边界 `NPCSynth` 只暴露
`clk/rst/imem_rdata/pc/inst/imem_addr`，与 `npc/eval` 同口径：
`-DSYNTHESIS`、排除 DPI-C/PMEM、保留 AXI 仲裁；`icsprout55`、
1200MHz 约束、yosys + iEDA。官方 `npc/eval` 对最终 RTL 复核结果：
**面积 24886.68，最高频率 516.894MHz，WNS −1.102ns**。

---

## 6. 结果分解

### 6.1 最终 PERF（standalone train）

```
cycles 293,290,382   inst 195,139,535   IPC 0.6653   CPI 1.5030
IFU stall          36,939,585 cycles (12.59%)   （基线 34.7%）
ICache access/hit/miss  182,828,298 / 163,243,506 / 19,584,792
ICache miss rate   10.71%（compulsory 462,948；replace 19,121,844）
BTB predicted      49,665,467；taken 重定向 13,607,042（6.97% commits）
load latency       2.0296 cycles（issue+wait）；store 1.00
```

CPI 拆解（近似）：

| 来源 | CPI | 说明 |
|---|---:|---|
| 基础 | 1.00 | 每拍一条 |
| 取指/ICache | 0.19 | 缺失 AR + 行内填充的剩余停顿 |
| taken 分支重定向 | 0.14 | 13.6M × 2 拍 |
| load 等待 | 0.08 | 15.6M × ~1.03 |
| store 等待 | 0.04 | 7.1M × 1 |
| 合计 | ~1.45 | 实测 1.503 |

### 6.2 逐项贡献

| 改动 | IPC | 说明 |
|---|---:|---|
| 基线 | 0.4725 | 全部取指 bypass |
| 3 级流水 + 直接映射 ICache + 早发 AR + 8 项 BTB | 0.5797 | 取指不再 2 拍/条；taken 分支基本不断流 |
| **行内流式填充** | **0.6653** | 填充与执行重叠，IFU stall 34.7%→12.6% |
| （反例）BTB 4 项 | 0.4713 | 预测数 49.7M→16.9M，重定向 13.6M→33M |
| （反例）允许填充期间命中其它行 | 0.5158 | F 跑超前、取消丢行，miss 19.5M→28.8M |

频率方面，多次综合的 517–545MHz 差异主要来自 yosys/ABC 映射与
高扇出缓冲，最终官方口径为 516.9MHz。**流水线拆分没有带来频率收益**：
基线 1.90ns 的路径中，ICache 读 + 译码 + RF 读并没有成为主导，
去掉它们后 E 段的 "旁路 mux + ALU + 写回 mux + rd_data 高扇出网络"
仍有约 1.93ns。也就是说，这个 PDK/综合流下 ALU+写回本身就接近
1.9ns，三级流水只是把前端移走，没有切开 ALU/写回。

---

## 7. 不足与后续工作

1. **频率是最大短板（517MHz）**。关键路径终点
   `last_result_*:D`/`u_regfile.rf[*]:D`，其中 `rd_data` 高扇出网络
   约 0.38ns。建议：
   - 增加 W 级：把写回 mux 的结果/控制寄存一拍，RF 写在 W；
     旁路从 W 和上一 WB 结果两级选择。需同步把 Difftest 的
     寄存器缓存更新放在 E 段 commit（用 `rd_data` 直接更新），
     避免 DPI 时序错位。
   - 或将 ALU 的移位器/加法器分段（多周期移位），以面积换频率。
   预计可到 ~650-800MHz，但面积会增加 0.3-0.6k，需要进一步压
   ICache/BTB 或接受 25k 上限的取舍。
2. **ICache 只有 64B，miss 率 10.7%**。容量缺失为主（compulsory
   仅 0.46M，replace 19.1M）。128B（8×16B）可显著降 miss，但
   +3.8k 面积，当前预算不够；可考虑 3 线/5 线折中或 victim buffer。
3. **分支重定向仍有 13.6M 次**（主要是循环退出）。可加 2-bit
   方向计数器、RAS、或循环预测器；面积开销很小，预计 IPC +0.02。
4. **load 仍占 2 拍**。可在 D 段算地址并早发 AR，或加 load 缓冲；
   store 可用写缓冲在 W 后退休（load 需检查未完成 store）。
5. **BTB 目标窗口 32KB**：代码超过 32KB 时部分跨窗口预测会失效
   （只影响性能，正确性由 `next_pc_ok` 保证）。生产版本可恢复
   完整目标位宽（+0.5k 面积）。
6. **mcycle 为 32 位**（mcycleh 读 0）。本项目仿真规模不溢出；
   若需要严格 64 位，需恢复 32 个触发器。

---

## 8. 复现

```bash
cd test/zc_eval

# 功能
make smoke-opt        # 自写 RV32E 冒烟测试
make sim-opt          # standalone microbench train -> result/sim-opt.log/.stdout
make sim-base         # 基线 RTL 同一负载

# 面积/频率（与 npc/eval 同口径）
make synth-opt        # -> result/synth-opt/
make synth-base       # -> result/synth-base/
make report           # IPC / 频率 / 面积 / 分数汇总
```

官方口径（会更新 `npc/config/f_cpu`）：

```bash
cd npc/eval && make all
```

依赖：Verilator ≥5、`riscv64-linux-gnu-*`、SDL2、`~/yosys-sta`
（`oss-cad-suite/bin/yosys`、`bin/iEDA`、`scripts/{yosys,sta}.tcl`、
`pdk/icsprout55`）。

---

## 9. 改动文件

- `npc/vsrc/top.v`：3 级流水、流式取指连接、旁路/重定向、DPI/perf。
- `npc/vsrc/IFU.v`：流式 PC/IFID、8 项 BTB（截断标签/目标 + opcode 门控）。
- `npc/vsrc/ICache.v`：4×16B 直接映射、早发 AR、行内流式填充、
  取消/排空、缺失类型计数。
- `npc/vsrc/EXU.v`：紧凑 alu_op、load/store 地址复用、pc_imm（AUIPC/分支共用）。
- `npc/vsrc/WBU.v`：纯 mux 写回（无加法器），pc_plus4 复用。
- `npc/vsrc/CSR.v`：mcycle 32 位。
- `npc/csrc/core/perf.h/.cpp`：新增 BTB/重定向/冲刷事件与 ICache
  缺失类型输出，报告增加分支预测与 miss 类型小节。
- `npc/config/f_cpu`：官方 eval 回写（51，即 510MHz 档）。
- `test/zc_eval/`：独立验证工程（Makefile、synth、smoke、report）。
- 未改动 `abstract-machine/`、`am-kernels/`、`nemu/`、`ysyxSoC/`。

> 注：`test/` 下另有一套由并发进程创建的工程（`test/rtl`、
> `test/npc-opt` 等），与本报告无关，本次工作未修改它。
