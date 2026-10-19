/***************************************************************************************
* npc-trace - 共享的反汇编器与 ELF 符号表 (M2)
*
* 从 text.cpp 抽出, 供 text / tui 复用。都做失败降级: 没有 capstone 或 ELF 时
* 返回 "<disasm not available>" / "???", 而不是崩溃。
***************************************************************************************/
#ifndef __NPC_TRACE_DISASM_H__
#define __NPC_TRACE_DISASM_H__

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace npctrace {

// Capstone 反汇编器(动态加载 libcapstone)
class Disasm {
 public:
  void init();
  bool ok() const { return ok_; }
  // 反汇编一条 32 位指令, 失败填 "<invalid>"/"<disasm not available>"
  void one(uint32_t pc, uint32_t inst, char* out, size_t out_sz);
  ~Disasm();

 private:
  void*    handle_ = nullptr;
  uintptr_t handle_cs_ = 0;
  void*    disasm_f_ = nullptr;
  void*    free_f_ = nullptr;
  bool     ok_ = false;
};

// ELF 函数符号表(用于 ftrace 的函数名)
class Symbols {
 public:
  bool load(const std::string& path);
  bool loaded() const { return !syms_.empty(); }
  // 查找 addr 所属函数名, 找不到返回 nullptr
  const char* find(uint32_t addr) const;

 private:
  struct Sym { uint32_t start; uint32_t end; const char* name; };
  std::vector<Sym> syms_;
  std::string strtab_;
};

}  // namespace npctrace

#endif  // __NPC_TRACE_DISASM_H__
