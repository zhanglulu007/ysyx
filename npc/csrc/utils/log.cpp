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
#include <deque>
#include <string>

FILE *log_fp = NULL;

// 日志环形缓冲区
static std::deque<std::string> log_buffer;
static const size_t MAX_LOG_LINES = 100000;  // 最多保存10万行日志
static bool use_log_buffer = false;  // 是否使用缓冲区

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

// 只写入日志文件，不输出到stdout
void log_write(const char *format, ...) {
  char buffer[1024];
  va_list args;
  
  va_start(args, format);
  vsnprintf(buffer, sizeof(buffer), format, args);
  va_end(args);
  
  if (use_log_buffer) {
    // 使用环形缓冲区
    log_buffer.push_back(std::string(buffer));
    
    // 如果超过最大行数，删除最旧的
    if (log_buffer.size() > MAX_LOG_LINES) {
      log_buffer.pop_front();
    }
  } else {
    // 直接写入文件
    if (log_fp != NULL) {
      fprintf(log_fp, "%s", buffer);
      fflush(log_fp);
    }
  }
}

// 启用日志缓冲区
void enable_log_buffer() {
  use_log_buffer = true;
  log_buffer.clear();
}

// 禁用日志缓冲区并刷新到文件
void flush_log_buffer() {
  if (log_fp != NULL && use_log_buffer) {
    for (const auto& line : log_buffer) {
      fprintf(log_fp, "%s", line.c_str());
    }
    fflush(log_fp);
  }
  log_buffer.clear();
  use_log_buffer = false;
}

void assert_fail_msg() {
  fprintf(stderr, ANSI_FMT("Assertion failed!\n", ANSI_FG_RED));
  fflush(stderr);
  if (log_fp != NULL) {
    fprintf(log_fp, "Assertion failed!\n");
    fflush(log_fp);
  }
}
