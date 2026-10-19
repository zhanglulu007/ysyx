/***************************************************************************************
* NPC TRACE - 事件模型与文件格式 (M0)
*
* 本文件只定义“接口与格式”: 统一事件、事件类型/标志/通道/区域、周期范围、trace 配置,
* 以及 trace.npct 的 header / index / meta 结构。真正的采集与写入在 M1 实现。
*
* 设计约定(见 docs/npc-TRACE与日志系统实施计划.md §3/§5/§6):
*   - 二进制是 source of truth, 文本只是视图;
*   - 通用事件定长 64B, itrace 走 16B delta 流, 索引每 4096 条一项;
*   - 所有结构体都做 static_assert 尺寸校验, 格式变更必须提升 TRACE_VERSION。
***************************************************************************************/
#ifndef __NPC_TRACE_EVENT_H__
#define __NPC_TRACE_EVENT_H__

#include <cstdint>
#include <cstddef>
#include <string>
#include <vector>

namespace npctrace {

// ── 文件魔法与版本 ─────────────────────────────────────────────────────────
#define TRACE_MAGIC_STR   "NPCTRACE"
#define TRACE_MAGIC_LEN   8
constexpr uint32_t TRACE_VERSION   = 1;
constexpr uint32_t TRACE_ENDIAN_ID = 0x01020304u;   // 用于识别字节序

// ── 尺寸常量 ───────────────────────────────────────────────────────────────
constexpr uint32_t TRACE_EVENT_SIZE     = 64;      // 通用事件字节数
constexpr uint32_t TRACE_ITRACE_SIZE    = 16;      // itrace delta 记录字节数
constexpr uint32_t TRACE_INDEX_INTERVAL = 4096;    // 每 N 条事件一个索引项
constexpr uint32_t TRACE_INDEX_SIZE     = 40;      // 索引项字节数

// ── 事件类型 ───────────────────────────────────────────────────────────────
// 值与“类别”分组保持连续区间, 便于 category_of() 用区间判断。
enum TraceType : uint16_t {
  TT_UNKNOWN = 0,

  // 指令流
  TT_ITRACE            = 1,

  // 访存(区分取指 / load / store)
  TT_MTRACE_IFETCH     = 10,
  TT_MTRACE_LOAD       = 11,
  TT_MTRACE_STORE      = 12,

  // 函数调用
  TT_FTRACE_CALL       = 20,
  TT_FTRACE_RET        = 21,

  // 异常 / 中断
  TT_ETRACE_EXCEPTION  = 30,
  TT_ETRACE_INTERRUPT  = 31,
  TT_ETRACE_MRET       = 32,
  TT_ETRACE_EBREAK     = 33,

  // CSR
  TT_CTRACE_READ       = 40,
  TT_CTRACE_WRITE      = 41,

  // 设备
  TT_DTRACE_READ       = 50,
  TT_DTRACE_WRITE      = 51,

  // AXI 通道
  TT_ATRACE_AR         = 60,
  TT_ATRACE_R          = 61,
  TT_ATRACE_AW         = 62,
  TT_ATRACE_W          = 63,
  TT_ATRACE_B          = 64,

  // 分支
  TT_BTRACE_BRANCH     = 70,

  // DiffTest
  TT_DIFFTEST_STEP     = 80,
  TT_DIFFTEST_SKIP     = 81,

  // PERF
  TT_PERF_COUNTER      = 90,

