/***************************************************************************************
* NPC Log System
* 日志系统头文件
***************************************************************************************/

#ifndef __LOG_H__
#define __LOG_H__

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cassert>

// ANSI颜色代码
#define ANSI_FG_BLACK   "\33[1;30m"
#define ANSI_FG_RED     "\33[1;31m"
#define ANSI_FG_GREEN   "\33[1;32m"
#define ANSI_FG_YELLOW  "\33[1;33m"
#define ANSI_FG_BLUE    "\33[1;34m"
#define ANSI_FG_MAGENTA "\33[1;35m"
#define ANSI_FG_CYAN    "\33[1;36m"
#define ANSI_FG_WHITE   "\33[1;37m"
#define ANSI_BG_BLACK   "\33[1;40m"
#define ANSI_BG_RED     "\33[1;41m"
#define ANSI_BG_GREEN   "\33[1;42m"
#define ANSI_BG_YELLOW  "\33[1;43m"
#define ANSI_BG_BLUE    "\33[1;44m"
#define ANSI_BG_MAGENTA "\33[1;45m"
#define ANSI_BG_CYAN    "\33[1;46m"
#define ANSI_BG_WHITE   "\33[1;47m"
#define ANSI_NONE       "\33[0m"

#define ANSI_FMT(str, fmt) fmt str ANSI_NONE

// 日志文件指针
extern FILE* log_fp;

// 日志初始化
void init_log(const char *log_file);

// 日志使能检查
bool log_enable();

// 日志写入宏
#ifdef CONFIG_LOG
#define log_write(...) \
  do { \
    if (log_enable() && log_fp != NULL) { \
      fprintf(log_fp, __VA_ARGS__); \
      fflush(log_fp); \
    } \
  } while (0)
#else
#define log_write(...)
#endif

// 内部日志函数
#define _Log(...) \
  do { \
    printf(__VA_ARGS__); \
    log_write(__VA_ARGS__); \
  } while (0)

// Log宏 - 带文件名、行号、函数名
#define Log(format, ...) \
    _Log(ANSI_FMT("[%s:%d %s] " format, ANSI_FG_BLUE) "\n", \
        __FILE__, __LINE__, __func__, ## __VA_ARGS__)

// Assert宏 - 断言失败时打印错误信息
#define Assert(cond, format, ...) \
  do { \
    if (!(cond)) { \
      fflush(stdout); \
      fprintf(stderr, ANSI_FMT(format, ANSI_FG_RED) "\n", ## __VA_ARGS__); \
      if (log_fp) fflush(log_fp); \
      assert(cond); \
    } \
  } while (0)

// panic宏 - 直接触发断言失败
#define panic(format, ...) Assert(0, format, ## __VA_ARGS__)

// TODO宏 - 提示未实现的功能
#define TODO() panic("please implement me")

#endif

