module IFU(
  input clk,
  input rst,
  input [31:0] pc_next,      
  input [31:0] imem_rdata,
  output reg [31:0] pc,      
  output [31:0] inst         
);

`ifndef SYNTHESIS
  import "DPI-C" function int pmem_read(input int raddr);
`endif

  always @(posedge clk) begin
    if (rst) begin
      pc <= 32'h80000000;
    end else begin
      pc <= pc_next;
    end
  end
  
`ifdef SYNTHESIS
  assign inst = rst ? 32'h00000013 : imem_rdata;
`else
  assign inst = rst ? 32'h00000013 : pmem_read(pc);
`endif

endmodule
