#include <am.h>
#include "npc.h"

void __am_gpu_init() {
  // GPU初始化（暂不需要）
  
}

void __am_gpu_config(AM_GPU_CONFIG_T *cfg) {
  // 返回一个虚拟的屏幕配置
  // 字符模式下不需要真实的显示
  *cfg = (AM_GPU_CONFIG_T) {
    .present = false,  // 表示GPU不存在
    .has_accel = false,
    .width = 0,
    .height = 0,
    .vmemsz = 0
  };
}

void __am_gpu_fbdraw(AM_GPU_FBDRAW_T *ctl) {
  // 字符模式下不需要绘制帧缓冲
  // 空实现即可
}

void __am_gpu_status(AM_GPU_STATUS_T *status) {
  status->ready = true;
}
