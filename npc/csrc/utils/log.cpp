/***************************************************************************************
* NPC Log System
* 日志系统实现
***************************************************************************************/

#include "log.h"
#include <cstdint>

// 全局日志文件指针
FILE *log_fp = NULL;

// 全局指令计数器（用于条件日志）
extern uint64_t g_nr_inst;

// 初始化日志系统
void init_log(const char *log_file) {
  log_fp = stdout;
  
  if (log_file != NULL) {
    FILE *fp = fopen(log_file, "w");
    if (fp == NULL) {
      printf("Warning: Cannot open log file '%s', using stdout\n", log_file);
      log_fp = stdout;
    } else {
      log_fp = fp;
      Log("Log is written to %s", log_file);
    }
  } else {
    Log("Log is written to stdout");
  }
}

// 检查是否启用日志
bool log_enable() {
#ifdef CONFIG_LOG
  #ifdef CONFIG_LOG_START
    #ifdef CONFIG_LOG_END
      // 如果定义了起始和结束指令数，只在范围内记录
      return (g_nr_inst >= CONFIG_LOG_START) && (g_nr_inst <= CONFIG_LOG_END);
    #else
      // 只定义了起始指令数
      return g_nr_inst >= CONFIG_LOG_START;
    #endif
  #else
    // 没有定义范围，总是启用
    return true;
  #endif
#else
  return false;
#endif
}

// 关闭日志文件
void close_log() {
  if (log_fp != NULL && log_fp != stdout && log_fp != stderr) {
    fclose(log_fp);
    log_fp = NULL;
  }
}

