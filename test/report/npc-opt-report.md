# NPC 流水线优化报告（test/npc-opt）

> 目标：在不修改 `npc/`、`am-kernels/`、`nemu/`、`abstract-machine/` 等目录的前提下，
> 对当前 NPC RTL 做面积、频率、IPC 的综合优化；以 **standalone 运行 microbench train**
> 的 IPC × 综合最高频率作为主评价指标，面积约束 < 25k。
>
> 结论：最终实现面积 **23,012.08**、最高频率 **790.143 MHz**、IPC **0.7114**，
> 综合得分 **562.1**；基线为面积 19,341.56、524.432 MHz、IPC 0.4725、得分 247.8。
> **得分提升 2.27×，IPC 提升 50.6%，频率提升 50.7%，面积仍低于 25k。**

---

## 1. 项目全景与调用链

### 1.1 工作台子项目

| 子项目 | 作用 | 与 NPC 的关系 |
|---|---|---|
| `npc/` | 当前 RTL、Verilator 仿真环境、SDB、trace、perf、eval | 被优化的对象 |
| `nemu/` | NEMU 参考模型 | 通过 `riscv32-nemu-interpreter-standalone-so` 做 DiffTest |
| `abstract-machine/` | AM 运行时与平台适配 | 生成 `riscv32e-npc` / `riscv32e-ysyxsoc` 程序镜像 |
| `am-kernels/` | cpu-tests、microbench、am-tests | CPU 正确性与性能负载 |
| `ysyxSoC/` | SoC 集成（`ysyxSoCFull`） | NPC 以 `ysyx_26020070` 接入 SoC |
| `nvboard/` | 虚拟开发板 | 可选外设仿真 |
| `test/` | 本次新建的优化与验证项目 | 只修改这里 |

### 1.2 NPC 的构建与运行链

```
AM 程序源码
  └─ make ARCH=riscv32e-npc
       ├─ riscv64-linux-gnu-gcc -march=rv32e_zicsr_zifencei -mabi=ilp32e
       ├─ link.ld: _pmem_start = 0x80000000
       └─ insert-arg.py: 把 mainargs(test/train/ref/huge) 写入镜像
            │
            ▼
npc/Makefile
  ├─ Verilator: vsrc/*.v + csrc/*.cpp -> build/obj_dir/Vtop
  ├─ DIFFTEST=1: 链接 NEMU .so，commit 时逐指令对比
  ├─ PERF=1: RTL 通过 DPI-C 上报事件，csrc/core/perf.cpp 汇总
  └─ SOC=1: 顶层换成 ysyxSoCFull，程序先装载到 flash
            │
            ▼
PMEM/Flash/SoC 总线 <-> NPC 核 <-> AXI4
```

- **commit 路径**：RTL 在每条指令退休时调用 `commit_instruction(pc, inst, next_pc)`，
  C++ 侧更新 `pc_cache/inst_cache/commit_count`，SDB 主循环据此推进。
- **DiffTest 路径**：`difftest_step()` 在每条指令后比较 GPR、PC、CSR；
  外设访问通过 `difftest_skip_ref()` 跳过。
- **性能路径**：`perf_event(id)` 在 RTL 内按事件脉冲上报，`perf_report()` 输出
  cycles/inst/IPC、指令混合、IFU/ICache/LSU/总线行为。
- **综合评估**：`npc/eval`（本次复制为 `test/eval-opt`）用 yosys + iEDA 在
  `icsprout55` 上做综合与 STA，输出面积/最高频率/关键路径。

---

## 2. 基线 RTL 深度分析

### 2.1 微架构

基线是一个**单发射、多周期、串行取指**的核：

```
IFU(IDLE) --AR--> IFU(WAIT) --R--> 指令有效 --> IDU/EXU/LSU/WBU 组合执行 --> commit
     ^                                                                        |
     └---------------------------- pc_next <---------------------------------┘
```

