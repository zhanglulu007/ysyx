// IFU - Instruction Fetch Unit
// 取指单元：通过 AXI4 从 MEM 模块取指令 (通过仲裁器)
// 两状态状态机: IDLE (等待arready握手) / WAIT (等待rvalid握手/指令执行完成)
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
  output ifu_access_fault,     // -> top: 取指访问异常 (跳转地址0)

  // ===== 性能计数器观测端口 (仅仿真用, 由 ENABLE_PERF 实例化的 PerfCounter 使用) =====
  output ifu_state,            // IFU 状态机状态 (IDLE=0 / WAIT=1)
  output ifu_ar_handshake,     // AR 通道握手 (state==IDLE && arready): 发出一次取指请求
  output ifu_r_handshake,      // R  通道握手 (rvalid && rready && !lsu_pending): 取到指令
  output ifu_lsu_pending       // WAIT 状态下正在等待 LSU (访存指令未完成)
);

  // DPI-C函数：通知C++侧
  import "DPI-C" function void update_pc_value(input int pc_val);
  import "DPI-C" function void update_inst_value(input int pc_val, input int inst_val);

  localparam IDLE = 1'b0 , WAIT = 1'b1;

  reg state;
  reg lsu_pending;          // 1 = 在 WAIT 状态中等待 LSU 响应
  reg is_load_pending;      // 1 = 等待中的 LSU 操作是 load (需要写回)
  reg [4:0] load_rd_saved;  // load 指令的目的寄存器
  reg ifu_fault_reg;        // 取指访问异常锁存 (rresp[1]错误)

  // AXI4 信号赋值
  assign ifu_araddr = pc;
  assign ifu_arvalid = (state == IDLE) && !rst;

  // AXI4 扩展信号
  assign ifu_arid = 4'b0000;      // ID固定为0
  assign ifu_arlen = 8'b00000000; // 单次传输 (len=0表示1个beat)
  assign ifu_arsize = 3'b010;     // 4字节传输 (2^2 = 4 bytes)
  assign ifu_arburst = 2'b01;     // INCR模式 (增量突发)

  assign ifu_rready = (state == WAIT) && !lsu_pending && !rst;
  assign ifu_valid = (state == WAIT) && ifu_rvalid && ifu_rready && !lsu_pending && !rst;
  assign inst = ifu_valid ? ifu_rdata : 32'h00000013;  // nop
  assign load_wb = (state == WAIT) && lsu_pending && lsu_rvalid && is_load_pending;
  assign load_rd = load_rd_saved;

  // ===== 性能计数器观测信号 =====
  assign ifu_state        = state;
  assign ifu_ar_handshake = (state == IDLE) && ifu_arvalid && ifu_arready && !rst;
  assign ifu_r_handshake  = (state == WAIT) && ifu_rvalid && ifu_rready && !lsu_pending && !rst;
  assign ifu_lsu_pending  = (state == WAIT) && lsu_pending && !rst;

  // 取指访问异常: 在取指握手完成且 rresp[1]=1 时置位, 输出给 top 用于跳转地址0
  assign ifu_access_fault = ifu_fault_reg;

  always @(posedge clk) begin
    if (rst) begin
      state           <= IDLE;
      lsu_pending     <= 1'b0;
      is_load_pending <= 1'b0;
      load_rd_saved   <= 5'b0;
      ifu_fault_reg   <= 1'b0;
      pc              <= 32'h30000000;  // flash 
      update_pc_value(32'h30000000);
    end else begin
      case (state)
        IDLE: begin
          if (ifu_arready) begin
            state       <= WAIT;
            lsu_pending <= 1'b0;
          end
        end

        WAIT: begin
          if (lsu_pending) begin
            if (lsu_rvalid || lsu_bvalid) begin
              if (lsu_access_fault) begin
                // load/store 访问异常: 跳转地址0
                ifu_fault_reg    <= 1'b1;
                pc               <= 32'h00000000;
                update_pc_value(32'h00000000);
              end else begin
                pc               <= pc_next;
                update_pc_value(pc_next);
              end
              state            <= IDLE;
              lsu_pending      <= 1'b0;
              is_load_pending  <= 1'b0;
            end
          end else if (ifu_rvalid && ifu_rready) begin
            // 取指访问异常: rresp[1]=1 表示设备返回错误 (SLVERR/DECERR)
            // 即使程序未启动CTE, 也跳转到地址0, 让你察觉程序运行不正常
            if (ifu_rresp[1]) begin
              ifu_fault_reg <= 1'b1;
              pc            <= 32'h00000000;
              update_pc_value(32'h00000000);
              state         <= IDLE;
            end else begin
              update_inst_value(pc, ifu_rdata);
              if (mem_valid) begin
                // Load 或 Store: 需要等待 LSU 完成
                lsu_pending     <= 1'b1;
                is_load_pending <= !mem_wen;  // mem_wen=0 -> load, mem_wen=1 -> store
                load_rd_saved   <= rd;
              end else begin
                // 非访存指令: 本周期完成执行, 写回寄存器 (由 top.v 处理)
                pc               <= pc_next;
                update_pc_value(pc_next);
                state            <= IDLE;
              end
            end
          end
        end

        default: state <= IDLE;
      endcase
    end
  end

endmodule
