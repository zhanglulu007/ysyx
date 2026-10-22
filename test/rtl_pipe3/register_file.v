// ============================================================================
//  RegisterFile - RV32E 16 x 32 寄存器堆
//
//  面积/时序优化:
//   * 读口不再插入 "raddr==0 ? 0 : rf[...]" 的 32-bit 零选择 mux —— 直接读
//     rf[raddr[3:0]], 靠 rf[0] 复位为 0 且永不写 x0 来保证 x0==0;
//   * 写口只对 rf[0] 做复位, 其余寄存器由软件初始化, 节省 512 个复位 mux.
// ============================================================================
module RegisterFile(
  input  clk,
  input  rst,

  input  [31:0] wdata,
  input  [4:0]  waddr,
  input         wen,

  input  [4:0]  raddr1,
  output [31:0] rdata1,
  input  [4:0]  raddr2,
  output [31:0] rdata2,

  output [31:0] a0_value
);

  reg [31:0] rf [0:15];

`ifndef SYNTHESIS
  integer init_i;
  initial begin
    for (init_i = 0; init_i < 16; init_i = init_i + 1) rf[init_i] = 32'b0;
  end
`endif

  always @(posedge clk) begin
    if (rst) begin
      rf[0] <= 32'b0;              // x0 恒为 0
    end else if (wen && (waddr != 5'b0)) begin
      rf[waddr[3:0]] <= wdata;
    end
  end

  assign rdata1   = rf[raddr1[3:0]];
  assign rdata2   = rf[raddr2[3:0]];
  assign a0_value = rf[10];

endmodule