- `IFU` 状态机只有 `IDLE/WAIT` 两态。
- 每条指令至少需要一次 AR 和一次 R 握手；在 standalone 下，PMEM 的
  `arready` 在 AR 当拍有效、R 在下一拍返回，因此**每条指令至少 2 周期**。
- 只有 `commit` 后 IFU 才会把 `pc` 更新为 `pc_next`，取指与执行完全串行。
- `commit = ifu_valid && (!mem_valid || lsu_done)`：load/store 在 LSU 完成前
  一直占用 EX，因此额外多 1 周期。

### 2.2 实测基线

`microbench train`（standalone，195.14M 指令）：

| 指标 | 数值 |
|---|---|
| Cycles | 413,015,094 |
| Instructions | 195,139,928 |
| IPC | **0.4725** |
| CPI | 2.1165 |
| 条件分支 | 52.59M（26.95%），taken 73.56% |
| Load / Store | 15.59M / 7.15M（11.65%） |

CPI 可以精确分解为：

```
CPI = 2.0000（每条指令 AR + R）
    + 0.1165（load/store 各多 1 周期，11.65%）
    = 2.1165
```

也就是说，**基线 IPC 的上限就是 0.5**；实测 0.4725 已经接近这个上限，
说明瓶颈不在分支/缓存，而在“取指与执行不重叠”这一结构本身。

### 2.3 I-Cache 的关键问题

基线 `top.v` 中：

```verilog
assign ifu_cacheable = ((ifu_araddr >= 32'h3000_0000) &&
                        (ifu_araddr <  32'h3100_0000)) ||
                       ((ifu_araddr >= 32'ha000_0000) &&
                        (ifu_araddr <  32'ha200_0000));
```

- standalone 程序链接在 **0x8000_0000**，不在上述范围内，
  所以 **standalone 下所有取指都 bypass ICache**，ICache 完全不参与性能。
- 即使地址可缓存，基线 ICache 的命中路径也是 `IDLE -> RETURN` 两拍，
  **命中并不会提升吞吐**，只是把“等 PMEM”换成“等 ICache 状态机”。
- 基线 ICache 为 4 块 × 16B 直接映射；在 SoC 模式下命中率约 90.5%
  （用仓库已有 195M PC trace 回放），但受两拍状态机限制，收益有限。

### 2.4 关键路径与面积

基线 `test/eval-baseline`（同 PDK、同约束）结果：

| 指标 | 数值 |
|---|---|
| 芯片面积 | **19,341.56** |
| 顺序单元面积 | 9,055.20（46.82%） |
| 最高频率 | **524.432 MHz** |
| WNS | −1.074 ns（约束 0.833 ns） |
| 关键路径 | `u_top.u_regfile.rf[9]_14__reg_p:D` |
| 等效周期 | 1.9068 ns |

关键路径的实质是**一拍内完成**：

```
ICache data mux -> IDU 译码 -> RegisterFile 读 mux
                -> EXU ALU -> WBU 写回 mux -> RegisterFile D
```

这也是为什么基线即使面积不大，频率也只有约 524 MHz：
多周期设计把“取指返回”和“整条指令执行”压在了同一个时钟周期里。

### 2.5 代码级问题清单

1. **串行取指**：`IFU` 两态状态机，无 fetch queue、无预取、无取指/执行重叠。
2. **standalone 绕过 ICache**：`ifu_cacheable` 范围不包含 0x8000_0000。
3. **ICache 命中也是两拍**：`IDLE -> RETURN`，没有流式取指。
4. **无分支预测**：73.56% 的条件分支 taken，每次 taken 都要等下一次串行取指；
   在基线里这被“2 周期/指令”掩盖了，但一旦做流水线就会暴露。
