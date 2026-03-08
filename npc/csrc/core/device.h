/***************************************************************************************
* NPC Device Management
* 设备管理模块头文件
***************************************************************************************/

#ifndef __DEVICE_H__
#define __DEVICE_H__

#include <cstdint>

// 初始化设备（设置启动时间）
void init_device();

// 检查地址是否为设备地址
bool is_device_addr(uint32_t addr);

// 设备读取
uint32_t device_read(uint32_t addr);

// 设备写入
void device_write(uint32_t addr, uint32_t data, uint8_t wmask);

#endif
