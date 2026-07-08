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

  // ===== ICache 指令缓存 (命中/缺失/AMAT) =====
  input icache_access,        // icache 收到一次取指访问 (IC_LOOKUP)
  input icache_hit,           // 命中 (可缓存且命中)
  input icache_miss,          // 缺失 (可缓存但未命中, 需回填)
  input icache_uncache,       // 不可缓存访问 (地址不在缓存范围, 直通总线)
  input icache_refill_req,    // 向总线发起一次回填/直通读请求 (IC_REFILL_AR)
  input icache_wait_ar,       // 处于等待总线 AR 握手状态
  input icache_wait_r,        // 处于等待总线 R  握手状态

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

  // ===== EXU 计算完成 & 分支结果 (阶段2) =====
  input exu_calc_done,        // EXU 完成一次计算 (一条非访存指令执行完成)
  input branch_taken,         // 分支是否真的跳转 (EXU 计算结果)
  // ===== 寄存器写回 (阶段2) =====
  input reg_wen               // 本周期写回寄存器堆 (rd != 0 且指令需要写回)
);

  // ========== 计数器定义 (64位, 避免长时间运行溢出) ==========
  // 总周期 & 停顿
  reg [63:0] cyc_total;           // 总周期数
  reg [63:0] cyc_stall;           // 处理器停顿周期 (IFU 未取到指令, 非 IDLE 等待)
  reg [63:0] cyc_ifu_wait_lsu;    // IFU 因等待 LSU 而停顿的周期

  // IFU - 指令供给
  reg [63:0] ifu_req_cnt;         // IFU 取指请求次数 (AR 握手)
  reg [63:0] ifu_ret_cnt;         // IFU 取到指令次数 (R 握手)
  // ---- 阶段2: IFU "取不到指令" 的原因细分 ----
  // IDLE 态: 取指请求尚未被 slave 接受 (等 AR 握手)
  reg [63:0] ifu_idle_cyc;        // IFU 处于 IDLE 的周期 (等待 AR 握手发出/接受)
  reg [63:0] cyc_ifu_wait_ar;     // IDLE 周期累计 (= 等待 AR 握手发出取指请求)
  // WAIT 态, 非访存指令: 等待 R 通道返回取指数据
  reg [63:0] cyc_ifu_wait_r_fetch;// WAIT 态等待取指 R 握手的周期 (纯粹的指令供给等待)
  reg [63:0] ifu_no_inst_cyc;     // IFU 未取到指令的周期 (WAIT 态未完成 R 握手, 且未在等LSU)
  // (IFU 等待 LSU 见 cyc_ifu_wait_lsu, 上面已定义)

  // LSU - 数据供给
  reg [63:0] load_cnt;            // load 指令次数
  reg [63:0] store_cnt;           // store 指令次数
  reg [63:0] load_ret_cnt;        // load 完成 (取到数据) 次数
  reg [63:0] store_ret_cnt;       // store 完成 次数
  reg [63:0] lsu_wait_ar_cyc;     // 等待 AR 握手的周期累计 (load 请求发出延迟)
  reg [63:0] lsu_wait_r_cyc;      // 等待 R  握手的周期累计 (load 延迟主体)
  reg [63:0] lsu_wait_aw_w_cyc;   // 等待 AW/W 握手的周期累计 (store 请求发出延迟)
  reg [63:0] lsu_wait_b_cyc;      // 等待 B  握手的周期累计 (store 延迟主体)

  // ICache - 指令缓存 (用于命中率与 AMAT 统计)
  // AMAT = access_time + (1 - p) * miss_penalty, 其中 p 为命中率.
  //   access_time  = 命中时从收到访存请求到得出命中结果所需的周期数 (命中服务周期)
  //   miss_penalty = 缺失时访问下游 DRAM 的周期数 (回填等待周期)
  reg [63:0] icache_access_cnt;   // icache 取指访问次数 (IC_LOOKUP)
  reg [63:0] icache_hit_cnt;      // 命中次数 (含命中服务周期计入 hit_cyc)
  reg [63:0] icache_miss_cnt;     // 缺失次数 (可缓存型, 需回填)
  reg [63:0] icache_uncache_cnt;  // 不可缓存访问次数 (直通总线)
  reg [63:0] icache_refill_cnt;   // 回填/直通读请求次数 (IC_REFILL_AR 进入)
  reg [63:0] icache_wait_ar_cyc;  // 等待总线 AR 握手的周期累计 (回填发出延迟)
  reg [63:0] icache_wait_r_cyc;   // 等待总线 R  握手的周期累计 (回填数据延迟)
  reg [63:0] icache_hit_cyc;      // 命中服务周期累计 (命中路径 access_time 累加, 含IC_LOOKUP本身)
  reg [63:0] icache_miss_cyc;     // 缺失服务周期累计 (一次缺失从IC_LOOKUP到回填完成的总周期)
  reg [63:0] icache_miss_acc;     // 当前缺失服务周期累加器 (miss期间每周期+1, 完成时计入miss_cyc)
  reg        icache_miss_pend;    // 正在处理一次缺失/不可缓存读 (IC_REFILL_AR/R 期间为1)

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

  // ---- 阶段2: 每种类别指令的累计执行周期 (用于计算各类指令平均 CPI) ----
  // inst_cyc_acc: 当前指令已花费的周期数累加器, 每个非复位周期 +1;
  //               当 ifu_valid (一条指令完成) 时, 把 acc 加到对应类别桶并清零.
  reg [63:0] inst_cyc_acc;
  reg [63:0] cyc_calc;            // 计算类指令累计周期
  reg [63:0] cyc_load;            // 加载类指令累计周期
  reg [63:0] cyc_store;           // 存储类指令累计周期
  reg [63:0] cyc_branch;          // 分支类指令累计周期
  reg [63:0] cyc_jump;            // 跳转类指令累计周期
  reg [63:0] cyc_u_type;          // U型指令累计周期
  reg [63:0] cyc_csr;             // CSR 类指令累计周期
  reg [63:0] cyc_sys;             // 系统类指令累计周期

  // EXU - 计算完成 & 分支 (阶段2)
  reg [63:0] exu_calc_cnt;        // EXU 完成计算次数
  reg [63:0] branch_taken_cnt;    // 实际跳转的分支次数 (用于分支 taken 率统计)

  // 寄存器写回 (阶段2)
  reg [63:0] reg_wb_cnt;          // 写回寄存器堆的次数 (rd != 0)
  reg [63:0] reg_wb_load_cnt;     // 其中由 load 完成触发的写回次数

  // ========== 计数逻辑 ==========
  // 停顿定义: 处理器既不在 IDLE(没有正在执行指令的空闲), 也没有取到新指令.
  //   即 IFU 处于 WAIT 态但本周期 ifu_valid=0 (含等待LSU / 等待取指握手).
  wire stall_this_cyc = !rst && ifu_state && !ifu_valid;
  // IFU 未取到指令且未在等LSU (纯粹的取指握手等待/数据供给等待)
  wire ifu_no_inst    = !rst && ifu_state && !ifu_valid && !ifu_lsu_pending;
  // IFU 等待取指 R 握手: WAIT 态, 非访存等待, 未取到指令
  wire ifu_wait_r_fetch = !rst && ifu_state && !ifu_lsu_pending && !ifu_valid;
  // IFU 等待 AR 握手 (IDLE 态): 取指地址尚未被 slave 接受
  wire ifu_wait_ar     = !rst && !ifu_state;

  always @(posedge clk) begin
    if (rst) begin
      cyc_total         <= 64'b0;
      cyc_stall         <= 64'b0;
      cyc_ifu_wait_lsu  <= 64'b0;
      ifu_req_cnt       <= 64'b0;
      ifu_ret_cnt       <= 64'b0;
      ifu_idle_cyc      <= 64'b0;
      cyc_ifu_wait_ar   <= 64'b0;
      cyc_ifu_wait_r_fetch <= 64'b0;
      ifu_no_inst_cyc   <= 64'b0;
      load_cnt          <= 64'b0;
      store_cnt         <= 64'b0;
      load_ret_cnt      <= 64'b0;
      store_ret_cnt     <= 64'b0;
      lsu_wait_ar_cyc   <= 64'b0;
      lsu_wait_r_cyc    <= 64'b0;
      lsu_wait_aw_w_cyc <= 64'b0;
      lsu_wait_b_cyc    <= 64'b0;
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
      dec_total         <= 64'b0;
      dec_calc          <= 64'b0;
      dec_load          <= 64'b0;
      dec_store         <= 64'b0;
      dec_branch        <= 64'b0;
      dec_jump          <= 64'b0;
      dec_u_type        <= 64'b0;
      dec_csr           <= 64'b0;
      dec_sys           <= 64'b0;
      inst_cyc_acc      <= 64'b0;
      cyc_calc          <= 64'b0;
      cyc_load          <= 64'b0;
      cyc_store         <= 64'b0;
      cyc_branch        <= 64'b0;
      cyc_jump          <= 64'b0;
      cyc_u_type        <= 64'b0;
      cyc_csr           <= 64'b0;
      cyc_sys           <= 64'b0;
      exu_calc_cnt      <= 64'b0;
      branch_taken_cnt  <= 64'b0;
      reg_wb_cnt        <= 64'b0;
      reg_wb_load_cnt   <= 64'b0;
    end else begin
      // 周期统计 (每个非复位周期 +1)
      cyc_total <= cyc_total + 64'd1;

      // 当前指令周期累加器 (每周期 +1, 在 ifu_valid 时归零并计入对应类别桶)
      inst_cyc_acc <= inst_cyc_acc + 64'd1;

      // 停顿统计
      if (stall_this_cyc)      cyc_stall           <= cyc_stall + 64'd1;
      if (ifu_lsu_pending)     cyc_ifu_wait_lsu    <= cyc_ifu_wait_lsu + 64'd1;
      if (ifu_no_inst)         ifu_no_inst_cyc     <= ifu_no_inst_cyc + 64'd1;
      if (!ifu_state)          ifu_idle_cyc        <= ifu_idle_cyc + 64'd1;   // IDLE 周期
      if (ifu_wait_ar)         cyc_ifu_wait_ar     <= cyc_ifu_wait_ar + 64'd1;
      if (ifu_wait_r_fetch)    cyc_ifu_wait_r_fetch<= cyc_ifu_wait_r_fetch + 64'd1;

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

      // ICache 事件: access/hit/miss/uncache 均在 IC_LOOKUP 单拍触发
      if (icache_access) icache_access_cnt <= icache_access_cnt + 64'd1;
      if (icache_hit)    begin
        icache_hit_cnt <= icache_hit_cnt + 64'd1;
        icache_hit_cyc <= icache_hit_cyc + 64'd1;   // 命中服务 = 1 周期 (IC_LOOKUP 本身)
      end
      if (icache_uncache) begin
        icache_uncache_cnt <= icache_uncache_cnt + 64'd1;
        icache_miss_pend   <= 1'b1;                 // 不可缓存读走与缺失相同的总线通路
        icache_miss_acc    <= 64'd1;                // 计入 IC_LOOKUP 当拍
      end
      if (icache_miss)    begin
        icache_miss_cnt  <= icache_miss_cnt + 64'd1;
        icache_miss_pend <= 1'b1;                   // 启动缺失服务周期统计
        icache_miss_acc  <= 64'd1;                  // 计入 IC_LOOKUP 当拍
      end
      if (icache_refill_req) icache_refill_cnt <= icache_refill_cnt + 64'd1;
      // 缺失/不可缓存服务周期累加: miss_pend 期间每周期 +1
      if (icache_miss_pend && (icache_wait_ar || icache_wait_r))
        icache_miss_acc <= icache_miss_acc + 64'd1;
      // 缺失服务完成 (miss_pend 且已回到 IC_IDLE): 把累加器计入 miss_cyc 并清标志
      if (icache_miss_pend && !icache_wait_ar && !icache_wait_r) begin
        icache_miss_cyc  <= icache_miss_cyc + icache_miss_acc;
        icache_miss_acc  <= 64'b0;
        icache_miss_pend <= 1'b0;
      end
      if (icache_wait_ar) icache_wait_ar_cyc <= icache_wait_ar_cyc + 64'd1;
      if (icache_wait_r)  icache_wait_r_cyc  <= icache_wait_r_cyc  + 64'd1;

      // 译码指令分类 + 每类指令累计周期 (仅在 ifu_valid 时统计)
      if (ifu_valid_dec) begin
        dec_total   <= dec_total   + 64'd1;
        // 指令完成: 把本条指令已花费周期计入对应类别桶, 并清零累加器
        if (is_calc)       begin dec_calc    <= dec_calc    + 64'd1; cyc_calc    <= cyc_calc    + inst_cyc_acc; end
        if (is_load_inst)  begin dec_load    <= dec_load    + 64'd1; cyc_load    <= cyc_load    + inst_cyc_acc; end
        if (is_store_inst) begin dec_store   <= dec_store   + 64'd1; cyc_store   <= cyc_store   + inst_cyc_acc; end
        if (is_branch)     begin dec_branch  <= dec_branch  + 64'd1; cyc_branch  <= cyc_branch  + inst_cyc_acc; end
        if (is_jump)       begin dec_jump    <= dec_jump    + 64'd1; cyc_jump    <= cyc_jump    + inst_cyc_acc; end
        if (is_u_type)     begin dec_u_type  <= dec_u_type  + 64'd1; cyc_u_type  <= cyc_u_type  + inst_cyc_acc; end
        if (is_csr)        begin dec_csr     <= dec_csr     + 64'd1; cyc_csr     <= cyc_csr     + inst_cyc_acc; end
        if (is_sys)        begin dec_sys     <= dec_sys     + 64'd1; cyc_sys     <= cyc_sys     + inst_cyc_acc; end
        inst_cyc_acc <= 64'd1;  // 本周期已算作下一条指令的第1个周期
      end

      // EXU 计算完成 & 分支 taken
      if (exu_calc_done) exu_calc_cnt <= exu_calc_cnt + 64'd1;
      if (ifu_valid && is_branch && branch_taken) branch_taken_cnt <= branch_taken_cnt + 64'd1;

      // 寄存器写回统计
      if (ifu_valid && reg_wen) reg_wb_cnt <= reg_wb_cnt + 64'd1;
    end
  end

  // ========== 仿真结束时输出性能计数报告 ==========
  // final 块在 Verilator 调用 g_top->final() 时触发 (ebreak 后 / 仿真退出前)
  final begin
    $display("");
    $display("============================================================");
    $display("             性能计数器报告 (Perf Counter Report)          ");
    $display("============================================================");

    // ---- 概览 ----
    $display("");
    $display("[概览 Overview]");
    $display("  总周期数 Total cycles         : %0d", cyc_total);
    $display("  退休指令数 Retired inst       : %0d  (= IFU取到 = IDU译码)", ifu_ret_cnt);
    $display("  IPC                           : %f", (cyc_total > 0) ? (1.0 * ifu_ret_cnt / cyc_total) : 0.0);
    $display("  平均CPI (1/IPC)               : %f", (ifu_ret_cnt > 0) ? (1.0 * cyc_total / ifu_ret_cnt) : 0.0);
    $display("  停顿周期 Stall cycles         : %0d  (%.2f%%)", cyc_stall,
             (cyc_total > 0) ? (100.0 * cyc_stall / cyc_total) : 0.0);
    $display("  寄存器写回 Reg writebacks     : %0d  (%.2f per inst)", reg_wb_cnt,
             (ifu_ret_cnt > 0) ? (1.0 * reg_wb_cnt / ifu_ret_cnt) : 0.0);

    // ---- IFU 指令供给 ----
    $display("");
    $display("[指令供给 IFU - Instruction Supply]");
    $display("  取指请求 Fetch req (AR握手)   : %0d", ifu_req_cnt);
    $display("  取到指令 Inst fetched (R握手) : %0d", ifu_ret_cnt);
    $display("  IFU空闲周期 IDLE cycles       : %0d  (%.2f%%)", ifu_idle_cyc,
             (cyc_total > 0) ? (100.0 * ifu_idle_cyc / cyc_total) : 0.0);
    $display("  未取到指令周期 no-instr cyc   : %0d  (%.2f%%)", ifu_no_inst_cyc,
             (cyc_total > 0) ? (100.0 * ifu_no_inst_cyc / cyc_total) : 0.0);
    $display("  等待LSU周期 wait-LSU cycles   : %0d  (%.2f%%)", cyc_ifu_wait_lsu,
             (cyc_total > 0) ? (100.0 * cyc_ifu_wait_lsu / cyc_total) : 0.0);
    // ---- 阶段2: IFU 取不到指令的原因细分 ----
    $display("");
    $display("  [阶段2] IFU 取不到指令的原因细分 (占总周期%%):");
    $display("    (1) 等AR握手 wait-AR  (IDLE, 取指请求未接受) : %0d  (%.2f%%)", cyc_ifu_wait_ar,
             (cyc_total > 0) ? (100.0 * cyc_ifu_wait_ar / cyc_total) : 0.0);
    $display("    (2) 等R握手 fetch   (WAIT, 等取指数据返回)  : %0d  (%.2f%%)", cyc_ifu_wait_r_fetch,
             (cyc_total > 0) ? (100.0 * cyc_ifu_wait_r_fetch / cyc_total) : 0.0);
    $display("    (3) 等LSU完成 mem   (WAIT, 访存指令阻塞)    : %0d  (%.2f%%)", cyc_ifu_wait_lsu,
             (cyc_total > 0) ? (100.0 * cyc_ifu_wait_lsu / cyc_total) : 0.0);
    $display("        -> 三者之和应 = 总周期 - IFU取到指令周期");

    // ---- LSU 数据供给 ----
    $display("");
    $display("[数据供给 LSU - Data Supply]");
    $display("  Load请求 requests            : %0d", load_cnt);
    $display("  Store请求 requests           : %0d", store_cnt);
    $display("  Load完成 completed (R握手)   : %0d", load_ret_cnt);
    $display("  Store完成 completed (B握手)  : %0d", store_ret_cnt);
    if (load_cnt > 0)
      $display("  Load平均延迟 avg latency(cyc): %.2f  (wait_R=%0d / load=%0d)",
               (1.0 * lsu_wait_r_cyc / load_cnt), lsu_wait_r_cyc, load_cnt);
    if (store_cnt > 0)
      $display("  Store平均延迟 avg latency    : %.2f  (wait_B=%0d / store=%0d)",
               (1.0 * lsu_wait_b_cyc / store_cnt), lsu_wait_b_cyc, store_cnt);
    $display("  等待AR握手周期 wait-AR cyc    : %0d", lsu_wait_ar_cyc);
    $display("  等待R握手周期  wait-R  cyc    : %0d", lsu_wait_r_cyc);
    $display("  等待AW/W周期   wait-AW/W cyc : %0d", lsu_wait_aw_w_cyc);
    $display("  等待B握手周期  wait-B  cyc   : %0d", lsu_wait_b_cyc);
    // ---- 阶段2: LSU 延迟细分 ----
    $display("");
    $display("  [阶段2] LSU 访存延迟细分:");
    if (load_cnt > 0)
      $display("    Load  发出延迟 (wait_AR/load)  : %.2f cyc/次  (AR握手等待)",
               1.0 * lsu_wait_ar_cyc / load_cnt);
    if (load_cnt > 0)
      $display("    Load  数据延迟 (wait_R /load)  : %.2f cyc/次  (R握手等待, 访存主体)",
               1.0 * lsu_wait_r_cyc / load_cnt);
    if (store_cnt > 0)
      $display("    Store 发出延迟 (wait_AW_W/store): %.2f cyc/次 (AW/W握手等待)",
               1.0 * lsu_wait_aw_w_cyc / store_cnt);
    if (store_cnt > 0)
      $display("    Store 回复延迟 (wait_B /store) : %.2f cyc/次 (B握手等待, 访存主体)",
               1.0 * lsu_wait_b_cyc / store_cnt);
    if ((load_cnt + store_cnt) > 0)
      $display("    全部访存占总周期比             : %.2f%%",
               (cyc_total > 0) ? (100.0 * (lsu_wait_ar_cyc + lsu_wait_r_cyc + lsu_wait_aw_w_cyc + lsu_wait_b_cyc) / cyc_total) : 0.0);

    // ---- ICache 指令缓存 (命中率 + AMAT) ----
    // 讲义 B4: AMAT = access_time + (1 - p) * miss_penalty, p 为命中率.
    //   access_time  = 命中服务周期 (命中: 1 周期, 即 IC_LOOKUP 本身)
    //   miss_penalty = 缺失服务周期 (一次缺失从 IC_LOOKUP 到回填完成的周期)
    $display("");
    $display("[指令缓存 ICache - Hit Rate & AMAT]");
    $display("  取指访问 accesses             : %0d", icache_access_cnt);
    $display("  命中 hits                    : %0d  (%.2f%%)",
             icache_hit_cnt,
             (icache_access_cnt > 0) ? (100.0 * icache_hit_cnt / icache_access_cnt) : 0.0);
    $display("  缺失 misses                   : %0d  (%.2f%%)",
             icache_miss_cnt,
             (icache_access_cnt > 0) ? (100.0 * icache_miss_cnt / icache_access_cnt) : 0.0);
    $display("  不可缓存 uncacheable          : %0d  (%.2f%%)",
             icache_uncache_cnt,
             (icache_access_cnt > 0) ? (100.0 * icache_uncache_cnt / icache_access_cnt) : 0.0);
    $display("  回填/直通读请求 refill req    : %0d  (应 = misses + uncacheable)", icache_refill_cnt);
    // 命中率 p 仅对可缓存访问计算 (排除不可缓存)
    if ((icache_hit_cnt + icache_miss_cnt) > 0) begin
      $display("  [可缓存命中率 p]              : %.4f  (hits / (hits+misses))",
               1.0 * icache_hit_cnt / (icache_hit_cnt + icache_miss_cnt));
    end
    // AMAT (单位: 周期)
    //   access_time = hit_cyc / hit_cnt
    //   miss_penalty= miss_cyc / miss_cnt
    //   AMAT        = access_time + (1-p) * miss_penalty
    if (icache_hit_cnt > 0)
      $display("  access_time (hit 周期/次)     : %.2f", 1.0 * icache_hit_cyc / icache_hit_cnt);
    if (icache_miss_cnt > 0)
      $display("  miss_penalty (miss 周期/次)   : %.2f  (wait_AR=%0d + wait_R=%0d + lookup)",
               1.0 * icache_miss_cyc / icache_miss_cnt, icache_wait_ar_cyc, icache_wait_r_cyc);
    if ((icache_hit_cnt > 0) && (icache_miss_cnt > 0)) begin
      $display("  AMAT (周期/次访问)           : %.2f",
               (1.0 * icache_hit_cyc / icache_hit_cnt) +
               (1.0 - 1.0 * icache_hit_cnt / (icache_hit_cnt + icache_miss_cnt)) *
               (1.0 * icache_miss_cyc / icache_miss_cnt));
    end
    $display("  等待总线AR握手周期 wait-AR cyc: %0d", icache_wait_ar_cyc);
    $display("  等待总线R握手周期  wait-R  cyc: %0d", icache_wait_r_cyc);
    if (cyc_total > 0)
      $display("  icache总线等待占总周期比      : %.2f%%",
               100.0 * (icache_wait_ar_cyc + icache_wait_r_cyc) / cyc_total);

    // ---- IDU 指令分类 (数量 + 占比 + 阶段2 平均CPI) ----
    $display("");
    $display("[指令分类 IDU - Instruction Mix]  (数量 / 占比 / 平均CPI)");
    if (dec_calc > 0)
      $display("  计算类 Calc   : 数量=%0d (%.2f%%)  平均CPI=%.2f  (cyc=%0d)",
               dec_calc, (dec_total > 0) ? (100.0 * dec_calc / dec_total) : 0.0,
               1.0 * cyc_calc / dec_calc, cyc_calc);
    if (dec_load > 0)
      $display("  加载类 Load   : 数量=%0d (%.2f%%)  平均CPI=%.2f  (cyc=%0d)",
               dec_load, (dec_total > 0) ? (100.0 * dec_load / dec_total) : 0.0,
               1.0 * cyc_load / dec_load, cyc_load);
    if (dec_store > 0)
      $display("  存储类 Store  : 数量=%0d (%.2f%%)  平均CPI=%.2f  (cyc=%0d)",
               dec_store, (dec_total > 0) ? (100.0 * dec_store / dec_total) : 0.0,
               1.0 * cyc_store / dec_store, cyc_store);
    if (dec_branch > 0)
      $display("  分支类 Branch : 数量=%0d (%.2f%%)  平均CPI=%.2f  (cyc=%0d)",
               dec_branch, (dec_total > 0) ? (100.0 * dec_branch / dec_total) : 0.0,
               1.0 * cyc_branch / dec_branch, cyc_branch);
    if (dec_jump > 0)
      $display("  跳转类 Jump   : 数量=%0d (%.2f%%)  平均CPI=%.2f  (cyc=%0d)",
               dec_jump, (dec_total > 0) ? (100.0 * dec_jump / dec_total) : 0.0,
               1.0 * cyc_jump / dec_jump, cyc_jump);
    if (dec_u_type > 0)
      $display("  U型 U-type    : 数量=%0d (%.2f%%)  平均CPI=%.2f  (cyc=%0d)",
               dec_u_type, (dec_total > 0) ? (100.0 * dec_u_type / dec_total) : 0.0,
               1.0 * cyc_u_type / dec_u_type, cyc_u_type);
    if (dec_csr > 0)
      $display("  CSR类 CSR     : 数量=%0d (%.2f%%)  平均CPI=%.2f  (cyc=%0d)",
               dec_csr, (dec_total > 0) ? (100.0 * dec_csr / dec_total) : 0.0,
               1.0 * cyc_csr / dec_csr, cyc_csr);
    if (dec_sys > 0)
      $display("  系统类 System : 数量=%0d (%.2f%%)  平均CPI=%.2f  (cyc=%0d)",
               dec_sys, (dec_total > 0) ? (100.0 * dec_sys / dec_total) : 0.0,
               1.0 * cyc_sys / dec_sys, cyc_sys);
    $display("  译码总数 Decoded total : %0d", dec_total);

    // ---- EXU 计算 & 分支 (阶段2) ----
    $display("");
    $display("[计算 EXU - Compute]");
    $display("  EXU完成计算 calc done        : %0d  (= 非访存指令数)", exu_calc_cnt);
    $display("  [阶段2] 分支 Branch 总数     : %0d", dec_branch);
    $display("          其中 taken (跳转)    : %0d  (%.2f%%)", branch_taken_cnt,
             (dec_branch > 0) ? (100.0 * branch_taken_cnt / dec_branch) : 0.0);
    $display("          其中 not-taken (顺序): %0d  (%.2f%%)", dec_branch - branch_taken_cnt,
             (dec_branch > 0) ? (100.0 * (dec_branch - branch_taken_cnt) / dec_branch) : 0.0);

    // ---- 阶段2: Amdahl 视角的时间占比 (指导瓶颈定位) ----
    $display("");
    $display("[阶段2] 时间占比分析 (Amdahl's law 视角)");
    $display("  指令供给等待 (等AR+等R取指)  : %.2f%%  -> 优化IFU/取指可获理论加速比上限",
             (cyc_total > 0) ? (100.0 * (cyc_ifu_wait_ar + cyc_ifu_wait_r_fetch) / cyc_total) : 0.0);
    $display("  数据供给等待 (等LSU)         : %.2f%%  -> 优化LSU/存储可获理论加速比上限",
             (cyc_total > 0) ? (100.0 * cyc_ifu_wait_lsu / cyc_total) : 0.0);
    $display("  Load类指令耗时占比          : %.2f%%",
             (cyc_total > 0) ? (100.0 * cyc_load / cyc_total) : 0.0);
    $display("  Store类指令耗时占比         : %.2f%%",
             (cyc_total > 0) ? (100.0 * cyc_store / cyc_total) : 0.0);

    // ---- 一致性检查 ----
    $display("");
    $display("[一致性检查 Consistency Check]");
    $display("  IFU取到 == IDU译码 ? %s", (ifu_ret_cnt == dec_total) ? "PASS 通过" : "FAIL 失败");
    $display("    ifu_ret_cnt=%0d  dec_total=%0d", ifu_ret_cnt, dec_total);
    $display("  Load请求 == Load完成 ? %s", (load_cnt == load_ret_cnt) ? "PASS 通过" : "FAIL 失败");
    $display("    load_cnt=%0d  load_ret_cnt=%0d", load_cnt, load_ret_cnt);
    $display("  Store请求 == Store完成 ? %s", (store_cnt == store_ret_cnt) ? "PASS 通过" : "FAIL 失败");
    $display("    store_cnt=%0d  store_ret_cnt=%0d", store_cnt, store_ret_cnt);
    $display("  各类指令之和 == 译码总数 ? %s",
             ((dec_calc+dec_load+dec_store+dec_branch+dec_jump+dec_u_type+dec_csr+dec_sys) == dec_total) ? "PASS 通过" : "FAIL 失败");
    // 各类周期之和与总周期之差 = 仿真尾部的"下一条指令未退休"周期数,
    // 通常为 1 (ebreak 退休后到 final() 之间经历的若干周期), 属正常现象.
    $display("  各类周期之和 == 总周期 ? %s",
             ((cyc_total - (cyc_calc+cyc_load+cyc_store+cyc_branch+cyc_jump+cyc_u_type+cyc_csr+cyc_sys)) <= 64'd2) ? "PASS 通过" : "FAIL 失败");
    $display("    sum_cyc=%0d  cyc_total=%0d  (差额=%0d 为仿真尾部未退休周期, 正常)",
             (cyc_calc+cyc_load+cyc_store+cyc_branch+cyc_jump+cyc_u_type+cyc_csr+cyc_sys), cyc_total,
             cyc_total - (cyc_calc+cyc_load+cyc_store+cyc_branch+cyc_jump+cyc_u_type+cyc_csr+cyc_sys));
    $display("  IFU取不到指令原因之和 == 停顿+IDLE ? %s",
             ((cyc_ifu_wait_ar + cyc_ifu_wait_r_fetch + cyc_ifu_wait_lsu) == (cyc_stall + ifu_idle_cyc)) ? "PASS 通过" : "FAIL 失败");
    $display("    wait_AR+wait_Rfetch+wait_LSU=%0d  stall+idle=%0d",
             (cyc_ifu_wait_ar + cyc_ifu_wait_r_fetch + cyc_ifu_wait_lsu), (cyc_stall + ifu_idle_cyc));
    $display("  icache回填数 == 缺失+不可缓存 ? %s",
             (icache_refill_cnt == (icache_miss_cnt + icache_uncache_cnt)) ? "PASS 通过" : "FAIL 失败");
    $display("    refill=%0d  miss+uncache=%0d", icache_refill_cnt, (icache_miss_cnt + icache_uncache_cnt));

    $display("============================================================");
    $display("");
  end

endmodule

`endif // ENABLE_PERF
