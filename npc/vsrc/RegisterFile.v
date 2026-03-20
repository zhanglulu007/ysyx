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
  
  // 32个寄存器（实际只使用前16个，RV32E）
  reg [31:0] rf [31:0];
  
  // DPI-C导入函数：通知C++侧寄存器更新
  import "DPI-C" function void update_reg_value(input int idx, input int value);
  
  // 写操作 - 时序逻辑
  always @(posedge clk) begin
    if (wen && waddr != 5'b0) begin
      // x0寄存器恒为0，不可写
      rf[waddr] <= wdata;
      // 通知C++侧更新（扩展到32位）
      update_reg_value({27'b0, waddr}, wdata);
    end
  end
  
  // 读操作 - 组合逻辑
  // x0寄存器恒为0
  assign rdata1 = (raddr1 == 5'b0) ? 32'b0 : rf[raddr1];
  assign rdata2 = (raddr2 == 5'b0) ? 32'b0 : rf[raddr2];
  
  // 读取a0寄存器（x10）的值
  assign a0_value = rf[10];

endmodule