5. **重复加法器**：
   - `top.v` 的 `addr = rs1 + imm_s/imm_i`（LSU 地址）；
   - `EXU.v` 的 `alu_result = rs1 + alu_src2`（ALU 加减）；
   - `EXU.v` 的 `branch_target = pc + imm`；
   - `WBU.v` 的 `pc_next` 又做多路选择。
6. **一位热码 + 优先级 case**：IDU 产生约 40 个 `is_*`，EXU/WBU/LSU 再用
   `case (1'b1)` 做优先级选择，面积和组合延迟都不理想。
7. **总线不区分优先级**：IFU 和 LSU 共享 AR 通道，基线每条指令一次 AR，
   数据侧没有优先权；在流水线化后这会放大 load 等待。
8. **面积结构**：寄存器堆 6.59k（34.1%）、ICache 5.59k（28.9%）、
   其它逻辑 5.95k（30.8%）、IFU 1.13k（5.8%）。

---

## 3. 优化设计

### 3.1 总体结构：三级顺序流水线

最终 RTL（`test/npc-opt/vsrc/top.v`）采用：

```
IF  : PC -> ICache 组合查表 -> IF/ID
ID  : 译码 + RegisterFile 读 + 立即数选择 -> ID/EX
EX  : 共享 adder + ALU 逻辑/移位/比较 + LSU FSM + 写回
```

- 命中时 **1 指令/周期**；I-Cache 缺失时流式填充。
- 顺序发射、顺序退休；只有一条 EX 通路，load/store 占用 EX 多拍。
- 分支/JAL/JALR 在 EX 解析；BTB 在 IF 预测，预测正确时无气泡。
- EX->ID 前递一条通路；load-use 由 load 的结构性停顿自然覆盖。

为什么是三级而不是两级：

- 两级（IF | EX）需要把 RF 读、ALU、写回放在同一拍，等价于基线的关键路径，
  频率仍然约 524 MHz，IPC 提升有限。
- 三级把 RF 读（ID）和 ALU/写回（EX）分开，才能把 1.9 ns 的关键路径拆短。
- 四级（IF | ID | EX | WB）理论上频率更高，但分支惩罚从 2 拍变成 3 拍，
  在 27% 分支、73.6% taken 的负载上 IPC 损失明显；本次未采用。

### 3.2 IF 级与新版 ICache

文件：`test/npc-opt/vsrc/ICache.v`

- **容量**：128B = **8 组 × 16B** 直接映射（可参数化 `SETS/WORDS`）。
- **组合读**：`if_pc -> tag compare -> data mux`，命中当拍即可送出指令，
  不再有 `IDLE -> RETURN` 的两拍状态机。
- **突发填充**：一次 AXI AR（`arlen=3`）读入 16B（4 个 32-bit beat）。
- **Early restart / 流式填充**：
  - 请求字已经写入或正在当前 beat 上返回时，`if_valid=1`；
  - 顺序取指可以“边填边取”，缺失代价从“整行填完”降到约 1–2 拍 + 行边界；
  - 填充期间若跳到别的行，会等当前 4-beat 突发收完，再处理新行。
- **失效策略**：AR 握手时先失效被替换的旧行，避免填充期间旧数据被误命中。
- **flush**：`fence.i` 时清空 valid；若正在填充则置 `discard`，收完突发但不置 valid。
- **地址范围**：不再做 `ifu_cacheable` 旁路，standalone 的 0x8000_0000 与
  SoC 的 flash/SDRAM 都走 ICache；这对 standalone 性能是决定性改动。

容量选择依据（用仓库已有 195M PC trace 回放的缺失率）：

| 配置 | 容量 | 行大小 | 缺失率 |
|---|---|---|---|
| 4 组 × 16B | 64B | 16B | 9.50% |
| 8 组 × 16B | **128B** | **16B** | **4.49%** |
| 4 组 × 32B | 128B | 32B | 3.48% |
| 8 组 × 32B | 256B | 32B | 1.71% |

