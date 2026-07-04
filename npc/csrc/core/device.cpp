/***************************************************************************************
* NPC Device Management
* 设备管理模块实现.
*
* 历史上 NPC 自身用 SDL2 实现了串口/键盘/VGA 帧缓冲等设备, 用于在 NPC 独立
* 仿真(未接入 ysyxSoC)时提供 IOE. 现已接入 ysyxSoC: 这些设备都由 SoC 中真实
* 的设备控制器(UART16550 / PS2 / VGA / GPIO) 实现, 并可通过 NVBoard 在板卡上
* 展示效果. 因此 NPC 自身的 SDL 设备代码已不再需要 —— 保留它反而会因为和
* NVBoard 共用同一个 SDL 上下文而产生冲突(例如 SDL_PollEvent 抢消费窗口事件,
* 导致 NVBoard 窗口显示残缺/全黑).
*
* 本文件仅保留三个仍被仿真主循环调用的接口作为空操作:
*   init_device()     —— 无需初始化任何 SDL 资源
*   device_update()   —— 每个时钟周期调用; NVBoard 模式下刷新由 nvboard_update()
*                        统一完成, 此处不做任何事
*   device_cleanup()  —— 无需清理任何 SDL 资源
***************************************************************************************/

#include "device.h"

void init_device() {
    // SoC 模式下所有设备均由 ysyxSoC 中的设备控制器实现, NPC 侧无需初始化.
}

void device_cleanup() {
    // 无 NPC 侧 SDL 资源需要清理.
}

void device_update() {
    // 仿真主循环每个时钟周期会调用本函数.
    // - NVBoard 模式: SDL 事件队列与画面刷新由 nvboard_update() 统一处理
    //   (在 cpu.cpp 的 exec_once 中调用), 此处不做任何事, 避免与 NVBoard 的
    //   SDL 上下文冲突.
    // - 非 NVBoard 模式: SoC 中的设备控制器自行工作, 亦无需 NPC 介入.
}
