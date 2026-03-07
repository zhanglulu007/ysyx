# NPC Utils - 工具函数

## 日志系统（Log System）

### 概述

NPC的日志系统参考NEMU实现，提供了灵活的日志记录功能，支持：
- 输出到stdout或文件
- 带颜色的格式化输出
- 条件日志（基于指令计数）
- 断言和错误处理

### 文件说明

- `log.h` - 日志系统头文件，定义宏和接口
- `log.cpp` - 日志系统实现

### 核心功能

#### 1. 日志初始化

```cpp
void init_log(const char *log_file);
```

- 如果`log_file`为NULL，输出到stdout
- 如果指定文件名，输出到文件
- 自动处理文件打开失败的情况

#### 2. 日志宏

**Log宏** - 带文件名、行号、函数名的日志：

```cpp
Log("Program loaded at 0x%08x", addr);
// 输出：[main.cpp:123 load_program] Program loaded at 0x80000000
```

**log_write宏** - 直接写入日志文件：

```cpp
log_write("[PMEM] Read at 0x%08x\n", addr);
```

**Assert宏** - 断言检查：

```cpp
Assert(ptr != NULL, "Pointer is NULL");
```

**panic宏** - 触发致命错误：

```cpp
panic("Unimplemented feature");
```

#### 3. 条件日志

通过编译选项控制日志范围：

```makefile
# 启用日志
-DCONFIG_LOG

# 指定日志起始指令数
-DCONFIG_LOG_START=1000

# 指定日志结束指令数
-DCONFIG_LOG_END=2000
```

只有在指定指令范围内才会记录日志，用于调试特定代码段。

### 使用示例

#### 基本使用

```cpp
#include "utils/log.h"

int main() {
    // 初始化日志系统
    init_log("npc.log");
    
    // 记录日志
    Log("NPC started");
    
    // 条件断言
    Assert(condition, "Condition failed");
    
    // 关闭日志
    close_log();
}
```

#### 命令行参数

```bash
# 输出到stdout
./Vtop program.bin

# 输出到文件
./Vtop program.bin -l npc.log

# 批处理模式 + 日志文件
./Vtop program.bin -b -l npc.log
```

### ANSI颜色代码

日志系统支持ANSI颜色输出：

```cpp
ANSI_FG_BLACK   - 黑色前景
ANSI_FG_RED     - 红色前景
ANSI_FG_GREEN   - 绿色前景
ANSI_FG_YELLOW  - 黄色前景
ANSI_FG_BLUE    - 蓝色前景
ANSI_FG_MAGENTA - 品红前景
ANSI_FG_CYAN    - 青色前景
ANSI_FG_WHITE   - 白色前景
ANSI_NONE       - 重置颜色
```

使用示例：

```cpp
printf(ANSI_FMT("Error message", ANSI_FG_RED) "\n");
```

### 日志输出示例

```
[main.cpp:234 init_log] Log is written to npc.log
[main.cpp:245 load_program] Loaded 4096 bytes from 'test.bin' into memory at 0x80000000
[main.cpp:267 main] Initialization complete
[main.cpp:283 main] Starting simulation from PC=0x80000000
[main.cpp:142 ebreak_handler] HIT GOOD TRAP at PC=0x80001234
[main.cpp:298 main] Simulation finished
[main.cpp:301 main] Exit reason: EBREAK instruction (program completed)
[main.cpp:302 main] Exit code: 0
[main.cpp:303 main] Total instructions executed: 12345
```

### 与NEMU的对比

| 特性 | NEMU | NPC |
|------|------|-----|
| 实现语言 | C | C++ |
| 日志文件 | ✅ | ✅ |
| 条件日志 | ✅ | ✅ |
| ANSI颜色 | ✅ | ✅ |
| Log宏 | ✅ | ✅ |
| Assert宏 | ✅ | ✅ |
| panic宏 | ✅ | ✅ |

### 配置选项

在Makefile中添加：

```makefile
# 启用日志
-DCONFIG_LOG

# 条件日志（可选）
-DCONFIG_LOG_START=1000
-DCONFIG_LOG_END=2000
```

### 性能考虑

- 日志写入会影响性能，特别是频繁调用时
- 使用条件日志可以减少性能影响
- 批处理模式下建议输出到文件
- log_write会自动fflush，确保日志及时写入

### 调试技巧

1. **使用Log宏记录关键事件**：
   ```cpp
   Log("Loading program from %s", filename);
   ```

2. **使用Assert检查条件**：
   ```cpp
   Assert(addr >= PMEM_BASE, "Invalid address: 0x%x", addr);
   ```

3. **使用条件日志调试特定代码段**：
   ```bash
   # 只记录第1000-2000条指令
   make build CFLAGS="-DCONFIG_LOG_START=1000 -DCONFIG_LOG_END=2000"
   ```

4. **分析日志文件**：
   ```bash
   # 查看所有日志
   cat npc.log
   
   # 查找特定事件
   grep "TRAP" npc.log
   
   # 统计指令数
   grep "Total instructions" npc.log
   ```

### 注意事项

1. 日志文件在程序退出时自动关闭
2. 如果日志文件打开失败，会回退到stdout
3. Assert失败会触发程序终止
4. 日志输出包含文件名、行号、函数名，便于定位问题
5. 条件日志需要正确维护g_nr_inst计数器

### 扩展建议

1. **日志级别**：添加DEBUG、INFO、WARN、ERROR级别
2. **日志过滤**：支持按模块过滤日志
3. **日志轮转**：支持日志文件大小限制和轮转
4. **性能统计**：记录各模块的执行时间
5. **日志分析工具**：开发日志分析脚本

### 总结

NPC的日志系统提供了完整的日志记录功能，参考NEMU实现，支持文件输出、条件日志、颜色输出等特性。合理使用日志系统可以大大提高调试效率。
