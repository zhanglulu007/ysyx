/***************************************************************************************
* NPC TRACE - 事件管理器实现 (M1)
***************************************************************************************/
#include "trace_manager.h"

#include <cstring>

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

}  // namespace npctrace
