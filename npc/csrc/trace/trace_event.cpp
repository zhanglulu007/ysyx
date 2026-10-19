/***************************************************************************************
* NPC TRACE - 事件模型与文件格式实现 (M0)
***************************************************************************************/
#include "trace_event.h"

#include <algorithm>
#include <cstdio>

namespace npctrace {

// ── 范围工具 ───────────────────────────────────────────────────────────────
bool range_valid(const CycleRange& r) {
  if (r.end == 0) return true;   // 到结束
  return r.begin < r.end;
}

void normalize_ranges(std::vector<CycleRange>& ranges) {
  if (ranges.empty()) return;

  std::sort(ranges.begin(), ranges.end(),
            [](const CycleRange& a, const CycleRange& b) {
              if (a.begin != b.begin) return a.begin < b.begin;
              return a.end < b.end;
            });

  std::vector<CycleRange> merged;
  merged.reserve(ranges.size());
  for (const CycleRange& r : ranges) {
    if (merged.empty()) {
      merged.push_back(r);
      continue;
    }
    CycleRange& last = merged.back();
    if (last.end == 0) continue;          // 已到结束, 吸收后续全部
    if (r.begin <= last.end) {            // 重叠或相接
      if (r.end == 0) last.end = 0;       // 扩展为到结束
      else if (r.end > last.end) last.end = r.end;
    } else {
      merged.push_back(r);
    }
  }

  for (size_t i = 0; i < merged.size(); i++) {
    merged[i].id = static_cast<uint32_t>(i + 1);
  }
  ranges.swap(merged);
}

bool range_contains(const CycleRange& r, uint64_t v) {
  if (v < r.begin) return false;
  if (r.end == 0) return true;
  return v < r.end;
}

const CycleRange* find_range(const std::vector<CycleRange>& ranges, uint64_t v) {
  if (ranges.empty()) return nullptr;

  // 找最后一个 begin <= v 的范围
  size_t lo = 0, hi = ranges.size();
  while (lo < hi) {
    size_t mid = lo + (hi - lo) / 2;
    if (ranges[mid].begin <= v) lo = mid + 1;
    else hi = mid;
  }
  if (lo == 0) return nullptr;
  const CycleRange& cand = ranges[lo - 1];
  return range_contains(cand, v) ? &cand : nullptr;
}

bool ranges_contain(const std::vector<CycleRange>& ranges, uint64_t v) {
  if (ranges.empty()) return true;   // 空 = 全量
  return find_range(ranges, v) != nullptr;
}

// ── 模型 ↔ 字符串 ──────────────────────────────────────────────────────────
const char* type_name(TraceType t) {
  switch (t) {
    case TT_UNKNOWN:           return "unknown";
    case TT_ITRACE:            return "itrace";
    case TT_MTRACE_IFETCH:     return "mtrace-ifetch";
    case TT_MTRACE_LOAD:       return "mtrace-load";
    case TT_MTRACE_STORE:      return "mtrace-store";
    case TT_FTRACE_CALL:       return "ftrace-call";
    case TT_FTRACE_RET:        return "ftrace-ret";
    case TT_ETRACE_EXCEPTION:  return "etrace-exception";
    case TT_ETRACE_INTERRUPT:  return "etrace-interrupt";
    case TT_ETRACE_MRET:       return "etrace-mret";
    case TT_ETRACE_EBREAK:     return "etrace-ebreak";
    case TT_CTRACE_READ:       return "ctrace-read";
    case TT_CTRACE_WRITE:      return "ctrace-write";
    case TT_DTRACE_READ:       return "dtrace-read";
    case TT_DTRACE_WRITE:      return "dtrace-write";
    case TT_ATRACE_AR:         return "atrace-ar";
    case TT_ATRACE_R:          return "atrace-r";
    case TT_ATRACE_AW:         return "atrace-aw";
    case TT_ATRACE_W:          return "atrace-w";
    case TT_ATRACE_B:          return "atrace-b";
    case TT_BTRACE_BRANCH:     return "btrace-branch";
    case TT_DIFFTEST_STEP:     return "difftest-step";
    case TT_DIFFTEST_SKIP:     return "difftest-skip";
    case TT_PERF_COUNTER:      return "perf-counter";
    case TT_RANGE_BEGIN:       return "range-begin";
    case TT_RANGE_END:         return "range-end";
  }
  return "unknown";
}

TraceCategory category_of(TraceType t) {
  switch (t) {
    case TT_ITRACE:                                   return TCAT_ITRACE;
    case TT_MTRACE_IFETCH:
    case TT_MTRACE_LOAD:
    case TT_MTRACE_STORE:                             return TCAT_MTRACE;
    case TT_FTRACE_CALL:
    case TT_FTRACE_RET:                               return TCAT_FTRACE;
    case TT_ETRACE_EXCEPTION:
    case TT_ETRACE_INTERRUPT:
    case TT_ETRACE_MRET:
    case TT_ETRACE_EBREAK:                            return TCAT_ETRACE;
    case TT_CTRACE_READ:
    case TT_CTRACE_WRITE:                             return TCAT_CTRACE;
    case TT_DTRACE_READ:
    case TT_DTRACE_WRITE:                             return TCAT_DTRACE;
    case TT_ATRACE_AR:
    case TT_ATRACE_R:
    case TT_ATRACE_AW:
    case TT_ATRACE_W:
    case TT_ATRACE_B:                                 return TCAT_ATRACE;
    case TT_BTRACE_BRANCH:                            return TCAT_BTRACE;
    case TT_DIFFTEST_STEP:
    case TT_DIFFTEST_SKIP:                            return TCAT_DIFFTEST;
    case TT_PERF_COUNTER:                             return TCAT_PERF;
    default:                                          return TCAT_NONE;
  }
}

const char* category_name(TraceCategory c) {
  switch (c) {
    case TCAT_ITRACE:   return "itrace";
    case TCAT_MTRACE:   return "mtrace";
    case TCAT_FTRACE:   return "ftrace";
    case TCAT_ETRACE:   return "etrace";
    case TCAT_CTRACE:   return "ctrace";
    case TCAT_DTRACE:   return "dtrace";
    case TCAT_ATRACE:   return "atrace";
    case TCAT_BTRACE:   return "btrace";
    case TCAT_DIFFTEST: return "difftest";
    case TCAT_PERF:     return "perf";
    default:            return "none";
  }
}

bool parse_category_name(const std::string& name, uint32_t* out) {
  if (name == "all") { *out = kTraceCategoryAll; return true; }
  struct { const char* n; uint32_t bit; } table[] = {
    {"itrace",   TCAT_ITRACE},   {"mtrace",   TCAT_MTRACE},
    {"ftrace",   TCAT_FTRACE},   {"etrace",   TCAT_ETRACE},
    {"ctrace",   TCAT_CTRACE},   {"dtrace",   TCAT_DTRACE},
    {"atrace",   TCAT_ATRACE},   {"btrace",   TCAT_BTRACE},
    {"difftest", TCAT_DIFFTEST}, {"perf",     TCAT_PERF},
  };
  for (const auto& e : table) {
    if (name == e.n) { *out = e.bit; return true; }
  }
  return false;
}

const char* range_unit_name(RangeUnit u) {
  return u == RangeUnit::COMMIT ? "commit" : "cycle";
}

bool parse_range_unit(const std::string& s, RangeUnit* out) {
  if (s == "cycle")  { *out = RangeUnit::CYCLE;  return true; }
  if (s == "commit") { *out = RangeUnit::COMMIT; return true; }
  return false;
}

const char* outside_policy_name(OutsidePolicy p) {
  switch (p) {
    case OutsidePolicy::DROP:     return "drop";
    case OutsidePolicy::RING:     return "ring";
    case OutsidePolicy::CRITICAL: return "critical";
  }
  return "ring";
}

bool parse_outside_policy(const std::string& s, OutsidePolicy* out) {
  if (s == "drop")     { *out = OutsidePolicy::DROP;     return true; }
  if (s == "ring")     { *out = OutsidePolicy::RING;     return true; }
  if (s == "critical") { *out = OutsidePolicy::CRITICAL; return true; }
  return false;
}

const char* text_mode_name(TextMode m) {
  switch (m) {
    case TextMode::DEFERRED: return "deferred";
    case TextMode::LIVE:     return "live";
    case TextMode::BOTH:     return "both";
    case TextMode::OFF:      return "off";
  }
  return "deferred";
}

bool parse_text_mode(const std::string& s, TextMode* out) {
  if (s == "deferred") { *out = TextMode::DEFERRED; return true; }
  if (s == "live")     { *out = TextMode::LIVE;     return true; }
  if (s == "both")     { *out = TextMode::BOTH;     return true; }
  if (s == "off")      { *out = TextMode::OFF;      return true; }
  return false;
}

// ── meta.json ──────────────────────────────────────────────────────────────
static void json_escape_into(std::string& out, const std::string& s) {
  for (char ch : s) {
    switch (ch) {
      case '"':  out += "\\\""; break;
      case '\\': out += "\\\\"; break;
      case '\n': out += "\\n";  break;
      case '\r': out += "\\r";  break;
      case '\t': out += "\\t";  break;
      default:
        if (static_cast<unsigned char>(ch) < 0x20) {
          char buf[8];
          snprintf(buf, sizeof(buf), "\\u%04x", ch);
          out += buf;
        } else {
          out += ch;
        }
    }
  }
}

std::string meta_to_json(const TraceMeta& meta) {
  std::string s;
  s.reserve(512);
  s += "{\n";
  s += "  \"version\": " + std::to_string(meta.version) + ",\n";

  s += "  \"config\": {\n";
  s += std::string("    \"soc\": ") + (meta.soc ? "1" : "0") + ",\n";

  s += "    \"trace\": \"";
  json_escape_into(s, meta.trace_types);
  s += "\",\n";

  s += std::string("    \"text_mode\": \"") + text_mode_name(meta.text_mode) + "\",\n";
  s += std::string("    \"outside\": \"") + outside_policy_name(meta.outside) + "\",\n";
  s += std::string("    \"range_unit\": \"") + range_unit_name(meta.range_unit) + "\",\n";
  s += "    \"ring_size\": " + std::to_string(meta.ring_size) + ",\n";

  s += "    \"ranges\": [";
  for (size_t i = 0; i < meta.ranges.size(); i++) {
    const CycleRange& r = meta.ranges[i];
    if (i) s += ",";
    s += "\n      {\"id\": " + std::to_string(r.id) +
         ", \"begin\": " + std::to_string(r.begin) +
         ", \"end\": " + std::to_string(r.end) + "}";
  }
  if (!meta.ranges.empty()) s += "\n    ";
  s += "]\n";
  s += "  },\n";

  s += "  \"program\": \"";
  json_escape_into(s, meta.program);
  s += "\",\n";

  s += "  \"elf\": \"";
  json_escape_into(s, meta.elf);
  s += "\",\n";

  s += "  \"elf_sha256\": \"";
  json_escape_into(s, meta.elf_sha256);
  s += "\",\n";

  s += "  \"git_commit\": \"";
  json_escape_into(s, meta.git_commit);
  s += "\",\n";

  s += "  \"cycle_per_time\": " + std::to_string(meta.cycle_per_time) + "\n";
  s += "}\n";
  return s;
}

}  // namespace npctrace
