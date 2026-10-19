/***************************************************************************************
* npc-trace - TUI 第一版 (M2)
*
* 行式交互浏览器: 以“指令”为单位组织时间轴, 每条指令下挂它关联的
* 访存/函数调用/CSR/异常/AXI/设备事件(按 commit_id 关联)。
*
* 支持: 指令流前后浏览、跳转、按类型过滤、按 PC/助记符/函数名搜索、事件详情。
* 无 TTY(批处理/管道)时退化为打印前 N 条, 不进入交互循环。
*
* 说明: 第一版一次性把 trace 读入内存; 长程序的分块/索引浏览在 M3。
***************************************************************************************/
#ifndef __NPC_TRACE_TUI_H__
#define __NPC_TRACE_TUI_H__

#include <string>
#include <vector>

#include "trace/trace_event.h"

namespace npctrace {

struct TuiOptions {
  std::string elf;                  // 符号表(可选)
  uint32_t types = kTraceCategoryAll;
  std::vector<CycleRange> ranges;   // 空 = 全部
  uint64_t max_insn = 0;            // 0 = 不限制(非 TTY 时打印上限见实现)
};

// 运行 TUI。返回 false 并填 *err 表示打开/读取失败。
bool run_tui(const std::string& trace_path, const TuiOptions& opt, std::string* err);

}  // namespace npctrace

#endif  // __NPC_TRACE_TUI_H__
