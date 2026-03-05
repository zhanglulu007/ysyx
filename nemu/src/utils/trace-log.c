/***************************************************************************************
* Copyright (c) 2014-2024 Zihao Yu, Nanjing University
*
* NEMU is licensed under Mulan PSL v2.
* You can use this software according to the terms and conditions of the Mulan PSL v2.
* You may obtain a copy of Mulan PSL v2 at:
*          http://license.coscl.org.cn/MulanPSL2
*
* THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
* EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
* MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
*
* See the Mulan PSL v2 for more details.
***************************************************************************************/

#include <common.h>
#include <stdarg.h>

#ifndef CONFIG_TARGET_AM

// 不同类型的 trace 日志文件指针
static FILE *itrace_fp = NULL;
static FILE *mtrace_fp = NULL;
static FILE *ftrace_fp = NULL;

// 主日志文件指针（用于混合输出模式）
extern FILE *log_fp;
extern uint64_t g_nr_guest_inst;

// 是否启用分离日志文件
static bool separate_logs = true;

/**
 * init_trace_log() - 初始化 trace 日志系统
 * 
 * @log_dir: 日志文件目录，如果为 NULL 则使用默认的 build 目录
 * @separate: 是否将不同类型的 trace 分离到不同文件
 * 
 * 这个函数会创建以下日志文件：
 * - itrace.txt: 指令追踪日志
 * - mtrace.txt: 内存访问追踪日志
 * - ftrace.txt: 函数调用追踪日志
 * 
 * 如果 separate 为 false，所有 trace 都会输出到主日志文件
 */
void init_trace_log(const char *log_dir, bool separate) {
  separate_logs = separate;
  
  if (!separate) {
    Log("Trace logs will be written to the main log file");
    return;
  }
  
  // 使用默认目录
  const char *dir = log_dir ? log_dir : "build";
  
  char path[256];
  
#ifdef CONFIG_ITRACE
  // 创建 itrace 日志文件
  snprintf(path, sizeof(path), "%s/itrace.txt", dir);
  itrace_fp = fopen(path, "w");
  if (itrace_fp) {
    Log("Instruction trace will be written to %s", path);
  } else {
    Log("Warning: Failed to open %s, using main log", path);
  }
#endif

#ifdef CONFIG_MTRACE
  // 创建 mtrace 日志文件
  snprintf(path, sizeof(path), "%s/mtrace.txt", dir);
  mtrace_fp = fopen(path, "w");
  if (mtrace_fp) {
    Log("Memory trace will be written to %s", path);
  } else {
    Log("Warning: Failed to open %s, using main log", path);
  }
#endif

#ifdef CONFIG_FTRACE
  // 创建 ftrace 日志文件
  snprintf(path, sizeof(path), "%s/ftrace.txt", dir);
  ftrace_fp = fopen(path, "w");
  if (ftrace_fp) {
    Log("Function trace will be written to %s", path);
  } else {
    Log("Warning: Failed to open %s, using main log", path);
  }
#endif
}

/**
 * trace_log_enable() - 检查是否应该输出 trace
 * 
 * 根据配置的 trace 时间窗口判断是否应该输出
 */
static inline bool trace_log_enable() {
  return MUXDEF(CONFIG_TRACE, 
    (g_nr_guest_inst >= CONFIG_TRACE_START) && 
    (g_nr_guest_inst <= CONFIG_TRACE_END), 
    false);
}

/**
 * itrace_write() - 写入指令追踪日志
 */
void itrace_write(const char *fmt, ...) {
  if (!trace_log_enable()) return;
  
  FILE *fp = (separate_logs && itrace_fp) ? itrace_fp : log_fp;
  if (fp == NULL) return;
  
  va_list ap;
  va_start(ap, fmt);
  vfprintf(fp, fmt, ap);
  va_end(ap);
  fflush(fp);
}

/**
 * mtrace_write() - 写入内存追踪日志
 */
void mtrace_write(const char *fmt, ...) {
  if (!trace_log_enable()) return;
  
  FILE *fp = (separate_logs && mtrace_fp) ? mtrace_fp : log_fp;
  if (fp == NULL) return;
  
  va_list ap;
  va_start(ap, fmt);
  vfprintf(fp, fmt, ap);
  va_end(ap);
  fflush(fp);
}

/**
 * ftrace_write() - 写入函数追踪日志
 */
void ftrace_write(const char *fmt, ...) {
  if (!trace_log_enable()) return;
  
  FILE *fp = (separate_logs && ftrace_fp) ? ftrace_fp : log_fp;
  if (fp == NULL) return;
  
  va_list ap;
  va_start(ap, fmt);
  vfprintf(fp, fmt, ap);
  va_end(ap);
  fflush(fp);
}

/**
 * close_trace_logs() - 关闭所有 trace 日志文件
 */
void close_trace_logs() {
  if (itrace_fp) {
    fclose(itrace_fp);
    itrace_fp = NULL;
  }
  if (mtrace_fp) {
    fclose(mtrace_fp);
    mtrace_fp = NULL;
  }
  if (ftrace_fp) {
    fclose(ftrace_fp);
    ftrace_fp = NULL;
  }
}

#endif // CONFIG_TARGET_AM
