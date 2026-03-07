/***************************************************************************************
* NPC Log System
* 日志系统实现
***************************************************************************************/

#include "log.h"
#include <cstdio>
#include <cstdlib>
#include <cstdarg>
#include <cassert>

FILE *log_fp = NULL;

void init_log(const char *log_file) {
  // 默认日志文件名
  const char *default_log = "npc.log";
  const char *actual_log_file = log_file ? log_file : default_log;
  
  // 打开日志文件
  FILE *fp = fopen(actual_log_file, "w");
  if (fp == NULL) {
    fprintf(stderr, "Can not open log file '%s', using stdout\n", actual_log_file);
    log_fp = stdout;
  } else {
    log_fp = fp;
  }
  
  Log("Log is written to %s", actual_log_file);
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

void assert_fail_msg() {
  fprintf(stderr, ANSI_FMT("Assertion failed!\n", ANSI_FG_RED));
  fflush(stderr);
  if (log_fp != NULL) {
    fprintf(log_fp, "Assertion failed!\n");
    fflush(log_fp);
  }
}
