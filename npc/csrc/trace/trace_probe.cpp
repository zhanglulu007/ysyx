/***************************************************************************************
* NPC TRACE - RTL 探针的 C++ 接入层实现 (M2)
***************************************************************************************/
#include "trace_probe.h"
#include "trace_manager.h"
#include "mtrace.h"
#include "../core/npc.h"

namespace npctrace {

// 地址区域判定。standalone 的 PMEM(0x80000000) 与 SoC 的 PSRAM 同址,
// 用 SOC_MODE 区分两套映射。
uint8_t addr_region(uint32_t a) {
#ifdef SOC_MODE
  // ysyxSoC 地址映射(见 ysyxSoC/src/SoC.scala)
  if (a >= 0x30000000u && a < 0x40000000u) return RG_FLASH;   // XIP flash 256MB
  if (a >= 0x0f000000u && a < 0x0f002000u) return RG_SRAM;    // SRAM 8KB
  if (a >= 0x20000000u && a < 0x20001000u) return RG_MROM;    // MROM 4KB
  if (a >= 0x80000000u && a < 0x80400000u) return RG_PSRAM;   // PSRAM 4MB
  if (a >= 0xa0000000u && a < 0xa2000000u) return RG_SDRAM;   // SDRAM 32MB
  if (a >= 0x10000000u && a < 0x10020000u) return RG_MMIO;    // UART/SPI/GPIO/KBD
  if (a >= 0x21000000u && a < 0x22000000u) return RG_MMIO;    // VGA
  return RG_UNKNOWN;
#else
  if (a >= 0x80000000u && a < 0x88000000u) return RG_PMEM;    // 128MB
  if (a >= 0x30000000u && a < 0x31000000u) return RG_FLASH;   // 16MB
  if (a >= 0x20000000u && a < 0x20001000u) return RG_MROM;
  if (a == 0x10000000u || a == 0x10000048u || a == 0x1000004cu ||
      a == 0x10000060u || a == 0x10000100u || a == 0x10000104u) return RG_MMIO;
  if (a >= 0x11000000u && a < 0x11000000u + 400u * 300u * 4u) return RG_FB;
  return RG_UNKNOWN;
#endif
}

}  // namespace npctrace

#ifdef ENABLE_TRACE

namespace {

using namespace npctrace;

// 统一发射: 填公共字段后交给 TraceManager 过滤/写盘。
void emit(uint16_t type, uint16_t flags, uint8_t channel, uint8_t region,
          uint32_t pc, uint32_t addr, uint32_t data, uint16_t len,
          uint32_t aux) {
  TraceEvent ev{};
  ev.cycle      = npc_get_cycle();
  ev.commit_id  = TraceManager::instance().inflight_commit();
  ev.type       = type;
  ev.flags      = flags;
  ev.channel    = channel;
  ev.region     = region;
  ev.pc         = pc;
  ev.addr       = addr;
  ev.data       = data;
  ev.len        = len;
  ev.aux        = aux;
  ev.t_start    = (uint32_t)ev.cycle;
  ev.t_end      = (uint32_t)ev.cycle;
  TraceManager::instance().emit(ev);
}

}  // namespace

extern "C" void trace_probe_ifetch(int addr, int data, int pc) {
  emit(TT_MTRACE_IFETCH, TF_READ | TF_FETCH, CH_IFU,
       addr_region((uint32_t)addr), (uint32_t)pc, (uint32_t)addr,
       (uint32_t)data, 4, 0);
  // 同步产出 npc.log 的 legacy 文本视图(二进制事件已含真实宽度)
  mtrace_legacy(false, true, (uint32_t)addr, 4, (uint32_t)data,
                (uint32_t)pc, npc_get_cycle());
}

extern "C" void trace_probe_mem(int is_write, int width, int addr, int data, int pc) {
  const uint8_t region = addr_region((uint32_t)addr);
  if (is_write) {
    emit(TT_MTRACE_STORE, TF_WRITE, CH_LSU, region,
         (uint32_t)pc, (uint32_t)addr, (uint32_t)data, (uint16_t)width, 0);
  } else {
    emit(TT_MTRACE_LOAD, TF_READ, CH_LSU, region,
         (uint32_t)pc, (uint32_t)addr, (uint32_t)data, (uint16_t)width, 0);
  }
  mtrace_legacy(is_write != 0, false, (uint32_t)addr, width,
                (uint32_t)data, (uint32_t)pc, npc_get_cycle());
}

extern "C" void trace_probe_axi(int channel, int id, int addr, int len, int size, int data) {
  TraceType t;
  TraceFlags f = TF_NONE;
  switch (channel) {
    case CH_AXI_AR: t = TT_ATRACE_AR; f = TF_READ;  break;
    case CH_AXI_R:  t = TT_ATRACE_R;  f = TF_READ;  break;
    case CH_AXI_AW: t = TT_ATRACE_AW; f = TF_WRITE; break;
    case CH_AXI_W:  t = TT_ATRACE_W;  f = TF_WRITE; break;
    case CH_AXI_B:  t = TT_ATRACE_B;  f = TF_WRITE; break;
    default: return;
  }
  // aux 打包 axi id(低4位) 与 arsize(高3位), 供查看器区分事务
  const uint32_t aux = (uint32_t)((id & 0xF) | ((size & 0x7) << 4) |
                                  ((len & 0xFF) << 8));
  emit(t, f, (uint8_t)channel, addr_region((uint32_t)addr),
       0, (uint32_t)addr, (uint32_t)data, (uint16_t)(size + 1), aux);
}

extern "C" void trace_probe_csr(int is_write, int csr_addr, int wdata, int rdata, int pc) {
  if (is_write) {
    emit(TT_CTRACE_WRITE, TF_WRITE, CH_NONE, RG_UNKNOWN,
         (uint32_t)pc, (uint32_t)(csr_addr & 0xFFF), (uint32_t)wdata, 4, 0);
  } else {
    emit(TT_CTRACE_READ, TF_READ, CH_NONE, RG_UNKNOWN,
         (uint32_t)pc, (uint32_t)(csr_addr & 0xFFF), (uint32_t)rdata, 4, 0);
  }
}

extern "C" void trace_probe_trap(int kind, int cause, int epc, int tvec, int pc) {
  TraceType t;
  if (kind == 1)      t = TT_ETRACE_MRET;
  else if (kind == 2) t = TT_ETRACE_EBREAK;
  else                t = TT_ETRACE_EXCEPTION;   // kind==0
  // aux 打包 mcause(低12位) 与 mtvec(高20位截断)
  const uint32_t aux = (uint32_t)((cause & 0xFFF) | ((tvec & 0xFFFFF) << 12));
  emit(t, TF_CRITICAL, CH_NONE, RG_UNKNOWN,
       (uint32_t)pc, (uint32_t)epc, (uint32_t)cause, 0, aux);
}

extern "C" void trace_probe_branch(int pc, int taken, int target) {
  emit(TT_BTRACE_BRANCH, taken ? TF_NONE : TF_NONE, CH_NONE, RG_UNKNOWN,
       (uint32_t)pc, (uint32_t)target, (uint32_t)taken, 0, (uint32_t)taken);
}

#else   // !ENABLE_TRACE

extern "C" void trace_probe_ifetch(int, int, int) {}
extern "C" void trace_probe_mem(int, int, int, int, int) {}
extern "C" void trace_probe_axi(int, int, int, int, int, int) {}
extern "C" void trace_probe_csr(int, int, int, int, int) {}
extern "C" void trace_probe_trap(int, int, int, int, int) {}
extern "C" void trace_probe_branch(int, int, int) {}

#endif  // ENABLE_TRACE
