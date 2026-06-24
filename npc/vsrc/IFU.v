// IFU - Instruction Fetch Unit
// 取指单元：通过 SimpleBus 从 MEM 模块取指令
// SimpleBus 协议: 取指有 1 周期延迟, load 指令额外 stall 1 周期

module IFU(
  input clk,
  input rst,
  input idu_ready,
  input mem_valid,            // 访存有效（来自 IDU）
  input mem_wen,              // 写使能（来自 IDU, 用于区分 load/store）
  input [31:0] pc_next,      // 下一个PC值
  input [31:0] ifu_rdata,    // 来自 MEM 的指令 (1 周期延迟)
  output reg [31:0] pc,      // 当前PC
  output [31:0] ifu_raddr,   // 发送到 MEM 的取指地址
  output [31:0] inst,        // 取出的指令
  output ifu_valid           // 取指有效信号
);

  // DPI-C函数：通知C++侧
  import "DPI-C" function void update_pc_value(input int pc_val);
  import "DPI-C" function void update_inst_value(input int pc_val, input int inst_val);

  // 三状态状态机:
  //   IDLE  - 发送取指地址, 等待 MEM 返回
  //   WAIT  - 指令有效, 译码并执行
  //   STALL - load 指令等待 LSU 返回数据
  localparam IDLE  = 2'b00;
  localparam WAIT  = 2'b01;
  localparam STALL = 2'b10;

  reg [1:0] state;

  // ifu_raddr 恒等于 pc, MEM 每周期在 posedge 采样并读存储器
  assign ifu_raddr = pc;

  always @(posedge clk) begin
    if (rst) begin
        state <= IDLE;
        pc    <= 32'h80000000;
        update_pc_value(32'h80000000);
    end else begin
        case (state)
            IDLE: begin
                // MEM 在本周期 posedge 读取 ifu_raddr, 下周期数据就绪
                state <= WAIT;
            end

            WAIT: begin
                // ifu_rdata 由 MEM 在上一个 IDLE posedge 寄存器化, 本周期有效
                update_inst_value(pc, ifu_rdata);

                if (idu_ready) begin
                    if (mem_valid && !mem_wen) begin
                        // ===== Load 指令: 需要等待 LSU 返回数据 =====
                        state <= STALL;
                    end else begin
                        // ===== 非 Load 指令: 正常推进 =====
                        pc <= pc_next;
                        update_pc_value(pc_next);
                        state <= IDLE;
                    end
                end
                // idu_ready == 0 时保持 WAIT (流水线互锁)
            end

            STALL: begin
                // Load 数据已就绪 (LSU 的 rdata 在 STALL 周期有效, 写回由 top.v 处理)
                pc <= pc_next;
                update_pc_value(pc_next);
                state <= IDLE;
            end

            default: state <= IDLE;
        endcase
    end
  end

  // 仅在 WAIT 状态输出真实指令, 其余时间输出 nop
  assign inst = (state == WAIT) ? ifu_rdata : 32'h00000013;  // nop = addi x0, x0, 0
  assign ifu_valid = (state == WAIT) && !rst;

endmodule
