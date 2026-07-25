module RTLStandalone_Synth(
  input clk,
  input rst,
  input [31:0] imem_rdata,

  output [31:0] imem_addr
);

  top u_core(
    .clk(clk),
    .rst(rst),
    .imem_rdata(imem_rdata),
    .pc(),
    .inst(),
    .imem_addr(imem_addr)
  );

endmodule
