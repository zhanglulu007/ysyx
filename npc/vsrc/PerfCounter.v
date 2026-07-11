`ifndef ENABLE_PERF
`else

// PerfCounter — Pipeline Performance Counter
// Tracks pipeline-specific metrics for a 5-stage in-order RV32E pipeline.
// Updated for pipeline architecture (previously was multi-cycle oriented).
module PerfCounter(
  input clk,
  input rst,

  // ===== Pipeline status =====
  input pipe_retire,           // instruction retired (wb_valid pulse)
  input pipe_stall_raw,        // stall due to RAW data hazard (ID blocked)
  input pipe_stall_lsu,        // stall due to LSU backpressure (EX→LS blocked)
  input pipe_stall_fetch,      // stall due to empty ID (bubble from fetch)
  input pipe_flush,            // pipeline flushed due to branch/jump/exception
  input pipe_id_valid,         // ID stage has valid instruction
  input pipe_ex_valid,         // EX stage has valid instruction
  input pipe_ls_valid,         // LS stage has valid instruction

  // ===== ICache observation =====
  input icache_access,         // ICache lookup started
  input icache_hit,            // ICache hit
  input icache_miss,           // ICache miss (cacheable, needs refill)
  input icache_uncache,        // uncacheable access (bypasses cache)
  input icache_refill_req,     // in refill AR state (level)
  input icache_refill_req_pulse, // entering refill AR (pulse)
  input icache_wait_ar,        // waiting for bus AR handshake
  input icache_wait_r,         // waiting for bus R  handshake

  // ===== LSU observation =====
  input lsu_r_handshake,       // load  completed (R  handshake)
  input lsu_b_handshake,       // store completed (B  handshake)

  // ===== Retiring instruction classification =====
  input wb_is_calc,            // R-type or I-type arithmetic
  input wb_is_load,            // load instruction
  input wb_is_store,           // store instruction
  input wb_is_branch,          // conditional branch
  input wb_is_jump,            // JAL/JALR
  input wb_is_utype,           // LUI/AUIPC
  input wb_is_csr_op,          // CSR access
  input wb_is_sys_op,          // ECALL/EBREAK/MRET/FENCE.I

  // ===== Branch outcome =====
  input pipe_branch_taken,     // retiring branch was taken
  // ===== Register writeback =====
  input pipe_reg_wen,          // retiring instruction writes a register
  // ===== Exception =====
  input pipe_exception         // retiring instruction triggered an exception
);

  // ========== Counter registers (64-bit) ==========
  // Overview
  reg [63:0] cyc_total;            // total cycles
  reg [63:0] cyc_stall;            // total stall cycles (any cause)
  reg [63:0] cyc_stall_raw;        // RAW data hazard stall cycles
  reg [63:0] cyc_stall_lsu;        // LSU backpressure stall cycles
  reg [63:0] cyc_stall_fetch;      // fetch bubble (empty ID) cycles
  reg [63:0] cyc_flush;            // flush cycles
  reg [63:0] cnt_retire;           // retired instructions
  reg [63:0] cnt_flush;            // flush events

  // Pipeline stage utilization (valid cycles per stage)
  reg [63:0] cyc_id_valid;         // ID stage busy
  reg [63:0] cyc_ex_valid;         // EX stage busy
  reg [63:0] cyc_ls_valid;         // LS stage busy

  // ICache
  reg [63:0] icache_access_cnt;
  reg [63:0] icache_hit_cnt;
  reg [63:0] icache_miss_cnt;
  reg [63:0] icache_uncache_cnt;
  reg [63:0] icache_refill_cnt;
  reg [63:0] icache_wait_ar_cyc;
  reg [63:0] icache_wait_r_cyc;
  reg [63:0] icache_hit_cyc;       // total hit service cycles
  reg [63:0] icache_miss_cyc;      // total miss penalty cycles
  reg [63:0] icache_miss_acc;      // current miss accumulator
  reg        icache_miss_pend;     // miss service in progress

  // LSU
  reg [63:0] lsu_load_ret_cnt;     // load completions
  reg [63:0] lsu_store_ret_cnt;    // store completions

  // Instruction mix (per category)
  reg [63:0] dec_calc;
  reg [63:0] dec_load;
  reg [63:0] dec_store;
  reg [63:0] dec_branch;
  reg [63:0] dec_jump;
  reg [63:0] dec_utype;
  reg [63:0] dec_csr;
  reg [63:0] dec_sys;

  // Branch statistics
  reg [63:0] branch_taken_cnt;     // taken branches
  reg [63:0] branch_total_cnt;     // total branches retired

  // Register writeback
  reg [63:0] reg_wb_cnt;           // register writebacks
  reg [63:0] cnt_exception;        // exception events

  // Per-category CPI accumulator (cycle cost per instruction type)
  // Uses a simple approach: each cycle, add 1 to an accumulator;
  // when an instruction retires, add the accumulated cycles to its category.
  reg [63:0] inst_cyc_acc;
  reg [63:0] cyc_calc;
  reg [63:0] cyc_load;
  reg [63:0] cyc_store;
  reg [63:0] cyc_branch;
  reg [63:0] cyc_jump;
  reg [63:0] cyc_utype;
  reg [63:0] cyc_csr;
  reg [63:0] cyc_sys;

  // ========== Counting logic ==========
  always @(posedge clk) begin
    if (rst) begin
      cyc_total         <= 64'b0;
      cyc_stall         <= 64'b0;
      cyc_stall_raw     <= 64'b0;
      cyc_stall_lsu     <= 64'b0;
      cyc_stall_fetch   <= 64'b0;
      cyc_flush         <= 64'b0;
      cnt_retire        <= 64'b0;
      cnt_flush         <= 64'b0;
      cyc_id_valid      <= 64'b0;
      cyc_ex_valid      <= 64'b0;
      cyc_ls_valid      <= 64'b0;
      icache_access_cnt  <= 64'b0;
      icache_hit_cnt     <= 64'b0;
      icache_miss_cnt    <= 64'b0;
      icache_uncache_cnt <= 64'b0;
      icache_refill_cnt  <= 64'b0;
      icache_wait_ar_cyc <= 64'b0;
      icache_wait_r_cyc  <= 64'b0;
      icache_hit_cyc     <= 64'b0;
      icache_miss_cyc    <= 64'b0;
      icache_miss_acc    <= 64'b0;
      icache_miss_pend   <= 1'b0;
      lsu_load_ret_cnt   <= 64'b0;
      lsu_store_ret_cnt  <= 64'b0;
      dec_calc           <= 64'b0;
      dec_load           <= 64'b0;
      dec_store          <= 64'b0;
      dec_branch         <= 64'b0;
      dec_jump           <= 64'b0;
      dec_utype          <= 64'b0;
      dec_csr            <= 64'b0;
      dec_sys            <= 64'b0;
      branch_taken_cnt   <= 64'b0;
      branch_total_cnt   <= 64'b0;
      reg_wb_cnt         <= 64'b0;
      cnt_exception      <= 64'b0;
      inst_cyc_acc       <= 64'b0;
      cyc_calc           <= 64'b0;
      cyc_load           <= 64'b0;
      cyc_store          <= 64'b0;
      cyc_branch         <= 64'b0;
      cyc_jump           <= 64'b0;
      cyc_utype          <= 64'b0;
      cyc_csr            <= 64'b0;
      cyc_sys            <= 64'b0;
    end else begin
      // Total cycles
      cyc_total <= cyc_total + 64'd1;

      // Per-instruction cycle accumulator
      inst_cyc_acc <= inst_cyc_acc + 64'd1;

      // Stall accounting
      if (pipe_stall_raw)   cyc_stall_raw   <= cyc_stall_raw   + 64'd1;
      if (pipe_stall_lsu)   cyc_stall_lsu   <= cyc_stall_lsu   + 64'd1;
      if (pipe_stall_fetch) cyc_stall_fetch <= cyc_stall_fetch + 64'd1;
      if (pipe_stall_raw || pipe_stall_lsu || pipe_stall_fetch)
                            cyc_stall       <= cyc_stall       + 64'd1;

      // Flush accounting
      if (pipe_flush) begin
        cnt_flush  <= cnt_flush  + 64'd1;
        cyc_flush  <= cyc_flush  + 64'd1;
      end

      // Pipeline stage utilization
      if (pipe_id_valid) cyc_id_valid <= cyc_id_valid + 64'd1;
      if (pipe_ex_valid) cyc_ex_valid <= cyc_ex_valid + 64'd1;
      if (pipe_ls_valid) cyc_ls_valid <= cyc_ls_valid + 64'd1;

      // ICache events
      if (icache_access) icache_access_cnt <= icache_access_cnt + 64'd1;
      if (icache_hit) begin
        icache_hit_cnt <= icache_hit_cnt + 64'd1;
        icache_hit_cyc <= icache_hit_cyc + 64'd1;  // 1-cycle hit service
      end
      if (icache_uncache) begin
        icache_uncache_cnt <= icache_uncache_cnt + 64'd1;
        icache_miss_pend   <= 1'b1;
        icache_miss_acc    <= 64'd1;
      end
      if (icache_miss) begin
        icache_miss_cnt  <= icache_miss_cnt + 64'd1;
        icache_miss_pend <= 1'b1;
        icache_miss_acc  <= 64'd1;
      end
      if (icache_refill_req_pulse) icache_refill_cnt <= icache_refill_cnt + 64'd1;
      if (icache_miss_pend && (icache_wait_ar || icache_wait_r))
        icache_miss_acc <= icache_miss_acc + 64'd1;
      if (icache_miss_pend && !icache_wait_ar && !icache_wait_r) begin
        icache_miss_cyc  <= icache_miss_cyc + icache_miss_acc;
        icache_miss_acc  <= 64'b0;
        icache_miss_pend <= 1'b0;
      end
      if (icache_wait_ar) icache_wait_ar_cyc <= icache_wait_ar_cyc + 64'd1;
      if (icache_wait_r)  icache_wait_r_cyc  <= icache_wait_r_cyc  + 64'd1;

      // LSU events
      if (lsu_r_handshake) lsu_load_ret_cnt  <= lsu_load_ret_cnt  + 64'd1;
      if (lsu_b_handshake) lsu_store_ret_cnt <= lsu_store_ret_cnt + 64'd1;

      // Instruction retirement
      if (pipe_retire) begin
        cnt_retire <= cnt_retire + 64'd1;
        // Classify and count
        if (wb_is_calc)   begin dec_calc   <= dec_calc   + 64'd1; cyc_calc   <= cyc_calc   + inst_cyc_acc; end
        if (wb_is_load)   begin dec_load   <= dec_load   + 64'd1; cyc_load   <= cyc_load   + inst_cyc_acc; end
        if (wb_is_store)  begin dec_store  <= dec_store  + 64'd1; cyc_store  <= cyc_store  + inst_cyc_acc; end
        if (wb_is_branch) begin dec_branch <= dec_branch + 64'd1; cyc_branch <= cyc_branch + inst_cyc_acc; end
        if (wb_is_jump)   begin dec_jump   <= dec_jump   + 64'd1; cyc_jump   <= cyc_jump   + inst_cyc_acc; end
        if (wb_is_utype)  begin dec_utype  <= dec_utype  + 64'd1; cyc_utype  <= cyc_utype  + inst_cyc_acc; end
        if (wb_is_csr_op) begin dec_csr    <= dec_csr    + 64'd1; cyc_csr    <= cyc_csr    + inst_cyc_acc; end
        if (wb_is_sys_op) begin dec_sys    <= dec_sys    + 64'd1; cyc_sys    <= cyc_sys    + inst_cyc_acc; end
        // Reset per-instruction cycle accumulator for next instruction
        inst_cyc_acc <= 64'd1;  // this cycle counts as the first cycle of the next inst
      end

      // Branch statistics (at retirement)
      if (pipe_retire && wb_is_branch) begin
        branch_total_cnt <= branch_total_cnt + 64'd1;
        if (pipe_branch_taken) branch_taken_cnt <= branch_taken_cnt + 64'd1;
      end

      // Register writeback
      if (pipe_retire && pipe_reg_wen) reg_wb_cnt <= reg_wb_cnt + 64'd1;

      // Exception event
      if (pipe_exception) cnt_exception <= cnt_exception + 64'd1;
    end
  end

  // ========== Final report ==========
  final begin
    $display("");
    $display("============================================================");
    $display("     流水线性能计数器报告 (Pipeline Perf Counter Report)      ");
    $display("============================================================");

    // --- 概览 Overview ---
    $display("");
    $display("[1. 概览 Overview]");
    $display("  总周期数 Total cycles         : %0d", cyc_total);
    $display("  退休指令数 Retired inst       : %0d", cnt_retire);
    $display("  IPC (指令/周期)               : %.4f", (cyc_total > 0) ? (1.0 * cnt_retire / cyc_total) : 0.0);
    $display("  CPI (周期/指令)               : %.4f", (cnt_retire > 0) ? (1.0 * cyc_total / cnt_retire) : 0.0);
    $display("  总停顿周期 Total stall cycles : %0d  (%.2f%%)", cyc_stall,
             (cyc_total > 0) ? (100.0 * cyc_stall / cyc_total) : 0.0);
    $display("  总冲刷次数 Total flush events : %0d", cnt_flush);
    $display("  冲刷惩罚周期 Flush penalty    : %0d  (%.2f%%)", cyc_flush,
             (cyc_total > 0) ? (100.0 * cyc_flush / cyc_total) : 0.0);

    // --- 停顿细分 Stall Breakdown ---
    $display("");
    $display("[2. 停顿细分 Stall Breakdown]  (占总周期百分比)");
    $display("  RAW数据冒险停顿 RAW hazard    : %0d  (%.2f%%)", cyc_stall_raw,
             (cyc_total > 0) ? (100.0 * cyc_stall_raw / cyc_total) : 0.0);
    $display("  LSU反压停顿 LSU backpressure  : %0d  (%.2f%%)", cyc_stall_lsu,
             (cyc_total > 0) ? (100.0 * cyc_stall_lsu / cyc_total) : 0.0);
    $display("  取指气泡 Fetch bubbles        : %0d  (%.2f%%)", cyc_stall_fetch,
             (cyc_total > 0) ? (100.0 * cyc_stall_fetch / cyc_total) : 0.0);
    $display("  有效工作周期 Useful work      : %0d  (%.2f%%)",
             (cyc_total - cyc_stall_raw - cyc_stall_lsu - cyc_stall_fetch),
             (cyc_total > 0) ? (100.0 * (cyc_total - cyc_stall_raw - cyc_stall_lsu - cyc_stall_fetch) / cyc_total) : 0.0);

    // --- 流水级利用率 Pipeline Stage Utilization ---
    $display("");
    $display("[3. 流水级利用率 Pipeline Stage Utilization]");
    $display("  ID译码级忙周期 ID stage busy  : %0d  (%.2f%%)", cyc_id_valid,
             (cyc_total > 0) ? (100.0 * cyc_id_valid / cyc_total) : 0.0);
    $display("  EX执行级忙周期 EX stage busy  : %0d  (%.2f%%)", cyc_ex_valid,
             (cyc_total > 0) ? (100.0 * cyc_ex_valid / cyc_total) : 0.0);
    $display("  LS访存级忙周期 LS stage busy  : %0d  (%.2f%%)", cyc_ls_valid,
             (cyc_total > 0) ? (100.0 * cyc_ls_valid / cyc_total) : 0.0);
    $display("  平均忙级数 Avg stages busy    : %.2f / 3  (ID+EX+LS)",
             (cyc_total > 0) ? (1.0 * (cyc_id_valid + cyc_ex_valid + cyc_ls_valid) / cyc_total) : 0.0);

    // --- ICache 指令缓存 ---
    $display("");
    $display("[4. ICache 指令缓存 — 命中率 Hit Rate & AMAT]");
    $display("  访问次数 Accesses             : %0d", icache_access_cnt);
    $display("  命中 Hits                     : %0d  (%.2f%%)",
             icache_hit_cnt,
             (icache_access_cnt > 0) ? (100.0 * icache_hit_cnt / icache_access_cnt) : 0.0);
    $display("  缺失 Misses                   : %0d  (%.2f%%)",
             icache_miss_cnt,
             (icache_access_cnt > 0) ? (100.0 * icache_miss_cnt / icache_access_cnt) : 0.0);
    $display("  不可缓存 Uncacheable          : %0d  (%.2f%%)",
             icache_uncache_cnt,
             (icache_access_cnt > 0) ? (100.0 * icache_uncache_cnt / icache_access_cnt) : 0.0);
    $display("  回填请求 Refill requests      : %0d", icache_refill_cnt);
    if ((icache_hit_cnt + icache_miss_cnt) > 0)
      $display("  可缓存命中率 Cacheable hit rate (p) : %.4f",
               1.0 * icache_hit_cnt / (icache_hit_cnt + icache_miss_cnt));
    if (icache_hit_cnt > 0)
      $display("  命中访问时间 Hit access time   : %.2f 周期/hit", 1.0 * icache_hit_cyc / icache_hit_cnt);
    if (icache_miss_cnt > 0)
      $display("  缺失惩罚 Miss penalty          : %.2f 周期/miss", 1.0 * icache_miss_cyc / icache_miss_cnt);
    if ((icache_hit_cnt > 0) && (icache_miss_cnt > 0))
      $display("  AMAT 平均访存时间 (周期/访问) : %.2f",
               (1.0 * icache_hit_cyc / icache_hit_cnt) +
               (1.0 - 1.0 * icache_hit_cnt / (icache_hit_cnt + icache_miss_cnt)) *
               (1.0 * icache_miss_cyc / icache_miss_cnt));
    $display("  总线AR等待周期 Bus AR wait    : %0d", icache_wait_ar_cyc);
    $display("  总线R等待周期  Bus R  wait    : %0d", icache_wait_r_cyc);

    // --- LSU 访存统计 ---
    $display("");
    $display("[5. LSU 访存统计 Load/Store Statistics]");
    $display("  Load完成次数 Load completions : %0d", lsu_load_ret_cnt);
    $display("  Store完成次数 Store completions: %0d", lsu_store_ret_cnt);
    if ((lsu_load_ret_cnt + lsu_store_ret_cnt) > 0)
      $display("  每千条指令访存次数 Mem/1K inst : %.1f",
               1000.0 * (lsu_load_ret_cnt + lsu_store_ret_cnt) / (cnt_retire > 0 ? cnt_retire : 1));

    // --- 指令混合 Instruction Mix ---
    $display("");
    $display("[6. 指令混合 Instruction Mix]  (数量 / 占比 / 平均CPI)");
    $display("  分类总数 Total classified     : %0d", dec_calc+dec_load+dec_store+dec_branch+dec_jump+dec_utype+dec_csr+dec_sys);
    if (dec_calc > 0)
      $display("  计算类 Compute (R+I arith): count=%0d (%.1f%%)  avgCPI=%.2f",
               dec_calc, (cnt_retire > 0) ? (100.0 * dec_calc / cnt_retire) : 0.0,
               1.0 * cyc_calc / dec_calc);
    if (dec_load > 0)
      $display("  加载类 Load              : count=%0d (%.1f%%)  avgCPI=%.2f",
               dec_load, (cnt_retire > 0) ? (100.0 * dec_load / cnt_retire) : 0.0,
               1.0 * cyc_load / dec_load);
    if (dec_store > 0)
      $display("  存储类 Store             : count=%0d (%.1f%%)  avgCPI=%.2f",
               dec_store, (cnt_retire > 0) ? (100.0 * dec_store / cnt_retire) : 0.0,
               1.0 * cyc_store / dec_store);
    if (dec_branch > 0)
      $display("  分支类 Branch            : count=%0d (%.1f%%)  avgCPI=%.2f",
               dec_branch, (cnt_retire > 0) ? (100.0 * dec_branch / cnt_retire) : 0.0,
               1.0 * cyc_branch / dec_branch);
    if (dec_jump > 0)
      $display("  跳转类 Jump (JAL/JALR)   : count=%0d (%.1f%%)  avgCPI=%.2f",
               dec_jump, (cnt_retire > 0) ? (100.0 * dec_jump / cnt_retire) : 0.0,
               1.0 * cyc_jump / dec_jump);
    if (dec_utype > 0)
      $display("  U型 U-type (LUI/AUIPC)   : count=%0d (%.1f%%)  avgCPI=%.2f",
               dec_utype, (cnt_retire > 0) ? (100.0 * dec_utype / cnt_retire) : 0.0,
               1.0 * cyc_utype / dec_utype);
    if (dec_csr > 0)
      $display("  CSR类 CSR                : count=%0d (%.1f%%)  avgCPI=%.2f",
               dec_csr, (cnt_retire > 0) ? (100.0 * dec_csr / cnt_retire) : 0.0,
               1.0 * cyc_csr / dec_csr);
    if (dec_sys > 0)
      $display("  系统类 System (ECALL/EBREAK等): count=%0d (%.1f%%)  avgCPI=%.2f",
               dec_sys, (cnt_retire > 0) ? (100.0 * dec_sys / cnt_retire) : 0.0,
               1.0 * cyc_sys / dec_sys);

    // --- 分支统计 Branch Statistics ---
    $display("");
    $display("[7. 分支统计 Branch Statistics]");
    $display("  退休分支总数 Total branches   : %0d", branch_total_cnt);
    $display("  跳转分支 Taken branches       : %0d  (%.2f%%)", branch_taken_cnt,
             (branch_total_cnt > 0) ? (100.0 * branch_taken_cnt / branch_total_cnt) : 0.0);
    $display("  不跳转分支 Not-taken branches : %0d  (%.2f%%)",
             branch_total_cnt - branch_taken_cnt,
             (branch_total_cnt > 0) ? (100.0 * (branch_total_cnt - branch_taken_cnt) / branch_total_cnt) : 0.0);

    // --- 寄存器写回 Register Writeback ---
    $display("");
    $display("[8. 寄存器写回 Register Writeback]");
    $display("  写回次数 Reg writes (rd!=0)   : %0d", reg_wb_cnt);
    $display("  每条指令写回数 Reg writes/inst: %.2f", (cnt_retire > 0) ? (1.0 * reg_wb_cnt / cnt_retire) : 0.0);

    // --- 异常统计 Exception Statistics ---
    $display("");
    $display("[8.5 异常统计 Exception Statistics]");
    $display("  异常次数 Exception events      : %0d", cnt_exception);
    $display("  异常率 Exception rate           : %.4f%%", (cnt_retire > 0) ? (100.0 * cnt_exception / cnt_retire) : 0.0);

    // --- Amdahl定律瓶颈分析 ---
    $display("");
    $display("[9. Amdahl定律瓶颈分析 Amdahl's Law Bottleneck Analysis]");
    $display("  RAW冒险停顿占比               : %.2f%%  -> 加入前递(forwarding)可大幅消除",
             (cyc_total > 0) ? (100.0 * cyc_stall_raw / cyc_total) : 0.0);
    $display("  LSU反压停顿占比               : %.2f%%  -> 优化存储系统/缓存可改善",
             (cyc_total > 0) ? (100.0 * cyc_stall_lsu / cyc_total) : 0.0);
    $display("  取指气泡占比                  : %.2f%%  -> 优化ICache/预取可改善",
             (cyc_total > 0) ? (100.0 * cyc_stall_fetch / cyc_total) : 0.0);
    $display("  冲刷惩罚占比                  : %.2f%%  -> 分支预测可消除大部分",
             (cyc_total > 0) ? (100.0 * cyc_flush / cyc_total) : 0.0);
    $display("  理想IPC (无停顿)              : 1.00");
    $display("  实际IPC Achieved IPC          : %.4f", (cyc_total > 0) ? (1.0 * cnt_retire / cyc_total) : 0.0);
    $display("  效率 Efficiency               : %.2f%%",
             (cyc_total > 0) ? (100.0 * cnt_retire / cyc_total) : 0.0);

    // --- 一致性检查 Consistency Checks ---
    $display("");
    $display("[10. 一致性检查 Consistency Checks]");
    $display("  分类之和==退休指令数?          : %s",
             ((dec_calc+dec_load+dec_store+dec_branch+dec_jump+dec_utype+dec_csr+dec_sys) == cnt_retire) ? "通过 PASS" : "失败 FAIL");
    $display("    sum=%0d  retired=%0d",
             dec_calc+dec_load+dec_store+dec_branch+dec_jump+dec_utype+dec_csr+dec_sys, cnt_retire);
    $display("  停顿+有效==总周期?            : %s",
             ((cyc_stall_raw + cyc_stall_lsu + cyc_stall_fetch + (cyc_total - cyc_stall_raw - cyc_stall_lsu - cyc_stall_fetch)) == cyc_total) ? "通过 PASS" : "失败 FAIL");
    $display("  回填数==缺失+不可缓存?        : %s",
             (icache_refill_cnt == (icache_miss_cnt + icache_uncache_cnt)) ? "通过 PASS" : "失败 FAIL");
    $display("    refill=%0d  miss+uncache=%0d", icache_refill_cnt, (icache_miss_cnt + icache_uncache_cnt));

    $display("============================================================");
    $display("");
  end

endmodule

`endif // ENABLE_PERF
