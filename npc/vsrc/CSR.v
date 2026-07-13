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
  output [31:0] mtvec_out,   // mtvec寄存器输出（异常入口地址）

  output [63:0] mcycle_out  // 周期计数输出
);

  // ========== CSR寄存器定义 ==========
  reg [3:0]  mstatus_fields; // {MPP[1:0], MPIE, MIE}
  reg [31:0] mtvec;     // 0x305 
  reg [30:0] mepc_hi;   // mepc[31:1], bit 0 is always zero
  reg [3:0]  mcause_code;
  reg [63:0] mcycle;    
  
  wire [31:0] mvendorid = 32'h79737978;  
  wire [31:0] marchid   = 32'h018d08e6;
  
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
      12'h300: csr_rdata = {19'b0, mstatus_fields[3:2], 3'b0,
                            mstatus_fields[1], 3'b0, mstatus_fields[0], 3'b0};
      12'h305: csr_rdata = mtvec;             
      12'h341: csr_rdata = {mepc_hi, 1'b0};
      12'h342: csr_rdata = {28'b0, mcause_code};
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
      mstatus_fields <= 4'b1100;
      mtvec   <= 32'b0;
      mepc_hi <= 31'b0;
      mcause_code <= 4'b0;
    end else begin
      // 异常处理优先级最高
      if (exception_en) begin
        mepc_hi <= exception_pc[31:1];
        mcause_code <= exception_cause[3:0];
      end
      // CSR写操作
      else if (csr_wen) begin
        case (csr_addr)
          12'h300: mstatus_fields <= {csr_wdata[12:11], csr_wdata[7], csr_wdata[3]};
          12'h305: mtvec   <= csr_wdata;  
          12'h341: mepc_hi <= csr_wdata[31:1];
          12'h342: mcause_code <= csr_wdata[3:0];
          default: ;
        endcase
      end
    end
  end
  
  // ========== 输出信号 ==========
  assign mepc_out  = {mepc_hi, 1'b0};
  assign mtvec_out = mtvec;
  assign mcycle_out = mcycle;

endmodule
