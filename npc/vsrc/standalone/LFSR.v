module LFSR(
  input  clk,
  input  rst,
  output [7:0] value
);

  reg [7:0] lfsr;

  wire feedback = lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3];

  always @(posedge clk) begin
    if (rst)
      lfsr <= 8'h5A;  // 非零种子
    else
      lfsr <= {lfsr[6:0], feedback};
  end

  assign value = lfsr;

endmodule
