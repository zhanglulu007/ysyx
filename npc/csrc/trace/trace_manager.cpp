/***************************************************************************************
* NPC TRACE - 事件管理器实现 (M1)
***************************************************************************************/
#include "trace_manager.h"

#include <cstdio>
#include <cstring>
#include <sstream>

#include "../core/npc.h"

namespace npctrace {

TraceManager& TraceManager::instance() {
  static TraceManager mgr;
  return mgr;
}

bool TraceManager::init(const TraceCliConfig& cfg, const TraceMeta& meta,
                        std::string* err) {
  if (enabled_) { *err = "TraceManager already initialized"; return false; }

  ranges_ = cfg.ranges;
  normalize_ranges(ranges_);          // 幂等: 已归一化的输入保持稳定
  range_unit_ = cfg.range_unit;
  outside_ = cfg.outside;
  types_ = cfg.types;
  sample_ = cfg.sample ? cfg.sample : 1;
  include_crit_outside_ = cfg.include_critical_outside;
  sample_counter_ = 0;

  TraceMeta m = meta;
  m.ranges = ranges_;                 // meta 与生效范围保持一致
  m.trace_types = cfg.types_str;
  m.text_mode = cfg.text_mode;
  m.outside = cfg.outside;
  m.range_unit = cfg.range_unit;
  m.ring_size = cfg.ring_size;

  if (!writer_.open(cfg.out_file, m, err)) return false;

  last_inside_ = false;
  cur_range_id_ = 0;
  next_seq_ = 0;
  stat_ring_ = 0;
  ring_cap_ = cfg.ring_size;
  snap_meta_ = m;
  snap_done_ = false;
  ring_.clear();
  enabled_ = true;
  return true;
}

void TraceManager::shutdown() {
  if (!enabled_) return;
  // 若结束时仍在范围内, 补一个 RANGE_END marker
  if (last_inside_ && cur_range_id_ != 0) {
    write_marker(TT_RANGE_END, cur_range_id_, 0, 0, 0);
  }
  writer_.close();
  enabled_ = false;
}

uint64_t TraceManager::axis_value(uint64_t cycle, uint64_t commit_id) const {
  return range_unit_ == RangeUnit::COMMIT ? commit_id : cycle;
}

bool TraceManager::pass_range(uint64_t cycle, uint64_t commit_id, uint32_t pc) {
  if (ranges_.empty()) {
    // 全量: 不产生 marker
    return true;
  }

  const uint64_t v = axis_value(cycle, commit_id);
  const CycleRange* r = find_range(ranges_, v);
  const bool inside = (r != nullptr);

  if (inside) {
    if (!last_inside_) {
      cur_range_id_ = r->id;
      writer_.set_index_range_id(r->id);
      write_marker(TT_RANGE_BEGIN, r->id, pc, cycle, commit_id);
      last_inside_ = true;
    } else if (cur_range_id_ != r->id) {
      // 相邻范围切换: 补 END(用最后一个范围内 cycle) + BEGIN
      write_marker(TT_RANGE_END, cur_range_id_, pc, last_inside_cycle_, commit_id);
      cur_range_id_ = r->id;
      writer_.set_index_range_id(r->id);
      write_marker(TT_RANGE_BEGIN, r->id, pc, cycle, commit_id);
    }
    // END marker 用最后一个范围内的 cycle, 使二次按 cycle 过滤时 BEGIN/END 成对保留
    last_inside_cycle_ = cycle;
  } else if (last_inside_) {
    write_marker(TT_RANGE_END, cur_range_id_, pc, last_inside_cycle_, commit_id);
    last_inside_ = false;
  }
  return inside;
}

bool TraceManager::keep_outside(const TraceEvent& ev) const {
  switch (outside_) {
    case OutsidePolicy::DROP:
      return false;
    case OutsidePolicy::CRITICAL:
      // 关键事件: 异常/中断/mret/ebreak/access fault/difftest 失败
      switch (ev.type) {
        case TT_ETRACE_EXCEPTION:
        case TT_ETRACE_INTERRUPT:
        case TT_ETRACE_MRET:
        case TT_ETRACE_EBREAK:
        case TT_DIFFTEST_STEP:
        case TT_DIFFTEST_SKIP:
          return true;
        default:
          return (ev.flags & TF_CRITICAL) != 0;
      }
    case OutsidePolicy::RING:
    default:
      // M1: ring 尚未实现, 范围外一律不写主 trace(失败快照在 M2)。
      // include_critical_outside 打开时, 关键事件仍写入。
      if (include_crit_outside_ && (ev.flags & TF_CRITICAL)) return true;
      return false;
  }
}

void TraceManager::write_marker(TraceType t, uint32_t range_id,
                                uint32_t pc, uint64_t cycle, uint64_t commit_id) {
  TraceEvent ev{};
  ev.seq = next_seq_++;
  ev.cycle = cycle;
  ev.commit_id = commit_id;
  ev.pc = pc;
  ev.type = static_cast<uint16_t>(t);
  ev.aux = range_id;
  writer_.write_event(ev);
}

void TraceManager::emit_itrace(uint32_t pc, uint32_t inst,
                               uint64_t cycle, uint64_t commit_id) {
  if (!enabled_) return;
  if (!(types_ & TCAT_ITRACE)) return;

  // ring: 先记录(不受 range/sample 影响), 失败时可用于回放
  ring_push_itrace(pc, inst, cycle, commit_id);

  if (!pass_range(cycle, commit_id, pc)) return;

  // 采样: 每 sample_ 条保留一条
  if (sample_ > 1) {
    if ((sample_counter_++ % sample_) != 0) return;
  }
  writer_.write_itrace(pc, inst, cycle, commit_id);
}

void TraceManager::on_commit(uint32_t pc, uint32_t inst,
                             uint64_t cycle, uint64_t commit_id) {
  emit_itrace(pc, inst, cycle, commit_id);
}

void TraceManager::emit(TraceEvent& ev) {
  if (!enabled_) return;

  // 1. type 过滤
  if (!(types_ & category_of(static_cast<TraceType>(ev.type)))) return;

  // ring: 先记录(不受 range/sample 影响)
  ring_push_event(ev);

  // 2. range 过滤(含边界 marker)
  const bool inside = pass_range(ev.cycle, ev.commit_id, ev.pc);
  if (!inside) {
    if (!keep_outside(ev)) { writer_.note_dropped(); return; }
    ev.flags |= TF_RING;
    stat_ring_++;
  }

  // 3. 采样
  if (sample_ > 1 && !(ev.flags & TF_CRITICAL)) {
    if ((sample_counter_++ % sample_) != 0) { writer_.note_dropped(); return; }
  }

  // 4. 落盘
  ev.seq = next_seq_++;
  writer_.write_event(ev);
}

void TraceManager::flush() {
  // M1 即时写盘, 无需 flush。
}

// ── 动态范围(SDB, §5.4) ────────────────────────────────────────────────────
// 范围变化会让 id 重编, 因此每次都先闭合当前区间并重置 last_inside_,
// 使下一个事件重新触发 RANGE_BEGIN marker。
bool TraceManager::dyn_range_add(uint64_t begin, uint64_t end, std::string* err) {
  CycleRange r{begin, end, 0};
  if (!range_valid(r)) {
    if (err) *err = "invalid range (begin must be < end; end==0 means open)";
    return false;
  }
  if (last_inside_ && cur_range_id_ != 0) {
    write_marker(TT_RANGE_END, cur_range_id_, 0, last_inside_cycle_, 0);
  }
  ranges_.push_back(r);
  normalize_ranges(ranges_);
  last_inside_ = false;
  cur_range_id_ = 0;
  return true;
}

void TraceManager::dyn_range_clear() {
  if (last_inside_ && cur_range_id_ != 0) {
    write_marker(TT_RANGE_END, cur_range_id_, 0, last_inside_cycle_, 0);
  }
  ranges_.clear();
  last_inside_ = false;
  cur_range_id_ = 0;
  writer_.set_index_range_id(0);
}

void TraceManager::dyn_range_start(uint64_t now) {
  std::string err;
  dyn_range_add(now, 0, &err);   // [now, +inf)
}

void TraceManager::dyn_range_stop(uint64_t now) {
  // 闭合最近一个开放(end==0)的范围; 没有则从 0 到 now
  if (last_inside_ && cur_range_id_ != 0) {
    write_marker(TT_RANGE_END, cur_range_id_, 0, last_inside_cycle_, 0);
  }
  bool closed = false;
  for (auto it = ranges_.rbegin(); it != ranges_.rend(); ++it) {
    if (it->end == 0) { it->end = now; closed = true; break; }
  }
  if (!closed) ranges_.push_back(CycleRange{0, now, 0});
  normalize_ranges(ranges_);
  last_inside_ = false;
  cur_range_id_ = 0;
}

std::string TraceManager::status_string() const {
  std::ostringstream os;
  os << "trace: " << (enabled_ ? "ON" : "OFF");
  if (enabled_) os << ", out=" << writer_.path();
  os << "\n";
  os << "  events=" << writer_.event_count()
     << " itrace=" << writer_.itrace_count()
     << " dropped=" << writer_.dropped_count() << "\n";
  os << "  ranges(" << range_unit_name(range_unit_) << ")="
     << (ranges_.empty() ? "(full)" : std::to_string(ranges_.size()))
     << ", outside=" << outside_policy_name(outside_)
     << ", sample=" << sample_ << "\n";
  os << "  inflight_commit=" << inflight_commit_;
  return os.str();
}

std::string TraceManager::range_list_string() const {
  if (ranges_.empty()) return "(full: no ranges, tracing everything)";
  std::ostringstream os;
  for (size_t i = 0; i < ranges_.size(); i++) {
    const CycleRange& r = ranges_[i];
    os << "  #" << r.id << " [" << r.begin << ", ";
    if (r.end == 0) os << "inf";
    else os << r.end;
    os << ")";
    if (i + 1 < ranges_.size()) os << "\n";
  }
  return os.str();
}

// ── ring buffer + 失败快照(§5.5) ───────────────────────────────────────────
void TraceManager::ring_push(const RingItem& it) {
  if (ring_cap_ == 0) return;
  while (ring_.size() >= ring_cap_) ring_.pop_front();
  ring_.push_back(it);
}

void TraceManager::ring_push_event(const TraceEvent& ev) {
  if (ring_cap_ == 0) return;
  RingItem it{};
  it.is_itrace = false;
  it.pc = ev.pc; it.inst = ev.data; it.addr = ev.addr;
  it.type = ev.type; it.flags = ev.flags; it.len = ev.len;
  it.channel = ev.channel; it.region = ev.region;
  it.cycle = ev.cycle; it.commit_id = ev.commit_id;
  ring_push(it);
}

void TraceManager::ring_push_itrace(uint32_t pc, uint32_t inst,
                                    uint64_t cycle, uint64_t commit_id) {
  if (ring_cap_ == 0) return;
  RingItem it{};
  it.is_itrace = true;
  it.pc = pc; it.inst = inst;
  it.type = TT_ITRACE;
  it.cycle = cycle; it.commit_id = commit_id;
  ring_push(it);
}

void TraceManager::dump_snapshot(const std::string& reason) {
  if (snap_done_) return;
  snap_done_ = true;

  // 1) snapshot.npct: 用标准格式写 ring 内容, npc-trace 可直接读
  BinaryWriter w;
  std::string err;
  TraceMeta m = snap_meta_;
  m.ranges.clear();                 // 快照即全量
  m.text_mode = TextMode::OFF;
  const bool wrote_npct = w.open(snap_path_, m, &err);
  if (wrote_npct) {
    uint64_t seq = 0;
    for (const RingItem& it : ring_) {
      if (it.is_itrace) {
        w.write_itrace(it.pc, it.inst, it.cycle, it.commit_id);
      } else {
        TraceEvent ev{};
        ev.seq = seq++;
        ev.cycle = it.cycle;
        ev.commit_id = it.commit_id;
        ev.pc = it.pc;
        ev.addr = it.addr;
        ev.data = it.inst;
        ev.type = it.type;
        ev.flags = it.flags | TF_RING;   // 标记来自 ring 回放
        ev.len = it.len;
        ev.channel = it.channel;
        ev.region = it.region;
        w.write_event(ev);
      }
    }
    w.close();
  }

  // 2) snapshot.log: 原因 + CPU 状态 + 最近事件文本
  bool wrote_log = false;
  FILE* f = fopen(snap_log_.c_str(), "w");
  if (f) {
    fprintf(f, "=== NPC trace snapshot ===\n");
    fprintf(f, "reason : %s\n", reason.c_str());
    fprintf(f, "cycle  : %llu\n", (unsigned long long)npc_get_cycle());
    fprintf(f, "pc     : 0x%08x\n", npc_get_pc());
    fprintf(f, "inst   : 0x%08x\n", npc_get_inst());
    static const char* rn[16] = {"$0", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
                                 "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5"};
    for (int i = 0; i < 16; i++) {
      fprintf(f, "  %-3s : 0x%08x\n", rn[i], npc_get_reg(i));
    }
    fprintf(f, "\nring: %zu / %llu entries\n",
            ring_.size(), (unsigned long long)ring_cap_);
    const size_t n = ring_.size();
    const size_t start = n > 64 ? n - 64 : 0;
    for (size_t i = start; i < n; i++) {
      const RingItem& it = ring_[i];
      if (it.is_itrace) {
        fprintf(f, "  [cyc=%llu commit=%llu] itrace  0x%08x: %08x\n",
                (unsigned long long)it.cycle, (unsigned long long)it.commit_id,
                it.pc, it.inst);
      } else {
        fprintf(f, "  [cyc=%llu commit=%llu] %-14s pc=0x%08x addr=0x%08x data=0x%08x len=%u\n",
                (unsigned long long)it.cycle, (unsigned long long)it.commit_id,
                type_name((TraceType)it.type), it.pc, it.addr, it.inst, it.len);
      }
    }
    fclose(f);
    wrote_log = true;
  }

  fprintf(stderr, "[npc-trace] snapshot: npct=%s log=%s (reason: %s)\n",
          wrote_npct ? snap_path_.c_str() : "FAILED",
          wrote_log ? snap_log_.c_str() : "FAILED",
          reason.c_str());
}

}  // namespace npctrace
