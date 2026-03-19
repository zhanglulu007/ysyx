// CSR - Control and Status Registers
// CSR寄存器模块：实现RISC-V的控制状态寄存器

module CSR(
  input clk,
  input rst,
  
  // CSR读写接口
  input [11:0] csr_addr,      // CSR地址
  input [31:0] csr_wdata,     // CSR写数据
  input csr_wen,              // CSR写使能
  output reg [31:0] csr_rdata,// CSR读数据
  
  // 异常处理接口
  input exception_en,         // 异常使能
  input [31:0] exception_pc,  // 异常发生时的PC
  input [31:0] exception_cause,// 异常原因
  
  // mret指令接口
  input mret_en,              // mret使能
  output [31:0] mepc_out,     // mepc寄存器输出（用于mret返回）
  output [31:0] mtvec_out     // mtvec寄存器输出（异常入口地址）
);

  // ========== CSR寄存器定义 ==========
  reg [31:0] mstatus;   // 0x300 
  reg [31:0] mtvec;     // 0x305 
  reg [31:0] mepc;      // 0x341 
  reg [31:0] mcause;    // 0x342 
  reg [63:0] mcycle;    
  
  wire [31:0] mvendorid = 32'h79737978;  
  wire [31:0] marchid   = 32'h26020070;
  
  // ========== mcycle计数器 ==========
  always @(posedge clk) begin
    if (rst) begin
      mcycle <= 64'b0;
    end else begin
      mcycle <= mcycle + 64'b1;
    end
  end
  
  // ========== CSR读操作 ==========
  always @(*) begin
    case (csr_addr)
      12'h300: csr_rdata = mstatus;           
      12'h305: csr_rdata = mtvec;             
      12'h341: csr_rdata = mepc;              
      12'h342: csr_rdata = mcause;            
      12'hB00: csr_rdata = mcycle[31:0];      
      12'hB80: csr_rdata = mcycle[63:32];     
      12'hF11: csr_rdata = mvendorid;         
      12'hF12: csr_rdata = marchid;           
      default: csr_rdata = 32'b0;
    endcase
  end
  
  // ========== CSR写操作 ==========
  always @(posedge clk) begin
    if (rst) begin
      mstatus <= 32'h1800;  
      mtvec   <= 32'b0;
      mepc    <= 32'b0;
      mcause  <= 32'b0;
    end else begin
      // 异常处理优先级最高
      if (exception_en) begin
        mepc   <= exception_pc;
        mcause <= exception_cause;
      end
      // CSR写操作
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
  
  // ========== 输出信号 ==========
  assign mepc_out  = mepc;
  assign mtvec_out = mtvec;

endmodule
