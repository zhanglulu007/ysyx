/***************************************************************************************
* npc-trace - TUI 第一版实现 (M2)
***************************************************************************************/
#include "tui.h"
#include "trace_file.h"
#include "disasm.h"

#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <string>
#include <unordered_map>
#include <vector>

#include <unistd.h>

namespace npctrace {

namespace {

// 一条指令 + 它关联的事件(按 commit_id 归并)
struct Insn {
  uint32_t pc = 0;
  uint32_t inst = 0;
  uint64_t cycle = 0;
  uint64_t commit = 0;
  std::vector<TraceEvent> events;
};

// 把事件类型压成简短标签
const char* short_type(TraceType t) {
  switch (t) {
    case TT_MTRACE_IFETCH:    return "IFETCH";
    case TT_MTRACE_LOAD:      return "LOAD";
    case TT_MTRACE_STORE:     return "STORE";
    case TT_FTRACE_CALL:      return "CALL";
    case TT_FTRACE_RET:       return "RET";
    case TT_ETRACE_EXCEPTION: return "EXCP";
    case TT_ETRACE_INTERRUPT: return "INTR";
    case TT_ETRACE_MRET:      return "MRET";
    case TT_ETRACE_EBREAK:    return "EBREAK";
    case TT_CTRACE_READ:      return "CSR_R";
    case TT_CTRACE_WRITE:     return "CSR_W";
    case TT_DTRACE_READ:      return "DEV_R";
    case TT_DTRACE_WRITE:     return "DEV_W";
    case TT_ATRACE_AR:        return "AXI_AR";
    case TT_ATRACE_R:         return "AXI_R";
    case TT_ATRACE_AW:        return "AXI_AW";
    case TT_ATRACE_W:         return "AXI_W";
    case TT_ATRACE_B:         return "AXI_B";
    case TT_BTRACE_BRANCH:    return "BRANCH";
    default:                  return type_name(t);
  }
}

struct Model {
  std::vector<Insn> insns;
  std::unordered_map<uint64_t, size_t> by_commit;
};

bool load_model(const std::string& path, const TuiOptions& opt,
                Model* m, TraceFileHeader* hdr, Disasm* dis, Symbols* syms,
                std::string* err) {
  TraceFile tf;
  if (!tf.open(path, err)) return false;
  *hdr = tf.header;

  dis->init();
  if (!opt.elf.empty()) syms->load(opt.elf);

  auto in_range = [&](uint64_t cyc) {
    return opt.ranges.empty() || ranges_contain(opt.ranges, cyc);
  };

  ITraceReader ir;
  EventReader er;
  if (!ir.open(path, tf.header, err)) return false;
  if (!er.open(path, tf.header, err)) return false;

  m->insns.reserve((size_t)tf.header.itrace_count);
  ITraceEntry ie{};
  while (ir.next(&ie)) {
    if (!(opt.types & TCAT_ITRACE)) break;
    if (!in_range(ie.cycle)) continue;
    Insn in;
    in.pc = ie.pc; in.inst = ie.inst; in.cycle = ie.cycle; in.commit = ie.commit_id;
    m->by_commit[in.commit] = m->insns.size();
    m->insns.push_back(std::move(in));
    if (opt.max_insn && m->insns.size() >= opt.max_insn) break;
  }

  TraceEvent ev{};
  while (er.next(&ev)) {
    const TraceType t = (TraceType)ev.type;
    if (t == TT_RANGE_BEGIN || t == TT_RANGE_END) continue;
    if (!(opt.types & category_of(t))) continue;
    if (!in_range(ev.cycle)) continue;
    auto it = m->by_commit.find(ev.commit_id);
    if (it != m->by_commit.end()) m->insns[it->second].events.push_back(ev);
  }
  return true;
}

void print_insn(const Model& m, size_t idx, Disasm* dis, Symbols* syms) {
  const Insn& in = m.insns[idx];
  char dis_str[160];
  dis->one(in.pc, in.inst, dis_str, sizeof(dis_str));
  const char* fn = syms->loaded() ? syms->find(in.pc) : nullptr;
  printf("     0x%08x: %08x  %-32s commit=%llu cyc=%llu\n",
         in.pc, in.inst, dis_str,
         (unsigned long long)in.commit, (unsigned long long)in.cycle);
  if (fn) printf("         ^ %s\n", fn);
  for (const auto& e : in.events) {
    const TraceType t = (TraceType)e.type;
    if (t == TT_FTRACE_CALL || t == TT_FTRACE_RET) {
      const char* tfn = syms->loaded() ? syms->find(e.addr) : nullptr;
      printf("         - %-7s %s [%s@0x%08x]\n", short_type(t),
             (t == TT_FTRACE_CALL) ? "call" : "ret", tfn ? tfn : "???", e.addr);
    } else if (t >= TT_ATRACE_AR && t <= TT_ATRACE_B) {
      printf("         - %-7s addr=0x%08x data=0x%08x aux=0x%08x\n",
             short_type(t), e.addr, e.data, e.aux);
    } else if (t >= TT_ETRACE_EXCEPTION && t <= TT_ETRACE_EBREAK) {
      printf("         - %-7s cause=%u epc=0x%08x pc=0x%08x\n",
             short_type(t), e.data, e.addr, e.pc);
    } else {
      printf("         - %-7s addr=0x%08x len=%u data=0x%08x\n",
             short_type(t), e.addr, e.len, e.data);
    }
  }
}

void print_help() {
  printf("commands: n/next  p/prev  g N/goto  t TYPE/filter  /PAT/search  q/quit\n");
  printf("          (TYPE: itrace mtrace ftrace etrace ctrace dtrace atrace btrace)\n");
}

}  // namespace

bool run_tui(const std::string& trace_path, const TuiOptions& opt, std::string* err) {
  Model m;
  TraceFileHeader hdr;
  Disasm dis;
  Symbols syms;
  if (!load_model(trace_path, opt, &m, &hdr, &dis, &syms, err)) return false;

  if (m.insns.empty()) {
    printf("(no instructions in trace)\n");
    return true;
  }

  size_t cur = 0;
  const bool tty = isatty(STDIN_FILENO) != 0;

  printf("=== npc-trace tui ===\n");
  printf("file:     %s\n", trace_path.c_str());
  printf("itrace:   %llu   events: %llu   insns loaded: %zu\n",
         (unsigned long long)hdr.itrace_count,
         (unsigned long long)hdr.event_count, m.insns.size());
  printf("elf:      %s\n\n", syms.loaded() ? opt.elf.c_str() : "(none)");

  // 非交互(管道/重定向): 打印前若干条后退出
  if (!tty) {
    size_t n = m.insns.size() < 40 ? m.insns.size() : 40;
    for (size_t i = 0; i < n; i++) print_insn(m, i, &dis, &syms);
    if (m.insns.size() > n)
      printf("... (%zu more; run in a terminal for interactive mode)\n",
             m.insns.size() - n);
    return true;
  }

  print_help();
  char line[256];
  while (true) {
    printf("\n--- insn %zu / %zu ---\n", cur + 1, m.insns.size());
    print_insn(m, cur, &dis, &syms);
    printf("> ");
    fflush(stdout);
    if (!fgets(line, sizeof(line), stdin)) break;

    // 去换行
    size_t L = strlen(line);
    while (L && (line[L - 1] == '\n' || line[L - 1] == '\r')) line[--L] = 0;
    if (L == 0) continue;

    if (line[0] == 'q') break;
    if (line[0] == 'h') { print_help(); continue; }
    if (line[0] == 'n' || strcmp(line, "next") == 0) {
      if (cur + 1 < m.insns.size()) cur++;
      continue;
    }
    if (line[0] == 'p' || strcmp(line, "prev") == 0) {
      if (cur > 0) cur--;
      continue;
    }
    if (line[0] == 'g') {
      char* arg = line + 1;
      while (*arg == ' ') arg++;
      long g = strtol(arg, nullptr, 0);
      if (g > 0 && (size_t)g <= m.insns.size()) cur = (size_t)g - 1;
      else printf("usage: g N (1-based, 1..%zu)\n", m.insns.size());
      continue;
    }
    if (line[0] == '/' || strcmp(line, "s") == 0 || strncmp(line, "search", 6) == 0) {
      // 搜索: 助记符(在反汇编串中) 或 函数名
      const char* pat = line + 1;
      while (*pat == ' ') pat++;
      if (*pat == 0) { printf("usage: /PATTERN\n"); continue; }
      bool found = false;
      for (size_t i = cur + 1; i < m.insns.size(); i++) {
        char disbuf[160];
        dis.one(m.insns[i].pc, m.insns[i].inst, disbuf, sizeof(disbuf));
        const char* fn = syms.loaded() ? syms.find(m.insns[i].pc) : nullptr;
        if (strstr(disbuf, pat) || (fn && strstr(fn, pat))) {
          cur = i; found = true; break;
        }
      }
      if (!found) printf("no match after current position\n");
      continue;
    }
    if (line[0] == 't') {
      const char* arg = line + 1;
      while (*arg == ' ') arg++;
      uint32_t bit = 0;
      if (npctrace::parse_category_name(arg, &bit)) {
        // 简化的运行时过滤: 命中则提示(真正生效见 --type)
        printf("filter '%s': use --type=%s when launching for a real filter\n",
               arg, arg);
      } else {
        printf("unknown type '%s'\n", arg);
      }
      continue;
    }
    printf("unknown command (h for help)\n");
  }
  return true;
}

}  // namespace npctrace
