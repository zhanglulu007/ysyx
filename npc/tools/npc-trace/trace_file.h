/***************************************************************************************
* npc-trace - trace.npct 读取层 (M0)
*
* M0 只实现“容器解析”: 校验 header、定位各 section、读取 meta.json。
* 事件/itrace 的解码与文本转写在 M1 实现(decode_event / text.cpp)。
***************************************************************************************/
#ifndef __NPC_TRACE_FILE_H__
#define __NPC_TRACE_FILE_H__

#include <cstdio>
#include <string>
#include <vector>

#include "trace/trace_event.h"

namespace npctrace {

struct TraceFile {
  TraceFileHeader header{};
  std::string      meta_json;        // meta 段原始文本
  std::vector<uint8_t> meta_raw;     // 便于 M1 直接解析

  // 打开并解析 header + meta。失败返回 false 并填 *err。
  bool open(const std::string& path, std::string* err);
  void close();

  const std::string& path() const { return path_; }

  FILE* fp = nullptr;
  ~TraceFile() { close(); }

 private:
  std::string path_;
};

// 打印 header 摘要(供 `npc-trace info`)
std::string format_header(const TraceFileHeader& h);

// 从 meta.json 文本里提取一个字符串字段值(极简解析, 够 M0 用)
std::string meta_field(const std::string& json, const std::string& key);

// 读取 summary 段(失败返回 false 并填 *err)
bool read_summary(const std::string& path, const TraceFileHeader& h,
                  TraceSummary* out, std::string* err);

// ── 流式读取(两个流各自按 cycle 单调递增, 供 text/export 归并) ─────────────
// 每个 reader 持有自己的 FILE*, 以免 itrace/event 两个流交替读时互相干扰。
struct ITraceEntry {
  uint32_t pc;
  uint32_t inst;
  uint64_t cycle;
  uint64_t commit_id;
};

// itrace delta 流解码器
class ITraceReader {
 public:
  ~ITraceReader() { if (fp_) fclose(fp_); }
  bool open(const std::string& path, const TraceFileHeader& h, std::string* err);
  bool next(ITraceEntry* out);          // false = 流结束
  uint64_t total() const { return total_; }
  uint64_t read() const { return read_; }
 private:
  FILE* fp_ = nullptr;
  uint64_t total_ = 0;
  uint64_t read_ = 0;
  uint32_t acc_pc_ = 0;
  uint64_t acc_cycle_ = 0;
  uint64_t acc_commit_ = 0;
  bool started_ = false;
};

// 定长事件流解码器
class EventReader {
 public:
  ~EventReader() { if (fp_) fclose(fp_); }
  bool open(const std::string& path, const TraceFileHeader& h, std::string* err);
  bool next(TraceEvent* out);
  uint64_t total() const { return total_; }
  uint64_t read() const { return read_; }
 private:
  FILE* fp_ = nullptr;
  uint64_t total_ = 0;
  uint64_t read_ = 0;
};

}  // namespace npctrace

#endif  // __NPC_TRACE_FILE_H__