虽然 4×32B 的缺失率略低，但 8-beat 填充会长时间占用读通道，实测
load 平均延迟从 1.65 升到 1.95+，IPC 反而从 0.699 降到 0.653。
最终选择 **8×16B**：缺失率与总线阻塞的折中最好，且面积比 4×32B 更低。

### 3.3 分支预测：BTB8 + BHT8

文件：`top.v` 中的 `btb_*` / `bht` 逻辑。

- **BTB**：8 项直接映射，`index = pc[4:2]`，`tag = pc[8:5]`，
  每项 `{valid, tag[3:0], target[31:0]}`，共 296 个触发器。
- **BHT**：8 项 × 2-bit 饱和计数器，`index = pc[4:2]`。
- **预测**：
  - 条件分支：BTB 命中且 BHT ≥ 2 时预测 taken；
  - JAL/JALR：BTB 命中即预测 taken；
  - 预测目标来自 BTB，下一拍从目标取指。
- **验证/更新**：EX 级比较实际 `taken/target`；不一致则清空 IF/ID、ID/EX，
  PC 跳到正确目标（2 拍惩罚）。taken 时写 BTB；分支按实际方向更新 BHT。
- **为什么不做 RAS**：trace 回放显示 RAS 只能再减少约 0.4M 次误预测
  （约 0.2% 周期），但需要 8×32-bit 的返回地址栈，面积收益比不高。
- **为什么不做 BTB16**：BTB16 可再减少约 1.5M 次误预测，
  但面积约 +1.5k，会逼近/超过 25k 上限；BTB8 的性价比更高。
- **哈希索引实验**：`pc[4:2] ^ pc[10:8]` 在 trace 模型上更好，
  但在 standalone 镜像上实测误预测从 13.28M 升到 13.53M，
  因此保留最简单的 `pc[4:2]`。

实测 BTB/BHT 效果：

| 指标 | 数值 |
|---|---|
| 分支 + 跳转 | 56.55M |
| BTB 误预测 | **13.28M**（23.47% 的分支/跳转，6.80% 的提交） |
| 前端清空 | 13.28M 条 |
| 取指/提交差 | 12.63M 条（含清空/重取） |

没有预测时每次 taken 都要 2 拍清空；BTB 把大部分循环分支的目标提前取回，
是 IPC 从“理论 0.5”走向 0.7+ 的关键。

### 3.4 ID 级：RF 读 + 立即数选择

- `RegisterFile` 仍为 16×32（RV32E），异步双读、同步写。
- ID 级只做：
  - RF 读；
  - EX->ID 前递（仅一条 2:1 旁路）；
  - 立即数选择 `imm_i/imm_s/imm_b/imm_j/imm_u`，以及 R 型的 `rs2`；
  - 生成紧凑控制（`alu_op/wb_sel/branch_op/use_pc/sub/...`）。
- **地址/分支目标/ALU 加减的共享 adder 放到 EX 级**，ID 级不再放 32-bit 加法器。
  这是从 722 MHz 提升到 790 MHz 的关键：
  - 基线/早期版本的关键路径是 `idex_add_result`（ID 级 RF 读 + adder + mux）；
  - 把 adder 移到 EX 后，ID 级只剩 RF 读 + 立即数 mux，关键路径缩短到 1.2656 ns。
- 立即数选择对 store 使用 `imm_s`，对 load/I 型使用 `imm_i`；
  这是实现过程中发现并修复的一个功能性 bug（见 §5.2）。

### 3.5 EX 级：紧凑 ALU + 共享 adder

文件：`test/npc-opt/vsrc/EXU.v`

- **共享 adder**（在 top 内实现）：
  - `add_a = use_pc ? pc : rs1`
  - `add_b = op_r_type ? rs2 : imm_sel`
  - `sub` 控制加减
  - 结果同时用于：load/store 地址、JAL/JALR/分支目标、AUIPC、ALU 加减。
