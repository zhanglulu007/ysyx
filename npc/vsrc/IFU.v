// IFU - Instruction Fetch Unit
// 取指单元：负责根据PC从存储器中取出指令

module IFU(
  input clk,
  input rst,
  input idready,
  input [31:0] pc_next,      // 下一个PC值
  output reg [31:0] pc,      // 当前PC
  output [31:0] inst,        // 取出的指令
  output ifvalid,          // 取指有效信号
  //SimpleBus
  output [31:0] ifu_raddr,
  input  [31:0] ifu_rdata
);

  // DPI-C函数：从存储器读取指令
  import "DPI-C" function int pmem_read(input int raddr);
  // DPI-C函数：通知C++侧PC更新
  import "DPI-C" function void update_pc_value(input int pc_val);

  parameter IDLE = 1'b0;
  parameter WAIT = 1'b1;

  reg state;
  
  always @(posedge clk) begin
    if (rst) begin
        state    <= IDLE;
        pc       <= 32'h80000000;
        ifu_rdata <= 32'h00000013;  // nop
        update_pc_value(32'h80000000);
    end else begin
        case (state)
            IDLE: begin
                // 发送读请求: ifu_raddr = pc
                // 寄存读到 pmem_read 的结果, 下一周期(WAIT)可用
                ifu_rdata <= pmem_read(pc);
                // PC 在 IDLE 时不更新 (没有有效指令执行)
                state <= WAIT;
            end
            WAIT: begin
                // ifu_rdata 是有效的指令, 执行并更新 PC
                pc <= pc_next;
                update_pc_value(pc_next);
                state <= IDLE; 
            end
        endcase
    end
end
  
  // 取指：从PC地址读取指令
  assign inst = (state == WAIT) ? ifu_rdata : 32'h00000013;  // nop = addi x0, x0, 0
  assign ifvalid = (state == WAIT) && !rst;

endmodule
