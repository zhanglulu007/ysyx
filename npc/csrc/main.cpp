// NPC仿真环境
// 实现存储器和仿真循环

#include <iostream>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cassert>
#include <sys/time.h>
#include <verilated.h>
#include <verilated_fst_c.h>
#include "Vtop.h"
#include "sdb/sdb.h"
#include "trace/trace.h"

// 存储器定义 - 128MB
#define PMEM_SIZE (128 * 1024 * 1024)
#define PMEM_BASE 0x80000000  // AM程序从0x80000000开始

// 设备地址定义
#define SERIAL_PORT 0x10000000  // 串口地址
#define RTC_ADDR_LO 0x10000048  // RTC低32位
#define RTC_ADDR_HI 0x1000004c  // RTC高32位

static uint8_t pmem[PMEM_SIZE];
static bool should_exit = false;
static uint32_t exit_code = 0;

// 全局变量：顶层模块指针和仿真上下文
Vtop* g_top = NULL;
static VerilatedContext* g_contextp = NULL;
static VerilatedFstC* g_tfp = NULL;

// 寄存器和PC缓存（在C++侧维护）
static uint32_t reg_cache[32] = {0};
static uint32_t pc_cache = 0;

// NPC状态
enum {
  NPC_RUNNING,
  NPC_STOP,
  NPC_END,
  NPC_ABORT,
  NPC_QUIT
};

static struct {
  int state;
  uint32_t halt_pc;
  uint32_t halt_ret;
} npc_state = { .state = NPC_STOP };

// RISC-V寄存器名称
static const char *regs[] = {
  "$0", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
  "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5",
  "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7",
  "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6"
};

// 地址转换
static inline uint8_t* guest_to_host(uint32_t paddr) {
  return pmem + (paddr - PMEM_BASE);
}

// 获取系统时间（微秒）
static uint64_t get_time_us() {
  struct timeval tv;
  gettimeofday(&tv, NULL);
  return (uint64_t)tv.tv_sec * 1000000 + tv.tv_usec;
}

static uint64_t boot_time = 0;  // 启动时间

// DPI-C函数：读取存储器
extern "C" int pmem_read(int raddr) {
  // 按4字节对齐读取
  raddr = raddr & ~0x3u;
  
  // 处理RTC时钟读取
  if (raddr == RTC_ADDR_LO) {
    uint64_t uptime = get_time_us() - boot_time;
    return (uint32_t)(uptime & 0xFFFFFFFF);
  }
  if (raddr == RTC_ADDR_HI) {
    uint64_t uptime = get_time_us() - boot_time;
    return (uint32_t)(uptime >> 32);
  }
  
  // 检查地址是否在有效范围内
  if (raddr < PMEM_BASE || raddr >= PMEM_BASE + PMEM_SIZE) {
    printf("ERROR: pmem_read address out of range: 0x%x (valid: 0x%x - 0x%x)\n", 
           raddr, PMEM_BASE, PMEM_BASE + PMEM_SIZE - 1);
    return 0;
  }
  
  uint32_t* p = (uint32_t*)guest_to_host(raddr);
  uint32_t data = *p;
  
#ifdef CONFIG_MTRACE
  mtrace_read(raddr, 4, data, pc_cache);
#endif
  
  return data;
}

// DPI-C函数：写入存储器
extern "C" void pmem_write(int waddr, int wdata, char wmask) {
  // 按4字节对齐写入
  waddr = waddr & ~0x3u;
  
  // 处理串口输出
  if (waddr == SERIAL_PORT) {
    // 串口只使用最低字节
    putchar(wdata & 0xFF);
    return;
  }
  
  // 检查地址是否在有效范围内
  if (waddr < PMEM_BASE || waddr >= PMEM_BASE + PMEM_SIZE) {
    printf("ERROR: pmem_write address out of range: 0x%x (valid: 0x%x - 0x%x)\n", 
           waddr, PMEM_BASE, PMEM_BASE + PMEM_SIZE - 1);
    return;
  }
  
#ifdef CONFIG_MTRACE
  mtrace_write(waddr, 4, wdata, pc_cache);
#endif
  
  uint8_t* p = guest_to_host(waddr);
  
  // 根据写掩码写入数据
  if (wmask & 0x01) p[0] = wdata & 0xFF;
  if (wmask & 0x02) p[1] = (wdata >> 8) & 0xFF;
  if (wmask & 0x04) p[2] = (wdata >> 16) & 0xFF;
  if (wmask & 0x08) p[3] = (wdata >> 24) & 0xFF;
}

