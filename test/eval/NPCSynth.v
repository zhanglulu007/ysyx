// 综合边界: 只保留核的时钟/复位与指令存储观察口, 便于同口径比较面积/频率
module NPCSynth(
  input  clk,
  input  rst,
  input  [31:0] imem_rdata,
  output [31:0] pc,
  output [31:0] inst,
  output [31:0] imem_addr
);

  top u_top(
    .clk(clk),
    .rst(rst),
    .imem_rdata(imem_rdata),
    .pc(pc),
    .inst(inst),
    .imem_addr(imem_addr)
  );

endmodule
