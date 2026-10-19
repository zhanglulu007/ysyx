/***************************************************************************************
* npc-trace - Chrome Trace 时间轴导出 (M1)
*
* 产出 Chrome Trace Event Format(JSON), 可直接用 chrome://tracing 或 Perfetto 打开。
* 最小实现: 每条 itrace / mem / ftrace 事件导出一个持续 1 cycle 的 "X" 事件,
* 分三个 lane(tid): 指令流 / 访存 / 函数调用。
*
* 关键: 所有事件都在 args 里带上 commit_id 与 pc, 使查看器中“选中一条指令”时
*       能凭 commit_id 关联到同一条指令的 mtrace/ftrace(实施计划 §5.2 / M1 验收)。
***************************************************************************************/
#ifndef __NPC_TRACE_EXPORT_CHROME_H__
#define __NPC_TRACE_EXPORT_CHROME_H__

#include <cstdio>
#include <string>
#include <vector>

#include "trace/trace_event.h"

namespace npctrace {

struct ChromeOptions {
  std::vector<CycleRange> ranges;        // 空 = 全部
  uint32_t types = kTraceCategoryAll;
  bool pretty = false;                   // 是否缩进(默认单行, 体积更小)
};

// 导出为 Chrome Trace JSON。成功返回 true; *events_out 返回写出的时间轴事件数。
bool export_chrome(const std::string& trace_path, FILE* out,
                   const ChromeOptions& opt, std::string* err,
                   uint64_t* events_out);

}  // namespace npctrace

#endif  // __NPC_TRACE_EXPORT_CHROME_H__