  // 范围边界 marker(总是写入, 用于文本分段)
  TT_RANGE_BEGIN       = 100,
  TT_RANGE_END         = 101,
};

// ── 事件类别(用于 --trace= 过滤) ───────────────────────────────────────────
enum TraceCategory : uint32_t {
  TCAT_NONE     = 0u,
  TCAT_ITRACE   = 1u << 0,
  TCAT_MTRACE   = 1u << 1,
  TCAT_FTRACE   = 1u << 2,
  TCAT_ETRACE   = 1u << 3,
  TCAT_CTRACE   = 1u << 4,
  TCAT_DTRACE   = 1u << 5,
  TCAT_ATRACE   = 1u << 6,
  TCAT_BTRACE   = 1u << 7,
  TCAT_DIFFTEST = 1u << 8,
  TCAT_PERF     = 1u << 9,
};

constexpr uint32_t kTraceCategoryAll =
    TCAT_ITRACE | TCAT_MTRACE | TCAT_FTRACE | TCAT_ETRACE | TCAT_CTRACE |
    TCAT_DTRACE | TCAT_ATRACE | TCAT_BTRACE | TCAT_DIFFTEST | TCAT_PERF;

// 默认与当前 NPC 已有的 itrace/ftrace/mtrace 行为对齐
constexpr uint32_t kTraceCategoryDefault =
    TCAT_ITRACE | TCAT_MTRACE | TCAT_FTRACE;

// ── 事件标志 ───────────────────────────────────────────────────────────────
enum TraceFlags : uint16_t {
  TF_NONE     = 0u,
  TF_READ     = 1u << 0,
  TF_WRITE    = 1u << 1,
  TF_FETCH    = 1u << 2,
  TF_PARTIAL  = 1u << 3,   // 跨范围边界
  TF_CRITICAL = 1u << 4,   // 关键事件
  TF_RING     = 1u << 5,   // 来自 ring 回放
};

// ── 通道(IFU/LSU/AXI) ──────────────────────────────────────────────────────
enum TraceChannel : uint8_t {
  CH_NONE   = 0,
  CH_IFU    = 1,
  CH_LSU    = 2,
  CH_AXI_AR = 3,
  CH_AXI_R  = 4,
  CH_AXI_AW = 5,
  CH_AXI_W  = 6,
  CH_AXI_B  = 7,
};

// ── 地址区域 ───────────────────────────────────────────────────────────────
enum TraceRegion : uint8_t {
  RG_UNKNOWN = 0,
  RG_PMEM    = 1,
  RG_FLASH   = 2,
  RG_SRAM    = 3,
  RG_SDRAM   = 4,
  RG_PSRAM   = 5,
  RG_MROM    = 6,
  RG_MMIO    = 7,
  RG_FB      = 8,
};

// ── 通用事件(定长 64B) ─────────────────────────────────────────────────────
struct TraceEvent {
  uint64_t seq;         // 全局单调序号
  uint64_t cycle;       // 主时间轴
  uint64_t commit_id;   // 指令提交编号
  uint32_t t_start;     // 事务开始周期
  uint32_t t_end;       // 事务结束周期
  uint32_t pc;          // 触发 PC
  uint32_t addr;        // 访存/设备/AXI 地址
  uint32_t data;        // 数据
  uint32_t parent;      // 因果父事件 seq(低 32 位)
  uint16_t type;        // TraceType
  uint16_t flags;       // TraceFlags
  uint16_t len;         // 访问长度(字节)
  uint8_t  hart;
  uint8_t  priv;
  uint8_t  channel;     // TraceChannel
  uint8_t  region;      // TraceRegion
  uint32_t aux;         // 事件特有字段
};
static_assert(sizeof(TraceEvent) == TRACE_EVENT_SIZE,
              "TraceEvent 必须是 64 字节定长");

// ── itrace delta 记录(定长 16B) ────────────────────────────────────────────
struct ITraceRecord {
  uint32_t pc_delta;
  uint32_t cycle_delta;
  uint32_t commit_delta;
  uint32_t inst;
};
static_assert(sizeof(ITraceRecord) == TRACE_ITRACE_SIZE,
              "ITraceRecord 必须是 16 字节定长");

// ── trace.npct header ──────────────────────────────────────────────────────
struct TraceFileHeader {
  char     magic[TRACE_MAGIC_LEN];   // "NPCTRACE"
  uint32_t version;                  // TRACE_VERSION
  uint32_t endian;                   // TRACE_ENDIAN_ID
  uint32_t header_size;              // sizeof(TraceFileHeader)
  uint32_t config_hash;              // 配置指纹
  uint64_t meta_off;    uint64_t meta_size;
  uint64_t itrace_off;  uint64_t itrace_size;
  uint64_t events_off;  uint64_t events_size;
  uint64_t index_off;   uint64_t index_size;
  uint64_t dict_off;    uint64_t dict_size;
  uint64_t summary_off; uint64_t summary_size;
  uint64_t event_count;              // events 区事件条数
  uint64_t itrace_count;             // itrace 区记录条数
  uint32_t index_interval;           // 通常 = TRACE_INDEX_INTERVAL
  uint32_t reserved;
};

// ── trace.npct 索引项(每 4096 条事件一个) ──────────────────────────────────
struct TraceIndexEntry {
  uint64_t seq;
  uint64_t cycle;
  uint64_t commit_id;
  uint32_t range_id;
  uint32_t reserved;
  uint64_t offset;                   // 事件区字节偏移
};
static_assert(sizeof(TraceIndexEntry) == TRACE_INDEX_SIZE,
              "TraceIndexEntry 必须是 40 字节");

// ── trace.npct summary 区 ──────────────────────────────────────────────────
struct TraceSummary {
  uint64_t event_count;
  uint64_t itrace_count;
  uint64_t dropped_count;     // 因范围/采样过滤丢弃的事件数
  uint64_t ring_count;        // 范围外进 ring 的事件数
  uint64_t first_cycle;
  uint64_t last_cycle;
  uint64_t first_commit;
  uint64_t last_commit;
  uint32_t range_count;
  uint32_t reserved;
};
static_assert(sizeof(TraceSummary) == 72, "TraceSummary 必须是 72 字节");

// ── 周期范围 ───────────────────────────────────────────────────────────────
struct CycleRange {
  uint64_t begin;   // 包含
  uint64_t end;     // 不包含; 0 表示到结束
  uint32_t id;      // 1 基, 用于文本分段标题
};

enum class RangeUnit { CYCLE, COMMIT };
enum class OutsidePolicy { DROP, RING, CRITICAL };
enum class TextMode { DEFERRED, LIVE, BOTH, OFF };

// ── 范围工具 ───────────────────────────────────────────────────────────────
// 合法性: begin < end, 或 end == 0(到结束)
bool range_valid(const CycleRange& r);

// 排序 + 去重 + 合并重叠/相接区间, 并重编 id 为 1..N
void normalize_ranges(std::vector<CycleRange>& ranges);

// v 是否落在单个范围内
bool range_contains(const CycleRange& r, uint64_t v);

// ranges 为空视为“全量”, 返回 true
bool ranges_contain(const std::vector<CycleRange>& ranges, uint64_t v);

// 在已 normalize 的 ranges 中二分查找包含 v 的范围, 找不到返回 nullptr
const CycleRange* find_range(const std::vector<CycleRange>& ranges, uint64_t v);

// ── 模型 ↔ 字符串 ──────────────────────────────────────────────────────────
const char*    type_name(TraceType t);
TraceCategory  category_of(TraceType t);
const char*    category_name(TraceCategory c);
// 解析类别名("itrace"/"all"/...), 成功写 *out 并返回 true
bool           parse_category_name(const std::string& name, uint32_t* out);

const char*    range_unit_name(RangeUnit u);
bool           parse_range_unit(const std::string& s, RangeUnit* out);
const char*    outside_policy_name(OutsidePolicy p);
bool           parse_outside_policy(const std::string& s, OutsidePolicy* out);
const char*    text_mode_name(TextMode m);
bool           parse_text_mode(const std::string& s, TextMode* out);

// ── meta.json ──────────────────────────────────────────────────────────────
struct TraceMeta {
  uint32_t version = TRACE_VERSION;

  // config
  bool                   soc = false;
  std::string            trace_types;    // "itrace,ftrace,mtrace"
  TextMode               text_mode = TextMode::DEFERRED;
  OutsidePolicy          outside   = OutsidePolicy::RING;
  RangeUnit              range_unit = RangeUnit::CYCLE;
  uint64_t               ring_size = 1000000;
  std::vector<CycleRange> ranges;

  // program
  std::string program;
  std::string elf;
  std::string elf_sha256;
  std::string git_commit;

  // 时间轴换算: 一个 cycle 对应多少 time 单位(Verilator timeInc)
  uint32_t cycle_per_time = 2;
};

// 序列化为 meta.json 文本
std::string meta_to_json(const TraceMeta& meta);

}  // namespace npctrace

#endif  // __NPC_TRACE_EVENT_H__
