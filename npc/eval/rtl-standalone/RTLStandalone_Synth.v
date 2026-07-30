// rtl-standalone synthesis boundary.
// The current top contains a SYNTHESIS-only AXI memory model, so the
// evaluation keeps the processor boundary at the instruction-memory ports.

module RTLStandalone_Synth(
  input clk,
  input rst,
  input [31:0] imem_rdata,

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
