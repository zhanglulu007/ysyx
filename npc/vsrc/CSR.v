module CSR(
  input clk,
  input rst,
  
  input [11:0] csr_addr,      
  input [31:0] csr_wdata,     
  input csr_wen,              
  output reg [31:0] csr_rdata,

  input is_ecall,             
  input [31:0] pc,            
  
  output reg [31:0] mepc,     
  output reg [31:0] mtvec,
  output [31:0] mstatus_out,
  output [31:0] mcause_out,
  output [31:0] mcycle_lo_out,
  output [31:0] mcycle_hi_out
);

  reg [31:0] mstatus;   // 0x300 
  //reg [31:0] mtvec;     // 0x305 
  //reg [31:0] mepc;      // 0x341 
  reg [31:0] mcause;    // 0x342
  reg [31:0] mcycle_lo;
  
  always @(*) begin
    case (csr_addr)
      12'h300: csr_rdata = mstatus;           
      12'h305: csr_rdata = mtvec;             
      12'h341: csr_rdata = mepc;              
      12'h342: csr_rdata = mcause;                      
      12'hb00: csr_rdata = mcycle_lo;
      12'hb80: csr_rdata = 32'b0;
      default: csr_rdata = 32'b0;
    endcase
  end
  
  always @(posedge clk) begin
    if (rst) begin
      mstatus <= 32'h1800;  
      mtvec   <= 32'b0;
      mepc    <= 32'b0;
      mcause  <= 32'b0;
      mcycle_lo <= 32'b0;
    end else begin
      mcycle_lo <= mcycle_lo + 32'd1;
      if (is_ecall) begin
        mepc   <= pc;
        mcause <= 32'd11;
      end
      else if (csr_wen) begin
        case (csr_addr)
          12'h300: mstatus <= csr_wdata;  
          12'h305: mtvec   <= csr_wdata;  
          12'h341: mepc    <= csr_wdata;  
          12'h342: mcause  <= csr_wdata;  
          default: ;
        endcase
      end
    end
  end
  
  assign mstatus_out = mstatus;
  assign mcause_out  = mcause;
  assign mcycle_lo_out = mcycle_lo;
  assign mcycle_hi_out = 32'b0;

endmodule
