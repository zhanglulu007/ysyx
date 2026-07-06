// PerfCounter - 性能计数器 (仅仿真用, 不参与综合)
// =============================================================================
// 用途: 统计 NPC 内部各类性能事件发生的频次, 在仿真结束时输出性能计数报告,
//       用于定位性能瓶颈 (指令供给 / 数据供给 / 计算效率 / 停顿).
//
// 开关: 仅当 Verilator 编译时传入宏定义 ENABLE_PERF 时, 本模块才被实例化
//       (见 ysyx_26020070.v 中 `ifdef ENABLE_PERF). 综合时不传该宏, 因此本模块
//       的代码不会出现在综合网表中, 不会影响电路面积和频率.
//
// 输出: Verilog 的 initial ... final 块在 Verilator 调用 g_top->final() 时触发,
//       通过 $display 打印性能计数报告到 stdout (同时被 npc.log 记录).
// =============================================================================

`ifndef ENABLE_PERF
`else

module PerfCounter(
  input clk,
  input rst,

  // ===== IFU 取指 (指令供给) =====
  input ifu_ar_handshake,     // IFU 发出一次取指请求 (AR 握手)
  input ifu_r_handshake,      // IFU 取到指令 (R 握手)
  input ifu_lsu_pending,      // IFU 正在等待 LSU (访存指令阻塞取指)
  input ifu_state,            // IFU 状态机状态 (0=IDLE, 1=WAIT)
  input ifu_valid,            // 取到有效指令 (一条指令完成)

  // ===== LSU 访存 (数据供给) =====
  input lsu_load_req,         // 发出 load 请求
  input lsu_store_req,        // 发出 store 请求
  input lsu_r_handshake,      // load 完成 (取到数据)
  input lsu_b_handshake,      // store 完成 (写回复)
  input lsu_wait_ar,          // 等待 AR 握手
  input lsu_wait_r,           // 等待 R 握手
  input lsu_wait_aw_w,        // 等待 AW/W 握手
  input lsu_wait_b,           // 等待 B 握手

  // ===== IDU 译码: 指令类别 (仅在 ifu_valid 时统计) =====
  input ifu_valid_dec,        // = 顶层 ifu_valid (用于门控译码类别计数)
  input is_calc,              // 计算类 (R型 + I型算术逻辑)
  input is_load_inst,         // 加载类
  input is_store_inst,        // 存储类
  input is_branch,            // 分支类
  input is_jump,              // 跳转类 (jal/jalr)
  input is_u_type,            // U型 (lui/auipc)
  input is_csr,               // CSR 类
  input is_sys,               // 系统类 (ebreak/ecall/mret)

  // ===== EXU 计算完成 =====
  input exu_calc_done         // EXU 完成一次计算 (一条非访存指令执行完成)
);

  // ========== 计数器定义 (64位, 避免长时间运行溢出) ==========
  // 总周期 & 停顿
  reg [63:0] cyc_total;           // 总周期数
  reg [63:0] cyc_stall;           // 处理器停顿周期 (IFU 未取到指令, 非 IDLE 等待)
  reg [63:0] cyc_ifu_wait_lsu;    // IFU 因等待 LSU 而停顿的周期

  // IFU - 指令供给
  reg [63:0] ifu_req_cnt;         // IFU 取指请求次数 (AR 握手)
  reg [63:0] ifu_ret_cnt;         // IFU 取到指令次数 (R 握手)
  reg [63:0] ifu_idle_cyc;        // IFU 处于 IDLE 的周期 (取指请求尚未发出/已发出未握手)
  reg [63:0] ifu_no_inst_cyc;     // IFU 未取到指令的周期 (WAIT 态但未完成 R 握手, 且未在等LSU)

  // LSU - 数据供给
  reg [63:0] load_cnt;            // load 指令次数
  reg [63:0] store_cnt;           // store 指令次数
  reg [63:0] load_ret_cnt;        // load 完成 (取到数据) 次数
  reg [63:0] store_ret_cnt;       // store 完成 次数
  reg [63:0] lsu_wait_ar_cyc;     // 等待 AR 握手的周期累计
  reg [63:0] lsu_wait_r_cyc;      // 等待 R  握手的周期累计 (load 延迟主体)
  reg [63:0] lsu_wait_aw_w_cyc;   // 等待 AW/W 握手的周期累计
  reg [63:0] lsu_wait_b_cyc;      // 等待 B  握手的周期累计 (store 延迟主体)

  // IDU - 译码出的各类指令数 (动态指令分类)
  reg [63:0] dec_total;           // 译码出的指令总数 (应 = ifu_ret_cnt = 动态指令数)
  reg [63:0] dec_calc;            // 计算类
  reg [63:0] dec_load;            // 加载类
  reg [63:0] dec_store;           // 存储类
  reg [63:0] dec_branch;          // 分支类
  reg [63:0] dec_jump;            // 跳转类
  reg [63:0] dec_u_type;          // U型
  reg [63:0] dec_csr;             // CSR 类
  reg [63:0] dec_sys;             // 系统类

  // EXU - 计算完成
  reg [63:0] exu_calc_cnt;        // EXU 完成计算次数

  // ========== 计数逻辑 ==========
  // 停顿定义: 处理器既不在 IDLE(没有正在执行指令的空闲), 也没有取到新指令.
  //   即 IFU 处于 WAIT 态但本周期 ifu_valid=0 (含等待LSU / 等待取指握手).
  wire stall_this_cyc = !rst && ifu_state && !ifu_valid;
  // IFU 未取到指令且未在等LSU (纯粹的取指握手等待/数据供给等待)
  wire ifu_no_inst    = !rst && ifu_state && !ifu_valid && !ifu_lsu_pending;

  always @(posedge clk) begin
    if (rst) begin
      cyc_total         <= 64'b0;
      cyc_stall         <= 64'b0;
      cyc_ifu_wait_lsu  <= 64'b0;
      ifu_req_cnt       <= 64'b0;
      ifu_ret_cnt       <= 64'b0;
      ifu_idle_cyc      <= 64'b0;
      ifu_no_inst_cyc   <= 64'b0;
      load_cnt          <= 64'b0;
      store_cnt         <= 64'b0;
      load_ret_cnt      <= 64'b0;
      store_ret_cnt     <= 64'b0;
      lsu_wait_ar_cyc   <= 64'b0;
      lsu_wait_r_cyc    <= 64'b0;
      lsu_wait_aw_w_cyc <= 64'b0;
      lsu_wait_b_cyc    <= 64'b0;
      dec_total         <= 64'b0;
      dec_calc          <= 64'b0;
      dec_load          <= 64'b0;
      dec_store         <= 64'b0;
      dec_branch        <= 64'b0;
      dec_jump          <= 64'b0;
      dec_u_type        <= 64'b0;
      dec_csr           <= 64'b0;
      dec_sys           <= 64'b0;
      exu_calc_cnt      <= 64'b0;
    end else begin
      // 周期统计 (每个非复位周期 +1)
      cyc_total <= cyc_total + 64'd1;

      // 停顿统计
      if (stall_this_cyc)           cyc_stall        <= cyc_stall + 64'd1;
      if (ifu_lsu_pending)          cyc_ifu_wait_lsu <= cyc_ifu_wait_lsu + 64'd1;
      if (ifu_no_inst)              ifu_no_inst_cyc  <= ifu_no_inst_cyc + 64'd1;
      if (!ifu_state)               ifu_idle_cyc     <= ifu_idle_cyc + 64'd1;  // IDLE 周期

      // IFU 事件
      if (ifu_ar_handshake) ifu_req_cnt <= ifu_req_cnt + 64'd1;
      if (ifu_r_handshake)  ifu_ret_cnt <= ifu_ret_cnt + 64'd1;

      // LSU 事件
      if (lsu_load_req)    load_cnt       <= load_cnt + 64'd1;
      if (lsu_store_req)   store_cnt      <= store_cnt + 64'd1;
      if (lsu_r_handshake) load_ret_cnt   <= load_ret_cnt + 64'd1;
      if (lsu_b_handshake) store_ret_cnt  <= store_ret_cnt + 64'd1;
      if (lsu_wait_ar)     lsu_wait_ar_cyc   <= lsu_wait_ar_cyc   + 64'd1;
      if (lsu_wait_r)      lsu_wait_r_cyc    <= lsu_wait_r_cyc    + 64'd1;
      if (lsu_wait_aw_w)   lsu_wait_aw_w_cyc <= lsu_wait_aw_w_cyc + 64'd1;
      if (lsu_wait_b)      lsu_wait_b_cyc    <= lsu_wait_b_cyc    + 64'd1;

      // 译码指令分类 (仅在 ifu_valid 时统计)
      if (ifu_valid_dec) begin
        dec_total   <= dec_total   + 64'd1;
        if (is_calc)       dec_calc    <= dec_calc    + 64'd1;
        if (is_load_inst)  dec_load    <= dec_load    + 64'd1;
        if (is_store_inst) dec_store   <= dec_store   + 64'd1;
        if (is_branch)     dec_branch  <= dec_branch  + 64'd1;
        if (is_jump)       dec_jump    <= dec_jump    + 64'd1;
        if (is_u_type)     dec_u_type  <= dec_u_type  + 64'd1;
        if (is_csr)        dec_csr     <= dec_csr     + 64'd1;
        if (is_sys)        dec_sys     <= dec_sys     + 64'd1;
      end

      // EXU 计算完成
      if (exu_calc_done) exu_calc_cnt <= exu_calc_cnt + 64'd1;
    end
  end

  // ========== 仿真结束时输出性能计数报告 ==========
  // final 块在 Verilator 调用 g_top->final() 时触发 (ebreak 后 / 仿真退出前)
  final begin
    $display("");
    $display("============================================================");
    $display("                  Performance Counter Report               ");
    $display("============================================================");

    // ---- 概览 ----
    $display("");
    $display("[Overview]");
    $display("  Total cycles              : %0d", cyc_total);
    $display("  Retired instructions      : %0d  (= IFU fetched = IDU decoded)", ifu_ret_cnt);
    $display("  IPC                       : %f", (cyc_total > 0) ? (1.0 * ifu_ret_cnt / cyc_total) : 0.0);
    $display("  Stall cycles              : %0d  (%.2f%%)", cyc_stall,
             (cyc_total > 0) ? (100.0 * cyc_stall / cyc_total) : 0.0);

    // ---- IFU 指令供给 ----
    $display("");
    $display("[IFU - Instruction Supply]");
    $display("  Fetch requests (AR hs)    : %0d", ifu_req_cnt);
    $display("  Instructions fetched (R hs): %0d", ifu_ret_cnt);
    $display("  IFU IDLE cycles           : %0d  (%.2f%%)", ifu_idle_cyc,
             (cyc_total > 0) ? (100.0 * ifu_idle_cyc / cyc_total) : 0.0);
    $display("  IFU no-instr cycles       : %0d  (%.2f%%)", ifu_no_inst_cyc,
             (cyc_total > 0) ? (100.0 * ifu_no_inst_cyc / cyc_total) : 0.0);
    $display("  IFU wait-LSU cycles       : %0d  (%.2f%%)", cyc_ifu_wait_lsu,
             (cyc_total > 0) ? (100.0 * cyc_ifu_wait_lsu / cyc_total) : 0.0);

    // ---- LSU 数据供给 ----
    $display("");
    $display("[LSU - Data Supply]");
    $display("  Load  requests            : %0d", load_cnt);
    $display("  Store requests            : %0d", store_cnt);
    $display("  Load  completed (R hs)    : %0d", load_ret_cnt);
    $display("  Store completed (B hs)    : %0d", store_ret_cnt);
    if (load_cnt > 0)
      $display("  Avg load  latency (cyc)   : %.2f  (wait_R=%0d / load=%0d)",
               (1.0 * lsu_wait_r_cyc / load_cnt), lsu_wait_r_cyc, load_cnt);
    if (store_cnt > 0)
      $display("  Avg store latency (cyc)   : %.2f  (wait_B=%0d / store=%0d)",
               (1.0 * lsu_wait_b_cyc / store_cnt), lsu_wait_b_cyc, store_cnt);
    $display("  LSU wait-AR cycles        : %0d", lsu_wait_ar_cyc);
    $display("  LSU wait-R  cycles        : %0d", lsu_wait_r_cyc);
    $display("  LSU wait-AW/W cycles      : %0d", lsu_wait_aw_w_cyc);
    $display("  LSU wait-B  cycles        : %0d", lsu_wait_b_cyc);

    // ---- IDU 指令分类 ----
    $display("");
    $display("[IDU - Instruction Mix]   (count / percent of decoded)");
    $display("  Calc    (R/I arith-log)  : %0d  (%.2f%%)", dec_calc,
             (dec_total > 0) ? (100.0 * dec_calc / dec_total) : 0.0);
    $display("  Load                    : %0d  (%.2f%%)", dec_load,
             (dec_total > 0) ? (100.0 * dec_load / dec_total) : 0.0);
    $display("  Store                   : %0d  (%.2f%%)", dec_store,
             (dec_total > 0) ? (100.0 * dec_store / dec_total) : 0.0);
    $display("  Branch                  : %0d  (%.2f%%)", dec_branch,
             (dec_total > 0) ? (100.0 * dec_branch / dec_total) : 0.0);
    $display("  Jump (jal/jalr)         : %0d  (%.2f%%)", dec_jump,
             (dec_total > 0) ? (100.0 * dec_jump / dec_total) : 0.0);
    $display("  U-type (lui/auipc)      : %0d  (%.2f%%)", dec_u_type,
             (dec_total > 0) ? (100.0 * dec_u_type / dec_total) : 0.0);
    $display("  CSR                     : %0d  (%.2f%%)", dec_csr,
             (dec_total > 0) ? (100.0 * dec_csr / dec_total) : 0.0);
    $display("  System (ebreak/ecall/..): %0d  (%.2f%%)", dec_sys,
             (dec_total > 0) ? (100.0 * dec_sys / dec_total) : 0.0);
    $display("  Decoded total           : %0d", dec_total);

    // ---- EXU 计算 ----
    $display("");
    $display("[EXU - Compute]");
    $display("  EXU calc done            : %0d", exu_calc_cnt);

    // ---- 一致性检查 ----
    $display("");
    $display("[Consistency Check]");
    $display("  IFU fetched == IDU decoded ? %s", (ifu_ret_cnt == dec_total) ? "PASS" : "FAIL");
    $display("    ifu_ret_cnt=%0d  dec_total=%0d", ifu_ret_cnt, dec_total);
    $display("  Load req == load done     ? %s", (load_cnt == load_ret_cnt) ? "PASS" : "FAIL");
    $display("    load_cnt=%0d  load_ret_cnt=%0d", load_cnt, load_ret_cnt);
    $display("  Store req == store done   ? %s", (store_cnt == store_ret_cnt) ? "PASS" : "FAIL");
    $display("    store_cnt=%0d  store_ret_cnt=%0d", store_cnt, store_ret_cnt);
    $display("  sum(dec_*) == dec_total   ? %s",
             ((dec_calc+dec_load+dec_store+dec_branch+dec_jump+dec_u_type+dec_csr+dec_sys) == dec_total) ? "PASS" : "FAIL");

    $display("============================================================");
    $display("");
  end

endmodule

`endif // ENABLE_PERF