// DPI-C函数：ebreak处理
extern "C" void ebreak_handler(int code) {
  // code是a0寄存器的值，0表示成功，非0表示失败
  if (code == 0) {
    printf("\n*** HIT GOOD TRAP ***\n");
  } else {
    printf("\n*** HIT BAD TRAP (code=%d) ***\n", code);
#ifdef CONFIG_ITRACE
    display_iringbuf();
#endif
  }
  should_exit = true;
  exit_code = code;
  npc_state.state = NPC_END;
  npc_state.halt_ret = code;
}

// DPI-C函数：从Verilog接收寄存器更新
extern "C" void update_reg_value(int idx, int value) {
  if (idx >= 0 && idx < 32) {
    reg_cache[idx] = value;
  }
}

// DPI-C函数：从Verilog接收PC更新
extern "C" void update_pc_value(int pc_val) {
  pc_cache = pc_val;
}

// DPI-C函数：从Verilog接收指令（用于itrace）
extern "C" void trace_inst(int pc, int inst) {
#ifdef CONFIG_ITRACE
  itrace_write(pc, inst);
#endif
}

// 寄存器访问接口（从缓存读取）
static uint32_t get_reg(int idx) {
  if (idx == 0) return 0;  // x0恒为0
  if (idx < 0 || idx >= 32) return 0;
  return reg_cache[idx];
}

static uint32_t get_pc() {
  return pc_cache;
}

// 寄存器名称转换为值
word_t npc_reg_str2val(const char *s, bool *success) {
  *success = true;
  
  if (strcmp(s, "pc") == 0) {
    return get_pc();
  }
  
  for (int i = 0; i < 32; i++) {
    if (strcmp(s, regs[i]) == 0) {
      return get_reg(i);
    }
    
    char xname[8];
    sprintf(xname, "x%d", i);
    if (strcmp(s, xname) == 0) {
      return get_reg(i);
    }
  }
  
  *success = false;
  return 0;
}

// 打印所有寄存器
void npc_reg_display() {
  for (int i = 0; i < 32; i++) {
    printf("%-4s  0x%08x\n", regs[i], get_reg(i));
  }
  printf("%-4s  0x%08x\n", "pc", get_pc());
}

// 内存访问接口
word_t pmem_read_word(uint32_t addr) {
  addr = addr & ~0x3u;
  
  if (addr < PMEM_BASE || addr >= PMEM_BASE + PMEM_SIZE) {
    return 0;
  }
  
  uint32_t* p = (uint32_t*)guest_to_host(addr);
  return *p;
}

bool in_pmem(uint32_t addr) {
  return addr >= PMEM_BASE && addr < PMEM_BASE + PMEM_SIZE;
}

// 加载二进制文件到存储器
static bool load_program(const char* filename) {
  FILE* fp = fopen(filename, "rb");
  if (!fp) {
    printf("ERROR: Cannot open file '%s'\n", filename);
    return false;
  }
  
  fseek(fp, 0, SEEK_END);
  long size = ftell(fp);
  fseek(fp, 0, SEEK_SET);
  
  if (size > PMEM_SIZE) {
    printf("ERROR: Program size (%ld bytes) exceeds memory size (%d bytes)\n", size, PMEM_SIZE);
    fclose(fp);
    return false;
  }
  
  size_t bytes_read = fread(pmem, 1, size, fp);
  fclose(fp);
  
  printf("Loaded %zu bytes from '%s' into memory at 0x%08x\n", bytes_read, filename, PMEM_BASE);
  return true;
}

