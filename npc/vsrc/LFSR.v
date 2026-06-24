// LFSR - 8-bit Linear Feedback Shift Register
// 用于生成伪随机数, 为 SimpleBus 延迟测试提供随机性
// 多项式: x^8 + x^6 + x^5 + x^4 + 1 (maximal length = 255)
// 自由运行: 每周期更新一次, 外部在需要时采样 value

module LFSR(
  input  clk,
  input  rst,
  output [7:0] value
);

  reg [7:0] lfsr;

  // Fibonacci LFSR: x^8 + x^6 + x^5 + x^4 + 1
  // taps at bit positions 8,6,5,4 (1-indexed) -> 7,5,4,3 (0-indexed)
  wire feedback = lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3];

  always @(posedge clk) begin
    if (rst)
      lfsr <= 8'h5A;  // 非零种子
    else
      lfsr <= {lfsr[6:0], feedback};
  end

  assign value = lfsr;

endmodule
