// RegisterFile - 寄存器堆模块
// 16个32位通用寄存器（RV32E）

module RegisterFile(
  input clk,
  input [31:0] wdata,         // 写入数据
  input [4:0] waddr,          // 写入地址
  input wen,                  // 写使能
  input [4:0] raddr1,         // 读端口1地址
  output [31:0] rdata1,       // 读端口1数据
  input [4:0] raddr2,         // 读端口2地址
  output [31:0] rdata2,       // 读端口2数据
  output [31:0] a0_value      // a0寄存器的值（x10）
);
  
  reg [31:0] rf [16:0];
  
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
