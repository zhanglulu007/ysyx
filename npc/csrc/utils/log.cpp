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
  log_fp = stdout;
  if (log_file != NULL) {
    FILE *fp = fopen(log_file, "w");
    if (fp == NULL) {
      fprintf(stderr, "Can not open log file '%s'\n", log_file);
      exit(1);
    }
    log_fp = fp;
  }
  Log("Log is written to %s", log_file ? log_file : "stdout");
}

void _Log(const char *format, ...) {
  va_list args;
  
  // 输出到stdout
  va_start(args, format);
  vprintf(format, args);
  va_end(args);
  
  // 输出到日志文件
  if (log_fp != NULL && log_fp != stdout) {
    va_start(args, format);
    vfprintf(log_fp, format, args);
    va_end(args);
    fflush(log_fp);
  }
}

void assert_fail_msg() {
  fprintf(stderr, ANSI_FMT("Assertion failed!\n", ANSI_FG_RED));
  fflush(stderr);
  if (log_fp != NULL) {
    fprintf(log_fp, "Assertion failed!\n");
    fflush(log_fp);
  }
}
