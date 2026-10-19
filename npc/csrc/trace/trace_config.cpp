/***************************************************************************************
* NPC TRACE - 命令行配置解析实现 (M0)
***************************************************************************************/
#include "trace_config.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <sstream>

namespace npctrace {

namespace {

// 把 "--opt=value" 拆成名称与值; 无 '=' 时值指向下一个 argv。
// 返回 false 表示需要值但缺失。
bool take_value(int argc, char** argv, int* i,
                const char* name, const char* eq,
                std::string* value) {
  if (eq != nullptr) {
    *value = eq + 1;
    return true;
  }
  if (*i + 1 >= argc) return false;
  *value = argv[*i + 1];
  (*i)++;
  return true;
}

bool parse_u64(const std::string& s, uint64_t* out) {
  if (s.empty()) return false;
  char* end = nullptr;
  errno = 0;
  unsigned long long v = strtoull(s.c_str(), &end, 0);
  if (errno != 0 || end == s.c_str() || *end != '\0') return false;
  *out = static_cast<uint64_t>(v);
  return true;
}

bool parse_u32(const std::string& s, uint32_t* out) {
  uint64_t v = 0;
  if (!parse_u64(s, &v) || v > 0xFFFFFFFFull) return false;
  *out = static_cast<uint32_t>(v);
  return true;
}

bool parse_bool(const std::string& s, bool* out) {
  if (s == "1" || s == "on" || s == "true" || s == "yes")  { *out = true;  return true; }
  if (s == "0" || s == "off" || s == "false" || s == "no") { *out = false; return true; }
  return false;
}

// "1000-2000" -> {1000, 2000}; 允许 "1000-" 表示 end=0(到结束)
bool parse_range_spec(const std::string& spec, CycleRange* out) {
  size_t dash = spec.find('-');
  if (dash == std::string::npos) return false;

  std::string a = spec.substr(0, dash);
  std::string b = spec.substr(dash + 1);

  uint64_t begin = 0, end = 0;
  if (!parse_u64(a, &begin)) return false;
  if (!b.empty() && !parse_u64(b, &end)) return false;

  out->begin = begin;
  out->end   = end;   // b 为空 => 0 => 到结束
  out->id    = 0;     // normalize 时重编
  return range_valid(*out);
}

// 从文件读取范围, 每行 "start end" 或 "start-end"
bool load_ranges_file(const std::string& path,
                      std::vector<CycleRange>* out, std::string* err) {
  std::ifstream f(path);
  if (!f) { *err = "cannot open ranges file: " + path; return false; }

  std::string line;
  int lineno = 0;
  while (std::getline(f, line)) {
    lineno++;
    // 去掉注释与空白
    size_t hash = line.find('#');
    if (hash != std::string::npos) line = line.substr(0, hash);
    std::istringstream iss(line);
    std::string a, b;
    if (!(iss >> a)) continue;           // 空行
    CycleRange r{};
    if (iss >> b) {
      uint64_t begin = 0, end = 0;
      if (!parse_u64(a, &begin) || !parse_u64(b, &end)) {
        *err = "bad range at " + path + ":" + std::to_string(lineno);
        return false;
      }
      r.begin = begin; r.end = end; r.id = 0;
    } else if (!parse_range_spec(a, &r)) {
      *err = "bad range at " + path + ":" + std::to_string(lineno);
      return false;
    }
    if (!range_valid(r)) {
      *err = "invalid range at " + path + ":" + std::to_string(lineno);
      return false;
    }
    out->push_back(r);
  }
  return true;
}

bool parse_range_list(const std::string& value,
                      std::vector<CycleRange>* out, std::string* err) {
  if (!value.empty() && value[0] == '@') {
    return load_ranges_file(value.substr(1), out, err);
  }

  // 逗号分隔(兼容 `--trace-range=1000-2000,5000-6000`)
  std::string cur;
  std::vector<std::string> items;
  for (char ch : value) {
    if (ch == ',') { items.push_back(cur); cur.clear(); }
    else cur += ch;
  }
  items.push_back(cur);

  for (const std::string& it : items) {
    if (it.empty()) continue;
    CycleRange r{};
    if (!parse_range_spec(it, &r)) {
      *err = "invalid --trace-range value: '" + it + "'";
      return false;
    }
    out->push_back(r);
  }
  return true;
}

bool parse_type_list(const std::string& value, uint32_t* out, std::string* err) {
  uint32_t mask = 0;
  std::string cur;
  std::vector<std::string> items;
  for (char ch : value) {
    if (ch == ',') { items.push_back(cur); cur.clear(); }
    else cur += ch;
  }
  items.push_back(cur);

  for (std::string it : items) {
    if (it.empty()) continue;
    uint32_t bit = 0;
    if (!parse_category_name(it, &bit)) {
      *err = "unknown trace type: '" + it + "'";
      return false;
    }
    mask |= bit;
  }
  if (mask == 0) { *err = "empty --trace type list"; return false; }
  *out = mask;
  return true;
}

}  // namespace

bool is_trace_option(const char* arg) {
  if (arg == nullptr) return false;
  // 精确匹配(先剥离 '=' 之后的部分), 避免把 --trace-text 误吞成 --trace
  static const char* opts[] = {
    "--trace", "--trace-out", "--trace-text", "--trace-text-out",
    "--trace-outside", "--trace-range", "--trace-range-unit",
    "--trace-start", "--trace-stop", "--trace-ring", "--trace-sample",
    "--trace-compress", "--trace-critical-outside",
    "--log-file", "--log-level", "--log-buffer",
  };
  size_t len = 0;
  for (const char* p = arg; *p != '\0' && *p != '='; p++) len++;
  for (const char* o : opts) {
    if (strlen(o) == len && strncmp(arg, o, len) == 0) return true;
  }
  return false;
}

bool parse_trace_option(int argc, char** argv, int* i,
                        TraceCliConfig* cfg, std::string* err) {
  const char* arg = argv[*i];

  // 拆 "name=value"
  std::string name = arg;
  const char* eq = nullptr;
  size_t eqpos = name.find('=');
  std::string value;
  if (eqpos != std::string::npos) {
    eq = arg + eqpos;
    name = name.substr(0, eqpos);
  }

  auto need_value = [&](std::string* v) -> bool {
    if (!take_value(argc, argv, i, name.c_str(), eq, v)) {
      *err = "option " + name + " requires a value";
      return false;
    }
    return true;
  };

  if (name == "--trace") {
    if (!need_value(&value)) return false;
    uint32_t mask = 0;
    if (!parse_type_list(value, &mask, err)) return false;
    cfg->types = mask;
    cfg->types_str = trace_types_summary(mask);
    cfg->enabled = true;
    return true;
  }
  if (name == "--trace-out") {
    if (!need_value(&value)) return false;
    cfg->out_file = value;
    cfg->enabled = true;
    return true;
  }
  if (name == "--trace-text") {
    if (!need_value(&value)) return false;
    if (!parse_text_mode(value, &cfg->text_mode)) {
      *err = "invalid --trace-text value: '" + value + "'";
      return false;
    }
    cfg->enabled = true;
    return true;
  }
  if (name == "--trace-text-out") {
    if (!need_value(&value)) return false;
    cfg->text_file = value;
    return true;
  }
  if (name == "--trace-outside") {
    if (!need_value(&value)) return false;
    if (!parse_outside_policy(value, &cfg->outside)) {
      *err = "invalid --trace-outside value: '" + value + "'";
      return false;
    }
    return true;
  }
  if (name == "--trace-range") {
    if (!need_value(&value)) return false;
    if (!parse_range_list(value, &cfg->ranges, err)) return false;
    cfg->enabled = true;
    return true;
  }
  if (name == "--trace-range-unit") {
    if (!need_value(&value)) return false;
    if (!parse_range_unit(value, &cfg->range_unit)) {
      *err = "invalid --trace-range-unit value: '" + value + "'";
      return false;
    }
    return true;
  }
  if (name == "--trace-start") {
    if (!need_value(&value)) return false;
    uint64_t begin = 0;
    if (!parse_u64(value, &begin)) {
      *err = "invalid --trace-start value: '" + value + "'";
      return false;
    }
    cfg->ranges.push_back(CycleRange{begin, 0, 0});
    cfg->enabled = true;
    return true;
  }
  if (name == "--trace-stop") {
    if (!need_value(&value)) return false;
    uint64_t end = 0;
    if (!parse_u64(value, &end)) {
      *err = "invalid --trace-stop value: '" + value + "'";
      return false;
    }
    // 闭合最近一个 end==0 的范围, 否则从 0 开始
    bool closed = false;
    for (auto it = cfg->ranges.rbegin(); it != cfg->ranges.rend(); ++it) {
      if (it->end == 0) { it->end = end; closed = true; break; }
    }
    if (!closed) cfg->ranges.push_back(CycleRange{0, end, 0});
    cfg->enabled = true;
    return true;
  }
  if (name == "--trace-ring") {
    if (!need_value(&value)) return false;
    if (!parse_u64(value, &cfg->ring_size)) {
      *err = "invalid --trace-ring value: '" + value + "'";
      return false;
    }
    return true;
  }
  if (name == "--trace-sample") {
    if (!need_value(&value)) return false;
    if (!parse_u32(value, &cfg->sample) || cfg->sample == 0) {
      *err = "invalid --trace-sample value: '" + value + "'";
      return false;
    }
    return true;
  }
  if (name == "--trace-compress") {
    if (!need_value(&value)) return false;
    if (!parse_bool(value, &cfg->compress)) {
      *err = "invalid --trace-compress value: '" + value + "'";
      return false;
    }
    return true;
  }
  if (name == "--trace-critical-outside") {
    if (!need_value(&value)) return false;
    if (!parse_bool(value, &cfg->include_critical_outside)) {
      *err = "invalid --trace-critical-outside value: '" + value + "'";
      return false;
    }
    return true;
  }
  if (name == "--log-file") {
    if (!need_value(&value)) return false;
    cfg->log_file = value;
    return true;
  }
  if (name == "--log-level") {
    if (!need_value(&value)) return false;
    static const char* levels[] = {"error", "warn", "info", "debug", "trace"};
    bool ok = false;
    for (const char* l : levels) if (value == l) { ok = true; break; }
    if (!ok) { *err = "invalid --log-level value: '" + value + "'"; return false; }
    cfg->log_level = value;
    return true;
  }
  if (name == "--log-buffer") {
    if (!need_value(&value)) return false;
    if (!parse_u32(value, &cfg->log_buffer_kb)) {
      *err = "invalid --log-buffer value: '" + value + "'";
      return false;
    }
    return true;
  }

  *err = "unknown option: " + name;
  return false;
}

bool finalize_trace_config(TraceCliConfig* cfg, std::string* err) {
  for (const CycleRange& r : cfg->ranges) {
    if (!range_valid(r)) {
      *err = "invalid cycle range (begin must be < end; end==0 means open)";
      return false;
    }
  }
  normalize_ranges(cfg->ranges);

  if (cfg->text_mode == TextMode::OFF && !cfg->enabled) {
    // 只给了 --trace-text=off 而无其他 trace 选项: 当作显式关闭
    cfg->enabled = true;
  }
  if (cfg->out_file.empty()) {
    *err = "--trace-out must not be empty";
    return false;
  }
  return true;
}

std::string trace_types_summary(uint32_t types) {
  if (types == kTraceCategoryAll) return "all";
  if (types == 0) return "none";

  static const struct { uint32_t bit; const char* name; } table[] = {
    {TCAT_ITRACE, "itrace"}, {TCAT_MTRACE, "mtrace"}, {TCAT_FTRACE, "ftrace"},
    {TCAT_ETRACE, "etrace"}, {TCAT_CTRACE, "ctrace"}, {TCAT_DTRACE, "dtrace"},
    {TCAT_ATRACE, "atrace"}, {TCAT_BTRACE, "btrace"},
    {TCAT_DIFFTEST, "difftest"}, {TCAT_PERF, "perf"},
  };
  std::string s;
  for (const auto& e : table) {
    if (types & e.bit) {
      if (!s.empty()) s += ",";
      s += e.name;
    }
  }
  return s;
}

std::string trace_cli_summary(const TraceCliConfig& cfg) {
  std::string s;
  s += "trace.enabled   = " + std::string(cfg.enabled ? "yes" : "no") + "\n";
  s += "trace.types     = " + trace_types_summary(cfg.types) + "\n";
  s += "trace.out       = " + cfg.out_file + "\n";
  s += std::string("trace.text_mode = ") + text_mode_name(cfg.text_mode) + "\n";
  s += "trace.text_out  = " + cfg.text_file + "\n";
  s += std::string("trace.outside   = ") + outside_policy_name(cfg.outside) + "\n";
  s += std::string("trace.range_unit= ") + range_unit_name(cfg.range_unit) + "\n";
  s += "trace.ring      = " + std::to_string(cfg.ring_size) + "\n";
  s += "trace.sample    = " + std::to_string(cfg.sample) + "\n";
  s += std::string("trace.compress  = ") + (cfg.compress ? "on" : "off") + "\n";
  s += std::string("trace.crit_out  = ") +
       (cfg.include_critical_outside ? "on" : "off") + "\n";

  s += "trace.ranges    = ";
  if (cfg.ranges.empty()) {
    s += "(full)\n";
  } else {
    for (size_t i = 0; i < cfg.ranges.size(); i++) {
      if (i) s += ", ";
      const CycleRange& r = cfg.ranges[i];
      s += "[" + std::to_string(r.begin) + "," +
           (r.end == 0 ? std::string("inf") : std::to_string(r.end)) + ")";
    }
    s += "\n";
  }

  s += "log.file        = " +
       (cfg.log_file.empty() ? std::string("(default)") : cfg.log_file) + "\n";
  s += "log.level       = " + cfg.log_level + "\n";
  return s;
}

}  // namespace npctrace
