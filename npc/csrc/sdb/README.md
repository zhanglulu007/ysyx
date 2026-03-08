# SDB源码说明

## 文件结构

```
csrc/sdb/
├── sdb.h           - sdb头文件，定义接口和数据结构
├── sdb.cpp         - sdb主逻辑，实现命令解析和执行
├── expr.cpp        - 表达式求值模块
└── watchpoint.cpp  - 监视点管理模块
```

## 模块说明

### sdb.h
定义了sdb的核心接口：
- `init_sdb()` - 初始化sdb
- `sdb_mainloop()` - sdb主循环
- `sdb_set_batch_mode()` - 设置批处理模式
- 表达式求值和监视点接口

### sdb.cpp
实现了sdb的命令系统：
- 命令表：定义所有支持的命令
- 命令处理函数：实现每个命令的功能
- readline集成：提供命令行编辑和历史记录

支持的命令：
- `c` - 继续执行
- `q` - 退出
- `si [N]` - 单步执行N条指令
- `info r/w` - 打印寄存器/监视点
- `x N EXPR` - 扫描内存
- `p EXPR` - 表达式求值
- `w EXPR` - 设置监视点
- `d N` - 删除监视点

### expr.cpp
实现表达式求值功能：
- 词法分析：使用正则表达式识别token
- 语法分析：递归下降解析
- 求值：支持算术、逻辑、比较运算和指针解引用

支持的token类型：
- 数字：十进制、十六进制
- 寄存器：$pc, $a0等
- 运算符：+, -, *, /, ==, !=, &&
- 括号：(, )
- 指针解引用：*

### watchpoint.cpp
实现监视点管理：
- 监视点池：预分配32个监视点
- 链表管理：使用链表管理活动和空闲监视点
- 监视点检查：每次执行后检查表达式值是否变化

## 与main.cpp的集成

main.cpp需要提供以下接口：
- `npc_reg_str2val()` - 寄存器名称转值
- `npc_reg_display()` - 打印所有寄存器
- `pmem_read_word()` - 读取内存字
- `in_pmem()` - 检查地址是否有效
- `cpu_exec()` - 执行N条指令

全局变量：
- `g_top` - Verilator顶层模块指针

## 编译依赖

- readline库：提供命令行编辑功能
- regex库：用于表达式词法分析
- Verilator生成的C++代码：访问RTL信号

## 调试技巧

1. 如果寄存器访问失败，检查Verilator生成的头文件（obj_dir/Vtop.h）确认正确的信号路径

2. 如果表达式求值出错，可以在expr.cpp中启用调试输出查看token解析过程

3. 如果监视点不工作，检查check_watchpoints()是否在cpu_exec()中被正确调用

## 扩展建议

可以在此基础上添加：
1. itrace - 指令追踪（需要集成反汇编库）
2. mtrace - 内存访问追踪
3. ftrace - 函数调用追踪（需要解析ELF符号表）
4. 断点功能
5. 反向执行
6. 更复杂的表达式支持