- **ALU**：
  - ADD/SUB 直接用 adder 结果；
  - AND/OR/XOR、SLL/SRL/SRA、SLT/SLTU；
  - 分支比较与 SLT/SLTU 共享 `eq/lt/ltu`；
  - 分支比较使用真实 `rs2`，ALU 比较使用 `alu_b`（立即数或 rs2），
    避免 I 型指令误用寄存器值。
- **写回选择**：`WB_ALU / WB_LOAD / WB_LINK / WB_IMMU / WB_CSR`。
- **前递**：EX 结果 -> ID 操作数，用于相邻指令 RAW；
  没有 WB 级寄存器版本（实测该版本频率降到 655 MHz，见 §4.2）。

### 3.6 LSU 与 AXI 仲裁

- LSU 保持原 AXI4 单拍读写语义：
  - load：AR -> R，EX 多 1 拍；
  - store：AW/W 同拍 -> B，EX 多 1 拍；
  - 支持 LB/LH/LW/LBU/LHU、SB/SH/SW 的 size/wstrb/符号扩展。
- **Arbiter 改为数据侧优先**：
  - 原来 IFU 总是优先，ICache 填充会阻塞 load；
  - 现在 `lsu_arvalid` 优先，ICache 填充让路；
  - load 平均延迟从 2.22 降到 1.65 拍，IPC 从 0.6986 升到 0.7114。
- 16B 行（4-beat）而不是 32B 行（8-beat），缩短单次填充对读通道的占用。

### 3.7 性能计数器

在 `csrc/core/perf.h` / `perf.cpp` 中新增：

- `PERF_BRANCH_MISPREDICT`：BTB 误预测次数；
- `PERF_IF_SQUASH`：前端清空次数；
- 报告增加 BTB 误预测率、refill/1k inst、fetch/commit 差值；
- 保留原有指令混合、ICache、LSU、总线一致性检查。

这些计数器是本次迭代的主要依据：例如“load 平均延迟 2.22”直接指向
Arbiter 优先级问题；“BTB 误预测 13.28M”量化了分支预测的剩余空间。

---

## 4. 设计空间探索与取舍

### 4.1 ICache 配置（实测 IPC，standalone train）

| 配置 | 容量 | 行 | IPC | 说明 |
|---|---|---|---|---|
| 4×32B | 128B | 32B | 0.653 | 8-beat 填充，load 被阻塞严重 |
| 8×16B | 128B | 16B | 0.6986 | 缺失率略高但填充短 |
| 8×16B + LSU 优先 | 128B | 16B | **0.7114** | 最终选择 |
| 8×32B | 256B | 32B | 0.7187 | IPC 更高，但面积约 +9k，超预算 |
| 4×16B | 64B | 16B | 未采用 | 缺失率 9.5%，预计 IPC 明显下降 |

### 4.2 关键路径方案对比

| 方案 | 关键路径 | fmax | IPC | 结论 |
|---|---|---|---|---|
| ID 级放 adder（早期） | `idex_add_result` | 722.0 MHz | 0.7114 | 频率偏低 |
| **EX 级放 adder（最终）** | `idex_alu_b` | **790.1 MHz** | 0.7114 | 采用 |
| WB 级前递（把 bypass 移到 EX） | `wb_data` | 655.0 MHz | 0.7114 | 频率更差，放弃 |
| 去掉 rs2 立即数 mux、EX 选择 rs2 | `idex_rs2` | 660.8 MHz | 0.7114 | 频率更差，放弃 |

结论：在当前 PDK 和 3 级结构下，**ID 级保留 bypass、EX 级放共享 adder**
是频率/面积/IPC 最平衡的组合。继续追求频率需要四级流水线或更激进的
retiming，但会牺牲分支惩罚和 IPC。

### 4.3 BTB 方案对比（trace 模型，195M PC）

