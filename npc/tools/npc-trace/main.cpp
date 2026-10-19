/***************************************************************************************
* npc-trace - trace.npct 查看器 (M0 骨架)
*
* M0 只提供子命令骨架与容器级能力:
*   info   容器 header + meta 摘要            (已实现)
*   stats  事件计数/时间范围摘要              (容器级; 事件级统计在 M1)
*   text   转写文本视图                       (M1)
*   export 导出 Chrome/Perfetto 时间轴        (M1: chrome)
*   tui    交互式浏览                         (M2)
*
* 用法:
*   npc-trace info   trace.npct
*   npc-trace stats  trace.npct
*   npc-trace text   trace.npct -o out.log --format=legacy [--range=BEG-END]
*   npc-trace export trace.npct --format=chrome -o trace.json
*   npc-trace tui    trace.npct
***************************************************************************************/
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <cerrno>
#include <string>
#include <vector>

#include "trace_file.h"
#include "text.h"
#include "export_chrome.h"

namespace {

void usage(const char* prog) {
  printf("Usage: %s <command> <trace.npct> [options]\n\n", prog);
  printf("Commands:\n");
  printf("  info     show header / meta summary\n");
  printf("  stats    show event counts and time range\n");
  printf("  text     transcribe to a text view (M1)\n");
  printf("  export   export a timeline for a viewer (M1: chrome)\n");
  printf("  tui      interactive browser (M2)\n\n");
  printf("Options:\n");
  printf("  -o, --out FILE      output file (text/export)\n");
  printf("  --format FMT        text: legacy|rich ; export: chrome|perfetto\n");
  printf("  --range BEG-END     restrict output to a cycle range (repeatable)\n");
  printf("  --type LIST         restrict to event categories, e.g. itrace,mtrace\n");
  printf("  --elf FILE          ELF for ftrace symbol names (text)\n");
  printf("  -h, --help          this message\n");
}

// M1/M2 命令统一给出清晰提示, 避免让人误以为“命令失败”
int not_yet(const char* cmd, const char* milestone) {
  fprintf(stderr, "npc-trace: '%s' is planned for %s and not implemented in M0.\n",
          cmd, milestone);
  fprintf(stderr, "           M0 delivers the container, CLI and build fixes only.\n");
  return 2;
}

struct Options {
  std::string out;
  std::string format;
  std::vector<std::string> ranges;
  std::string types;
  std::string elf;
};

// 解析 M0 认识的选项(语义在 M1 生效; M0 仅接收以免报错)
bool parse_opts(int argc, char** argv, int start, Options* opt, std::string* err) {
  for (int i = start; i < argc; i++) {
    std::string a = argv[i];
    auto value = [&](const char* eq) -> std::string {
      if (eq != nullptr) return std::string(eq + 1);
      if (i + 1 < argc) return std::string(argv[++i]);
      return std::string();
    };
    size_t eqpos = a.find('=');
    const char* eq = eqpos == std::string::npos ? nullptr : argv[i] + eqpos;
    std::string name = eqpos == std::string::npos ? a : a.substr(0, eqpos);

    if (name == "-o" || name == "--out") {
      opt->out = value(eq);
      if (opt->out.empty()) { *err = "--out requires a value"; return false; }
    } else if (name == "--format") {
      opt->format = value(eq);
    } else if (name == "--range") {
      std::string v = value(eq);
      if (v.empty()) { *err = "--range requires a value"; return false; }
      opt->ranges.push_back(v);
    } else if (name == "--type") {
      opt->types = value(eq);
    } else if (name == "--elf") {
      opt->elf = value(eq);
    } else {
      *err = "unknown option: " + name;
      return false;
    }
  }
  return true;
}

std::string section(const std::string& json, const std::string& key) {
  std::string v = npctrace::meta_field(json, key);
  return v.empty() ? std::string("(none)") : v;
}

// ── 二次过滤选项解析 ───────────────────────────────────────────────────────
bool parse_u64_s(const std::string& s, uint64_t* v) {
  if (s.empty()) return false;
  char* e = nullptr;
  errno = 0;
  unsigned long long x = strtoull(s.c_str(), &e, 0);
  if (errno != 0 || e == s.c_str() || *e != '\0') return false;
  *v = x;
  return true;
}

// "1000-2000" / "1000-" (end=0=到结束)
bool parse_range_s(const std::string& s, npctrace::CycleRange* out) {
  size_t d = s.find('-');
  if (d == std::string::npos) return false;
  uint64_t b = 0, e = 0;
  if (!parse_u64_s(s.substr(0, d), &b)) return false;
  std::string rb = s.substr(d + 1);
  if (!rb.empty() && !parse_u64_s(rb, &e)) return false;
  out->begin = b;
  out->end = e;
  out->id = 0;
  return npctrace::range_valid(*out);
}

// "itrace,mtrace" -> mask
bool parse_types_s(const std::string& s, uint32_t* mask) {
  *mask = 0;
  std::string cur;
  std::vector<std::string> items;
  for (char c : s) {
    if (c == ',') { items.push_back(cur); cur.clear(); }
    else cur += c;
  }
  items.push_back(cur);
  for (std::string& it : items) {
    if (it.empty()) continue;
    uint32_t bit = 0;
    if (!npctrace::parse_category_name(it, &bit)) return false;
    *mask |= bit;
  }
  return *mask != 0;
}

int cmd_info(const std::string& file) {
  npctrace::TraceFile tf;
  std::string err;
  if (!tf.open(file, &err)) {
    fprintf(stderr, "npc-trace: %s\n", err.c_str());
    return 1;
  }

  printf("=== npc-trace info: %s ===\n", file.c_str());
  printf("%s", npctrace::format_header(tf.header).c_str());
  printf("\nmeta.json:\n");
  if (tf.meta_json.empty()) {
    printf("  (empty)\n");
  } else {
    for (size_t i = 0; i < tf.meta_json.size(); i += 4096) {
      std::string chunk = tf.meta_json.substr(i, 4096);
      printf("%s", chunk.c_str());
      if (!chunk.empty() && chunk.back() != '\n') printf("\n");
    }
  }
  printf("\nkey fields:\n");
  printf("  program    = %s\n", section(tf.meta_json, "program").c_str());
  printf("  elf        = %s\n", section(tf.meta_json, "elf").c_str());
  printf("  git_commit = %s\n", section(tf.meta_json, "git_commit").c_str());
  printf("  soc        = %s\n", section(tf.meta_json, "soc").c_str());
  printf("  trace      = %s\n", section(tf.meta_json, "trace").c_str());
  printf("  text_mode  = %s\n", section(tf.meta_json, "text_mode").c_str());
  printf("  outside    = %s\n", section(tf.meta_json, "outside").c_str());
  printf("  range_unit = %s\n", section(tf.meta_json, "range_unit").c_str());
  return 0;
}

int cmd_stats(const std::string& file) {
  npctrace::TraceFile tf;
  std::string err;
  if (!tf.open(file, &err)) {
    fprintf(stderr, "npc-trace: %s\n", err.c_str());
    return 1;
  }

  printf("=== npc-trace stats: %s ===\n", file.c_str());
  printf("events:  %llu\n", (unsigned long long)tf.header.event_count);
  printf("itrace:  %llu\n", (unsigned long long)tf.header.itrace_count);
  printf("index:   %llu entries (interval=%u)\n",
         (unsigned long long)(tf.header.index_size / npctrace::TRACE_INDEX_SIZE),
         tf.header.index_interval);
  const double ev_bytes = tf.header.events_size;
  const double it_bytes = tf.header.itrace_size;
  printf("size:    events=%.0f B  itrace=%.0f B  total=%.0f B\n",
         ev_bytes, it_bytes, ev_bytes + it_bytes);
  // 事件级分类统计在 M1 (需要解码 events 段)
  printf("\nNote: per-type breakdown requires M1 event decoding.\n");
  return 0;
}

int cmd_text(const std::string& file, const Options& opt) {
  npctrace::TextOptions to;
  to.rich = (opt.format == "rich");
  to.elf = opt.elf;

  // 类型二次过滤
  if (!opt.types.empty()) {
    if (!parse_types_s(opt.types, &to.types)) {
      fprintf(stderr, "npc-trace: invalid --type list: '%s'\n", opt.types.c_str());
      return 1;
    }
  }
  // 范围二次过滤
  for (const std::string& r : opt.ranges) {
    npctrace::CycleRange cr{};
    if (!parse_range_s(r, &cr)) {
      fprintf(stderr, "npc-trace: invalid --range value: '%s'\n", r.c_str());
      return 1;
    }
    to.ranges.push_back(cr);
  }
  npctrace::normalize_ranges(to.ranges);

  FILE* out = stdout;
  bool close_out = false;
  if (!opt.out.empty() && opt.out != "-") {
    out = fopen(opt.out.c_str(), "w");
    if (!out) { fprintf(stderr, "npc-trace: cannot open '%s'\n", opt.out.c_str()); return 1; }
    close_out = true;
  }

  uint64_t lines = 0;
  std::string err;
  bool ok = npctrace::transcribe(file, out, to, &err, &lines);
  if (close_out) fclose(out);
  if (!ok) { fprintf(stderr, "npc-trace: %s\n", err.c_str()); return 1; }

  fprintf(stderr, "npc-trace: wrote %llu lines\n", (unsigned long long)lines);
  return 0;
}

int cmd_export(const std::string& file, const Options& opt) {
  if (!opt.format.empty() && opt.format != "chrome") {
    fprintf(stderr, "npc-trace: export format '%s' not supported (M1: chrome)\n",
            opt.format.c_str());
    return 2;
  }
  npctrace::ChromeOptions co;
  if (!opt.types.empty() && !parse_types_s(opt.types, &co.types)) {
    fprintf(stderr, "npc-trace: invalid --type list: '%s'\n", opt.types.c_str());
    return 1;
  }
  for (const std::string& r : opt.ranges) {
    npctrace::CycleRange cr{};
    if (!parse_range_s(r, &cr)) {
      fprintf(stderr, "npc-trace: invalid --range value: '%s'\n", r.c_str());
      return 1;
    }
    co.ranges.push_back(cr);
  }
  npctrace::normalize_ranges(co.ranges);

  FILE* out = stdout;
  bool close_out = false;
  if (!opt.out.empty() && opt.out != "-") {
    out = fopen(opt.out.c_str(), "w");
    if (!out) { fprintf(stderr, "npc-trace: cannot open '%s'\n", opt.out.c_str()); return 1; }
    close_out = true;
  }

  uint64_t n = 0;
  std::string err;
  bool ok = npctrace::export_chrome(file, out, co, &err, &n);
  if (close_out) fclose(out);
  if (!ok) { fprintf(stderr, "npc-trace: %s\n", err.c_str()); return 1; }

  fprintf(stderr, "npc-trace: exported %llu timeline events\n", (unsigned long long)n);
  return 0;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc < 2 || strcmp(argv[1], "-h") == 0 || strcmp(argv[1], "--help") == 0) {
    usage(argv[0]);
    return argc < 2 ? 1 : 0;
  }

  std::string cmd = argv[1];
  if (cmd == "help") { usage(argv[0]); return 0; }

  if (argc < 3) {
    fprintf(stderr, "npc-trace: '%s' requires a trace file\n", cmd.c_str());
    usage(argv[0]);
    return 1;
  }
  std::string file = argv[2];

  Options opt;
  std::string err;
  if (!parse_opts(argc, argv, 3, &opt, &err)) {
    fprintf(stderr, "npc-trace: %s\n", err.c_str());
    return 1;
  }

  if (cmd == "info")   return cmd_info(file);
  if (cmd == "stats")  return cmd_stats(file);
  if (cmd == "text")   return cmd_text(file, opt);
  if (cmd == "export") return cmd_export(file, opt);
  if (cmd == "tui")    return not_yet("tui", "M2");

  fprintf(stderr, "npc-trace: unknown command '%s'\n", cmd.c_str());
  usage(argv[0]);
  return 1;
}
