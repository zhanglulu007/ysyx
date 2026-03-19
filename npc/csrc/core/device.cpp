/***************************************************************************************
* NPC Device Management
* 设备管理模块实现
***************************************************************************************/

#include "device.h"
#include "memory.h"
#include <cstdio>
#include <sys/time.h>

static uint64_t boot_time = 0;  // 启动时间

// 获取系统时间（微秒）
static uint64_t get_time_us() {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (uint64_t)tv.tv_sec * 1000000 + tv.tv_usec;
}

// 初始化设备
void init_device() {
    boot_time = get_time_us();
}

// 检查地址是否为设备地址
bool is_device_addr(uint32_t addr) {
    return (addr == SERIAL_PORT || addr == RTC_ADDR_LO || addr == RTC_ADDR_HI);
}

// 设备读取
uint32_t device_read(uint32_t addr) {
    if (addr == RTC_ADDR_LO) {
        uint64_t uptime = get_time_us() - boot_time;
        return (uint32_t)(uptime & 0xFFFFFFFF);
    }
    if (addr == RTC_ADDR_HI) {
        uint64_t uptime = get_time_us() - boot_time;
        return (uint32_t)(uptime >> 32);
    }
    return 0;
}

// 设备写入
void device_write(uint32_t addr, uint32_t data, uint8_t wmask) {
    if (addr == SERIAL_PORT) {
        putc(data & 0xFF, stderr);
    }
}
