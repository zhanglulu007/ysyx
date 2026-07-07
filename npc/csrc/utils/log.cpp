/***************************************************************************************
* NPC Log System
* 日志系统实现
***************************************************************************************/

#include "log.h"
#include <cstdio>
#include <cstdlib>
#include <cstdarg>
#include <cassert>
#include <string.h>
#include <ctime>

FILE *log_fp = NULL;

void init_log(const char *log_file) {
  // 默认日志文件名
  const char *default_log = "npc.log";
  const char *actual_log_file = log_file ? log_file : default_log;

  // 以追加模式打开日志文件: 多次运行的日志累积在同一文件中, 不覆盖历史.
  FILE *fp = fopen(actual_log_file, "a");
  if (fp == NULL) {
    fprintf(stderr, "Can not open log file '%s', using stdout\n", actual_log_file);
    log_fp = stdout;
  } else {
    log_fp = fp;
  }

  // 写入本次运行的会话分隔标记, 便于在追加日志中区分多次运行.
  time_t now = time(NULL);
  char tbuf[64] = {0};
  strftime(tbuf, sizeof(tbuf), "%Y-%m-%d %H:%M:%S", localtime(&now));
  fprintf(log_fp, "\n==================== NPC session start ==== %s ====================\n", tbuf);
  fflush(log_fp);

  Log("Log is appended to %s", actual_log_file);
}

void _Log(const char *format, ...) {
  va_list args;

  // 输出到日志文件
  if (log_fp != NULL) {
    va_start(args, format);
    vfprintf(log_fp, format, args);
    va_end(args);
    fflush(log_fp);
  }

  // 同时输出到stdout（用户可见）
  va_start(args, format);
  vprintf(format, args);
  va_end(args);
}

// 只写入日志文件，不输出到stdout (trace 行实时落盘)
void log_write(const char *format, ...) {
  if (log_fp == NULL) return;
  va_list args;
  va_start(args, format);
  vfprintf(log_fp, format, args);
  va_end(args);
  fflush(log_fp);   // 实时落盘, 追加模式下保证不丢失
}

// 兼容接口: 已不再使用内存缓冲, 保留为空操作
void enable_log_buffer() {
  // no-op: 日志已实时写入文件, 无需缓冲
}

void flush_log_buffer() {
  // no-op: 日志已实时写入文件, 无需刷新
}

void assert_fail_msg() {
  fprintf(stderr, ANSI_FMT("Assertion failed!\n", ANSI_FG_RED));
  fflush(stderr);
  if (log_fp != NULL) {
    fprintf(log_fp, "Assertion failed!\n");
    fflush(log_fp);
  }
}
