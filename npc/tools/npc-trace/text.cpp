/***************************************************************************************
* npc-trace - 文本转写实现 (M1)
***************************************************************************************/
#include "text.h"
#include "trace_file.h"
#include "disasm.h"

#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <string>
#include <vector>

namespace npctrace {

namespace {

// ── 输出辅助 ───────────────────────────────────────────────────────────────
void hex_bytes(std::string& s, uint32_t inst) {
  char b[8];
  const uint8_t* p = (const uint8_t*)&inst;
  for (int i = 3; i >= 0; i--) { snprintf(b, sizeof(b), " %02x", p[i]); s += b; }
}

// 事件类型 → legacy 前缀(与仿真侧一致)
const char* legacy_tag(TraceType t) {
  switch (t) {
    case TT_MTRACE_IFETCH:
    case TT_MTRACE_LOAD:
    case TT_MTRACE_STORE: return "[MTRACE]";
    case TT_FTRACE_CALL:
    case TT_FTRACE_RET:   return "[FTRACE]";
    default:              return nullptr;
  }
}

struct Counters { uint64_t lines = 0; uint64_t filtered = 0; };

}  // namespace

bool transcribe(const std::string& trace_path, FILE* out,
                const TextOptions& opt, std::string* err, uint64_t* lines_out) {
  TraceFile tf;
  if (!tf.open(trace_path, err)) return false;

  Disasm dis; dis.init();
  Symbols syms;
  if (!opt.elf.empty()) syms.load(opt.elf);

  uint64_t lines = 0;
  Counters ctr;

  auto in_range = [&](uint64_t cycle) -> bool {
    if (opt.ranges.empty()) return true;
    return ranges_contain(opt.ranges, cycle);
  };
  auto type_on = [&](TraceCategory cat) -> bool {
    if (cat == TCAT_NONE) return true;   // marker 等无类别事件始终输出
    return (opt.types & cat) != 0;
  };

  auto emit_section = [&](const char* kind, uint32_t range_id, uint64_t cycle) {
    fprintf(out, "\n==================== TRACE %s %u", kind, range_id);
    if (cycle) fprintf(out, " (at cycle %llu)", (unsigned long long)cycle);
    fprintf(out, " ====================\n");
    lines++;
  };

  ITraceReader ir;
  EventReader er;
  if (!ir.open(trace_path, tf.header, err)) return false;
  if (!er.open(trace_path, tf.header, err)) return false;

  ITraceEntry ie{};
  bool have_i = ir.next(&ie);
  TraceEvent ev{};
  bool have_e = er.next(&ev);

  int func_depth = 0;

  while (have_i || have_e) {
    bool ev_is_begin = have_e && ((TraceType)ev.type == TT_RANGE_BEGIN);
    bool ev_is_end   = have_e && ((TraceType)ev.type == TT_RANGE_END);
    bool take_itrace;
    if (have_i && have_e) {
      if (ev_is_begin && ev.cycle <= ie.cycle)      take_itrace = false;
      else if (ev_is_end && ev.cycle < ie.cycle)    take_itrace = false;
      else                                         take_itrace = (ie.cycle <= ev.cycle);
    } else {
      take_itrace = have_i;
    }

    if (take_itrace) {
      if (type_on(TCAT_ITRACE) && in_range(ie.cycle)) {
        char dis_str[160];
        dis.one(ie.pc, ie.inst, dis_str, sizeof(dis_str));
        if (opt.rich) {
          fprintf(out, "[cyc=%llu commit=%llu pc=0x%08x] %08x  %s\n",
                  (unsigned long long)ie.cycle,
                  (unsigned long long)ie.commit_id, ie.pc, ie.inst, dis_str);
        } else {
          std::string line;
          char hdr[32];
          snprintf(hdr, sizeof(hdr), "0x%08x:", ie.pc);
          line = hdr;
          hex_bytes(line, ie.inst);
          line += ' ';
          line += dis_str;
          fprintf(out, "%s\n", line.c_str());
        }
        lines++;
      } else {
        ctr.filtered++;
      }
      have_i = ir.next(&ie);
    } else {
      const TraceType t = (TraceType)ev.type;

      if (t == TT_RANGE_BEGIN) {
        if (in_range(ev.cycle)) emit_section("RANGE", ev.aux, ev.cycle);
        have_e = er.next(&ev);
        continue;
      }
      if (t == TT_RANGE_END) {
        if (in_range(ev.cycle)) emit_section("END", ev.aux, ev.cycle);
        have_e = er.next(&ev);
        continue;
      }

      if (type_on(category_of(t)) && in_range(ev.cycle)) {
        char fname[128];
        const char* fn = syms.loaded() ? syms.find(ev.addr) : nullptr;
        snprintf(fname, sizeof(fname), "%s", fn ? fn : "???");

        if (opt.rich) {
          fprintf(out, "[cyc=%llu commit=%llu pc=0x%08x] %s",
                  (unsigned long long)ev.cycle,
                  (unsigned long long)ev.commit_id, ev.pc, legacy_tag(t));
          if (t == TT_FTRACE_CALL) {
            fprintf(out, " call [%s@0x%08x]", fname, ev.addr);
          } else if (t == TT_FTRACE_RET) {
            fprintf(out, " ret  [%s@0x%08x]", fname, ev.addr);
          } else {
            fprintf(out, " %s at 0x%08x len=%u data=0x%08x",
                    (ev.flags & TF_WRITE) ? "WRITE" : "READ ",
                    ev.addr, ev.len, ev.data);
          }
          fprintf(out, "\n");
        } else {
          if (t == TT_FTRACE_CALL || t == TT_FTRACE_RET) {
            int indent = func_depth * 2;
            if (indent > 40) indent = 40;
            fprintf(out, "[FTRACE] 0x%08x: %*s%s [%s@0x%08x]\n",
                    ev.pc, indent, "",
                    (t == TT_FTRACE_CALL) ? "call" : "ret ", fname, ev.addr);
            if (t == TT_FTRACE_CALL) func_depth++;
            else if (func_depth > 0) func_depth--;
          } else {
            fprintf(out,
                    "[MTRACE] cyc=%llu %s at 0x%08x len=%u data=0x%08x pc=0x%08x\n",
                    (unsigned long long)ev.cycle,
                    (ev.flags & TF_WRITE) ? "WRITE" : "READ ",
                    ev.addr, ev.len, ev.data, ev.pc);
          }
        }
        lines++;
      } else {
        ctr.filtered++;
      }
      have_e = er.next(&ev);
    }
  }
  (void)ctr;

  if (lines_out) *lines_out = lines;
  return true;
}

}  // namespace npctrace
