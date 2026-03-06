module IFU(
  input clk,
  input rst,
  input [31:0] pc_next,      // 下一个PC值
  output reg [31:0] pc,      // 当前PC
  output [31:0] inst         // 取出的指令
);
  import "DPI-C" function int pmem_read(input int raddr);
  
  // PC寄存器更新
  always @(posedge clk) begin
    if (rst) begin
      pc <= 32'h80000000;  
    end else begin
      pc <= pc_next;
    end
  end
  
  // 取指：从PC地址读取指令
  assign inst = rst ? 32'h00000013 : pmem_read(pc);  // nop = addi x0, x0, 0

endmodule
