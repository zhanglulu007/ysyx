module RegisterFile(
  input clk,
  input rst,

  input [31:0] wdata,         
  input [4:0] waddr,          
  input wen,

  input [4:0] raddr1,         
  output [31:0] rdata1,       
  input [4:0] raddr2,         
  output [31:0] rdata2,

  output [31:0] a0_value      
);

  reg [31:0] rf [15:0];

`ifndef SYNTHESIS
  import "DPI-C" function void update_reg_value(input int idx, input int value);
`endif
  
  always @(posedge clk) begin
    if (!rst && wen) begin
      rf[waddr[3:0]] <= wdata;
`ifndef SYNTHESIS
      update_reg_value({27'b0, waddr}, wdata);
`endif
    end
  end

  assign rdata1 = (raddr1 == 5'b0) ? 32'd0 : rf[raddr1[3:0]];
  assign rdata2 = (raddr2 == 5'b0) ? 32'd0 : rf[raddr2[3:0]];
  assign a0_value = rf[10];

endmodule
