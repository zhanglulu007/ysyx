// IFU - Instruction Fetch Unit with Prefetch Buffer
// 取指单元：通过 AXI4 从 MEM 模块取指令 (通过仲裁器)
// 支持 burst 预取: 一次 AXI 事务取多条指令缓存到内部 buffer,
// 减少 PSRAM/Flash 等高延迟存储器的访问次数.
//
// 状态机:
//   IDLE  : 等待 AXI AR ready 或 buffer 空需要发送新请求
//   WAIT  : 等待 AXI R 通道返回数据
//   RDATA : 收集 R 通道数据写入 buffer
//
// AXI4 扩展: 添加 id, len, size, burst, last 等信号

module IFU(
  input clk,
  input rst,
  input [31:0] pc_next,        // 下一个PC值 (来自WBU)
  input mem_valid,              // 访存有效 (load/store, 来自IDU)
  input mem_wen,                // 写使能 (store, 来自IDU)
  input [4:0] rd,              // 目的寄存器 (来自IDU)

  // ===== AXI4 AR 通道 (读地址) =====
  input  ifu_arready,
  output ifu_arvalid,
  output [31:0] ifu_araddr,
  output [ 3:0] ifu_arid,      // AXI4: Transaction ID
  output [ 7:0] ifu_arlen,     // AXI4: Burst length
  output [ 2:0] ifu_arsize,    // AXI4: Transfer size
  output [ 1:0] ifu_arburst,   // AXI4: Burst type

  // ===== AXI4 R 通道 (读数据) =====
  input  ifu_rvalid,
  output ifu_rready,
  input  [31:0] ifu_rdata,
  input  [ 1:0] ifu_rresp,
  input  ifu_rlast,            // AXI4: Last beat
  input  [ 3:0] ifu_rid,       // AXI4: Transaction ID

  // ===== LSU 完成信号 (来自 MEM 的 R/B 通道) =====
  input  lsu_rvalid,
  input  lsu_bvalid,
  input  lsu_access_fault,  // LSU 报告的 load/store 访问异常

  // ===== 输出 =====
  output reg [31:0] pc,        // 当前PC
  output [31:0] inst,          // -> IDU: 当前指令
  output ifu_valid,            // -> IDU: 指令有效 (译码/执行周期)
  output load_wb,              // -> top: load 写回触发
  output [4:0] load_rd,        // -> load 目的寄存器
  output ifu_access_fault      // -> top: 取指访问异常 (跳转地址0)
);

  // DPI-C函数：通知C++侧
  import "DPI-C" function void update_pc_value(input int pc_val);
  import "DPI-C" function void update_inst_value(input int pc_val, input int inst_val);

  // ========== 参数 ==========
  // Burst 大小: 一次取 4 条指令 (16 字节), arlen=3 表示 4 个 beat
  localparam BURST_LEN     = 8'd3;   // 4 beats
  localparam BURST_BYTES   = 5'd16;  // 4 * 4 = 16 字节
  // Buffer 深度: 存 4 条指令 (与 burst 大小匹配)
  localparam BUFFER_DEPTH  = 4;

  // ========== 内部状态 ==========
  localparam IDLE  = 2'd0;
  localparam WAIT  = 2'd1;
  localparam RDATA = 2'd2;

  reg [1:0] state;
  reg lsu_pending;          // 1 = 在 WAIT 状态中等待 LSU 响应
  reg is_load_pending;      // 1 = 等待中的 LSU 操作是 load (需要写回)
  reg [4:0] load_rd_saved;  // load 指令的目的寄存器
  reg ifu_fault_reg;        // 取指访问异常锁存 (rresp[1]错误)

  // ========== 指令缓冲队列 ==========
  // 环形 FIFO 缓冲预取回来的指令
  reg [31:0] buf_inst [0:BUFFER_DEPTH-1];  // 指令缓冲区
  reg [31:0] buf_pc   [0:BUFFER_DEPTH-1];  // 对应的 PC 值
  reg [ BUFFER_DEPTH-1:0] buf_valid;        // 每项是否有效
  reg [ BUFFER_DEPTH-1:0] buf_fault;        // 每项是否有访问异常

  reg [$clog2(BUFFER_DEPTH)-1:0] buf_wptr;  // 写指针
  reg [$clog2(BUFFER_DEPTH)-1:0] buf_rptr;  // 读指针
  wire                            buf_empty = (buf_wptr == buf_rptr) && !buf_valid[buf_rptr];
  wire                            buf_full  = (buf_wptr == buf_rptr) &&  buf_valid[buf_rptr];

  // 预取请求目标 PC (当前取指 PC, 按 BURST_BYTES 对齐)
  reg [31:0] fetch_pc;
  wire [31:0] fetch_pc_aligned = {fetch_pc[31:4], 4'h0};  // 16 字节对齐

  // Burst 进度计数 (WAIT/RDATA 状态下)
  reg [7:0] beat_cnt;       // 已接收的 beat 数

  // ========== AXI4 信号赋值 ==========
  // 只在 IDLE 状态、buffer 非满、且没有 LSU 需要等待时发起新请求
  assign ifu_arvalid = (state == IDLE) && !buf_full && !lsu_pending && !rst;
  assign ifu_araddr  = fetch_pc_aligned;
  assign ifu_arid    = 4'b0000;
  assign ifu_arlen   = BURST_LEN;
  assign ifu_arsize  = 3'b010;       // 4 字节传输
  assign ifu_arburst = 2'b01;        // INCR 模式

  // R ready: 在 WAIT/RDATA 状态下接收数据
  assign ifu_rready = ((state == WAIT) || (state == RDATA)) && !lsu_pending && !rst;

  // ========== 输出给 IDU ==========
  // 从 buffer 读指针处取指: 当 buffer 非空时提供指令
  wire buf_has_inst = buf_valid[buf_rptr];
  reg  buf_consume;  // 当前指令已被消费

  assign ifu_valid = buf_has_inst && !buf_fault[buf_rptr] && !lsu_pending && !rst;
  assign inst      = ifu_valid ? buf_inst[buf_rptr] : 32'h00000013;  // nop

  assign load_wb = (state == IDLE || state == WAIT) && lsu_pending && lsu_rvalid && is_load_pending;
  assign load_rd = load_rd_saved;

  assign ifu_access_fault = ifu_fault_reg;

  // ========== 组合逻辑: 从 buffer 输出指令时同步更新 pc ==========
  always @(*) begin
    if (buf_has_inst && !buf_fault[buf_rptr] && !lsu_pending && !rst) begin
      pc = buf_pc[buf_rptr];
    end else begin
      pc = fetch_pc_aligned + beat_cnt * 4;  // fallback
    end
  end

  // ========== 主状态机 ==========
  always @(posedge clk) begin
    if (rst) begin
      state         <= IDLE;
      lsu_pending   <= 1'b0;
      is_load_pending <= 1'b0;
      load_rd_saved <= 5'b0;
      ifu_fault_reg <= 1'b0;
      fetch_pc      <= 32'h30000000;  // flash 复位地址
      beat_cnt      <= 8'd0;
      buf_wptr      <= 0;
      buf_rptr      <= 0;
      buf_consume   <= 1'b0;
      // 清空 buffer 有效位
      for (integer i = 0; i < BUFFER_DEPTH; i = i + 1) begin
        buf_valid[i] <= 1'b0;
        buf_fault[i] <= 1'b0;
        buf_inst[i]  <= 32'h00000013;
        buf_pc[i]    <= 32'h30000000;
      end
      update_pc_value(32'h30000000);
    end else begin
      // 默认: 不消费 buffer
      buf_consume <= 1'b0;

      case (state)
        // ========== IDLE: 检查是否需要发起新请求 ==========
        IDLE: begin
          // 先检查 LSU 是否已完成 (从上一周期延续)
          if (lsu_pending) begin
            if (lsu_rvalid || lsu_bvalid) begin
              if (lsu_access_fault) begin
                ifu_fault_reg <= 1'b1;
                fetch_pc      <= 32'h00000000;
                update_pc_value(32'h00000000);
              end else begin
                fetch_pc <= pc_next;
              end
              lsu_pending     <= 1'b0;
              is_load_pending <= 1'b0;
            end
          end else if (ifu_arready && !buf_full) begin
            // AXI AR 握手成功, 进入 WAIT 等待数据
            state    <= WAIT;
            beat_cnt <= 8'd0;
          end
        end

        // ========== WAIT: 等待 AXI R 通道数据 ==========
        WAIT: begin
          if (ifu_rvalid && ifu_rready) begin
            // 收到一个 beat 的数据
            if (ifu_rresp[1]) begin
              // 访问异常: 标记整个 burst 为故障
              ifu_fault_reg <= 1'b1;
              fetch_pc      <= 32'h00000000;
              update_pc_value(32'h00000000);
              state         <= IDLE;
              // 清空 buffer
              for (integer i = 0; i < BUFFER_DEPTH; i = i + 1) begin
                buf_valid[i] <= 1'b0;
                buf_fault[i] <= 1'b0;
              end
              buf_wptr <= 0;
              buf_rptr <= 0;
            end else begin
              // 写入 buffer
              buf_inst[buf_wptr]  <= ifu_rdata;
              buf_pc[buf_wptr]    <= fetch_pc_aligned + beat_cnt * 4;
              buf_valid[buf_wptr] <= 1'b1;
              buf_fault[buf_wptr] <= 1'b0;

              if (ifu_rlast) begin
                // Burst 完成: 回到 IDLE
                state    <= IDLE;
                buf_wptr <= buf_wptr + 1;
                beat_cnt <= 8'd0;
              end else begin
                // 还有更多 beat
                state    <= RDATA;
                buf_wptr <= buf_wptr + 1;
                beat_cnt <= beat_cnt + 1;
              end

              // 更新 update_inst_value (将第一条指令通知 C++ 侧用于 trace)
              if (beat_cnt == 0) begin
                update_inst_value(fetch_pc_aligned, ifu_rdata);
              end
            end
          end
        end

        // ========== RDATA: 继续接收 burst 剩余 beat ==========
        RDATA: begin
          if (ifu_rvalid && ifu_rready) begin
            if (ifu_rresp[1]) begin
              ifu_fault_reg <= 1'b1;
              fetch_pc      <= 32'h00000000;
              update_pc_value(32'h00000000);
              state         <= IDLE;
              for (integer i = 0; i < BUFFER_DEPTH; i = i + 1) begin
                buf_valid[i] <= 1'b0;
                buf_fault[i] <= 1'b0;
              end
              buf_wptr <= 0;
              buf_rptr <= 0;
            end else begin
              buf_inst[buf_wptr]  <= ifu_rdata;
              buf_pc[buf_wptr]    <= fetch_pc_aligned + ({24'd0, beat_cnt} + 32'd1) * 4;
              buf_valid[buf_wptr] <= 1'b1;
              buf_fault[buf_wptr] <= 1'b0;

              if (ifu_rlast) begin
                state    <= IDLE;
                buf_wptr <= buf_wptr + 1;
                beat_cnt <= 8'd0;
              end else begin
                buf_wptr <= buf_wptr + 1;
                beat_cnt <= beat_cnt + 1;
              end
            end
          end
        end

        default: state <= IDLE;
      endcase

      // ========== buffer 消费逻辑 (独立于状态机) ==========
      // 当 buffer 非空、无 LSU 等待、且当前指令已被消耗 (WBU 已给出 pc_next)
      if (buf_valid[buf_rptr] && !buf_fault[buf_rptr] && !lsu_pending && !rst) begin
        // 检查是否需要推进读指针: 两种情况
        // 1. 当前是最后一条指令 (pc_next 指向下个 16 字节区域)
        // 2. 分支/跳转 (pc_next != pc+4)
        // 简化为: 一旦 WBU 更新了 pc_next 且与当前指令不连续, 就消费
        if (pc_next != (buf_pc[buf_rptr] + 4) || (pc_next[31:4] != buf_pc[buf_rptr][31:4])) begin
          // 分支/跳转或不连续: 清空 buffer, 重新预取
          for (integer i = 0; i < BUFFER_DEPTH; i = i + 1) begin
            buf_valid[i] <= 1'b0;
            buf_fault[i] <= 1'b0;
          end
          buf_rptr      <= 0;
          buf_wptr      <= 0;
          fetch_pc      <= pc_next;
          update_pc_value(pc_next);
          buf_consume   <= 1'b1;
        end else begin
          // 正常连续执行: 消费当前 buffer 项
          buf_valid[buf_rptr] <= 1'b0;
          buf_fault[buf_rptr] <= 1'b0;
          buf_rptr <= buf_rptr + 1;
          buf_consume <= 1'b1;
        end
      end
    end
  end

endmodule