/***************************************************************************************
* NPC Device Management
* 设备管理模块头文件.
*
* 接入 ysyxSoC 后, 串口/键盘/VGA/GPIO 等设备均由 SoC 中的设备控制器实现,
* NPC 侧不再维护任何 SDL 设备资源. 本模块仅保留仿真主循环需要的三个接口
* (init_device / device_update / device_cleanup), 实现均为空操作.
* 设备的可视化展示统一交由 NVBoard 处理.
***************************************************************************************/

#ifndef __DEVICE_H__
#define __DEVICE_H__

// 初始化设备(NPC 侧无 SDL 资源, 空操作).
void init_device();

// 每个时钟周期调用(NVBoard 模式下刷新由 nvboard_update() 统一完成, 空操作).
void device_update();

// 清理设备资源(空操作).
void device_cleanup();

#endif
