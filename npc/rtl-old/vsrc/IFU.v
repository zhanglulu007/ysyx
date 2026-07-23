// IFU - Instruction Fetch Unit
// 取指单元：负责根据PC从存储器中取出指令

module IFU(
  input clk,
  input rst,
  input [31:0] pc_next,      // 下一个PC值
  input [31:0] imem_rdata,
  output reg [31:0] pc,      // 当前PC
  output [31:0] inst         // 取出的指令
);

`ifndef SYNTHESIS
  // DPI-C函数：从存储器读取指令
  import "DPI-C" function int pmem_read(input int raddr);
  
  // DPI-C函数：通知C++侧PC更新
  import "DPI-C" function void update_pc_value(input int pc_val);
`endif
  
  // PC寄存器更新
  always @(posedge clk) begin
    if (rst) begin
      pc <= 32'h80000000;  // AM程序从0x80000000开始
`ifndef SYNTHESIS
      // 复位时同步初始PC值到C++侧
      update_pc_value(32'h80000000);
`endif
    end else begin
      pc <= pc_next;
`ifndef SYNTHESIS
      // PC更新后立即同步到C++侧
      update_pc_value(pc_next);
`endif
    end
  end
  
  // 取指：从PC地址读取指令
  // 在复位期间返回nop指令，避免读取无效地址
`ifdef SYNTHESIS
  assign inst = rst ? 32'h00000013 : imem_rdata;
`else
  assign inst = rst ? 32'h00000013 : pmem_read(pc);  // nop = addi x0, x0, 0
`endif

endmodule
