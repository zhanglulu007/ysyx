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

  // ----- IFU 取不到指令的原因分析 -----
  // 取不到指令 = IFU 处于 WAIT 态, 但未完成 R 握手
  // 细分原因: 等待 AR 握手 / 等待 R 握手 / 等待 LSU
  input ifu_no_inst,          // IFU 本周期未取到指令 (WAIT && !r_handshake && !rst)
  input ifu_wait_ar,          // IFU 正在等待 AR 握手 (刚发请求, 设备未 ready)
  input ifu_wait_r,           // IFU 正在等待 R  握手 (请求已发, 等待返回数据)
  input ifu_stall_lsu,        // IFU 未取到指令是因为在等 LSU

  // ===== LSU 访存 (数据供给) =====
  input lsu_load_req,         // 发出 load 请求
  input lsu_store_req,        // 发出 store 请求
  input lsu_r_handshake,      // load 完成 (取到数据)
  input lsu_b_handshake,      // store 完成 (写回复)
  input lsu_wait_ar,          // 等待 AR 握手
  input lsu_wait_r,           // 等待 R 握手
  input lsu_wait_aw_w,        // 等待 AW/W 握手
  input lsu_wait_b,           // 等待 B 握手

  // ----- LSU 访存延迟细分 -----
  // 每个 load/store 事务从发请求到完成的周期数 (用于计算平均延迟)
  input lsu_load_latency_pulse,  // 一个 load  事务完成时的周期数 (脉冲, 值为延迟周期)
  input lsu_store_latency_pulse, // 一个 store 事务完成时的周期数 (脉冲, 值为延迟周期)
  input lsu_load_latency_valid,  // lsu_load_latency_pulse 有效
  input lsu_store_latency_valid, // lsu_store_latency_pulse 有效

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

  // ----- 指令类别细分 (新增) -----
  input is_r_type,            // R型指令 (add/sub/and/or/...)
  input is_i_arith,          // I型算术逻辑 (addi/slti/xori/...)
  input is_load_lb_lh_lw,    // 加载: lb/lh/lw (有符号)
  input is_load_lbu_lhu,      // 加载: lbu/lhu (无符号)
  input is_store_sb_sh,       // 存储: sb/sh (1/2字节)
  input is_store_sw,         // 存储: sw (4字节)
  input is_branch_taken,      // 分支实际跳转了 (branch_taken)
  input is_branch_not_taken,  // 分支未跳转
  input is_jal_i,             // jal 指令
  input is_jalr_i,            // jalr 指令
  input is_lui_i,             // lui 指令
  input is_auipc_i,           // auipc 指令

  // ===== EXU 计算完成 =====
  input exu_calc_done         // EXU 完成一次计算 (一条非访存指令执行完成)
);

  // ========== 计数器定义 (64位, 避免长时间运行溢出) ==========
  // 总周期 & 停顿
  reg [63:0] cyc_total;           // 总周期数
  reg [63:0] cyc_stall;           // 处理器停顿周期 (IFU 未取到指令, 非 IDLE 等待)
  reg [63:0] cyc_ifu_wait_lsu;    // IFU 因等待 LSU 而停顿的周期

  // ----- IFU 取不到指令的原因细分 -----
  reg [63:0] ifu_no_inst_cyc;     // IFU 未取到指令的总周期
  reg [63:0] ifu_wait_ar_cyc;    // IFU 未取到指令: 等待 AR 握手的周期
  reg [63:0] ifu_wait_r_cyc;     // IFU 未取到指令: 等待 R  握手的周期
  reg [63:0] ifu_stall_lsu_cyc;  // IFU 未取到指令: 等待 LSU 的周期
  reg [63:0] ifu_idle_cyc;       // IFU 处于 IDLE 的周期

  // ----- IFU 取指请求和完成 -----
  reg [63:0] ifu_req_cnt;         // IFU 取指请求次数 (AR 握手)
  reg [63:0] ifu_ret_cnt;         // IFU 取到指令次数 (R 握手)

  // ----- IFU 取指失败原因分析 (脉冲事件计数) -----
  reg [63:0] ifu_evt_wait_ar;    // 事件: IFU 发请求后设备未立即 ready (需要等AR)
  reg [63:0] ifu_evt_retry_ar;   // 事件: IFU 在 WAIT 态因 AR 未握手而多等了一周期
  // 注: ifu_evt_wait_ar 在 AR 未立即握手时 +1, 表示"取指请求未被立即接受"的次数

  // LSU - 数据供给
  reg [63:0] load_cnt;            // load 指令次数
  reg [63:0] store_cnt;           // store 指令次数
  reg [63:0] load_ret_cnt;        // load 完成 (取到数据) 次数
  reg [63:0] store_ret_cnt;       // store 完成 次数

  // ----- LSU 访存延迟累计 (用于计算平均) -----
  reg [63:0] load_latency_sum;    // 所有 load  事务的延迟周期数总和
  reg [63:0] store_latency_sum;   // 所有 store 事务的延迟周期数总和
  // 最大/最小延迟
  reg [63:0] load_latency_max;    // 最长 load  延迟
  reg [63:0] load_latency_min;    // 最短 load  延迟 (初始为 -1 即全1)
  reg [63:0] store_latency_max;   // 最长 store 延迟
  reg [63:0] store_latency_min;   // 最短 store 延迟

  // LSU 等待周期累计
  reg [63:0] lsu_wait_ar_cyc;     // 等待 AR 握手的周期累计
  reg [63:0] lsu_wait_r_cyc;      // 等待 R  握手的周期累计 (load 延迟主体)
  reg [63:0] lsu_wait_aw_w_cyc;   // 等待 AW/W 握手的周期累计
  reg [63:0] lsu_wait_b_cyc;      // 等待 B  握手的周期累计 (store 延迟主体)

  // IDU - 译码出的各类指令数 (动态指令分类)
  reg [63:0] dec_total;           // 译码出的指令总数 (应 = ifu_ret_cnt = 动态指令数)

  // ----- 指令类别细分 (新增) -----
  reg [63:0] dec_calc;            // 计算类 (R+I 算术逻辑)
  reg [63:0] dec_r_type;          //   R型
  reg [63:0] dec_i_arith;         //   I型算术逻辑
  reg [63:0] dec_load;            // 加载类
  reg [63:0] dec_load_lb_lh_lw;  //     lb/lh/lw (有符号)
  reg [63:0] dec_load_lbu_lhu;    //     lbu/lhu (无符号)
  reg [63:0] dec_store;           // 存储类
  reg [63:0] dec_store_sb_sh;     //     sb/sh (1/2字节)
  reg [63:0] dec_store_sw;        //     sw (4字节)
  reg [63:0] dec_branch;          // 分支类
  reg [63:0] dec_branch_taken;    //   分支实际跳转次数
  reg [63:0] dec_branch_nt;      //   分支未跳转次数
  reg [63:0] dec_jump;            // 跳转类
  reg [63:0] dec_jal;             //   jal
  reg [63:0] dec_jalr;            //   jalr
  reg [63:0] dec_u_type;          // U型
  reg [63:0] dec_lui;             //   lui
  reg [63:0] dec_auipc;          //   auipc
  reg [63:0] dec_csr;             // CSR 类
  reg [63:0] dec_sys;             // 系统类

  // ----- 各类指令执行周期统计 (新增) -----
  // 方法: 在指令进入 EXU 时打一个时间戳, 在指令写回时计算差值
  // 由于当前 NPC 是单周期执行 (非流水线), 每条非访存指令固定 1 周期完成
  // 但 load/store 需要多周期. 我们通过 LSU 的延迟来统计.
  // 这里我们通过 exu_calc_done 脉冲来统计"计算类指令数", 以及通过 LSU 延迟来统计访存指令的周期.
  // 另外, 可以通过 cyc_total / dec_total 得到平均每条指令的周期 (即 1/IPC)
  // 此处我们新增: 分支跳转成功/失败次数, 用于分析控制流开销.

  // EXU - 计算完成
  reg [63:0] exu_calc_cnt;        // EXU 完成计算次数

  // ========== 计数逻辑 ==========
  // 停顿定义: 处理器既不在 IDLE(没有正在执行指令的空闲), 也没有取到新指令.
  //   即 IFU 处于 WAIT 态但本周期 ifu_valid=0 (含等待LSU / 等待取指握手).
  wire stall_this_cyc = !rst && ifu_state && !ifu_valid;

  always @(posedge clk) begin
    if (rst) begin
      cyc_total         <= 64'b0;
      cyc_stall         <= 64'b0;
      cyc_ifu_wait_lsu  <= 64'b0;
      ifu_req_cnt       <= 64'b0;
      ifu_ret_cnt       <= 64'b0;
      ifu_idle_cyc      <= 64'b0;
      ifu_no_inst_cyc   <= 64'b0;
      ifu_wait_ar_cyc   <= 64'b0;
      ifu_wait_r_cyc    <= 64'b0;
      ifu_stall_lsu_cyc <= 64'b0;
      ifu_evt_wait_ar   <= 64'b0;
      load_cnt          <= 64'b0;
      store_cnt         <= 64'b0;
      load_ret_cnt      <= 64'b0;
      store_ret_cnt     <= 64'b0;
      load_latency_sum  <= 64'b0;
      store_latency_sum <= 64'b0;
      load_latency_max  <= 64'b0;
      load_latency_min  <= 64'hFFFFFFFFFFFFFFFF;
      store_latency_max <= 64'b0;
      store_latency_min <= 64'hFFFFFFFFFFFFFFFF;
      lsu_wait_ar_cyc   <= 64'b0;
      lsu_wait_r_cyc    <= 64'b0;
      lsu_wait_aw_w_cyc <= 64'b0;
      lsu_wait_b_cyc    <= 64'b0;
      dec_total         <= 64'b0;
      dec_calc          <= 64'b0;
      dec_r_type        <= 64'b0;
      dec_i_arith       <= 64'b0;
      dec_load          <= 64'b0;
      dec_load_lb_lh_lw <= 64'b0;
      dec_load_lbu_lhu  <= 64'b0;
      dec_store         <= 64'b0;
      dec_store_sb_sh   <= 64'b0;
      dec_store_sw      <= 64'b0;
      dec_branch        <= 64'b0;
      dec_branch_taken  <= 64'b0;
      dec_branch_nt     <= 64'b0;
      dec_jump          <= 64'b0;
      dec_jal           <= 64'b0;
      dec_jalr          <= 64'b0;
      dec_u_type        <= 64'b0;
      dec_lui           <= 64'b0;
      dec_auipc         <= 64'b0;
      dec_csr           <= 64'b0;
      dec_sys           <= 64'b0;
      exu_calc_cnt      <= 64'b0;
    end else begin
      // 周期统计 (每个非复位周期 +1)
      cyc_total <= cyc_total + 64'd1;

      // 停顿统计
      if (stall_this_cyc)           cyc_stall        <= cyc_stall + 64'd1;
      if (ifu_lsu_pending)          cyc_ifu_wait_lsu <= cyc_ifu_wait_lsu + 64'd1;

      // IFU 状态统计
      if (ifu_no_inst)              ifu_no_inst_cyc  <= ifu_no_inst_cyc + 64'd1;
      if (ifu_wait_ar)              ifu_wait_ar_cyc   <= ifu_wait_ar_cyc  + 64'd1;
      if (ifu_wait_r)               ifu_wait_r_cyc    <= ifu_wait_r_cyc   + 64'd1;
      if (ifu_stall_lsu)            ifu_stall_lsu_cyc <= ifu_stall_lsu_cyc + 64'd1;
      if (!ifu_state)               ifu_idle_cyc     <= ifu_idle_cyc + 64'd1;  // IDLE 周期

      // IFU 事件
      if (ifu_ar_handshake) ifu_req_cnt <= ifu_req_cnt + 64'd1;
      if (ifu_r_handshake)  ifu_ret_cnt <= ifu_ret_cnt + 64'd1;
      // 事件: IFU 发请求时, 若 arready=0, 则取指未被立即接受
      // ifu_ar_handshake 为 1 时表示 AR 握手成功 (在本周期发请求且设备 ready)
      // 我们检测: 在 IDLE 态, ifu_arvalid=1 但 arready=0 的情况
      // 这个信号由顶层在 IFU 发请求但 arready=0 时产生一个脉冲
      // 此处我们先在顶层产生 ifu_ar_rejected 信号

      // LSU 事件
      if (lsu_load_req) begin
        load_cnt       <= load_cnt + 64'd1;
      end
      if (lsu_store_req) begin
        store_cnt      <= store_cnt + 64'd1;
      end
      if (lsu_r_handshake) load_ret_cnt   <= load_ret_cnt + 64'd1;
      if (lsu_b_handshake) store_ret_cnt  <= store_ret_cnt + 64'd1;

      // LSU 延迟统计 (脉冲方式: LSU 完成时送来本次事务的延迟周期数)
      if (lsu_load_latency_valid) begin
        load_latency_sum <= load_latency_sum + lsu_load_latency_pulse;
        if (lsu_load_latency_pulse > load_latency_max)
          load_latency_max <= lsu_load_latency_pulse;
        if (lsu_load_latency_pulse < load_latency_min)
          load_latency_min <= lsu_load_latency_pulse;
      end
      if (lsu_store_latency_valid) begin
        store_latency_sum <= store_latency_sum + lsu_store_latency_pulse;
        if (lsu_store_latency_pulse > store_latency_max)
          store_latency_max <= lsu_store_latency_pulse;
        if (lsu_store_latency_pulse < store_latency_min)
          store_latency_min <= lsu_store_latency_pulse;
      end

      if (lsu_wait_ar)     lsu_wait_ar_cyc   <= lsu_wait_ar_cyc   + 64'd1;
      if (lsu_wait_r)      lsu_wait_r_cyc    <= lsu_wait_r_cyc    + 64'd1;
      if (lsu_wait_aw_w)   lsu_wait_aw_w_cyc <= lsu_wait_aw_w_cyc + 64'd1;
      if (lsu_wait_b)      lsu_wait_b_cyc    <= lsu_wait_b_cyc    + 64'd1;

      // 译码指令分类 (仅在 ifu_valid 时统计)
      if (ifu_valid_dec) begin
        dec_total   <= dec_total   + 64'd1;
        if (is_calc)             dec_calc    <= dec_calc    + 64'd1;
        if (is_load_inst)        dec_load    <= dec_load    + 64'd1;
        if (is_store_inst)       dec_store   <= dec_store   + 64'd1;
        if (is_branch)           dec_branch  <= dec_branch  + 64'd1;
        if (is_branch_taken)     dec_branch_taken <= dec_branch_taken + 64'd1;
        if (is_branch_not_taken) dec_branch_nt    <= dec_branch_nt    + 64'd1;
        if (is_jump)             dec_jump    <= dec_jump    + 64'd1;
        if (is_jump && is_jal_i)   dec_jal     <= dec_jal     + 64'd1;
        if (is_jump && is_jalr_i)  dec_jalr    <= dec_jalr    + 64'd1;
        if (is_u_type)           dec_u_type  <= dec_u_type  + 64'd1;
        if (is_u_type && is_lui)  dec_lui    <= dec_lui     + 64'd1;
        if (is_u_type && is_auipc) dec_auipc <= dec_auipc + 64'd1;
        if (is_csr)              dec_csr     <= dec_csr     + 64'd1;
        if (is_sys)              dec_sys     <= dec_sys     + 64'd1;

        // 指令类别细分
        if (is_r_type)            dec_r_type  <= dec_r_type  + 64'd1;
        if (is_i_arith)           dec_i_arith <= dec_i_arith + 64'd1;
        if (is_load_lb_lh_lw)    dec_load_lb_lh_lw <= dec_load_lb_lh_lw + 64'd1;
        if (is_load_lbu_lhu)     dec_load_lbu_lhu  <= dec_load_lbu_lhu  + 64'd1;
        if (is_store_sb_sh)      dec_store_sb_sh   <= dec_store_sb_sh   + 64'd1;
        if (is_store_sw)          dec_store_sw      <= dec_store_sw      + 64'd1;
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
    $display("                 性能计数器报告 (Perf Counter Report)      ");
    $display("============================================================");

    // ---- 概览 ----
    $display("");
    $display("[1. 概览 Overview]");
    $display("  总周期数 Total cycles         : %0d", cyc_total);
    $display("  退休指令数 Retired inst       : %0d  (= IFU取到 = IDU译码)", ifu_ret_cnt);
    $display("  IPC                           : %f", (cyc_total > 0) ? (1.0 * ifu_ret_cnt / cyc_total) : 0.0);
    $display("  CPI (cycles/inst)            : %f", (ifu_ret_cnt > 0) ? (1.0 * cyc_total / ifu_ret_cnt) : 0.0);
    $display("  停顿周期 Stall cycles         : %0d  (%.2f%%)", cyc_stall,
             (cyc_total > 0) ? (100.0 * cyc_stall / cyc_total) : 0.0);

    // ---- IFU 指令供给 ----
    $display("");
    $display("[2. 指令供给 IFU - Instruction Supply]");
    $display("  取指请求 Fetch req (AR握手)   : %0d", ifu_req_cnt);
    $display("  取到指令 Inst fetched (R握手) : %0d", ifu_ret_cnt);
    $display("  IFU空闲周期 IDLE cycles       : %0d  (%.2f%%)", ifu_idle_cyc,
             (cyc_total > 0) ? (100.0 * ifu_idle_cyc / cyc_total) : 0.0);
    $display("  未取到指令周期 no-instr cyc   : %0d  (%.2f%%)", ifu_no_inst_cyc,
             (cyc_total > 0) ? (100.0 * ifu_no_inst_cyc / cyc_total) : 0.0);
    $display("    其中: 等待AR握手 wait-AR     : %0d  (%.2f%%)", ifu_wait_ar_cyc,
             (ifu_no_inst_cyc > 0) ? (100.0 * ifu_wait_ar_cyc / ifu_no_inst_cyc) : 0.0);
    $display("    其中: 等待R握手  wait-R     : %0d  (%.2f%%)", ifu_wait_r_cyc,
             (ifu_no_inst_cyc > 0) ? (100.0 * ifu_wait_r_cyc / ifu_no_inst_cyc) : 0.0);
    $display("    其中: 等待LSU     wait-LSU  : %0d  (%.2f%%)", ifu_stall_lsu_cyc,
             (ifu_no_inst_cyc > 0) ? (100.0 * ifu_stall_lsu_cyc / ifu_no_inst_cyc) : 0.0);
    $display("  等待LSU总周期 (含取到指令周期) : %0d  (%.2f%%)", cyc_ifu_wait_lsu,
             (cyc_total > 0) ? (100.0 * cyc_ifu_wait_lsu / cyc_total) : 0.0);

    // ---- LSU 数据供给 ----
    $display("");
    $display("[3. 数据供给 LSU - Data Supply]");
    $display("  Load请求  requests           : %0d", load_cnt);
    $display("  Store请求 requests           : %0d", store_cnt);
    $display("  Load完成  completed (R握手)  : %0d", load_ret_cnt);
    $display("  Store完成 completed (B握手)  : %0d", store_ret_cnt);

    // Load 延迟统计
    if (load_cnt > 0) begin
      $display("  Load 平均延迟 avg lat (cyc) : %.2f", (1.0 * load_latency_sum / load_cnt));
      $display("  Load 最小延迟 min lat (cyc) : %0d", (load_latency_min == 64'hFFFFFFFFFFFFFFFF) ? 0 : load_latency_min);
      $display("  Load 最大延迟 max lat (cyc) : %0d", load_latency_max);
    end
    // Store 延迟统计
    if (store_cnt > 0) begin
      $display("  Store 平均延迟 avg lat (cyc) : %.2f", (1.0 * store_latency_sum / store_cnt));
      $display("  Store 最小延迟 min lat (cyc) : %0d", (store_latency_min == 64'hFFFFFFFFFFFFFFFF) ? 0 : store_latency_min);
      $display("  Store 最大延迟 max lat (cyc) : %0d", store_latency_max);
    end

    $display("  等待AR握手周期 wait-AR cyc    : %0d", lsu_wait_ar_cyc);
    $display("  等待R握手周期  wait-R  cyc    : %0d", lsu_wait_r_cyc);
    $display("  等待AW/W周期   wait-AW/W cyc : %0d", lsu_wait_aw_w_cyc);
    $display("  等待B握手周期  wait-B  cyc   : %0d", lsu_wait_b_cyc);

    // ---- IDU 指令分类 ----
    $display("");
    $display("[4. 指令分类 IDU - Instruction Mix]  (数量/占比 of decoded)");
    $display("  计算类 Calc (R+I算术逻辑)     : %0d  (%.2f%%)", dec_calc,
             (dec_total > 0) ? (100.0 * dec_calc / dec_total) : 0.0);
    $display("    R型  R-type               : %0d  (%.2f%%)", dec_r_type,
             (dec_total > 0) ? (100.0 * dec_r_type / dec_total) : 0.0);
    $display("    I型  I-type(arith)       : %0d  (%.2f%%)", dec_i_arith,
             (dec_total > 0) ? (100.0 * dec_i_arith / dec_total) : 0.0);
    $display("  加载类 Load                   : %0d  (%.2f%%)", dec_load,
             (dec_total > 0) ? (100.0 * dec_load / dec_total) : 0.0);
    $display("    LB/LH/LW (有符号)          : %0d", dec_load_lb_lh_lw);
    $display("    LBU/LHU (无符号)           : %0d", dec_load_lbu_lhu);
    $display("  存储类 Store                  : %0d  (%.2f%%)", dec_store,
             (dec_total > 0) ? (100.0 * dec_store / dec_total) : 0.0);
    $display("    SB/SH (1/2字节)            : %0d", dec_store_sb_sh);
    $display("    SW (4字节)                 : %0d", dec_store_sw);
    $display("  分支类 Branch                 : %0d  (%.2f%%)", dec_branch,
             (dec_total > 0) ? (100.0 * dec_branch / dec_total) : 0.0);
    if (dec_branch > 0) begin
      $display("    taken (跳转)              : %0d  (%.2f%%)", dec_branch_taken,
               (100.0 * dec_branch_taken / dec_branch));
      $display("    not taken (不跳转)         : %0d  (%.2f%%)", dec_branch_nt,
               (100.0 * dec_branch_nt / dec_branch));
    end
    $display("  跳转类 Jump (jal/jalr)        : %0d  (%.2f%%)", dec_jump,
             (dec_total > 0) ? (100.0 * dec_jump / dec_total) : 0.0);
    $display("    jal                       : %0d", dec_jal);
    $display("    jalr                      : %0d", dec_jalr);
    $display("  U型 U-type (lui/auipc)        : %0d  (%.2f%%)", dec_u_type,
             (dec_total > 0) ? (100.0 * dec_u_type / dec_total) : 0.0);
    $display("    lui                       : %0d", dec_lui);
    $display("    auipc                     : %0d", dec_auipc);
    $display("  CSR类 CSR                     : %0d  (%.2f%%)", dec_csr,
             (dec_total > 0) ? (100.0 * dec_csr / dec_total) : 0.0);
    $display("  系统类 System (ebreak/ecall/..): %0d  (%.2f%%)", dec_sys,
             (dec_total > 0) ? (100.0 * dec_sys / dec_total) : 0.0);
    $display("  译码总数 Decoded total        : %0d", dec_total);

    // ---- 各类指令平均执行周期分析 ----
    $display("");
    $display("[5. 各类指令平均执行周期 Analysis]");
    if (dec_calc > 0 && cyc_total > 0) begin
      // 计算类指令: 在当前单周期 NPC 中, 每条计算指令占 1 周期
      // 但平均 CPI = cyc_total / dec_total, 其中计算类占比高代表 CPI 更接近 1
      $display("  计算类指令占比              : %.2f%% (期望CPI贡献接近1)",
               (dec_total > 0) ? (100.0 * dec_calc / dec_total) : 0.0);
    end
    if (load_cnt > 0) begin
      $display("  Load 指令平均延迟 (cyc)    : %.2f  (含总线等待)", (1.0 * load_latency_sum / load_cnt));
      $display("  Load 指令 CPI 贡献          : %.2f  (load_cnt * avg_lat / dec_total)",
               (dec_total > 0) ? (1.0 * load_latency_sum / dec_total) : 0.0);
    end
    if (store_cnt > 0) begin
      $display("  Store 指令平均延迟 (cyc)   : %.2f  (含总线等待)", (1.0 * store_latency_sum / store_cnt));
      $display("  Store 指令 CPI 贡献         : %.2f  (store_cnt * avg_lat / dec_total)",
               (dec_total > 0) ? (1.0 * store_latency_sum / dec_total) : 0.0);
    end
    $display("  理论最佳 CPI (全计算指令)    : 1.0");
    $display("  实际 CPI                    : %f", (ifu_ret_cnt > 0) ? (1.0 * cyc_total / ifu_ret_cnt) : 0.0);
    $display("  CPI 缺口 (gap to ideal)    : %f", (ifu_ret_cnt > 0) ? ((1.0 * cyc_total / ifu_ret_cnt) - 1.0) : 0.0);

    // ---- EXU 计算 ----
    $display("");
    $display("[6. 计算 EXU - Compute]");
    $display("  EXU完成计算 calc done        : %0d", exu_calc_cnt);

    // ---- 一致性检查 ----
    $display("");
    $display("[7. 一致性检查 Consistency Check]");
    $display("  IFU取到 == IDU译码 ? %s", (ifu_ret_cnt == dec_total) ? "PASS 通过" : "FAIL 失败");
    $display("    ifu_ret_cnt=%0d  dec_total=%0d", ifu_ret_cnt, dec_total);
    $display("  Load请求 == Load完成 ? %s", (load_cnt == load_ret_cnt) ? "PASS 通过" : "FAIL 失败");
    $display("    load_cnt=%0d  load_ret_cnt=%0d", load_cnt, load_ret_cnt);
    $display("  Store请求 == Store完成 ? %s", (store_cnt == store_ret_cnt) ? "PASS 通过" : "FAIL 失败");
    $display("    store_cnt=%0d  store_ret_cnt=%0d", store_cnt, store_ret_cnt);
    $display("  各类指令之和 == 译码总数 ? %s",
             ((dec_calc+dec_load+dec_store+dec_branch+dec_jump+dec_u_type+dec_csr+dec_sys) == dec_total) ? "PASS 通过" : "FAIL 失败");

    $display("============================================================");
    $display("");
  end

endmodule

`endif // ENABLE_PERF
