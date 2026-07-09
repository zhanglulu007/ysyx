module ysyx_00000000(input clock, input reset, input io_interrupt,
  output io_master_awvalid, input io_master_awready, output [31:0] io_master_awaddr, output [3:0] io_master_awid, output [7:0] io_master_awlen, output [2:0] io_master_awsize, output [1:0] io_master_awburst,
  output io_master_wvalid, input io_master_wready, output [31:0] io_master_wdata, output [3:0] io_master_wstrb, output io_master_wlast,
  input io_master_bvalid, output io_master_bready, input [1:0] io_master_bresp, input [3:0] io_master_bid,
  output io_master_arvalid, input io_master_arready, output [31:0] io_master_araddr, output [3:0] io_master_arid, output [7:0] io_master_arlen, output [2:0] io_master_arsize, output [1:0] io_master_arburst,
  input io_master_rvalid, output io_master_rready, input [31:0] io_master_rdata, input [1:0] io_master_rresp, input io_master_rlast, input [3:0] io_master_rid,
  input io_slave_awvalid, output io_slave_awready, input [31:0] io_slave_awaddr, input [3:0] io_slave_awid, input [7:0] io_slave_awlen, input [2:0] io_slave_awsize, input [1:0] io_slave_awburst,
  input io_slave_wvalid, output io_slave_wready, input [31:0] io_slave_wdata, input [3:0] io_slave_wstrb, input io_slave_wlast,
  output io_slave_bvalid, input io_slave_bready, output [1:0] io_slave_bresp, output [3:0] io_slave_bid,
  input io_slave_arvalid, output io_slave_arready, input [31:0] io_slave_araddr, input [3:0] io_slave_arid, input [7:0] io_slave_arlen, input [2:0] io_slave_arsize, input [1:0] io_slave_arburst,
  output io_slave_rvalid, input io_slave_rready, output [31:0] io_slave_rdata, output [1:0] io_slave_rresp, output io_slave_rlast, output [3:0] io_slave_rid
);
  ysyx_26020070 u_cpu (.clock(clock), .reset(reset), .io_interrupt(io_interrupt), .*);
endmodule
