#include <am.h>
#include "ysyxsoc.h"

static uint64_t rdcycle() {
  uint32_t lo, hi;
  asm volatile("csrr %0, mcycle" : "=r"(lo));
  asm volatile("csrr %0, mcycleh" : "=r"(hi));
  return ((uint64_t)hi << 32) | lo;
}

void __am_timer_init() {
}

void __am_timer_uptime(AM_TIMER_UPTIME_T *uptime) {
  uptime->us = rdcycle() / CPU_FREQ_MHZ;
}

void __am_timer_rtc(AM_TIMER_RTC_T *rtc) {
  rtc->second = 0;
  rtc->minute = 0;
  rtc->hour   = 0;
  rtc->day    = 1;
  rtc->month  = 1;
  rtc->year   = 2026;
}
