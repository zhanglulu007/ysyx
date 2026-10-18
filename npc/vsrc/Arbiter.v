module Arbiter(
  input clk,
  input rst,

  // IFU AXI4 AR
  input ifu_arvalid,
  output ifu_arready,
  input [31:0] ifu_araddr,
  input [3:0] ifu_arid,
  input [7:0] ifu_arlen,
  input [2:0] ifu_arsize,
  input [1:0] ifu_arburst,

  // IFU AXI4 R
  output ifu_rvalid,
  input ifu_rready,
  output [1:0] ifu_rresp,
  output [31:0] ifu_rdata,
  output ifu_rlast,
  output [3:0] ifu_rid,

  // LSU AXI4 AR
  input lsu_arvalid,
  output lsu_arready,
  input [31:0] lsu_araddr,
  input [3:0] lsu_arid,
  input [7:0] lsu_arlen,
  input [2:0] lsu_arsize,
  input [1:0] lsu_arburst,

  // LSU AXI4 R
  output lsu_rvalid,
  input lsu_rready,
  output [1:0] lsu_rresp,
  output [31:0] lsu_rdata,
  output lsu_rlast,
  output [3:0] lsu_rid,

  // LSU AXI4 AW
  input lsu_awvalid,
  output lsu_awready,
  input [31:0] lsu_awaddr,
  input [3:0] lsu_awid,
  input [7:0] lsu_awlen,
  input [2:0] lsu_awsize,
  input [1:0] lsu_awburst,

  // LSU AXI4 W
  input lsu_wvalid,
  output lsu_wready,
  input [31:0] lsu_wdata,
  input [3:0] lsu_wstrb,
  input lsu_wlast,

  // LSU AXI4 B
  output lsu_bvalid,
  input lsu_bready,
  output [1:0] lsu_bresp,
  output [3:0] lsu_bid,

  // PMEM AXI4 AR
  output mem_arvalid,
  input mem_arready,
  output [31:0] mem_araddr,
  output [3:0] mem_arid,
  output [7:0] mem_arlen,
  output [2:0] mem_arsize,
  output [1:0] mem_arburst,

  // PMEM AXI4 R
  input mem_rvalid,
  output mem_rready,
  input [1:0] mem_rresp,
  input [31:0] mem_rdata,
  input mem_rlast,
  input [3:0] mem_rid,

  // PMEM AXI4 AW
  output mem_awvalid,
  input mem_awready,
  output [31:0] mem_awaddr,
  output [3:0] mem_awid,
  output [7:0] mem_awlen,
  output [2:0] mem_awsize,
  output [1:0] mem_awburst,

  // PMEM AXI4 W
  output mem_wvalid,
  input mem_wready,
  output [31:0] mem_wdata,
  output [3:0] mem_wstrb,
  output mem_wlast,

  // PMEM AXI4 B
  input mem_bvalid,
  output mem_bready,
  input [1:0] mem_bresp,
  input [3:0] mem_bid
);

  assign mem_awvalid = lsu_awvalid;
  assign mem_awaddr = lsu_awaddr;
  assign mem_awid = lsu_awid;
  assign mem_awlen = lsu_awlen;
  assign mem_awsize = lsu_awsize;
  assign mem_awburst = lsu_awburst;
  assign lsu_awready = mem_awready;
  assign mem_wvalid = lsu_wvalid;
  assign mem_wdata = lsu_wdata;
  assign mem_wstrb = lsu_wstrb;
  assign mem_wlast = lsu_wlast;
  assign lsu_wready = mem_wready;
  assign lsu_bvalid = mem_bvalid;
  assign lsu_bresp = mem_bresp;
  assign lsu_bid = mem_bid;
  assign mem_bready = lsu_bready;

  localparam AR_NONE = 2'b00, AR_IFU = 2'b01, AR_LSU = 2'b10;
  localparam IFU_ID = 4'b0001, LSU_ID = 4'b0010;

  reg [1:0] ar_grant;

  wire ifu_ar_select = (ar_grant == AR_NONE) ? ifu_arvalid : (ar_grant == AR_IFU);
  wire lsu_ar_select = (ar_grant == AR_NONE) ? (!ifu_arvalid && lsu_arvalid) : (ar_grant == AR_LSU);

  assign mem_arvalid = ifu_ar_select || lsu_ar_select;
  assign mem_araddr = ifu_ar_select ? ifu_araddr : lsu_araddr;
  assign mem_arid = ifu_ar_select ? ifu_arid : lsu_arid;
  assign mem_arlen = ifu_ar_select ? ifu_arlen : lsu_arlen;
  assign mem_arsize = ifu_ar_select ? ifu_arsize : lsu_arsize;
  assign mem_arburst = ifu_ar_select ? ifu_arburst : lsu_arburst;

  assign ifu_arready = ifu_ar_select && mem_arready;
  assign ifu_rvalid = mem_rvalid && (mem_rid == IFU_ID);
  assign ifu_rresp = mem_rresp;
  assign ifu_rdata = mem_rdata;
  assign ifu_rlast = mem_rlast;
  assign ifu_rid = mem_rid;

  assign lsu_arready = lsu_ar_select && mem_arready;
  assign lsu_rvalid = mem_rvalid && (mem_rid == LSU_ID);
  assign lsu_rresp = mem_rresp;
  assign lsu_rdata = mem_rdata;
  assign lsu_rlast = mem_rlast;
  assign lsu_rid = mem_rid;

  assign mem_rready = (mem_rid == IFU_ID) ? ifu_rready : lsu_rready;

  wire ar_fire = mem_arvalid && mem_arready;

  always @(posedge clk) begin
    if (rst) begin
      ar_grant <= AR_NONE;
    end else begin
      if (ar_grant == AR_NONE && !ar_fire) begin
        if (ifu_arvalid) begin
          ar_grant <= AR_IFU;
        end else if (lsu_arvalid) begin
          ar_grant <= AR_LSU;
        end
      end else if (ar_fire) begin
        ar_grant <= AR_NONE;
      end
    end
  end

endmodule