| 方案 | 误预测 | 相对 BTB8 |
|---|---|---|
| 无预测 | 42.68M | — |
| BTB8 + BHT8 | 13.86M | 基线 |
| BTB8 + BHT8 + hash8 | 13.50M | −2.6% |
| BTB8 + BHT8 + RAS | 13.21M | −4.7% |
| BTB16 + BHT32 | 11.88M | −14.3% |

实际 standalone 镜像上 hash 反而略差，RAS/BTB16 的面积收益比也不高，
最终保留 **BTB8 + BHT8**。

---

## 5. 验证

### 5.1 验证环境

- `test/npc-baseline`：原始 `npc/` 的冻结副本，用于 A/B 对比；
- `test/npc-opt`：优化后的 RTL + csrc + Makefile；
- `test/eval-opt` / `test/eval-baseline`：yosys-sta 综合评估；
- `test/prog`：microbench test/ref/huge 镜像（通过 patch mainargs 生成）
  与 `fence.i` 自修改代码测试；
- `test/tools`：PC trace 分析、反汇编分类、面积分解脚本。

### 5.2 正确性结果

| 测试 | 结果 |
|---|---|
| cpu-tests 33 个（add/bit/div/.../wanshu） | **33/33 PASS**（HIT GOOD TRAP） |
| microbench `test` + NEMU DiffTest | **PASS**（约 52.2 万条指令逐条对比） |
| microbench `train` standalone | **PASS**（10 个 benchmark 全部 Passed） |
| `fence.i` 自修改代码测试 | **PASS**（a0=0，HIT GOOD TRAP） |
| SoC 模式 `add`（VysyxSoCFull） | **PASS**（HIT GOOD TRAP，5,778 条指令） |
| am-tests `Hello, AM World` + yield | 正常输出，ecall/mret 路径工作 |
| SoC 模式编译 | **成功**（VysyxSoCFull + 外设） |

实现过程中修复的关键功能 bug：

1. **store 地址用了 `imm_i` 而不是 `imm_s`**：
   `sw a5,4(sp)` 被算成 `sp+15`，导致后续 load 读到 0；
   用 DiffTest 在 `add` 测试的 0x80000054 定位。
2. **分支比较误用 ALU B 操作数**：
   `bgeu` 等分支比较用了立即数/ALU B，而不是真实 `rs2`；
   导致 `leap-year` 等测试在 `__udivsi3` 中走错分支。
3. **I 型逻辑/比较误用 `rs2` 寄存器值**：
   `andi/ori/xori/slti/sltiu` 应该用 `imm_i`，不是 `rs2` 字段。
4. **Load 地址在第二拍使用了过期的前递值**：
   load 第一拍 AR 用前递后的 rs1，第二拍 R 返回时如果 WB 前递被清掉，
   byte/half 选择会用到旧地址；修复为“访存停顿期间保持 WB 前递数据”。

这些 bug 也说明：**DiffTest + 定向 cpu-tests + 逐拍性能计数器** 的组合
对流水线改造是必要的，单靠 microbench 通过不足以发现所有数据通路问题。

### 5.3 性能与面积结果

| 指标 | 基线 | 优化后 | 变化 |
|---|---|---|---|
| Cycles | 413,015,094 | **274,288,613** | **−33.6%** |
| Instructions | 195,139,928 | 195,138,537 | ≈0 |
| IPC | 0.4725 | **0.7114** | **+50.6%** |
| CPI | 2.1165 | **1.4056** | −33.6% |
| 芯片面积 | 19,341.56 | **23,012.08** | +19.0% |
| 顺序单元面积 | 9,055.20（46.8%） | 12,061.28（52.4%） | +33.2% |
| 最高频率 | 524.432 MHz | **790.143 MHz** | **+50.7%** |
| 关键路径 | regfile D（1.9068 ns） | `idex_alu_b`（1.2656 ns） | −33.6% |
| WNS @1200MHz | −1.074 ns | −0.433 ns | 改善 |
| **IPC × fmax** | **247.8** | **562.1** | **+126.8%（2.27×）** |
| 面积约束 | — | < 25k | **满足，余量 1,988（7.9%）** |

