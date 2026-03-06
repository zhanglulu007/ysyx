module RegisterFile(
  input clk,
  input [31:0] wdata,         
  input [4:0] waddr,          
  input wen,                  
  input [4:0] raddr1,         
  output [31:0] rdata1,       
  input [4:0] raddr2,         
  output [31:0] rdata2,       
  output [31:0] a0_value      // a0寄存器的值（x10）
);
  
  // 32个寄存器（实际只使用前16个，RV32E）
  reg [31:0] rf [31:0];
  
  // 写操作 - 时序逻辑
  always @(posedge clk) begin
    if (wen && waddr != 5'b0) begin
      // x0寄存器恒为0，不可写
      rf[waddr] <= wdata;
    end
  end
  
  // 读操作 - 组合逻辑
  // x0寄存器恒为0
  assign rdata1 = (raddr1 == 5'b0) ? 32'b0 : rf[raddr1];
  assign rdata2 = (raddr2 == 5'b0) ? 32'b0 : rf[raddr2];
  
  // 读取a0寄存器（x10）的值
  assign a0_value = rf[10];

endmodule
