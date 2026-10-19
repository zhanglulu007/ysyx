/***************************************************************************************
* NPC TRACE - 命令行配置解析 (M0)
*
* 解析 `--trace-*` / `--log-*` 选项, 填充 TraceCliConfig。
* 设计要点:
*   - 只负责“解析”, 不启动任何采集(M1 才接 TraceManager);
*   - 显式 --trace=<类别> 才把 enabled 置 true, 因此不写任何 --trace-* 时
*     NPC 行为与 M0 之前完全一致(TRACE=1 时沿用旧 itrace/ftrace/mtrace);
*   - 同时支持 `--opt=value` 与 `--opt value`。
***************************************************************************************/
#ifndef __NPC_TRACE_CONFIG_H__
#define __NPC_TRACE_CONFIG_H__

#include <cstdint>
#include <string>
#include <vector>

#include "trace_event.h"

namespace npctrace {

struct TraceCliConfig {
  bool     enabled = false;          // 是否显式出现过 --trace=...
  uint32_t types = kTraceCategoryDefault;
  std::string types_str = "itrace,mtrace,ftrace";

  std::string out_file  = "trace.npct";
  TextMode    text_mode = TextMode::DEFERRED;
  std::string text_file = "npc.trace.log";

  OutsidePolicy outside = OutsidePolicy::RING;
  RangeUnit     range_unit = RangeUnit::CYCLE;
  uint64_t      ring_size = 1000000;
  uint32_t      sample = 1;
  bool          compress = true;
  bool          include_critical_outside = false;

  std::vector<CycleRange> ranges;

  // 日志
  std::string log_file;              // 空 = 沿用 -l / 默认 npc.log
  std::string log_level = "info";    // M0 仅记录, M3 才分级生效
  uint32_t    log_buffer_kb = 0;     // 0 = 默认缓冲
};

// argv[i] 是否为 trace/log 相关选项(不消费, 只判断)
bool is_trace_option(const char* arg);

// 尝试在位置 *i 解析一个选项。命中则消费(必要时消费下一项), 返回 true;
// 解析失败(参数缺失/非法)返回 false 并填 *err。
bool parse_trace_option(int argc, char** argv, int* i,
                        TraceCliConfig* cfg, std::string* err);

// 解析结束后的收尾: 范围排序合并、补默认值、一致性检查。
// 失败返回 false 并填 *err。
bool finalize_trace_config(TraceCliConfig* cfg, std::string* err);

// 供日志/配置摘要使用: 返回如 "itrace,mtrace,ftrace"
std::string trace_types_summary(uint32_t types);

// 人类可读的配置摘要(多行)
std::string trace_cli_summary(const TraceCliConfig& cfg);

}  // namespace npctrace

#endif  // __NPC_TRACE_CONFIG_H__
