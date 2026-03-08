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
  // Machine-mode CSRs
  reg [31:0] mstatus;   // 0x300 - Machine status register
  reg [31:0] mtvec;     // 0x305 - Machine trap-handler base address
  reg [31:0] mepc;      // 0x341 - Machine exception program counter
  reg [31:0] mcause;    // 0x342 - Machine trap cause
  reg [63:0] mcycle;    // 0xB00/0xB80 - Machine cycle counter (64-bit)
  
  // Read-only identification CSRs
  wire [31:0] mvendorid = 32'h79737978;  // 0xF11 - "ysyx" in ASCII
  wire [31:0] marchid   = 32'h26020070;  // 0xF12 - 学号（需要根据实际学号修改）
  
  // ========== mcycle计数器 ==========
  // mcycle每个时钟周期自动加1
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
      12'h300: csr_rdata = mstatus;           // mstatus
      12'h305: csr_rdata = mtvec;             // mtvec
      12'h341: csr_rdata = mepc;              // mepc
      12'h342: csr_rdata = mcause;            // mcause
      12'hB00: csr_rdata = mcycle[31:0];      // mcycle (low 32 bits)
      12'hB80: csr_rdata = mcycle[63:32];     // mcycleh (high 32 bits)
      12'hF11: csr_rdata = mvendorid;         // mvendorid
      12'hF12: csr_rdata = marchid;           // marchid
      default: csr_rdata = 32'b0;
    endcase
  end
  
  // ========== CSR写操作 ==========
  always @(posedge clk) begin
    if (rst) begin
      mstatus <= 32'h1800;  // 初始化：MPP=11 (Machine mode)
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
          12'h300: mstatus <= csr_wdata;  // mstatus
          12'h305: mtvec   <= csr_wdata;  // mtvec
          12'h341: mepc    <= csr_wdata;  // mepc
          12'h342: mcause  <= csr_wdata;  // mcause
          // mcycle是只读的，通过硬件自动递增
          // mvendorid和marchid是只读的
          default: ;
        endcase
      end
    end
  end
  
  // ========== 输出信号 ==========
  assign mepc_out  = mepc;
  assign mtvec_out = mtvec;

endmodule
