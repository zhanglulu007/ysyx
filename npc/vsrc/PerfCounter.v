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
  input pipe_reg_wen           // retiring instruction writes a register
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
    end
  end

  // ========== Final report ==========
  final begin
    $display("");
    $display("============================================================");
    $display("        Pipeline Performance Counter Report                 ");
    $display("============================================================");

    // --- Overview ---
    $display("");
    $display("[1. Overview]");
    $display("  Total cycles                 : %0d", cyc_total);
    $display("  Retired instructions         : %0d", cnt_retire);
    $display("  IPC                          : %.4f", (cyc_total > 0) ? (1.0 * cnt_retire / cyc_total) : 0.0);
    $display("  CPI (1/IPC)                  : %.4f", (cnt_retire > 0) ? (1.0 * cyc_total / cnt_retire) : 0.0);
    $display("  Total stall cycles           : %0d  (%.2f%%)", cyc_stall,
             (cyc_total > 0) ? (100.0 * cyc_stall / cyc_total) : 0.0);
    $display("  Total flush events           : %0d", cnt_flush);
    $display("  Flush penalty cycles         : %0d  (%.2f%%)", cyc_flush,
             (cyc_total > 0) ? (100.0 * cyc_flush / cyc_total) : 0.0);

    // --- Stall Breakdown ---
    $display("");
    $display("[2. Stall Breakdown]  (percentage of total cycles)");
    $display("  RAW data hazard stalls       : %0d  (%.2f%%)", cyc_stall_raw,
             (cyc_total > 0) ? (100.0 * cyc_stall_raw / cyc_total) : 0.0);
    $display("  LSU backpressure stalls      : %0d  (%.2f%%)", cyc_stall_lsu,
             (cyc_total > 0) ? (100.0 * cyc_stall_lsu / cyc_total) : 0.0);
    $display("  Fetch bubbles (empty ID)     : %0d  (%.2f%%)", cyc_stall_fetch,
             (cyc_total > 0) ? (100.0 * cyc_stall_fetch / cyc_total) : 0.0);
    $display("  Useful work cycles           : %0d  (%.2f%%)",
             (cyc_total - cyc_stall_raw - cyc_stall_lsu - cyc_stall_fetch),
             (cyc_total > 0) ? (100.0 * (cyc_total - cyc_stall_raw - cyc_stall_lsu - cyc_stall_fetch) / cyc_total) : 0.0);

    // --- Pipeline Stage Utilization ---
    $display("");
    $display("[3. Pipeline Stage Utilization]");
    $display("  ID stage busy cycles         : %0d  (%.2f%%)", cyc_id_valid,
             (cyc_total > 0) ? (100.0 * cyc_id_valid / cyc_total) : 0.0);
    $display("  EX stage busy cycles         : %0d  (%.2f%%)", cyc_ex_valid,
             (cyc_total > 0) ? (100.0 * cyc_ex_valid / cyc_total) : 0.0);
    $display("  LS stage busy cycles         : %0d  (%.2f%%)", cyc_ls_valid,
             (cyc_total > 0) ? (100.0 * cyc_ls_valid / cyc_total) : 0.0);
    $display("  Avg stages busy              : %.2f / 3  (ID+EX+LS)",
             (cyc_total > 0) ? (1.0 * (cyc_id_valid + cyc_ex_valid + cyc_ls_valid) / cyc_total) : 0.0);

    // --- ICache ---
    $display("");
    $display("[4. ICache — Hit Rate & AMAT]");
    $display("  Accesses                     : %0d", icache_access_cnt);
    $display("  Hits                         : %0d  (%.2f%%)",
             icache_hit_cnt,
             (icache_access_cnt > 0) ? (100.0 * icache_hit_cnt / icache_access_cnt) : 0.0);
    $display("  Misses                       : %0d  (%.2f%%)",
             icache_miss_cnt,
             (icache_access_cnt > 0) ? (100.0 * icache_miss_cnt / icache_access_cnt) : 0.0);
    $display("  Uncacheable                  : %0d  (%.2f%%)",
             icache_uncache_cnt,
             (icache_access_cnt > 0) ? (100.0 * icache_uncache_cnt / icache_access_cnt) : 0.0);
    $display("  Refill requests              : %0d", icache_refill_cnt);
    if ((icache_hit_cnt + icache_miss_cnt) > 0)
      $display("  Cacheable hit rate (p)       : %.4f",
               1.0 * icache_hit_cnt / (icache_hit_cnt + icache_miss_cnt));
    if (icache_hit_cnt > 0)
      $display("  Hit access time (cycles/hit) : %.2f", 1.0 * icache_hit_cyc / icache_hit_cnt);
    if (icache_miss_cnt > 0)
      $display("  Miss penalty (cycles/miss)   : %.2f", 1.0 * icache_miss_cyc / icache_miss_cnt);
    if ((icache_hit_cnt > 0) && (icache_miss_cnt > 0))
      $display("  AMAT (cycles/access)         : %.2f",
               (1.0 * icache_hit_cyc / icache_hit_cnt) +
               (1.0 - 1.0 * icache_hit_cnt / (icache_hit_cnt + icache_miss_cnt)) *
               (1.0 * icache_miss_cyc / icache_miss_cnt));
    $display("  Bus AR wait cycles           : %0d", icache_wait_ar_cyc);
    $display("  Bus R  wait cycles           : %0d", icache_wait_r_cyc);

    // --- LSU ---
    $display("");
    $display("[5. LSU — Load/Store Statistics]");
    $display("  Load completions             : %0d", lsu_load_ret_cnt);
    $display("  Store completions            : %0d", lsu_store_ret_cnt);
    if ((lsu_load_ret_cnt + lsu_store_ret_cnt) > 0)
      $display("  Memory inst per 1K retired   : %.1f",
               1000.0 * (lsu_load_ret_cnt + lsu_store_ret_cnt) / (cnt_retire > 0 ? cnt_retire : 1));

    // --- Instruction Mix ---
    $display("");
    $display("[6. Instruction Mix]  (count / %% / avg CPI)");
    $display("  Total classified             : %0d", dec_calc+dec_load+dec_store+dec_branch+dec_jump+dec_utype+dec_csr+dec_sys);
    if (dec_calc > 0)
      $display("  Compute (R+I arith)  : count=%0d (%.1f%%)  avgCPI=%.2f",
               dec_calc, (cnt_retire > 0) ? (100.0 * dec_calc / cnt_retire) : 0.0,
               1.0 * cyc_calc / dec_calc);
    if (dec_load > 0)
      $display("  Load                 : count=%0d (%.1f%%)  avgCPI=%.2f",
               dec_load, (cnt_retire > 0) ? (100.0 * dec_load / cnt_retire) : 0.0,
               1.0 * cyc_load / dec_load);
    if (dec_store > 0)
      $display("  Store                : count=%0d (%.1f%%)  avgCPI=%.2f",
               dec_store, (cnt_retire > 0) ? (100.0 * dec_store / cnt_retire) : 0.0,
               1.0 * cyc_store / dec_store);
    if (dec_branch > 0)
      $display("  Branch               : count=%0d (%.1f%%)  avgCPI=%.2f",
               dec_branch, (cnt_retire > 0) ? (100.0 * dec_branch / cnt_retire) : 0.0,
               1.0 * cyc_branch / dec_branch);
    if (dec_jump > 0)
      $display("  Jump (JAL/JALR)      : count=%0d (%.1f%%)  avgCPI=%.2f",
               dec_jump, (cnt_retire > 0) ? (100.0 * dec_jump / cnt_retire) : 0.0,
               1.0 * cyc_jump / dec_jump);
    if (dec_utype > 0)
      $display("  U-type (LUI/AUIPC)   : count=%0d (%.1f%%)  avgCPI=%.2f",
               dec_utype, (cnt_retire > 0) ? (100.0 * dec_utype / cnt_retire) : 0.0,
               1.0 * cyc_utype / dec_utype);
    if (dec_csr > 0)
      $display("  CSR                  : count=%0d (%.1f%%)  avgCPI=%.2f",
               dec_csr, (cnt_retire > 0) ? (100.0 * dec_csr / cnt_retire) : 0.0,
               1.0 * cyc_csr / dec_csr);
    if (dec_sys > 0)
      $display("  System (ECALL/EBREAK etc.): count=%0d (%.1f%%)  avgCPI=%.2f",
               dec_sys, (cnt_retire > 0) ? (100.0 * dec_sys / cnt_retire) : 0.0,
               1.0 * cyc_sys / dec_sys);

    // --- Branch Statistics ---
    $display("");
    $display("[7. Branch Statistics]");
    $display("  Total branches retired       : %0d", branch_total_cnt);
    $display("  Taken branches               : %0d  (%.2f%%)", branch_taken_cnt,
             (branch_total_cnt > 0) ? (100.0 * branch_taken_cnt / branch_total_cnt) : 0.0);
    $display("  Not-taken branches           : %0d  (%.2f%%)",
             branch_total_cnt - branch_taken_cnt,
             (branch_total_cnt > 0) ? (100.0 * (branch_total_cnt - branch_taken_cnt) / branch_total_cnt) : 0.0);

    // --- Register Writeback ---
    $display("");
    $display("[8. Register Writeback]");
    $display("  Reg writes (rd != 0)         : %0d", reg_wb_cnt);
    $display("  Reg writes per retired inst  : %.2f", (cnt_retire > 0) ? (1.0 * reg_wb_cnt / cnt_retire) : 0.0);

    // --- Amdahl's Law Analysis ---
    $display("");
    $display("[9. Amdahl's Law Bottleneck Analysis]");
    $display("  RAW hazard stall share       : %.2f%%  -> forwarding could recover most of this",
             (cyc_total > 0) ? (100.0 * cyc_stall_raw / cyc_total) : 0.0);
    $display("  LSU backpressure share       : %.2f%%  -> better memory/cache could help",
             (cyc_total > 0) ? (100.0 * cyc_stall_lsu / cyc_total) : 0.0);
    $display("  Fetch bubble share           : %.2f%%  -> better ICache/prefetch could help",
             (cyc_total > 0) ? (100.0 * cyc_stall_fetch / cyc_total) : 0.0);
    $display("  Flush penalty share          : %.2f%%  -> branch prediction could recover this",
             (cyc_total > 0) ? (100.0 * cyc_flush / cyc_total) : 0.0);
    $display("  Ideal IPC (no stalls)        : 1.00");
    $display("  Achieved IPC                 : %.4f", (cyc_total > 0) ? (1.0 * cnt_retire / cyc_total) : 0.0);
    $display("  Efficiency                   : %.2f%%",
             (cyc_total > 0) ? (100.0 * cnt_retire / cyc_total) : 0.0);

    // --- Consistency Checks ---
    $display("");
    $display("[10. Consistency Checks]");
    $display("  Classified sum == retired?   : %s",
             ((dec_calc+dec_load+dec_store+dec_branch+dec_jump+dec_utype+dec_csr+dec_sys) == cnt_retire) ? "PASS" : "FAIL");
    $display("    sum=%0d  retired=%0d",
             dec_calc+dec_load+dec_store+dec_branch+dec_jump+dec_utype+dec_csr+dec_sys, cnt_retire);
    $display("  Stall + useful == total?     : %s",
             ((cyc_stall_raw + cyc_stall_lsu + cyc_stall_fetch + (cyc_total - cyc_stall_raw - cyc_stall_lsu - cyc_stall_fetch)) == cyc_total) ? "PASS" : "FAIL");
    $display("  refill == miss+uncache?      : %s",
             (icache_refill_cnt == (icache_miss_cnt + icache_uncache_cnt)) ? "PASS" : "FAIL");
    $display("    refill=%0d  miss+uncache=%0d", icache_refill_cnt, (icache_miss_cnt + icache_uncache_cnt));

    $display("============================================================");
    $display("");
  end

endmodule

`endif // ENABLE_PERF
