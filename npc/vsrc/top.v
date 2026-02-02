module top(
  input clk,
  input rst,
  input btc,
  input [15:0] sw,
  output [6:0] seg0,
  output [6:0] seg1,
  output reg [15:0] led
);

  // prencoder83 u_prencoder83 (
  //   .x(sw),
  //   .en(clk),
  //   .y(led[2:0])
  // );

  // alu u_alu (
  //   .A(sw[7:4]),
  //   .B(sw[3:0]),
  //   .sel(sw[10:8]),
  //   .out(led[3:0]),
  //   .Z(led[4]),
  //   .O(led[5]),
  //   .C(led[6])
  // );

  lfsr u_lfsr (
    .clk(clk),
    .rst_n(~rst),
    .btn_step(btc),
    .hex0(seg0),
    .hex1(seg1)
  );

endmodule