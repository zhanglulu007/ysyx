// ysyx_00000000 — Chisel BlackBox wrapper for ysyx_26020070
module ysyx_00000000(
  input         clock,
  input         reset,
  input         io_interrupt,
  output        io_master_awvalid, input io_master_awready, output [31:0] io_master_awaddr, output [3:0] io_master_awid, output [7:0] io_master_awlen, output [2:0] io_master_awsize, output [1:0] io_master_awburst,
  output        io_master_wvalid,  input io_master_wready,  output [31:0] io_master_wdata,  output [3:0] io_master_wstrb,  output io_master_wlast,
  input         io_master_bvalid,  output io_master_bready, input [1:0] io_master_bresp,   input [3:0] io_master_bid,
  output        io_master_arvalid, input io_master_arready, output [31:0] io_master_araddr, output [3:0] io_master_arid, output [7:0] io_master_arlen, output [2:0] io_master_arsize, output [1:0] io_master_arburst,
  input         io_master_rvalid,  output io_master_rready, input [31:0] io_master_rdata,  input [1:0] io_master_rresp,   input io_master_rlast, input [3:0] io_master_rid,
  input         io_slave_awvalid,  output io_slave_awready, input [31:0] io_slave_awaddr,   input [3:0] io_slave_awid,  input [7:0] io_slave_awlen, input [2:0] io_slave_awsize, input [1:0] io_slave_awburst,
  input         io_slave_wvalid,   output io_slave_wready,  input [31:0] io_slave_wdata,    input [3:0] io_slave_wstrb,  input io_slave_wlast,
  output        io_slave_bvalid,   input io_slave_bready,   output [1:0] io_slave_bresp,    output [3:0] io_slave_bid,
  input         io_slave_arvalid,  output io_slave_arready, input [31:0] io_slave_araddr,   input [3:0] io_slave_arid,  input [7:0] io_slave_arlen, input [2:0] io_slave_arsize, input [1:0] io_slave_arburst,
  output        io_slave_rvalid,   input io_slave_rready,   output [31:0] io_slave_rdata,   output [1:0] io_slave_rresp, output io_slave_rlast, output [3:0] io_slave_rid
);
  ysyx_26020070 u_cpu (
    .clock, .reset, .io_interrupt,
    .io_master_awvalid, .io_master_awready, .io_master_awaddr, .io_master_awid, .io_master_awlen, .io_master_awsize, .io_master_awburst,
    .io_master_wvalid, .io_master_wready, .io_master_wdata, .io_master_wstrb, .io_master_wlast,
    .io_master_bvalid, .io_master_bready, .io_master_bresp, .io_master_bid,
    .io_master_arvalid, .io_master_arready, .io_master_araddr, .io_master_arid, .io_master_arlen, .io_master_arsize, .io_master_arburst,
    .io_master_rvalid, .io_master_rready, .io_master_rdata, .io_master_rresp, .io_master_rlast, .io_master_rid,
    .io_slave_awvalid, .io_slave_awready, .io_slave_awaddr, .io_slave_awid, .io_slave_awlen, .io_slave_awsize, .io_slave_awburst,
    .io_slave_wvalid, .io_slave_wready, .io_slave_wdata, .io_slave_wstrb, .io_slave_wlast,
    .io_slave_bvalid, .io_slave_bready, .io_slave_bresp, .io_slave_bid,
    .io_slave_arvalid, .io_slave_arready, .io_slave_araddr, .io_slave_arid, .io_slave_arlen, .io_slave_arsize, .io_slave_arburst,
    .io_slave_rvalid, .io_slave_rready, .io_slave_rdata, .io_slave_rresp, .io_slave_rlast, .io_slave_rid
  );
endmodule
