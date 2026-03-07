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
  return *p;
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
  }
  should_exit = true;
  exit_code = code;
}

// 加载二进制文件到存储器
static bool load_program(const char* filename) {
  FILE* fp = fopen(filename, "rb");
  if (!fp) {
    printf("ERROR: Cannot open file '%s'\n", filename);
    return false;
  }
  
  // 读取文件大小
  fseek(fp, 0, SEEK_END);
  long size = ftell(fp);
  fseek(fp, 0, SEEK_SET);
  
  if (size > PMEM_SIZE) {
    printf("ERROR: Program size (%ld bytes) exceeds memory size (%d bytes)\n", size, PMEM_SIZE);
    fclose(fp);
    return false;
  }
  
  // 读取到存储器（从PMEM_BASE对应的位置开始）
  size_t bytes_read = fread(pmem, 1, size, fp);
  fclose(fp);
  
  printf("Loaded %zu bytes from '%s' into memory at 0x%08x\n", bytes_read, filename, PMEM_BASE);
  return true;
}

// 在指定地址写入ebreak指令
static void write_ebreak_at(uint32_t addr) {
  if (addr >= PMEM_SIZE) {
    printf("ERROR: EBREAK address out of range: 0x%08x\n", addr);
    return;
  }
  
  uint32_t ebreak_inst = 0x00100073;
  uint8_t* p = guest_to_host(addr);
  
  p[0] = ebreak_inst & 0xFF;
  p[1] = (ebreak_inst >> 8) & 0xFF;
  p[2] = (ebreak_inst >> 16) & 0xFF;
  p[3] = (ebreak_inst >> 24) & 0xFF;
  
  printf("Wrote EBREAK instruction at address 0x%08x\n", addr);
}

// 查找halt函数地址（简化版本：查找特定的指令模式）
// halt函数通常是一个死循环：jalr x0, x0, 0 (0x00000067)
static uint32_t find_halt_address() {
  uint32_t halt_pattern = 0x00000067; // jalr x0, x0, 0
  
  // 在前64KB范围内搜索
  for (uint32_t offset = 0; offset < 64 * 1024; offset += 4) {
    uint32_t* p = (uint32_t*)(pmem + offset);
    if (*p == halt_pattern) {
      uint32_t addr = offset;
      printf("Found halt() at address 0x%08x\n", addr);
      return addr;
    }
  }
  
  printf("WARNING: halt() function not found, using default address\n");
  return 0;
}

int main(int argc, char** argv) {
    // 检查命令行参数
    if (argc < 2) {
        printf("Usage: %s <program.bin>\n", argv[0]);
        printf("Example: %s build/dummy-minirv-npc.bin\n", argv[0]);
        return 1;
    }
    
    const char* program_file = argv[1];
    
    // 初始化Verilator上下文
    VerilatedContext* const contextp = new VerilatedContext;
    contextp->commandArgs(argc, argv);
    
    // 创建顶层模块
    Vtop* const top = new Vtop{contextp};
    
    // 启用波形追踪Verilated::traceEverOn(true);
    // VerilatedFstC* tfp = new VerilatedFstC;
    // top->trace(tfp, 99); 
    // tfp->open("wave/dump.fst");
    // Verilated::traceEverOn(true);
    // VerilatedFstC* tfp = new VerilatedFstC;
    // top->trace(tfp, 99); 
    // tfp->open("wave/dump.fst");
    
    // 加载程序
    printf("NPC - minirv processor simulator\n");
    printf("=================================\n\n");
    
    if (!load_program(program_file)) {
        return 1;
    }
    
    // 初始化启动时间
    boot_time = get_time_us();
    
    printf("\n");
    
    // 复位
    top->rst = 1;
    top->clk = 0;
    top->eval();
    //tfp->dump(contextp->time());
    
    contextp->timeInc(1);
    top->clk = 1;
    top->eval();
    //tfp->dump(contextp->time());
    
    contextp->timeInc(1);
    top->rst = 0;
    
    // 仿真循环 - 持续运行直到ebreak
    //int cycles = 0;
    //int max_cycles = 10000000; // 增加最大周期数
    printf("Starting simulation from PC=0x%08x...\n\n", PMEM_BASE);
    
    while (!contextp->gotFinish() && !should_exit /*&& cycles < max_cycles*/) {
        // 下降沿
        top->clk = 0;
        top->eval();
        //tfp->dump(contextp->time());
        
        contextp->timeInc(1);
        
        // 上升沿
        top->clk = 1;
        top->eval();
        //tfp->dump(contextp->time());
        
        contextp->timeInc(1);
        //cycles++;
    }
    
    printf("\nSimulation finished after %d cycles.\n", cycles);
    
    if (should_exit) {
        printf("Exit reason: EBREAK instruction (program completed)\n");
        printf("Exit code: %d\n", exit_code);
    }//  else if (cycles >= max_cycles) {
    //     printf("Exit reason: Maximum cycles reached (possible infinite loop)\n");
    //     exit_code = 1;
    // }
    
    // 清理
    top->final();
    //tfp->close();
    
    delete top;
    //delete tfp;
    delete contextp;
    
    return exit_code;
}