// 单步执行
static void exec_once() {
  // 下降沿
  g_top->clk = 0;
  g_top->eval();
  if (g_tfp) g_tfp->dump(g_contextp->time());
  
  g_contextp->timeInc(1);
  
  // 上升沿
  g_top->clk = 1;
  g_top->eval();
  if (g_tfp) g_tfp->dump(g_contextp->time());
  
  g_contextp->timeInc(1);
}

// CPU执行n条指令
void cpu_exec(uint64_t n) {
  if (npc_state.state == NPC_END || npc_state.state == NPC_ABORT) {
    printf("Program has already exited. Use 'q' to quit.\n");
    return;
  }
  
  npc_state.state = NPC_RUNNING;
  
  uint64_t cycles = 0;
  bool hit_watchpoint = false;
  
  while (cycles < n || n == (uint64_t)-1) {
    exec_once();
    cycles++;
    
    // 检查是否遇到ebreak
    if (should_exit || npc_state.state != NPC_RUNNING) {
      break;
    }
    
    // 检查监视点
    if (check_watchpoints()) {
      hit_watchpoint = true;
      npc_state.state = NPC_STOP;
      printf("Program stopped due to watchpoint.\n");
      break;
    }
    
    // 避免无限循环
    if (cycles % 1000000 == 0 && n == (uint64_t)-1) {
      printf("Executed %lu cycles...\n", cycles);
    }
  }
  
  if (npc_state.state == NPC_RUNNING) {
    npc_state.state = NPC_STOP;
  }
  
  if (!hit_watchpoint && npc_state.state == NPC_STOP) {
    printf("Executed %lu cycles.\n", cycles);
  }
}


int main(int argc, char** argv) {
    // 检查命令行参数
    if (argc < 2) {
        printf("Usage: %s <program.bin> [-b]\n", argv[0]);
        printf("  -b: batch mode (non-interactive)\n");
        printf("Example: %s build/dummy-riscv32e-npc.bin\n", argv[0]);
        return 1;
    }
    
    const char* program_file = argv[1];
    bool batch_mode = false;
    
    // 解析命令行参数
    for (int i = 2; i < argc; i++) {
        if (strcmp(argv[i], "-b") == 0) {
            batch_mode = true;
            sdb_set_batch_mode();
        }
    }
    
    // 初始化Verilator上下文
    g_contextp = new VerilatedContext;
    g_contextp->commandArgs(argc, argv);
    
    // 创建顶层模块
    g_top = new Vtop{g_contextp};
    
    // 启用波形追踪（可选）
    // Verilated::traceEverOn(true);
    // g_tfp = new VerilatedFstC;
    // g_top->trace(g_tfp, 99); 
    // g_tfp->open("wave/dump.fst");
    
    // 加载程序
    printf("NPC - RISC-V processor simulator with Simple Debugger\n");
    printf("======================================================\n\n");
    
    if (!load_program(program_file)) {
        return 1;
    }
    
    // 初始化启动时间
    boot_time = get_time_us();
    
    printf("\n");
    
    // 复位
    g_top->rst = 1;
    g_top->clk = 0;
    g_top->eval();
    
    g_contextp->timeInc(1);
    g_top->clk = 1;
    g_top->eval();
    
    g_contextp->timeInc(1);
    g_top->rst = 0;
    
    // 初始化trace
#ifdef CONFIG_ITRACE
    init_disasm();
#endif
    
    // 初始化sdb
    init_sdb();
    
    printf("Starting simulation from PC=0x%08x...\n", PMEM_BASE);
    
    if (batch_mode) {
        printf("Running in batch mode...\n\n");
    } else {
        printf("Entering interactive mode. Type 'help' for commands.\n\n");
    }
    
    // 进入sdb主循环
    sdb_mainloop();
    
    printf("\nSimulation finished.\n");
    
    if (should_exit) {
        printf("Exit reason: EBREAK instruction (program completed)\n");
        printf("Exit code: %d\n", exit_code);
    }
    
    // 清理
    g_top->final();
    if (g_tfp) {
        g_tfp->close();
        delete g_tfp;
    }
    
    delete g_top;
    delete g_contextp;
    
    return exit_code;
}
