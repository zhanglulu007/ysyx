#include <am.h>
#include <klib-macros.h>
#include "ysyxsoc.h"

/* CLINT 在 NPC 内部，位于 0x0200_0000 ~ 0x0200_ffff
 * mtime    偏移 0xBFF8 (64-bit)
 * mtimecmp 偏移 0x4000 (64-bit)
 */
#define CLINT_BASE       0x02000000
#define CLINT_MTIME_LO   (CLINT_BASE + 0xBFF8)
#define CLINT_MTIME_HI   (CLINT_BASE + 0xBFFC)

static uint64_t boot_time = 0;

void __am_timer_init() {
  boot_time  = (uint64_t)inl(CLINT_MTIME_LO);
  boot_time |= (uint64_t)inl(CLINT_MTIME_HI) << 32;
}

void __am_timer_uptime(AM_TIMER_UPTIME_T *uptm) {
  uint64_t now  = (uint64_t)inl(CLINT_MTIME_LO);
  now          |= (uint64_t)inl(CLINT_MTIME_HI) << 32;
  uptm->us      = now - boot_time;
}

void __am_timer_rtc(AM_TIMER_RTC_T *rtc) {
  rtc->year   = 0;
  rtc->month  = 0;
  rtc->day    = 0;
  rtc->hour   = 0;
  rtc->minute = 0;
  rtc->second = 0;
}