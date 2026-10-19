/***************************************************************************************
* npc-trace - 共享反汇编器与 ELF 符号表实现 (M2)
***************************************************************************************/
#include "disasm.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <algorithm>
#include <dlfcn.h>
#include <elf.h>

#if defined(__has_include)
#  if __has_include(<capstone/capstone.h>)
#    include <capstone/capstone.h>
#    define NPCTRACE_HAVE_CAPSTONE 1
#  endif
#endif

namespace npctrace {

// ── Disasm ─────────────────────────────────────────────────────────────────
void Disasm::init() {
#ifdef NPCTRACE_HAVE_CAPSTONE
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
  disasm_f_ = dlsym(handle_, "cs_disasm");
  free_f_ = dlsym(handle_, "cs_free");
  if (!cs_open_f || !disasm_f_ || !free_f_) return;
  csh h = 0;
  cs_arch arch = CS_ARCH_RISCV;
  cs_mode mode = (cs_mode)(CS_MODE_RISCV32 | CS_MODE_RISCVC);
  if (cs_open_f(arch, mode, &h) == 0) {
    handle_cs_ = (uintptr_t)h;
    ok_ = true;
  }
#endif
}

void Disasm::one(uint32_t pc, uint32_t inst, char* out, size_t out_sz) {
#ifdef NPCTRACE_HAVE_CAPSTONE
  if (!ok_) { snprintf(out, out_sz, "<disasm not available>"); return; }
  auto disasm_f = (size_t (*)(csh, const uint8_t*, size_t, uint64_t, size_t, cs_insn**))disasm_f_;
  auto free_f = (void (*)(cs_insn*, size_t))free_f_;
  cs_insn* insn = nullptr;
  size_t n = disasm_f((csh)handle_cs_, (const uint8_t*)&inst, 4, pc, 0, &insn);
  if (n == 0) { snprintf(out, out_sz, "<invalid>"); return; }
  int r = snprintf(out, out_sz, "%s", insn->mnemonic);
  if (insn->op_str[0] != '\0' && r < (int)out_sz - 1)
    snprintf(out + r, out_sz - r, "\t%s", insn->op_str);
  free_f(insn, n);
#else
  (void)pc; (void)inst;
  snprintf(out, out_sz, "<disasm not available>");
#endif
}

Disasm::~Disasm() {
  if (handle_) dlclose(handle_);
}

// ── Symbols ────────────────────────────────────────────────────────────────
bool Symbols::load(const std::string& path) {
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

  struct Raw { uint32_t addr; uint32_t size; uint32_t name_off; };
  std::vector<Raw> raw;
  for (const auto& s : syms) {
    if (ELF32_ST_TYPE(s.st_info) != STT_FUNC) continue;
    if (s.st_value == 0) continue;
    raw.push_back({s.st_value, s.st_size, s.st_name});
  }
  std::sort(raw.begin(), raw.end(),
            [](const Raw& a, const Raw& b) { return a.addr < b.addr; });

  strtab_ = strtab;                 // 先固定, 使后面的 name 指针稳定
  syms_.clear();
  for (size_t i = 0; i < raw.size(); i++) {
    uint32_t end = raw[i].size ? raw[i].addr + raw[i].size
                               : (i + 1 < raw.size() ? raw[i + 1].addr
                                                     : raw[i].addr + 4);
    syms_.push_back(Sym{raw[i].addr, end, strtab_.c_str() + raw[i].name_off});
  }
  return !syms_.empty();
}

const char* Symbols::find(uint32_t addr) const {
  size_t lo = 0, hi = syms_.size();
  while (lo < hi) {
    size_t mid = lo + (hi - lo) / 2;
    if (syms_[mid].start <= addr) lo = mid + 1; else hi = mid;
  }
  if (lo == 0) return nullptr;
  const Sym& s = syms_[lo - 1];
  if (addr >= s.end) return nullptr;
  return s.name;
}

}  // namespace npctrace