面积分解（近似，按 netlist 实例名前缀统计）：

| 部分 | 基线 | 优化后 |
|---|---|---|
| RegisterFile | 6,593.72 | 5,199.08 |
| ICache | 5,587.12 | 4,525.62 |
| IFU | 1,127.00 | —（并入 top/other） |
| top/other（含流水线寄存器、BTB/BHT、译码、ALU、CSR） | 5,951.96 | 13,236.67 |
| Arbiter/LSU | 81.76 | 89.42 |
| **合计** | **19,341.56** | **23,012.08** |

> 说明：优化后 `top/other` 变大主要来自 3 级流水线寄存器（IF/ID、ID/EX）、
> BTB/BHT（约 2.4k）以及 CSR/控制逻辑；ICache 从 64B 扩大到 128B，
> 但由于去掉了两拍状态机和冗余 mux，面积反而略降。

### 5.4 周期分解（优化后）

| 来源 | 周期数 | 占比 |
|---|---|---|
| 基础（1 指令/周期） | 195.14M | 71.1% |
| Load 额外等待 | 25.71M | 9.4% |
| Store 额外等待 | 7.15M | 2.6% |
| BTB 误预测（2 拍/次） | 26.55M | 9.7% |
| ICache AR 等待 | 15.43M | 5.6% |
| ICache R 等待 | 9.04M | 3.3% |
| 其它/重叠 | — | — |

（各项存在重叠，不能严格相加；上表用于定位主要瓶颈。）

---

## 6. 剩余瓶颈与下一步

### 6.1 分支误预测（约 26.6M 周期，9.7%）

- 13.28M 次误预测，主要是：
  - 循环退出时 BHT 仍预测 taken（每次循环一次）；
  - BTB 冲突/容量缺失；
  - JALR 返回地址变化（BTB 目标不稳定）。
- 可尝试：
  - BTB16 / 2-way BTB（面积 +1.5–2.5k，预计 IPC +1–2%）；
  - RAS（4–8 项，面积 +0.5–1k，预计 IPC +0.3%）；
  - tournament/loop predictor（面积/复杂度更高）。

### 6.2 Load 延迟（25.7M 周期，9.4%）

- 平均 load 延迟 1.65 拍；其中约 1 拍是 AXI AR->R 的固有延迟，
  0.65 拍是总线竞争/Arbiter 等待。
- **ID 级预发射 load** 可以把 AR 提前一拍，理论再省约 15M 周期（IPC +5%），
  但需要在 ID 级重新引入地址加法器/前递，可能把频率拉回 700 MHz 左右；
  需要做频率-IPC 联合评估。
- 数据 cache / store buffer 在当前 25k 面积约束下不划算。

### 6.3 ICache 等待（24.5M 周期，8.9%）

- AR 等待 15.4M，主要是 load 优先后 ICache 让路；
- R 等待 9.0M，主要是行边界/分支目标缺失。
- 可尝试：
  - next-line prefetch（在当前行命中时预取下一行）；
  - 2-line fetch buffer；
  - 更大的 ICache（8×32B，IPC +1%，面积 +9k，超预算）。

### 6.4 频率（790 MHz）

- 关键路径 `idex_alu_b` 1.2656 ns，仍在 ID 级（RF 读 + 前递 + 立即数 mux）。
- 进一步拆分需要四级流水线（IF | ID | EX | WB）或把 RF 读做成
  寄存器输出；前者会增加分支惩罚，后者会增加 1 拍取指延迟。
- 在 25k 面积和当前分支密度下，790 MHz + IPC 0.711 是较好的平衡点。

### 6.5 SoC 模式

