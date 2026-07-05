// 最小 VGA 测试: 往帧缓冲写几个像素, 验证 VGA 数据通路.
// 像素格式 [23:16]=R [15:8]=G [7:0]=B
#define VGA_FB_BASE 0x21000000L

typedef unsigned int uint32_t;

void _start() {
  volatile uint32_t *fb = (volatile uint32_t *)VGA_FB_BASE;
  // 写 4 个像素: 红, 绿, 蓝, 白 (位于屏幕左上角)
  fb[0]                  = 0x00FF0000; // (0,0) 红
  fb[1]                  = 0x0000FF00; // (1,0) 绿
  fb[640]                = 0x000000FF; // (0,1) 蓝
  fb[641]                = 0x00FFFFFF; // (1,1) 白
  // 再写一条对角线
  for (int i = 0; i < 100; i++) {
    fb[i * 640 + i] = 0x00FFFF00; // 黄色对角线
  }
  while (1);
}
