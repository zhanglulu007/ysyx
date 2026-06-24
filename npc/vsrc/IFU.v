// IFU - Instruction Fetch Unit
// 取指单元：通过 SimpleBus 从 MEM 模块取指令
// SimpleBus 协议: 支持有效信号 reqValid/respValid
// 两状态状态机: IDLE (发送取指请求) / WAIT (等待响应, 执行指令)
// 单周期设计: 非访存指令 2 周期完成, load/store 3 周期完成

module IFU(
  input clk,
  input rst,
  input [31:0] pc_next,        // 下一个PC值 (来自WBU)
  input mem_valid,              // 访存有效 (load/store, 来自IDU)
  input mem_wen,                // 写使能 (store, 来自IDU)
  input [4:0] rd,              // 目的寄存器 (来自IDU)
  input ifu_respValid,         // MEM -> IFU: 取指响应有效
  input lsu_respValid,         // MEM -> LSU: 访存响应有效
  input [31:0] ifu_rdata,      // MEM -> IFU: 取出的指令
  output reg [31:0] pc,        // 当前PC
  output ifu_reqValid,         // IFU -> MEM: 取指请求有效
  output [31:0] ifu_raddr,     // IFU -> MEM: 取指地址
  output [31:0] inst,          // -> IDU: 当前指令
  output ifu_valid,            // -> IDU: 指令有效 (译码/执行周期)
  output load_wb,              // -> top: load 写回触发
  output [4:0] load_rd         // -> top: load 目的寄存器
);

  // DPI-C函数：通知C++侧
  import "DPI-C" function void update_pc_value(input int pc_val);
  import "DPI-C" function void update_inst_value(input int pc_val, input int inst_val);

  // ========== 两状态状态机 ==========
  // IDLE - 发送取指请求
  // WAIT - 等待取指响应, 执行指令, 可能等待LSU响应
  localparam IDLE = 1'b0;
  localparam WAIT = 1'b1;

  reg state;
  reg lsu_pending;          // 1 = 在 WAIT 状态中等待 LSU 响应
  reg is_load_pending;      // 1 = 等待中的 LSU 操作是 load (需要写回)
  reg [4:0] load_rd_saved;  // load 指令的目的寄存器

  // ifu_raddr 恒等于 pc, MEM 仅在 reqValid 有效时采样
  assign ifu_raddr = pc;

  // ifu_reqValid: 在 IDLE 状态发送取指请求
  assign ifu_reqValid = (state == IDLE) && !rst;

  // ifu_valid: 仅在取指响应有效且未等待 LSU 时有效
  assign ifu_valid = (state == WAIT) && ifu_respValid && !lsu_pending && !rst;

  // inst: 有效指令或 NOP
  //   - 当 ifu_valid=1 时输出真实指令
  //   - 当等待 LSU 时输出 NOP (防止 IDU 重复译码 load/store)
  assign inst = ifu_valid ? ifu_rdata : 32'h00000013;  // nop = addi x0, x0, 0

  // load_wb: 当 LSU 返回 load 数据时触发写回 (组合逻辑)
  assign load_wb = (state == WAIT) && lsu_pending && lsu_respValid && is_load_pending;
  assign load_rd = load_rd_saved;

  always @(posedge clk) begin
    if (rst) begin
      state           <= IDLE;
      lsu_pending     <= 1'b0;
      is_load_pending <= 1'b0;
      load_rd_saved   <= 5'b0;
      pc              <= 32'h80000000;
      update_pc_value(32'h80000000);
    end else begin
      case (state)
        IDLE: begin
          // 发送取指请求 (ifu_reqValid=1), 下一周期进入 WAIT
          state       <= WAIT;
          lsu_pending <= 1'b0;
        end

        WAIT: begin
          if (lsu_pending) begin
            // ===== 等待 LSU 响应 =====
            if (lsu_respValid) begin
              // LSU 操作完成
              //   - load:  数据已通过 load_wb 写回 (组合逻辑, 本周期 posedge 写入)
              //   - store: 写入已完成
              pc               <= pc_next;
              update_pc_value(pc_next);
              state            <= IDLE;
              lsu_pending      <= 1'b0;
              is_load_pending  <= 1'b0;
            end
            // lsu_respValid == 0: 继续保持 WAIT 等待
          end else if (ifu_respValid) begin
            // ===== 取指响应有效, 执行指令 =====
            update_inst_value(pc, ifu_rdata);

            if (mem_valid) begin
              // Load 或 Store: 需要等待 LSU 完成
              // LSU 请求在本周期已发送 (mem_valid/mem_wen 由 IDU 组合逻辑产生)
              lsu_pending     <= 1'b1;
              is_load_pending <= !mem_wen;  // mem_wen=0 -> load, mem_wen=1 -> store
              load_rd_saved   <= rd;
              // 保持 WAIT 状态
            end else begin
              // 非访存指令: 本周期完成执行, 写回寄存器 (由 top.v 处理)
              pc               <= pc_next;
              update_pc_value(pc_next);
              state            <= IDLE;
            end
          end
          // ifu_respValid == 0: 继续保持 WAIT 等待取指响应
        end

        default: state <= IDLE;
      endcase
    end
  end

endmodule
