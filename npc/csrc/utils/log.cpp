/***************************************************************************************
* NPC Log System
* 日志系统实现
***************************************************************************************/

#include "log.h"
#include "../core/npc.h"
#include <cstdio>
#include <cstdlib>
#include <cstdarg>
#include <cstring>
#include <ctime>
#include <unistd.h>

FILE *log_fp = NULL;

static int log_level = LOG_INFO;
static bool log_color_stdout = false;
static char log_buffer[1 << 20];
static const char *level_names[] = {"ERROR", "WARN", "INFO", "DEBUG"};

void log_set_level(int level) {
  log_level = level;
}

int log_get_level() {
  return log_level;
}

void init_log(const char *log_file) {
  const char *default_log = "npc.log";
  const char *actual_log_file = log_file ? log_file : default_log;

  FILE *fp = fopen(actual_log_file, "a");
  if (fp == NULL) {
    fprintf(stderr, "Can not open log file '%s', using stdout\n", actual_log_file);
    log_fp = stdout;
  } else {
    log_fp = fp;
    setvbuf(log_fp, log_buffer, _IOFBF, sizeof(log_buffer));
  }
  log_color_stdout = isatty(fileno(stdout));

  const char *env_level = getenv("NPC_LOG_LEVEL");
  if (env_level != NULL) {
    if (strcmp(env_level, "error") == 0) log_level = LOG_ERROR;
    else if (strcmp(env_level, "warn") == 0) log_level = LOG_WARN;
    else if (strcmp(env_level, "debug") == 0) log_level = LOG_DEBUG;
    else log_level = LOG_INFO;
  }

  time_t now = time(NULL);
  char tbuf[64] = {0};
  strftime(tbuf, sizeof(tbuf), "%Y-%m-%d %H:%M:%S", localtime(&now));
  fprintf(log_fp, "\n==================== NPC session start ==== %s ====================\n", tbuf);
  fflush(log_fp);

  Log("Log is appended to %s", actual_log_file);
}

void _Log(int level, const char *file, int line, const char *func,
          const char *format, ...) {
  if (level > log_level) return;

  char msg[4096];
  va_list args;
  va_start(args, format);
  vsnprintf(msg, sizeof(msg), format, args);
  va_end(args);

  const char *base = strrchr(file, '/');
  base = base ? base + 1 : file;

  uint64_t cyc = npc_get_cycle();
  uint64_t commit = npc_get_commit_count();
  uint64_t time = npc_get_time();

  const char *lvl = (level >= 0 && level <= LOG_DEBUG) ? level_names[level] : "INFO";

  if (log_fp != NULL && log_fp != stdout) {
    fprintf(log_fp, "[%s] [cyc=%llu commit=%llu time=%llu] [%s:%d %s] %s\n",
            lvl, (unsigned long long)cyc, (unsigned long long)commit,
            (unsigned long long)time, base, line, func, msg);
  }

  if (log_color_stdout) {
    printf("%s[%s] [cyc=%llu commit=%llu time=%llu] [%s:%d %s] %s%s\n",
           ANSI_FG_BLUE, lvl, (unsigned long long)cyc, (unsigned long long)commit,
           (unsigned long long)time, base, line, func, msg, ANSI_NONE);
  } else {
    printf("[%s] [cyc=%llu commit=%llu time=%llu] [%s:%d %s] %s\n",
           lvl, (unsigned long long)cyc, (unsigned long long)commit,
           (unsigned long long)time, base, line, func, msg);
  }
}

// 只写入日志文件，不输出到stdout；flush 由 log_flush() 统一完成
void log_write(const char *format, ...) {
  if (log_fp == NULL) return;
  va_list args;
  va_start(args, format);
  vfprintf(log_fp, format, args);
  va_end(args);
}

void log_flush() {
  if (log_fp != NULL) fflush(log_fp);
}

void log_trace_prefix_at(char *buf, size_t size, const char *tag,
                         uint32_t pc, uint64_t cycle, uint64_t commit, uint64_t time) {
  snprintf(buf, size, "[%s] cyc=%llu commit=%llu time=%llu pc=0x%08x ",
           tag, (unsigned long long)cycle, (unsigned long long)commit,
           (unsigned long long)time, pc);
}

void assert_fail_msg() {
  fprintf(stderr, ANSI_FMT("Assertion failed!\n", ANSI_FG_RED));
  fflush(stderr);
  log_flush();
}
