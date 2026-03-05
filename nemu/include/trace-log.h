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

#ifndef __TRACE_LOG_H__
#define __TRACE_LOG_H__

#include <common.h>

#ifndef CONFIG_TARGET_AM

// 初始化 trace 日志系统
void init_trace_log(const char *log_dir, bool separate);

// 不同类型的 trace 写入函数
void itrace_write(const char *fmt, ...);
void mtrace_write(const char *fmt, ...);
void ftrace_write(const char *fmt, ...);

// 关闭所有 trace 日志文件
void close_trace_logs();

#endif // CONFIG_TARGET_AM

#endif // __TRACE_LOG_H__
