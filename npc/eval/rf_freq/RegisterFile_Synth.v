module RegisterFile_Synth(
  input clk,
  input rst,

  // 输入寄存器 (隔离外部I/O延迟)
  input [4:0]  in_waddr,
  input [31:0] in_wdata,
  input        in_wen,
  input [4:0]  in_raddr1,
  input [4:0]  in_raddr2,

  // 输出寄存器 (把读延迟纳入关键路径, 屏蔽外部I/O)
  output reg [31:0] out_rdata1,
  output reg [31:0] out_rdata2
);

  // ===== 输入端触发器 =====
  reg [4:0]  r_waddr;
  reg [31:0] r_wdata;
  reg        r_wen;
  reg [4:0]  r_raddr1;
  reg [4:0]  r_raddr2;

  always @(posedge clk) begin
    if (rst) begin
      r_waddr  <= 5'b0;
      r_wdata  <= 32'b0;
      r_wen    <= 1'b0;
      r_raddr1 <= 5'b0;
      r_raddr2 <= 5'b0;
    end else begin
      r_waddr  <= in_waddr;
      r_wdata  <= in_wdata;
      r_wen    <= in_wen;
      r_raddr1 <= in_raddr1;
      r_raddr2 <= in_raddr2;
    end
  end

  // ===== 可综合寄存器堆 (16个32位寄存器, RV32E) =====
  reg [31:0] regs [0:15];

  // 同步写 (x0硬连线为0)
  always @(posedge clk) begin
    if (r_wen && r_waddr != 5'b0 && !r_waddr[4]) begin
      regs[r_waddr[3:0]] <= r_wdata;
    end
  end

  // ===== 组合读 =====
  wire [31:0] read1 = (r_raddr1 == 5'b0 || r_raddr1[4]) ? 32'b0 : regs[r_raddr1[3:0]];
  wire [31:0] read2 = (r_raddr2 == 5'b0 || r_raddr2[4]) ? 32'b0 : regs[r_raddr2[3:0]];

  // ===== 输出端触发器 =====
  always @(posedge clk) begin
    if (rst) begin
      out_rdata1 <= 32'b0;
      out_rdata2 <= 32'b0;
    end else begin
      out_rdata1 <= read1;
      out_rdata2 <= read2;
    end
  end

endmodule
