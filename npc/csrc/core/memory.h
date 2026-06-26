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

// 地址转换
uint8_t* guest_to_host(uint32_t paddr);

// 内存访问接口
uint32_t pmem_read_word(uint32_t addr);
bool in_pmem(uint32_t addr);

// 程序加载
bool load_program(const char* filename);

// DPI-C接口（供Verilog调用）
extern "C" {
    int pmem_read(int raddr);
    void pmem_write(int waddr, int wdata, char wmask);
}

extern "C" void flash_read(int32_t addr, int32_t *data);
extern "C" void mrom_read(int32_t addr, int32_t *data); 

#endif
