module PMEM(
  input clk,
  input rst,
  
  input mem_valid,           
  input mem_wen,             

  input [31:0] mem_addr,   
  input [31:0] mem_wdata,
  input [7:0] mem_wmask,       

  output [31:0] mem_rdata        
);
  import "DPI-C" function int pmem_read(input int raddr);
  import "DPI-C" function void pmem_write(input int waddr, input int wdata, input byte wmask);
  
  assign mem_rdata = (!rst && mem_valid && !mem_wen) ? pmem_read(mem_addr) : 32'b0;
  
  always @(posedge clk) begin
    if (!rst && mem_valid && mem_wen) begin
      pmem_write(mem_addr, mem_wdata, mem_wmask);
    end
  end

endmodule
