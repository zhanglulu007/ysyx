/***************************************************************************************
* npc-trace - 文本转写实现 (M1)
***************************************************************************************/
#include "text.h"
#include "trace_file.h"

#include <cstring>
#include <cstdlib>
#include <algorithm>
#include <dlfcn.h>
#include <elf.h>
#include <string>
#include <vector>

// 若构建时能找到 capstone 头文件则支持反汇编; 否则退化为 <disasm unavailable>
#if defined(__has_include)
#  if __has_include(<capstone/capstone.h>)
#    include <capstone/capstone.h>
#    define NPCTRACE_HAVE_CAPSTONE 1
#  endif
#endif

namespace npctrace {

namespace {

// ── 反汇编器 ───────────────────────────────────────────────────────────────
class Disasm {
 public:
  void init() {
#ifdef NPCTRACE_HAVE_CAPSTONE
    // 依次尝试: 环境变量 / 从 npc 目录 / 从 npc/tools/npc-trace 目录
    const char* candidates[] = {
      getenv("NPC_CAPSTONE_SO"),
      "../nemu/tools/capstone/repo/libcapstone.so.5",
      "../../nemu/tools/capstone/repo/libcapstone.so.5",
      "nemu/tools/capstone/repo/libcapstone.so.5",
    };
    for (const char* c : candidates) {
      if (c == nullptr) continue;
      handle_ = dlopen(c, RTLD_LAZY);
      if (handle_) break;
    }
    if (!handle_) return;

    auto cs_open_f = (int (*)(cs_arch, cs_mode, csh*))dlsym(handle_, "cs_open");
    disasm_f_ = (size_t (*)(csh, const uint8_t*, size_t, uint64_t, size_t,
                            cs_insn**))dlsym(handle_, "cs_disasm");
    free_f_ = (void (*)(cs_insn*, size_t))dlsym(handle_, "cs_free");
    if (!cs_open_f || !disasm_f_ || !free_f_) { ok_ = false; return; }
    cs_arch arch = CS_ARCH_RISCV;
    cs_mode mode = (cs_mode)(CS_MODE_RISCV32 | CS_MODE_RISCVC);
    ok_ = (cs_open_f(arch, mode, &handle_cs_) == 0);
#endif
  }

  bool ok() const { return ok_; }

  // 反汇编一条 32 位指令到 out(如 "mv\ts0, zero"); 失败填 "<invalid>"
  void one(uint32_t pc, uint32_t inst, char* out, size_t out_sz) {
#ifdef NPCTRACE_HAVE_CAPSTONE
    if (!ok_) { snprintf(out, out_sz, "<disasm not available>"); return; }
    cs_insn* insn = nullptr;
    size_t n = disasm_f_(handle_cs_, (const uint8_t*)&inst, 4, pc, 0, &insn);
    if (n == 0) { snprintf(out, out_sz, "<invalid>"); return; }
    int r = snprintf(out, out_sz, "%s", insn->mnemonic);
    if (insn->op_str[0] != '\0' && r < (int)out_sz - 1)
      snprintf(out + r, out_sz - r, "\t%s", insn->op_str);
    free_f_(insn, n);
#else
    (void)pc; (void)inst;
    snprintf(out, out_sz, "<disasm not available>");
#endif
  }

  ~Disasm() {
#ifdef NPCTRACE_HAVE_CAPSTONE
    if (handle_) dlclose(handle_);
#endif
  }

