#include <am.h>

void __am_gpu_init() {
}

void __am_gpu_config(AM_GPU_CONFIG_T *cfg) {
  cfg->present  = false;
  cfg->has_accel = false;
  cfg->width    = 0;
  cfg->height   = 0;
  cfg->vmemsz   = 0;
}

void __am_gpu_fbdraw(AM_GPU_FBDRAW_T *ctl) {
}

void __am_gpu_status(AM_GPU_STATUS_T *status) {
  status->ready = false;
}