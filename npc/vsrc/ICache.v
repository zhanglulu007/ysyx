// ICache — 最小直通版本, 用于隔离问题
module ICache #(
  parameter BLOCK_SIZE   = 16,
  parameter NR_CACHE_BLK = 16
)(
  input clk, input rst,
  input cpu_arvalid, output cpu_arready, input [31:0] cpu_araddr, input [3:0] cpu_arid, input [7:0] cpu_arlen, input [2:0] cpu_arsize, input [1:0] cpu_arburst,
  output cpu_rvalid, input cpu_rready, output [31:0] cpu_rdata, output [1:0] cpu_rresp, output cpu_rlast, output [3:0] cpu_rid,
  output bus_arvalid, input bus_arready, output [31:0] bus_araddr, output [3:0] bus_arid, output [7:0] bus_arlen, output [2:0] bus_arsize, output [1:0] bus_arburst,
  input bus_rvalid, output bus_rready, input [31:0] bus_rdata, input [1:0] bus_rresp, input bus_rlast, input [3:0] bus_rid,
  output icache_access, output icache_hit, output icache_miss, output icache_uncache,
  output icache_refill_req, output icache_wait_ar, output icache_wait_r
);
  // 完全直通: AR 和 R 都原样转发
  assign cpu_arready = bus_arready;
  assign bus_arvalid = cpu_arvalid;
  assign bus_araddr  = cpu_araddr;
  assign bus_arid    = cpu_arid;
  assign bus_arlen   = cpu_arlen;
  assign bus_arsize  = cpu_arsize;
  assign bus_arburst = cpu_arburst;

  assign cpu_rvalid = bus_rvalid;
  assign bus_rready = cpu_rready;
  assign cpu_rdata  = bus_rdata;
  assign cpu_rresp  = bus_rresp;
  assign cpu_rlast  = bus_rlast;
  assign cpu_rid    = bus_rid;

  assign icache_access = 1'b0;
  assign icache_hit = 1'b0;
  assign icache_miss = 1'b0;
  assign icache_uncache = 1'b0;
  assign icache_refill_req = 1'b0;
  assign icache_wait_ar = 1'b0;
  assign icache_wait_r = 1'b0;
endmodule
