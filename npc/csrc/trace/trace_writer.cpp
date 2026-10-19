/***************************************************************************************
* NPC TRACE - 二进制写入器实现 (M1)
***************************************************************************************/
#include "trace_writer.h"

#include <cstring>
#include <unistd.h>

namespace npctrace {

namespace {

// 把一个临时文件的内容整体拷贝到 out。失败返回 false。
bool append_file(FILE* out, const std::string& path) {
  FILE* in = fopen(path.c_str(), "rb");
  if (in == nullptr) return false;
  char buf[64 * 1024];
  size_t n;
  bool ok = true;
  while ((n = fread(buf, 1, sizeof(buf), in)) > 0) {
    if (fwrite(buf, 1, n, out) != n) { ok = false; break; }
  }
  if (ferror(in)) ok = false;
  fclose(in);
  return ok;
}

}  // namespace

BinaryWriter::~BinaryWriter() {
  if (events_fp_) fclose(events_fp_);
  if (itrace_fp_) fclose(itrace_fp_);
  if (index_fp_)  fclose(index_fp_);
  if (opened_) {
    // 未 close() 就析构: 清掉临时文件, 不留下半截产物
    unlink(tmp_events_.c_str());
    unlink(tmp_itrace_.c_str());
    unlink(tmp_index_.c_str());
  }
}

bool BinaryWriter::open(const std::string& path, const TraceMeta& meta,
                        std::string* err) {
  if (opened_) { *err = "writer already open"; return false; }
  path_ = path;
  meta_ = meta;

  tmp_events_ = path + ".tmp.events";
  tmp_itrace_ = path + ".tmp.itrace";
  tmp_index_  = path + ".tmp.index";

  events_fp_ = fopen(tmp_events_.c_str(), "wb");
  itrace_fp_ = fopen(tmp_itrace_.c_str(), "wb");
  index_fp_  = fopen(tmp_index_.c_str(), "wb");
  if (!events_fp_ || !itrace_fp_ || !index_fp_) {
    *err = "cannot create temporary files next to '" + path + "'";
    return false;
  }

  meta_size_ = 0;
  event_count_ = itrace_count_ = index_count_ = dropped_count_ = 0;
  last_pc_ = 0; last_cycle_ = 0; last_commit_ = 0;
  itrace_started_ = false;
  opened_ = true;
  return true;
}

void BinaryWriter::write_event(const TraceEvent& ev) {
  if (!opened_) return;

  // 每 TRACE_INDEX_INTERVAL 条事件记一个索引项(指向事件区内的偏移)
  if (event_count_ % TRACE_INDEX_INTERVAL == 0) {
    TraceIndexEntry ie{};
    ie.seq = ev.seq;
    ie.cycle = ev.cycle;
    ie.commit_id = ev.commit_id;
    ie.range_id = index_range_id_;
    ie.offset = event_count_ * TRACE_EVENT_SIZE;
    fwrite(&ie, sizeof(ie), 1, index_fp_);
    index_count_++;
  }

  fwrite(&ev, sizeof(ev), 1, events_fp_);
  event_count_++;

  if (event_count_ == 1) {
    // 首条事件决定 summary 的时间范围
    summary_first_cycle_ = ev.cycle;
    summary_first_commit_ = ev.commit_id;
  }
  if (ev.cycle >= summary_last_cycle_) summary_last_cycle_ = ev.cycle;
  if (ev.commit_id >= summary_last_commit_) summary_last_commit_ = ev.commit_id;
}

void BinaryWriter::write_itrace(uint32_t pc, uint32_t inst,
                                uint64_t cycle, uint64_t commit_id) {
  if (!opened_) return;

  ITraceRecord rec{};
  if (!itrace_started_) {
    rec.pc_delta = pc;
    rec.cycle_delta = (uint32_t)cycle;
    rec.commit_delta = (uint32_t)commit_id;
    itrace_started_ = true;
  } else {
    rec.pc_delta = pc - last_pc_;
    rec.cycle_delta = (uint32_t)(cycle - last_cycle_);
    rec.commit_delta = (uint32_t)(commit_id - last_commit_);
  }
  rec.inst = inst;

  fwrite(&rec, sizeof(rec), 1, itrace_fp_);
  itrace_count_++;

  last_pc_ = pc;
  last_cycle_ = cycle;
  last_commit_ = commit_id;
}

bool BinaryWriter::close() {
  if (!opened_) return true;

  // 关掉临时写句柄
  if (events_fp_) { fclose(events_fp_); events_fp_ = nullptr; }
  if (itrace_fp_) { fclose(itrace_fp_); itrace_fp_ = nullptr; }
  if (index_fp_)  { fclose(index_fp_);  index_fp_ = nullptr; }

  std::string tmp_final = path_ + ".tmp.final";
  FILE* out = fopen(tmp_final.c_str(), "wb");
  if (out == nullptr) {
    last_error_ = "cannot create '" + tmp_final + "'";
    return false;
  }

  // 先占位写 header, 各段偏移随后回填
  TraceFileHeader h{};
  memcpy(h.magic, TRACE_MAGIC_STR, TRACE_MAGIC_LEN);
  h.version = TRACE_VERSION;
  h.endian = TRACE_ENDIAN_ID;
  h.header_size = sizeof(TraceFileHeader);
  h.config_hash = 0;
  h.index_interval = TRACE_INDEX_INTERVAL;
  h.event_count = event_count_;
  h.itrace_count = itrace_count_;

  if (fwrite(&h, sizeof(h), 1, out) != 1) { last_error_ = "write header"; fclose(out); return false; }

  // meta.json
  std::string meta_json = meta_to_json(meta_);
  meta_size_ = meta_json.size();
  h.meta_off = sizeof(TraceFileHeader);
  h.meta_size = meta_size_;                    // 必须回填, 否则读回看不到 meta
  if (fwrite(meta_json.data(), 1, meta_json.size(), out) != meta_json.size()) {
    last_error_ = "write meta"; fclose(out); return false;
  }

  // itrace
  h.itrace_off = h.meta_off + h.meta_size;
  h.itrace_size = itrace_count_ * TRACE_ITRACE_SIZE;
  if (!append_file(out, tmp_itrace_)) { last_error_ = "append itrace"; fclose(out); return false; }

  // events
  h.events_off = h.itrace_off + h.itrace_size;
  h.events_size = event_count_ * TRACE_EVENT_SIZE;
  if (!append_file(out, tmp_events_)) { last_error_ = "append events"; fclose(out); return false; }

  // index
  h.index_off = h.events_off + h.events_size;
  h.index_size = index_count_ * TRACE_INDEX_SIZE;
  if (!append_file(out, tmp_index_)) { last_error_ = "append index"; fclose(out); return false; }

  // dict (M1 暂无) -> summary
  h.dict_off = h.index_off + h.index_size;
  h.dict_size = 0;

  TraceSummary sum{};
  sum.event_count = event_count_;
  sum.itrace_count = itrace_count_;
  sum.dropped_count = dropped_count_;
  sum.ring_count = ring_count_;
  sum.first_cycle = summary_first_cycle_;
  sum.last_cycle = summary_last_cycle_;
  sum.first_commit = summary_first_commit_;
  sum.last_commit = summary_last_commit_;
  sum.range_count = (uint32_t)meta_.ranges.size();
  sum.reserved = 0;

  h.summary_off = h.dict_off;
  h.summary_size = sizeof(TraceSummary);
  if (fwrite(&sum, sizeof(sum), 1, out) != 1) { last_error_ = "write summary"; fclose(out); return false; }

  // 回填 header
  if (fseek(out, 0, SEEK_SET) != 0 || fwrite(&h, sizeof(h), 1, out) != 1) {
    last_error_ = "rewrite header"; fclose(out); return false;
  }
  if (fclose(out) != 0) { last_error_ = "close output"; return false; }

  // 原子替换
  if (rename(tmp_final.c_str(), path_.c_str()) != 0) {
    last_error_ = "rename to '" + path_ + "' failed";
    unlink(tmp_final.c_str());
    return false;
  }

  unlink(tmp_events_.c_str());
  unlink(tmp_itrace_.c_str());
  unlink(tmp_index_.c_str());
  opened_ = false;
  return true;
}

}  // namespace npctrace
