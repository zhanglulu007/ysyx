/***************************************************************************************
* npc-trace - 文本转写 (M1)
*
* 由 trace.npct 生成可读文本视图, 是“二进制是 source of truth, 文本只是视图”的落地:
*   - legacy: 与仿真时写入 npc.log 的格式一致(0x.../「[MTRACE]」/「[FTRACE]」), 兼容
*             现有 grep 与脚本;
*   - rich:   统一 [cyc=.. commit=.. pc=..] 前缀, 便于人工关联阅读。
*
* 反汇编与函数名解析都在这里离线完成(采集侧只写 pc/inst/addr), 故本工具即使
* 没有 capstone/ELF 也能转写出不算美观但完整的文本。
***************************************************************************************/
#ifndef __NPC_TRACE_TEXT_H__
#define __NPC_TRACE_TEXT_H__

#include <cstdio>
#include <string>
#include <vector>

#include "trace/trace_event.h"

namespace npctrace {

struct TextOptions {
  bool rich = false;                       // false=legacy, true=rich
  std::vector<CycleRange> ranges;          // 二次过滤; 空 = 全部
  uint32_t types = kTraceCategoryAll;      // 类型二次过滤(含 itrace)
  std::string elf;                         // 符号表来源(空则不做函数名解析)
  bool disasm = true;                      // 是否调用 capstone 反汇编
};

// 把 trace 转写到 out。成功返回 true; 失败填 *err。
// *lines_out(可选)返回实际写出的行数, 便于与事件数核对。
bool transcribe(const std::string& trace_path, FILE* out,
                const TextOptions& opt, std::string* err,
                uint64_t* lines_out);

}  // namespace npctrace

#endif  // __NPC_TRACE_TEXT_H__
