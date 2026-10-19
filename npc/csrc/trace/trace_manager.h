/***************************************************************************************
* NPC TRACE - 事件管理器 (M1)
*
* TraceManager 是所有 trace 事件进入 trace.npct 的唯一入口, 负责:
*   1. 持有 BinaryWriter, 决定 trace 是否启用;
*   2. 过滤链: type_mask -> range -> sample -> write(见实施计划 §5.4 规则 7);
*   3. 静态多段范围: 进入/离开范围时写入 RANGE_BEGIN/END marker, 供文本分段;
*   4. 范围外策略 outside: DROP / RING / CRITICAL;
*   5. 分配全局单调 seq。
*
* 单例; 未 init 或 init 失败时 enabled() 为 false, 所有 emit 立即返回(TRACE=0 零开销)。
***************************************************************************************/
#ifndef __NPC_TRACE_MANAGER_H__
#define __NPC_TRACE_MANAGER_H__

#include <cstdint>
#include <deque>
#include <string>
#include <vector>

#include "trace_config.h"
#include "trace_event.h"
#include "trace_writer.h"

namespace npctrace {

class TraceManager {
 public:
  static TraceManager& instance();

  // 启动写入。cfg.ranges 需已 normalize。meta 里的 ranges 会被覆盖为 cfg.ranges。
  bool init(const TraceCliConfig& cfg, const TraceMeta& meta, std::string* err);

  // 收尾: 关闭 writer(拼接/回填/改名)。
  void shutdown();

  bool enabled() const { return enabled_; }

  // 每条提交指令调用: 写 itrace(若启用)并推进范围 marker。
  void on_commit(uint32_t pc, uint32_t inst, uint64_t cycle, uint64_t commit_id);

  // 通用事件入口(seq 由管理器分配)。会按过滤链决定是否落盘。
  void emit(TraceEvent& ev);

  // 便捷入口: itrace(delta 流)。等价于 on_commit 里的 itrace 部分。
  void emit_itrace(uint32_t pc, uint32_t inst, uint64_t cycle, uint64_t commit_id);

  // M1 写盘是即时的, flush 目前为空操作(保留接口给 M3 的批量写)。
  void flush();

  uint64_t event_count()  const { return writer_.event_count(); }
  uint64_t itrace_count() const { return writer_.itrace_count(); }
  uint64_t dropped_count() const { return writer_.dropped_count(); }
  const std::string& out_path() const { return writer_.path(); }

  // 在飞指令的 commit_id: 由 exec_once 在每轮开始时设置(commit_count + 1),
  // 使同一条指令执行期间产生的 mtrace/ftrace 事件与末尾的 itrace 共享同一个
  // commit_id, 从而可在查看器中按 commit_id 关联(§5.2)。
  void     set_inflight_commit(uint64_t id) { inflight_commit_ = id; }
  uint64_t inflight_commit() const { return inflight_commit_; }

  // ── 动态范围(SDB, §5.4) ──────────────────────────────────────────────────
  // 运行时增删范围, 从下一个事件起生效; 已写入的事件不删除。
  bool   dyn_range_add(uint64_t begin, uint64_t end, std::string* err);
  void   dyn_range_clear();                    // 清空所有范围 -> 回到全量
  void   dyn_range_start(uint64_t now);         // 从现在起开始记录
  void   dyn_range_stop(uint64_t now);          // 结束当前区间

  // SDB `trace status` / `trace range list` 的文本
  std::string status_string() const;
  std::string range_list_string() const;

  // ── ring buffer + 失败快照(§5.5) ─────────────────────────────────────────
  // 失败时把"最近 N 条事件"落成 snapshot.npct(标准格式, npc-trace 可直接读)
  // 与 snapshot.log(含 CPU 状态)。可重复调用, 只生效一次。
  void dump_snapshot(const std::string& reason);

 private:
  TraceManager() = default;
  TraceManager(const TraceManager&) = delete;
  TraceManager& operator=(const TraceManager&) = delete;

  uint64_t axis_value(uint64_t cycle, uint64_t commit_id) const;

  // 范围检查 + 边界 marker。返回事件是否落在范围内(空 ranges 视为全量)。
  bool pass_range(uint64_t cycle, uint64_t commit_id, uint32_t pc);

  // 范围外是否应保留(CRITICAL 策略下放行关键事件)。
  bool keep_outside(const TraceEvent& ev) const;

  void write_marker(TraceType t, uint32_t range_id,
                    uint32_t pc, uint64_t cycle, uint64_t commit_id);

  // ring 里的一项(itrace 或通用事件)。自包含, 不依赖 tools 侧类型。
  struct RingItem {
    bool     is_itrace;
    uint32_t pc;
    uint32_t inst;      // itrace: 指令编码; 事件: data
    uint32_t addr;
    uint16_t type;
    uint16_t flags;
    uint16_t len;
    uint8_t  channel;
    uint8_t  region;
    uint64_t cycle;
    uint64_t commit_id;
  };
  void ring_push_event(const TraceEvent& ev);
  void ring_push_itrace(uint32_t pc, uint32_t inst, uint64_t cycle, uint64_t commit_id);
  void ring_push(const RingItem& it);

  BinaryWriter writer_;
  bool     enabled_ = false;

  std::vector<CycleRange> ranges_;      // 已 normalize; 空 = 全量
  RangeUnit     range_unit_ = RangeUnit::CYCLE;
  OutsidePolicy outside_ = OutsidePolicy::RING;
  uint32_t      types_ = kTraceCategoryDefault;
  uint32_t      sample_ = 1;
  uint64_t      sample_counter_ = 0;
  bool          include_crit_outside_ = false;
  uint64_t      inflight_commit_ = 0;

  bool     last_inside_ = false;
  uint32_t cur_range_id_ = 0;
  uint64_t last_inside_cycle_ = 0;   // 最后一个落在范围内的 cycle(供 END marker)
  uint64_t next_seq_ = 0;

  // 统计(进入 summary)
  uint64_t stat_ring_ = 0;

  // ring buffer + 快照
  std::deque<RingItem> ring_;
  uint64_t    ring_cap_ = 1000000;
  TraceMeta   snap_meta_;                 // init 时保存, 供 snapshot 复用
  std::string snap_path_ = "snapshot.npct";
  std::string snap_log_  = "snapshot.log";
  bool        snap_done_ = false;
};
}  // namespace npctrace

#endif  // __NPC_TRACE_MANAGER_H__