- SoC 模式已编译并通过 `add` 测试；但 SoC 的真实存储延迟远高于
  standalone PMEM（实测 `add` IPC 0.0208），因此：
  - ICache 命中率、预取、load 预发射在 SoC 上收益会更大；
  - 建议后续在 SoC 模式用 `microbench train` 做一轮性能评估，
    再决定是否加 next-line prefetch / 数据 cache。

---

## 7. 复现命令

```bash
# 1) 正确性 + 性能（standalone）
cd /home/zhangshenlu/ysyx-workbench/test/npc-opt
./run_verify.sh --diff

# 2) 综合 + STA（面积/频率）
cd /home/zhangshenlu/ysyx-workbench/test/eval-opt
make sta
make report

# 3) 单独跑 microbench train
./build/obj_dir/Vtop \
  /home/zhangshenlu/ysyx-workbench/am-kernels/benchmarks/microbench/build/microbench-riscv32e-npc.bin \
  -b

# 4) SoC 模式编译/运行
make SOC=1 PERF=0 F=0 build
./build/obj_dir_soc/VysyxSoCFull \
  /home/zhangshenlu/ysyx-workbench/am-kernels/tests/cpu-tests/build/add-riscv32e-ysyxsoc.bin -b
```

---

## 8. 文件清单

```
test/
├── npc-opt/                 # 优化后的 NPC 项目（最终交付）
│   ├── vsrc/
│   │   ├── top.v            # 3 级流水线、BTB/BHT、共享 adder、DPI
│   │   ├── ICache.v         # 128B 8×16B、组合读、流式填充
│   │   ├── EXU.v            # 紧凑 ALU/分支比较
│   │   ├── IDU.v            # 译码（保留原有接口）
│   │   ├── LSU.v            # AXI4 load/store
│   │   ├── Arbiter.v        # 数据侧优先仲裁
│   │   ├── RegisterFile.v   # 16×32 RV32E 寄存器堆
│   │   ├── CSR.v            # mstatus/mtvec/mepc/mcause/mcycle
│   │   ├── PMEM.v           # standalone DPI 内存模型
│   │   └── ysyx_26020070.v  # SoC 顶层
│   ├── csrc/                # Verilator 仿真、SDB、trace、perf、DiffTest
│   ├── config/f_cpu         # STA 更新为 79（790MHz）
│   ├── run_verify.sh        # 一键正确性/性能验证
│   └── run_synth.sh         # 一键综合/STA
├── npc-baseline/            # 原始 npc 的冻结副本（A/B 基线）
├── eval-opt/                # 优化版综合评估
├── eval-baseline/           # 基线综合评估
├── prog/                    # microbench test/ref/huge + fence.i 测试
├── tools/                   # trace 分析、反汇编分类、面积分解
└── report/npc-opt-report.md # 本报告
```

> 除 `test/` 外，工作台其它目录均未修改；所有构建产物、日志、结果都落在
> `test/` 下。

---

## 9. 结论

- 基线 NPC 的核心问题是**串行取指**：每条指令 2 个 AXI 周期，IPC 上限 0.5；
  同时 standalone 下 ICache 被范围判断完全旁路。
- 通过 **3 级流水线 + 组合读/流式填充 ICache + BTB/BHT + 共享 adder/紧凑 ALU
  + 数据侧优先仲裁**，在面积仅 +19% 的前提下：
  - IPC 从 **0.4725 → 0.7114（+50.6%）**；
  - 最高频率从 **524.4 → 790.1 MHz（+50.7%）**；
  - IPC × fmax 从 **247.8 → 562.1（2.27×）**；
  - 面积 **23,012.08 < 25,000**，满足约束。
- 33 个 cpu-tests、microbench test（DiffTest）、microbench train、`fence.i`
  自修改代码测试、SoC `add` 测试全部通过。
- 剩余主要优化空间在分支误预测、load 预发射、ICache 预取；这些方向
  在 SoC 高延迟环境下可能比 standalone 更有价值。
