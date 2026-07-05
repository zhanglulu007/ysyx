#include <am.h>
#include "ysyxsoc.h"

// ====================================================================
// AM GPU (VGA) 实现
// --------------------------------------------------------------------
// ysyxSoC 的 VGA 控制器提供 2MB 帧缓冲, 映射到 0x2100_0000~0x211f_ffff,
// 每像素 32 位 (ARGB, 低 24 位有效: [23:16]=R [15:8]=G [7:0]=B),
// 行主序存储: 字节地址 = VGA_FB_BASE + (y * VGA_WIDTH + x) * 4.
//
// AM 程序中 pixel() 返回 (r<<16)|(g<<8)|b, 与该像素格式完全一致, 可直接按
// 32 位写入. NVBoard 的 VGA 是自动刷新的 (VGA 控制器持续把帧缓冲扫描输出),
// 因此 AM_GPU_STATUS 恒就绪, 无需画面同步; sync 字段被忽略.
// ====================================================================

#define VGABASE  ((volatile uint32_t *)VGA_FB_BASE)

void __am_gpu_init() {
  // 帧缓冲上电内容未定义. 此处不做全屏清屏: 在 flash 上执行时, 一次全屏
  // 写入 (640*480 次 APB 写) 开销很大 (每次访问经 AXI->APB Xbar 到 VGA 控制器),
  // 会让 ioe_init() 卡很久. NVBoard 的 VGA 会持续扫描输出帧缓冲, 软件后续
  // 通过 AM_GPU_FBDRAW 写入的像素会自动出现在屏幕上, 故无需启动时清屏.
}

void __am_gpu_config(AM_GPU_CONFIG_T *cfg) {
  cfg->present   = true;
  cfg->has_accel = false;
  cfg->width     = VGA_WIDTH;
  cfg->height    = VGA_HEIGHT;
  cfg->vmemsz    = VGA_WIDTH * VGA_HEIGHT * 4;
}

void __am_gpu_fbdraw(AM_GPU_FBDRAW_T *ctl) {
  int x = ctl->x, y = ctl->y;
  int w = ctl->w, h = ctl->h;
  uint32_t *pixels = (uint32_t *)ctl->pixels;

  if (pixels != NULL) {
    // 逐行把像素写入帧缓冲对应位置
    for (int j = 0; j < h; j++) {
      // 裁剪: 超出屏幕范围的行不写
      int yy = y + j;
      if (yy < 0 || yy >= VGA_HEIGHT) continue;
      // x 方向逐像素写 (便于裁剪); 帧缓冲按字编址
      for (int i = 0; i < w; i++) {
        int xx = x + i;
        if (xx < 0 || xx >= VGA_WIDTH) continue;
        VGABASE[yy * VGA_WIDTH + xx] = pixels[j * w + i];
      }
    }
  }
  // sync 字段: NVBoard 的 VGA 自动刷新, 无需处理
}

void __am_gpu_status(AM_GPU_STATUS_T *status) {
  // VGA 控制器持续扫描输出, 软件可随时写帧缓冲, 故恒就绪
  status->ready = true;
}
