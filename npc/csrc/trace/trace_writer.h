/***************************************************************************************
* NPC TRACE - 二进制写入器 (M1)
*
* 把事件流写成 trace.npct。文件布局见实施计划 §6:
*
*   header | meta.json | itrace(delta 16B) | events(定长 64B) | index | summary
*
* 实现要点:
*   - itrace 与 events 是两个独立流, 但会交错产生, 因此各自先写到临时文件,
*     close() 时按上述顺序拼接并回填 header 偏移; 内存占用 O(1), 可支撑长程序。
*   - index 每 TRACE_INDEX_INTERVAL 条事件一项, 便于查看器按 cycle/commit 定位。
*   - 任何一步失败都会在 *err 中给出可读原因, 且不留下半截正式文件。
***************************************************************************************/
#ifndef __NPC_TRACE_WRITER_H__
#define __NPC_TRACE_WRITER_H__

#include <cstdio>
#include <string>

#include "trace_event.h"

namespace npctrace {

class BinaryWriter {
 public:
  BinaryWriter() = default;
  ~BinaryWriter();

  BinaryWriter(const BinaryWriter&) = delete;
  BinaryWriter& operator=(const BinaryWriter&) = delete;

  // 打开输出。meta 会被序列化进 meta 区。失败返回 false 并填 *err。
  bool open(const std::string& path, const TraceMeta& meta, std::string* err);

  // 写入一条通用事件(定长 64B), 并在跨过索引间隔时补一条索引。
  void write_event(const TraceEvent& ev);

  // 写入一条 itrace delta 记录。pc/cycle/commit 与上一条的差值会被编码。
  void write_itrace(uint32_t pc, uint32_t inst, uint64_t cycle, uint64_t commit_id);

  // 拼接各段、回填 header、删除临时文件。幂等; 返回是否成功。
  bool close();

  uint64_t event_count() const { return event_count_; }
  uint64_t itrace_count() const { return itrace_count_; }
  uint64_t dropped_count() const { return dropped_count_; }
  void     note_dropped(uint64_t n = 1) { dropped_count_ += n; }

  // 写入下一条索引项时使用的 range id(由 TraceManager 在切换范围时设置)。
  void set_index_range_id(uint32_t id) { index_range_id_ = id; }

  bool     is_open() const { return opened_; }
  const std::string& path() const { return path_; }
  const std::string& last_error() const { return last_error_; }

 private:
  bool     opened_ = false;
  uint32_t index_range_id_ = 0;

  std::string path_;
  std::string tmp_events_;
  std::string tmp_itrace_;
  std::string tmp_index_;
  std::string last_error_;

  FILE* events_fp_ = nullptr;
  FILE* itrace_fp_ = nullptr;
  FILE* index_fp_  = nullptr;

  TraceMeta meta_;
  uint64_t  meta_size_ = 0;

  uint64_t event_count_  = 0;
  uint64_t itrace_count_ = 0;
  uint64_t index_count_  = 0;
  uint64_t dropped_count_ = 0;
  uint64_t ring_count_   = 0;

  // summary 的时间/提交范围
  uint64_t summary_first_cycle_ = 0;
  uint64_t summary_last_cycle_  = 0;
  uint64_t summary_first_commit_ = 0;
  uint64_t summary_last_commit_  = 0;

  // itrace delta 编码基准
  uint32_t last_pc_     = 0;
  uint64_t last_cycle_  = 0;
  uint64_t last_commit_ = 0;
  bool     itrace_started_ = false;

  uint64_t dropped_at_last_index_ = 0;
};

}  // namespace npctrace

#endif  // __NPC_TRACE_WRITER_H__
