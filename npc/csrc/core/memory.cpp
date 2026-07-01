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

// MROM 镜像 (内容由 mrom_load() 读入, 偏移0对应 0x20000000)
static uint8_t mrom[MROM_SIZE];

// Flash 颗粒镜像 (W25Q128JV, 16MB). 偏移0对应 flash 物理地址 0x30000000.
// 仿真初始化时往其中写入内容, 相当于模拟了用烧录器往 flash 颗粒中烧录数据的过程.
static uint8_t flash[FLASH_SIZE];

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

// 读入二进制文件作为 MROM 内容 (偏移0对应 0x20000000)
bool mrom_load(const char* filename) {
    FILE* fp = fopen(filename, "rb");
    if (!fp) {
        Log("ERROR: Cannot open MROM file '%s'", filename);
        return false;
    }
    size_t bytes_read = fread(mrom, 1, MROM_SIZE, fp);
    fclose(fp);
    Log("Loaded %zu bytes from '%s' into MROM at 0x%08x", bytes_read, filename, MROM_BASE);
    return true;
}

// 获取 MROM 镜像缓冲区指针 (供 DiffTest 同步到 NEMU 使用)
uint8_t* get_mrom_buffer() {
    return mrom;
}

// 获取 flash 颗粒镜像缓冲区指针 (供 DiffTest 同步到 NEMU 使用)
uint8_t* get_flash_buffer() {
    return flash;
}


void flash_init(const char* program_file) {
    
    // for (uint32_t off = 0; off < FLASH_SIZE; off++) {
    //     flash[off] = (uint8_t)(off ^ 0x5a);
    // }
    // Log("Flash initialized: %d bytes at 0x%08x (background = byte_offset ^ 0x5a)",
    //     FLASH_SIZE, FLASH_BASE);

    if (program_file) {
        FILE *fp = fopen(program_file, "rb");
        if (fp) {
            size_t n = fread(flash, 1, FLASH_SIZE, fp);
            fclose(fp);
            Log("Flash programmed: program '%s' (%zu bytes) burned at offset 0x0 (phys 0x%08x)",
                program_file, n, FLASH_BASE);
        } else {
            Log("Flash program WARNING: program file '%s' not found", program_file);
        }
    }

    // #define FLASH_PROG_OFF 0x1000
    // FILE *fp = fopen("test/char-test.bin", "rb");
    // if (fp) {
    //     size_t max = FLASH_SIZE - FLASH_PROG_OFF;
    //     size_t n = fread(flash + FLASH_PROG_OFF, 1, max, fp);
    //     fclose(fp);
    //     Log("Flash programmed: char-test.bin (%zu bytes) burned at offset 0x%x (phys 0x%08x)",
    //         n, FLASH_PROG_OFF, FLASH_BASE + FLASH_PROG_OFF);
    // } else {
    //     Log("Flash program skipped: test/char-test.bin not found");
    // }
}

// spi_top_apb.v 
extern "C" void flash_read(int32_t addr, int32_t *data) {
    uint32_t off = (uint32_t)addr & ~0x3u;
    uint32_t value = 0;
    for (int i = 0; i < 4; i++) {
        uint32_t boff = off + i;
        value |= (boff < FLASH_SIZE ? (uint32_t)flash[boff] : 0u) << (8 * i);
    }
    *data = (int32_t)value;
}

// 注意: 当 LSU 以 1/2 字节粒度访问 (如 lbu) 时, araddr 不再被总线对齐,
// 若不在此处 &~3, 会以非对齐地址为起点拼 4 字节, 导致 LSU 字节选择错位.
extern "C" void mrom_read(int32_t addr, int32_t *data) {
    uint32_t off = ((uint32_t)addr & ~0x3u) - MROM_BASE;
    uint32_t value = 0;
    for (int i = 0; i < 4; i++) {
        uint32_t boff = off + i;
        value |= (boff < MROM_SIZE ? (uint32_t)mrom[boff] : 0u) << (8 * i);
    }
    *data = (int32_t)value;
}
