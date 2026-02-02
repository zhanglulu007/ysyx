module top(
  input clk,
  input rst,
  input [7:0] sw,
  output reg [15:0] led
);

  prencoder83 u_prencoder83 (
    .x(sw),
    .en(clk),
    .y(led[2:0])
  );

endmodule