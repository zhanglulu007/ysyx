# npc-opt —— 三级顺序流水线 NPC

本目录是 `npc/` 的优化副本，保留原有 AXI4 接口、DPI-C trace/DiffTest/perf
探针和 `ysyx_26020070` SoC 顶层，核心改成 3 级顺序流水线。

## 微架构

```
IF  : PC -> ICache 组合查表 -> IF/ID
ID  : 译码 + RegisterFile 读 + 立即数选择 -> ID/EX
EX  : 共享 adder + ALU 逻辑/移位/比较 + LSU FSM + 写回
```

- 命中时 1 指令/周期；I-Cache 缺失时 4-beat 突发流式填充。
- BTB(8 项) + 2-bit BHT(8 项) 在 IF 预测，EX 验证；误预测清空 2 拍。
- 共享 adder 负责：load/store 地址、JAL/JALR/分支目标、AUIPC、ALU 加减。
- EX->ID 一条前递；load-use 由 load 的结构性停顿覆盖。
- LSU 保持 AXI4 单拍读写；Arbiter 数据侧优先，避免 ICache 填充阻塞 load。

## 关键文件

| 文件 | 说明 |
|---|---|
| `vsrc/top.v` | 流水线、BTB/BHT、共享 adder、DPI/trace/perf、SYNTHESIS 内存模型 |
| `vsrc/ICache.v` | 128B = 8 组 × 16B，组合读、early-restart 流式填充、flush |
| `vsrc/EXU.v` | 紧凑 ALU，分支比较与 slt/sltu 共享 eq/lt/ltu |
| `vsrc/IDU.v` | 指令译码（保留原有 is_* 接口） |
| `vsrc/LSU.v` | AXI4 load/store、size/wstrb/符号扩展 |
| `vsrc/Arbiter.v` | IFU/LSU AR 仲裁（LSU 优先） |
| `vsrc/RegisterFile.v` | 16×32 RV32E 寄存器堆 |
| `vsrc/CSR.v` | mstatus/mtvec/mepc/mcause/mcycle |
| `vsrc/PMEM.v` | standalone DPI 内存模型 |
| `vsrc/ysyx_26020070.v` | SoC 封装 |
| `csrc/core/perf.cpp` | 性能事件汇总（新增 mispredict/squash） |

## 构建/运行

```bash
# standalone（默认）
make PERF=1 F=0 build
./build/obj_dir/Vtop <program.bin> -b

# DiffTest（需要 NEMU .so）
./build/obj_dir/Vtop <program.bin> -b -d \
  $HOME/ysyx-workbench/nemu/build/riscv32-nemu-interpreter-standalone-so

# SoC 模式
make SOC=1 build
./build/obj_dir_soc/VysyxSoCFull <program-ysyxsoc.bin> -b
```

本目录的 `Makefile` 中 `WORKBENCH_ROOT` 默认指向
`/home/zhangshenlu/ysyx-workbench`，也可以通过命令行覆盖：

```bash
make WORKBENCH_ROOT=/path/to/ysyx-workbench build
```

## 验证脚本

```bash
./run_verify.sh          # 构建 + 33 cpu-tests + fence.i + microbench train
./run_verify.sh --diff   # 额外跑 microbench test 的 DiffTest
./run_synth.sh           # 调用 test/eval-opt 做综合 + STA
```

日志在 `build/verify/`，综合结果在 `../eval-opt/result/`。

## 最终结果

| 指标 | 数值 |
|---|---|
| IPC（microbench train） | **0.7114** |
| 最高频率（icsprout55） | **790.143 MHz** |
| 面积 | **23,012.08**（< 25k） |
| 关键路径 | `idex_alu_b` 1.2656 ns |

更完整的分析见 `../report/npc-opt-report.md`。