 private:
#ifdef NPCTRACE_HAVE_CAPSTONE
  void* handle_ = nullptr;
  csh   handle_cs_ = 0;
  size_t (*disasm_f_)(csh, const uint8_t*, size_t, uint64_t, size_t, cs_insn**) = nullptr;
  void   (*free_f_)(cs_insn*, size_t) = nullptr;
#endif
  bool ok_ = false;
};

// ── ELF 符号表(用于 ftrace 的函数名) ───────────────────────────────────────
struct Sym { uint32_t start; uint32_t end; const char* name; };

class Symbols {
 public:
  bool load(const std::string& path) {
    FILE* fp = fopen(path.c_str(), "rb");
    if (!fp) return false;
    Elf32_Ehdr eh;
    if (fread(&eh, sizeof(eh), 1, fp) != 1 ||
        memcmp(eh.e_ident, ELFMAG, SELFMAG) != 0) { fclose(fp); return false; }

    std::vector<Elf32_Shdr> sh(eh.e_shnum);
    if (fseek(fp, eh.e_shoff, SEEK_SET) != 0 ||
        fread(sh.data(), sizeof(Elf32_Shdr), eh.e_shnum, fp) != eh.e_shnum) {
      fclose(fp); return false;
    }

    const Elf32_Shdr* sym_h = nullptr;
    const Elf32_Shdr* str_h = nullptr;
    for (const auto& s : sh) {
      if (s.sh_type == SHT_SYMTAB) { sym_h = &s; str_h = &sh[s.sh_link]; break; }
    }
    if (!sym_h || !str_h) { fclose(fp); return false; }

    std::vector<Elf32_Sym> syms(sym_h->sh_size / sizeof(Elf32_Sym));
    if (fseek(fp, sym_h->sh_offset, SEEK_SET) != 0 ||
        fread(syms.data(), sym_h->sh_size, 1, fp) != 1) { fclose(fp); return false; }

    std::string strtab(str_h->sh_size, '\0');
    if (fseek(fp, str_h->sh_offset, SEEK_SET) != 0 ||
        fread(&strtab[0], str_h->sh_size, 1, fp) != 1) { fclose(fp); return false; }
    fclose(fp);

    // 只保留函数符号, 按起始地址排序, 用下一个符号补齐 st_size=0 的范围
    struct Raw { uint32_t addr; uint32_t size; uint32_t name_off; };
    std::vector<Raw> raw;
    for (const auto& s : syms) {
      if (ELF32_ST_TYPE(s.st_info) != STT_FUNC) continue;
      if (s.st_value == 0) continue;
      raw.push_back({s.st_value, s.st_size, s.st_name});
    }
    std::sort(raw.begin(), raw.end(),
              [](const Raw& a, const Raw& b) { return a.addr < b.addr; });

    strtab_ = strtab;
    for (size_t i = 0; i < raw.size(); i++) {
      uint32_t end = raw[i].size ? raw[i].addr + raw[i].size
                                 : (i + 1 < raw.size() ? raw[i + 1].addr
                                                       : raw[i].addr + 4);
      Sym sy{raw[i].addr, end, strtab_.c_str() + raw[i].name_off};
      syms_.push_back(sy);
    }
    return !syms_.empty();
  }

  // 查找 addr 所属函数名, 找不到返回 nullptr
  const char* find(uint32_t addr) const {
    // 二分: 找最后一个 start <= addr
    size_t lo = 0, hi = syms_.size();
    while (lo < hi) {
      size_t mid = lo + (hi - lo) / 2;
      if (syms_[mid].start <= addr) lo = mid + 1; else hi = mid;
    }
    if (lo == 0) return nullptr;
    const Sym& s = syms_[lo - 1];
    return (addr < s.end) ? s.name : nullptr;
  }

 private:
  std::vector<Sym> syms_;
  std::string strtab_;
};

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
    // itrace 用 TCAT_ITRACE; 其余按 category_of
    if (cat == TCAT_NONE) return true;   // marker 等无类别事件始终输出
    return (opt.types & cat) != 0;
  };

  // 分段标题
  auto emit_section = [&](const char* kind, uint32_t range_id, uint64_t cycle) {
    fprintf(out, "\n==================== TRACE %s %u", kind, range_id);
    if (cycle) fprintf(out, " (at cycle %llu)", (unsigned long long)cycle);
    fprintf(out, " ====================\n");
    lines++;
  };

  // ── 归并 itrace 流与 event 流(两流均按 cycle 非降序) ──
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
    // 谁 cycle 更小谁先出; 相等时 itrace 先(提交点)。
    // marker 特例: RANGE_BEGIN 在同 cycle 时优先(标题落在段首);
    //              RANGE_END   在同 cycle 时靠后(标题落在段尾)。
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

      // 范围 marker: 转换为分段标题。marker 也要经过二次范围过滤,
      // 否则被过滤掉的段会留下空标题。
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
        const char* fn = syms.find(ev.addr);
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
          // legacy: 与仿真侧格式一致
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
