/***************************************************************************************
* npc-trace - Chrome Trace 时间轴导出实现 (M1)
***************************************************************************************/
#include "export_chrome.h"
#include "trace_file.h"

#include <cstring>

namespace npctrace {

namespace {

// pid=1; tid: 1=指令流 2=访存 3=函数调用
constexpr int kPid = 1;
constexpr int kTidInstr = 1;
constexpr int kTidMem   = 2;
constexpr int kTidFunc  = 3;

const char* lane_name(int tid) {
  switch (tid) {
    case kTidInstr: return "instr";
    case kTidMem:   return "mem";
    case kTidFunc:  return "func";
    default:        return "other";
  }
}

// 输出一个 "X" 事件(name 已安全, 仅含 [A-Za-z0-9_.-])
void emit_x(FILE* out, bool* first, const char* name, uint64_t ts, uint64_t dur,
            int tid, const char* extra_args) {
  if (!*first) fprintf(out, ",\n");
  *first = false;
  fprintf(out,
          "{\"name\":\"%s\",\"cat\":\"%s\",\"ph\":\"X\",\"ts\":%llu,\"dur\":%llu,"
          "\"pid\":%d,\"tid\":%d,\"args\":{%s}}",
          name, lane_name(tid), (unsigned long long)ts, (unsigned long long)dur,
          kPid, tid, extra_args ? extra_args : "");
}

}  // namespace

bool export_chrome(const std::string& trace_path, FILE* out,
                   const ChromeOptions& opt, std::string* err, uint64_t* events_out) {
  TraceFile tf;
  if (!tf.open(trace_path, err)) return false;

  auto in_range = [&](uint64_t cycle) -> bool {
    if (opt.ranges.empty()) return true;
    return ranges_contain(opt.ranges, cycle);
  };
  auto type_on = [&](TraceCategory cat) -> bool {
    if (cat == TCAT_NONE) return false;   // marker 不进入时间轴
    return (opt.types & cat) != 0;
  };

  if (fprintf(out, "[") < 0) { *err = "write error"; return false; }
  bool first = true;
  uint64_t count = 0;
  char args[160];

  ITraceReader ir;
  EventReader er;
  if (!ir.open(trace_path, tf.header, err)) return false;
  if (!er.open(trace_path, tf.header, err)) return false;

  ITraceEntry ie{};
  bool have_i = ir.next(&ie);
  TraceEvent ev{};
  bool have_e = er.next(&ev);

  while (have_i || have_e) {
    bool take_itrace = have_i && (!have_e || ie.cycle <= ev.cycle);

    if (take_itrace) {
      if (type_on(TCAT_ITRACE) && in_range(ie.cycle)) {
        snprintf(args, sizeof(args), "\"commit\":%llu,\"pc\":\"0x%08x\",\"inst\":\"0x%08x\"",
                 (unsigned long long)ie.commit_id, ie.pc, ie.inst);
        char nm[32];
        snprintf(nm, sizeof(nm), "I_0x%08x", ie.pc);
        emit_x(out, &first, nm, ie.cycle, 1, kTidInstr, args);
        count++;
      }
      have_i = ir.next(&ie);
    } else {
      const TraceType t = (TraceType)ev.type;
      if (t != TT_RANGE_BEGIN && t != TT_RANGE_END &&
          type_on(category_of(t)) && in_range(ev.cycle)) {
        if (t == TT_MTRACE_IFETCH || t == TT_MTRACE_LOAD || t == TT_MTRACE_STORE) {
          snprintf(args, sizeof(args),
                   "\"commit\":%llu,\"pc\":\"0x%08x\",\"addr\":\"0x%08x\",\"len\":%u,\"data\":\"0x%08x\",\"kind\":\"%s\"",
                   (unsigned long long)ev.commit_id, ev.pc, ev.addr, ev.len, ev.data,
                   (t == TT_MTRACE_IFETCH) ? "ifetch"
                     : (t == TT_MTRACE_STORE ? "store" : "load"));
          char nm[48];
          snprintf(nm, sizeof(nm), "%s_0x%08x",
                   (t == TT_MTRACE_IFETCH) ? "IF" : (t == TT_MTRACE_STORE ? "ST" : "LD"),
                   ev.addr);
          emit_x(out, &first, nm, ev.cycle, 1, kTidMem, args);
          count++;
        } else if (t == TT_FTRACE_CALL || t == TT_FTRACE_RET) {
          snprintf(args, sizeof(args),
                   "\"commit\":%llu,\"pc\":\"0x%08x\",\"target\":\"0x%08x\"",
                   (unsigned long long)ev.commit_id, ev.pc, ev.addr);
          char nm[32];
          snprintf(nm, sizeof(nm), "%s_0x%08x",
                   (t == TT_FTRACE_CALL) ? "call" : "ret", ev.addr);
          emit_x(out, &first, nm, ev.cycle, 1, kTidFunc, args);
          count++;
        }
      }
      have_e = er.next(&ev);
    }
  }

  if (fprintf(out, "]\n") < 0) { *err = "write error"; return false; }
  if (events_out) *events_out = count;
  return true;
}

}  // namespace npctrace
