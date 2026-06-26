/***************************************************************************************
* NPC Memory Management
* 存储器管理模块实现
***************************************************************************************/

#include "memory.h"
#include "device.h"
#include "npc.h"
#include "../utils/log.h"
#include "../utils/difftest.h"
#include "../trace/mtrace.h"
#include <cstdio>
#include <cstring>

// 物理内存
static uint8_t pmem[PMEM_SIZE];

// mtrace去重变量（仅 TRACE 开启时使用）
#ifdef ENABLE_TRACE
static uint64_t last_read_cycle = 0;
static uint32_t last_read_addr = 0;
static uint64_t last_write_cycle = 0;
static uint32_t last_write_addr = 0;
#endif

// 地址转换
uint8_t* guest_to_host(uint32_t paddr) {
    return pmem + (paddr - PMEM_BASE);
}

// DPI-C函数：读取存储器
extern "C" int pmem_read(int raddr) {
    // 按4字节对齐读取
    raddr = raddr & ~0x3u;

    // 处理设备读取
    if (is_device_addr(raddr)) {
        difftest_skip_ref();  // MMIO 访问结果不确定，跳过 REF 对比
        return device_read(raddr);
    }

    // 帧缓冲区不可读（只写），返回0
    if (is_fb_addr(raddr)) {
        difftest_skip_ref();
        return 0;
    }
    
    // 检查地址是否在有效范围内
    if (raddr < PMEM_BASE || raddr >= PMEM_BASE + PMEM_SIZE) {
        printf("ERROR: pmem_read address out of range: 0x%x (valid: 0x%x - 0x%x)\n", 
               raddr, PMEM_BASE, PMEM_BASE + PMEM_SIZE - 1);
        return 0;
    }
    
    uint32_t* p = (uint32_t*)guest_to_host(raddr);
    uint32_t ret = *p;
    
    // mtrace记录（TRACE 开启时才记录）
#ifdef ENABLE_TRACE
    uint64_t cycle = npc_get_cycle();
    uint32_t pc = npc_get_pc();
    if (cycle != last_read_cycle || raddr != last_read_addr) {
        mtrace_read(raddr, 4, ret, pc);
        last_read_cycle = cycle;
        last_read_addr = raddr;
    }
#endif
    
    return ret;
}

// DPI-C函数：写入存储器
extern "C" void pmem_write(int waddr, int wdata, char wmask) {
    // 按4字节对齐写入
    waddr = waddr & ~0x3u;

    // 处理设备寄存器写入
    if (is_device_addr(waddr)) {
        difftest_skip_ref();  // MMIO 写入，跳过 REF 对比
        device_write(waddr, wdata, (uint8_t)wmask);
        return;
    }

    // 帧缓冲写入
    if (is_fb_addr(waddr)) {
        difftest_skip_ref();
        fb_write(waddr, wdata, (uint8_t)wmask);
        return;
    }
    
    // 检查地址是否在有效范围内
    if (waddr < PMEM_BASE || waddr >= PMEM_BASE + PMEM_SIZE) {
        printf("ERROR: pmem_write address out of range: 0x%x (valid: 0x%x - 0x%x)\n", 
               waddr, PMEM_BASE, PMEM_BASE + PMEM_SIZE - 1);
        return;
    }
    
    uint8_t* p = guest_to_host(waddr);
    
    // mtrace记录（TRACE 开启时才记录）
#ifdef ENABLE_TRACE
    int len = __builtin_popcount((uint8_t)wmask);
    uint64_t cycle = npc_get_cycle();
    uint32_t pc = npc_get_pc();
    if (cycle != last_write_cycle || waddr != last_write_addr) {
        mtrace_write(waddr, len, wdata, pc);
        last_write_cycle = cycle;
        last_write_addr = waddr;
    }
#endif
    
    // 根据写掩码写入数据
    if (wmask & 0x01) p[0] = wdata & 0xFF;
    if (wmask & 0x02) p[1] = (wdata >> 8) & 0xFF;
    if (wmask & 0x04) p[2] = (wdata >> 16) & 0xFF;
    if (wmask & 0x08) p[3] = (wdata >> 24) & 0xFF;
}

// 内存访问接口
uint32_t pmem_read_word(uint32_t addr) {
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
bool load_program(const char* filename) {
    FILE* fp = fopen(filename, "rb");
    if (!fp) {
        Log("ERROR: Cannot open file '%s'", filename);
        return false;
    }
    
    fseek(fp, 0, SEEK_END);
    long size = ftell(fp);
    fseek(fp, 0, SEEK_SET);
    
    if (size > PMEM_SIZE) {
        Log("ERROR: Program size (%ld bytes) exceeds memory size (%d bytes)", size, PMEM_SIZE);
        fclose(fp);
        return false;
    }
    
    size_t bytes_read = fread(pmem, 1, size, fp);
    fclose(fp);
    
    Log("Loaded %zu bytes from '%s' into memory at 0x%08x", bytes_read, filename, PMEM_BASE);
    return true;
}

extern "C" void flash_read(int32_t addr, int32_t *data) { }
extern "C" void mrom_read(int32_t addr, int32_t *data) { *data = 0x00100073; }
