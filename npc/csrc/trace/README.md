# NPC Trace Support

## 概述

为NPC实现了trace支持，包括：
- **itrace**：指令追踪（Instruction Trace）
- **mtrace**：内存追踪（Memory Trace）

## 文件结构

```
csrc/trace/
├── trace.h       - trace头文件
├── itrace.cpp    - 指令追踪实现
├── mtrace.cpp    - 内存追踪实现
├── disasm.cpp    - 反汇编器（使用capstone）
└── README.md     - 本文件
```

## itrace - 指令追踪

### 功能
- 记录最近执行的16条指令（环形缓冲区）
- 使用capstone库进行反汇编
- 在程序出错时自动显示最近执行的指令

### 实现方式
1. 在top.v中通过DPI-C调用`trace_inst(pc, inst)`
2. C++侧将指令写入环形缓冲区
3. 使用capstone库反汇编指令
4. 在ebreak或错误时显示iringbuf

### 输出格式
```
Recent executed instructions (iringbuf):
    0x80000000: 97 02 00 00   auiw    t0, 0
    0x80000004: 93 82 82 00   addi    t0, t0, 8
--> 0x80000008: 73 90 52 30   csrw    mtvec, t0
```

最后一条指令（标记为`-->`）是当前执行的指令。

## mtrace - 内存追踪

### 功能
- 记录所有内存读写操作
- 显示地址、长度、数据和PC

### 实现方式
1. 在`pmem_read()`和`pmem_write()`中调用mtrace函数
2. 打印内存访问信息

### 输出格式
```
[MTRACE] READ  at 0x80000000 len=4 data=0x00000297 pc=0x80000000
[MTRACE] WRITE at 0x80001000 len=4 data=0x12345678 pc=0x80000010
```

## 反汇编器

### 依赖
- capstone库（libcapstone-dev）

### 安装
```bash
# Ubuntu/Debian
sudo apt-get install libcapstone-dev

# macOS
brew install capstone
```

### 特性
- 支持RISC-V 32位指令集
- 支持压缩指令（RVC）
- 动态加载capstone库
- 如果库不可用，显示原始字节

## 配置选项

在Makefile中通过编译选项控制：

```makefile
-DCONFIG_ITRACE    # 启用指令追踪
-DCONFIG_MTRACE    # 启用内存追踪
```

可以注释掉相应的宏定义来禁用trace功能。

## 性能影响

### itrace
- 每条指令执行时调用一次DPI-C函数
- 需要反汇编（如果capstone可用）
- 性能影响：中等

### mtrace
- 每次内存访问时打印一行
- 输出量大，影响性能
- 性能影响：较大

建议：
- 调试时启用trace
- 性能测试时禁用trace

## 使用示例

### 查看最近执行的指令

程序出错时会自动显示：
```
*** HIT BAD TRAP (code=1) ***

Recent executed instructions (iringbuf):
    0x80000000: 97 02 00 00   auiw    t0, 0
    0x80000004: 93 82 82 00   addi    t0, t0, 8
--> 0x80000008: 73 90 52 30   csrw    mtvec, t0
```

### 查看内存访问

运行程序时会实时打印：
```
[MTRACE] READ  at 0x80000000 len=4 data=0x00000297 pc=0x80000000
[MTRACE] READ  at 0x80000004 len=4 data=0x00028293 pc=0x80000004
[MTRACE] WRITE at 0x80001000 len=4 data=0x12345678 pc=0x80000010
```

## 与NEMU的对比

| 特性 | NEMU | NPC |
|------|------|-----|
| itrace | ✅ | ✅ |
| mtrace | ✅ | ✅ |
| ftrace | ✅ | ❌（待实现） |
| 环形缓冲区 | ✅ | ✅ |
| 反汇编 | capstone | capstone |
| 条件trace | ✅ | ❌ |

## 扩展方向

### 1. 条件trace
添加条件判断，只在特定条件下记录trace：
```cpp
#ifdef CONFIG_ITRACE_COND
  if (ITRACE_COND) {
    itrace_write(pc, inst);
  }
#endif
```

### 2. ftrace - 函数追踪
- 解析ELF符号表
- 识别函数调用（jal, jalr）
- 识别函数返回（ret）
- 显示调用栈

### 3. trace输出到文件
将trace输出重定向到文件而不是stdout：
```cpp
extern FILE* trace_fp;
fprintf(trace_fp, "[MTRACE] ...\n");
```

### 4. 更详细的信息
- 显示寄存器值
- 显示内存内容
- 显示指令类型

## 调试技巧

### 1. 定位错误指令
查看iringbuf的最后一条指令（标记为`-->`）

### 2. 追踪内存访问
观察mtrace输出，找到非法内存访问

### 3. 结合sdb使用
- 使用sdb单步执行
- 观察每条指令的trace输出
- 设置监视点观察内存变化

## 注意事项

1. capstone库必须安装才能使用反汇编功能
2. mtrace输出量很大，建议重定向到文件
3. trace会影响性能，不适合长时间运行
4. 环形缓冲区大小可以调整（IRINGBUF_SIZE）
