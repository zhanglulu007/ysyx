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
  output reg [31:0] mtvec     
);

  reg [31:0] mstatus;   // 0x300 
  //reg [31:0] mtvec;     // 0x305 
  //reg [31:0] mepc;      // 0x341 
  reg [31:0] mcause;    // 0x342 
  reg [63:0] mcycle;    
  
  always @(*) begin
    case (csr_addr)
      12'h300: csr_rdata = mstatus;           
      12'h305: csr_rdata = mtvec;             
      12'h341: csr_rdata = mepc;              
      12'h342: csr_rdata = mcause;                      
      12'hb00: csr_rdata = mcycle[31:0]; 
      12'hb80: csr_rdata = mcycle[63:32];
      default: csr_rdata = 32'b0;
    endcase
  end
  
  always @(posedge clk) begin
    if (rst) begin
      mstatus <= 32'h1800;  
      mtvec   <= 32'b0;
      mepc    <= 32'b0;
      mcause  <= 32'b0;
      mcycle  <= 64'b0;
    end else begin
      mcycle <= mcycle + 64'b1;
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
  
  // assign mepc_out  = mepc;
  // assign mtvec_out = mtvec;

endmodule
