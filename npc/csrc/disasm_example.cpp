// 正确使用Capstone反汇编的示例代码
// 参考NEMU的实现，避免频繁创建/释放句柄

#include <capstone/capstone.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>

// ============================================
// 全局句柄 - 只初始化一次
// ============================================
static csh g_capstone_handle = 0;
static bool g_disasm_initialized = false;

// ============================================
// 初始化反汇编器（程序启动时调用一次）
// ============================================
void init_disasm() {
  if (g_disasm_initialized) {
    printf("WARNING: Disassembler already initialized\n");
    return;
  }
  
  // 打开capstone句柄
  cs_err err = cs_open(
    CS_ARCH_RISCV,                    // RISC-V架构
    CS_MODE_RISCV32 | CS_MODE_RISCVC, // RV32 + 压缩指令
    &g_capstone_handle
  );
  
  if (err != CS_ERR_OK) {
    printf("ERROR: Failed to initialize capstone: %d\n", err);
    exit(1);
  }
  
  // 可选：启用详细信息
  cs_option(g_capstone_handle, CS_OPT_DETAIL, CS_OPT_ON);
  
  g_disasm_initialized = true;
  printf("Capstone disassembler initialized successfully\n");
}

// ============================================
// 清理反汇编器（程序结束时调用一次）
// ============================================
void cleanup_disasm() {
  if (g_disasm_initialized && g_capstone_handle != 0) {
    cs_close(&g_capstone_handle);
    g_capstone_handle = 0;
    g_disasm_initialized = false;
    printf("Capstone disassembler cleaned up\n");
  }
}

// ============================================
// 反汇编单条指令（可以频繁调用）
// ============================================
void disassemble_inst(uint32_t pc, uint32_t inst, char* buf, size_t buf_size) {
  if (!g_disasm_initialized) {
    snprintf(buf, buf_size, "ERROR: disasm not initialized");
    return;
  }
  
  cs_insn *insn = nullptr;
  
  // 使用全局句柄进行反汇编
  // 注意：这里不创建新句柄，只是使用已有的
  size_t count = cs_disasm(
    g_capstone_handle,     // 复用全局句柄
    (uint8_t*)&inst,       // 指令字节
    4,                     // 指令长度（最多4字节）
    pc,                    // PC地址
    1,                     // 只反汇编1条指令
    &insn                  // 输出结果
  );
  
  if (count > 0) {
    // 格式化输出：助记符 + 操作数
    if (insn->op_str[0] != '\0') {
      snprintf(buf, buf_size, "%-8s %s", insn->mnemonic, insn->op_str);
    } else {
      snprintf(buf, buf_size, "%s", insn->mnemonic);
    }
    
    // 释放指令结构（不是释放句柄！）
    cs_free(insn, count);
  } else {
    // 反汇编失败，可能是非法指令
    snprintf(buf, buf_size, ".word 0x%08x", inst);
  }
}

// ============================================
// 带格式化的指令追踪（用于调试）
// ============================================
void trace_instruction(uint32_t pc, uint32_t inst) {
  char disasm_buf[128];
  disassemble_inst(pc, inst, disasm_buf, sizeof(disasm_buf));
  
  // 格式化输出：PC: 指令字节 反汇编结果
  printf("0x%08x: %08x  %s\n", pc, inst, disasm_buf);
}

// ============================================
// 错误示例：不要这样做！
// ============================================
#if 0
// ❌ 错误做法：每次都创建和释放句柄
void bad_disassemble(uint32_t pc, uint32_t inst) {
  csh handle;
  
  // 每次调用都创建句柄 - 非常慢！
  cs_open(CS_ARCH_RISCV, CS_MODE_RISCV32, &handle);
  
  cs_insn *insn;
  cs_disasm(handle, (uint8_t*)&inst, 4, pc, 1, &insn);
  
  printf("%s %s\n", insn->mnemonic, insn->op_str);
  
  cs_free(insn, 1);
  
  // 每次调用都释放句柄 - 触发大量内存操作！
  cs_close(&handle);
}
#endif

// ============================================
// 使用示例
// ============================================
#if 0
int main() {
  // 1. 程序启动时初始化（只调用一次）
  init_disasm();
  
  // 2. 仿真循环中频繁调用（可以调用数百万次）
  for (int i = 0; i < 1000000; i++) {
    uint32_t pc = 0x80000000 + i * 4;
    uint32_t inst = 0x00000013; // nop
    
    // 这个调用很快，因为复用了全局句柄
    trace_instruction(pc, inst);
  }
  
  // 3. 程序结束时清理（只调用一次）
  cleanup_disasm();
  
  return 0;
}
#endif

// ============================================
// 性能对比说明
// ============================================
/*
假设运行马里奥需要执行1000万条指令：

错误做法（每次创建/释放句柄）：
- 1000万次 cs_open/cs_close
- 每次约1000次内存分配
- 总计：100亿次内存操作
- 触发数百万次缺页中断
- 预估时间：数小时

正确做法（复用全局句柄）：
- 1次 cs_open/cs_close
- 1000万次 cs_disasm（轻量级）
- 总计：约1000次内存分配
- 几乎无缺页中断
- 预估时间：数秒到数分钟

性能差异：10-100倍！
*/
