/***************************************************************************************
* NPC Memory Management
* 存储器管理模块头文件
***************************************************************************************/

#ifndef __MEMORY_H__
#define __MEMORY_H__

#include <cstdint>

// 存储器配置
#define PMEM_SIZE (128 * 1024 * 1024)  // 128MB
#define PMEM_BASE 0x80000000           // AM程序从0x80000000开始

// 设备地址定义
#define SERIAL_PORT 0x10000000  // 串口地址
#define RTC_ADDR_LO 0x10000048  // RTC低32位
#define RTC_ADDR_HI 0x1000004c  // RTC高32位

// MROM 配置 (0x2000_0000 ~ 0x2000_0fff, 共4KB)
#define MROM_BASE 0x20000000
#define MROM_SIZE 0x1000

#define FLASH_BASE 0x30000000
#define FLASH_SIZE 0x1000000   // 16MB (W25Q128JV 颗粒容量)

// 地址转换
uint8_t* guest_to_host(uint32_t paddr);

// 内存访问接口
uint32_t pmem_read_word(uint32_t addr);
bool in_pmem(uint32_t addr);

// 程序加载
bool load_program(const char* filename);

// 读入二进制文件作为 MROM 内容 (偏移0对应 0x20000000)
bool mrom_load(const char* filename);

// 获取 MROM 镜像缓冲区指针 (供 DiffTest 同步到 NEMU 使用)
uint8_t* get_mrom_buffer();

// 初始化 flash 颗粒内容 (模拟烧录器烧录数据). program_file 非 NULL 时
// 将程序镜像烧录到 flash 偏移 0 (用 flash 替代 MROM, 复位从 flash 取指).
void flash_init(const char* program_file = nullptr);

// 获取 flash 颗粒镜像缓冲区指针 (供 DiffTest 同步到 NEMU 使用)
uint8_t* get_flash_buffer();

// DPI-C接口（供Verilog调用）
extern "C" {
    int pmem_read(int raddr);
    void pmem_write(int waddr, int wdata, char wmask);
}

extern "C" void flash_read(int32_t addr, int32_t *data);
extern "C" void mrom_read(int32_t addr, int32_t *data); 

#endif
