# NPC C++ 源码结构说明

## 目录结构

```
csrc/
├── main_new.cpp          # 主程序入口（新版本）
├── main.cpp              # 主程序入口（旧版本，保留备份）
├── core/                 # 核心模块
│   ├── npc.cpp/h         # NPC状态管理
│   ├── cpu.cpp/h         # CPU执行控制
│   ├── memory.cpp/h      # 存储器管理
│   ├── device.cpp/h      # 设备管理（串口、RTC）
│   ├── reg.cpp/h         # 寄存器访问接口
│   ├── ebreak.cpp/h      # EBREAK指令处理
│   └── ftrace_dpi.cpp/h  # FTRACE的DPI-C接口
├── sdb/                  # 简易调试器
│   ├── sdb.cpp/h         # 调试器主循环和命令
│   ├── expr.cpp          # 表达式求值
│   └── watchpoint.cpp    # 监视点管理
├── utils/                # 工具模块
│   ├── log.cpp/h         # 日志系统
│   └── difftest.cpp/h    # 差分测试
└── trace/                # 追踪模块
    ├── itrace.cpp/h      # 指令追踪
    ├── mtrace.cpp/h      # 内存追踪
    └── ftrace.cpp/h      # 函数追踪
```

## 模块说明

### 1. core/ - 核心模块

#### npc.cpp/h - NPC状态管理
- 管理NPC的运行状态（RUNNING/STOP/END/ABORT/QUIT）
- 维护周期计数器
- 缓存寄存器和PC值
- 提供DPI-C接口供Verilog更新状态

#### cpu.cpp/h - CPU执行控制
- 初始化和管理Verilator仿真环境
- 实现单步执行（exec_once）
- 实现批量执行（cpu_exec）
- 协调trace系统的输出

#### memory.cpp/h - 存储器管理
- 管理128MB物理内存
- 实现DPI-C接口（pmem_read/pmem_write）
- 处理内存访问和地址转换
- 程序加载功能

#### device.cpp/h - 设备管理
- 串口设备（SERIAL_PORT）
- RTC时钟设备（RTC_ADDR_LO/HI）
- 设备地址检测和读写

#### reg.cpp/h - 寄存器访问接口
- 寄存器名称到值的转换
- 寄存器显示功能
- 支持多种寄存器命名（x0-x31, $0, ra, sp等）

#### ebreak.cpp/h - EBREAK指令处理
- 处理EBREAK指令
- 区分GOOD TRAP和BAD TRAP
- 设置退出状态

#### ftrace_dpi.cpp/h - FTRACE的DPI-C接口
- 提供ftrace_call_handler
- 提供ftrace_ret_handler
- 连接Verilog和ftrace模块

### 2. sdb/ - 简易调试器

#### sdb.cpp/h - 调试器主循环
- 命令行界面
- 支持的命令：c, q, si, info, x, p, w, d
- 批处理模式支持

#### expr.cpp - 表达式求值
- 支持算术表达式
- 支持寄存器引用（$pc, $ra等）
- 支持内存解引用（*addr）

#### watchpoint.cpp - 监视点管理
- 创建和删除监视点
- 监视点触发检测
- 监视点列表显示

### 3. utils/ - 工具模块

#### log.cpp/h - 日志系统
- 文件日志输出
- 日志缓冲区（用于长时间运行）
- 彩色输出支持
- 断言和panic宏

#### difftest.cpp/h - 差分测试
- 与NEMU进行差分测试
- 寄存器状态对比
- 错误检测和报告

### 4. trace/ - 追踪模块

#### itrace.cpp/h - 指令追踪
- 使用Capstone进行反汇编
- 指令环形缓冲区（用于错误分析）
- 支持控制台和文件输出

#### mtrace.cpp/h - 内存追踪
- 记录内存读写操作
- 延迟输出（避免输出交错）
- 去重机制（同一周期同一地址）

#### ftrace.cpp/h - 函数追踪
- 解析ELF符号表
- 跟踪函数调用和返回
- 显示调用深度
- 延迟输出

## 编译说明

使用新的目录结构编译：

```bash
make build    # 只编译
make run PROG=test/mem.bin    # 编译并运行
```

Makefile已更新为使用 `main_new.cpp` 和新的目录结构。

## 迁移说明

从旧版本（main.cpp）迁移到新版本：

1. 旧的 `main.cpp` 已保留作为备份
2. 新的 `main_new.cpp` 是重构后的主程序
3. trace文件已从 `utils/` 移动到 `trace/`
4. 核心功能已拆分到 `core/` 目录

## 设计原则

1. **模块化**：每个模块职责单一，接口清晰
2. **分层**：core提供底层功能，sdb/trace/utils提供高层功能
3. **可维护性**：代码结构清晰，易于理解和修改
4. **可扩展性**：新功能可以方便地添加到相应模块
