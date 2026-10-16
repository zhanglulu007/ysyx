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

  // CLINT AXI4 AR
  output clint_arvalid,
  input clint_arready,
  output [31:0] clint_araddr,
  output [3:0] clint_arid,
  output [7:0] clint_arlen,
  output [2:0] clint_arsize,
  output [1:0] clint_arburst,

  // CLINT AXI4 R
  input clint_rvalid,
  output clint_rready,
  input [1:0] clint_rresp,
  input [31:0] clint_rdata,
  input clint_rlast,
  input [3:0] clint_rid,

  // CLINT AXI4 AW
  output clint_awvalid,
  input clint_awready,
  output [31:0] clint_awaddr,
  output [3:0] clint_awid,
  output [7:0] clint_awlen,
  output [2:0] clint_awsize,
  output [1:0] clint_awburst,

  // CLINT AXI4 W
  output clint_wvalid,
  input clint_wready,
  output [31:0] clint_wdata,
  output [3:0] clint_wstrb,
  output clint_wlast,

  // CLINT AXI4 B
  input clint_bvalid,
  output clint_bready,
  input [1:0] clint_bresp,
  input [3:0] clint_bid,

  // MEM AXI4 AR
  output mem_arvalid,
  input mem_arready,
  output [31:0] mem_araddr,
  output [3:0] mem_arid,
  output [7:0] mem_arlen,
  output [2:0] mem_arsize,
  output [1:0] mem_arburst,

  // MEM AXI4 R
  input mem_rvalid,
  output mem_rready,
  input [1:0] mem_rresp,
  input [31:0] mem_rdata,
  input mem_rlast,
  input [3:0] mem_rid,

  // MEM AXI4 AW
  output mem_awvalid,
  input mem_awready,
  output [31:0] mem_awaddr,
  output [3:0] mem_awid,
  output [7:0] mem_awlen,
  output [2:0] mem_awsize,
  output [1:0] mem_awburst,

  // MEM AXI4 W
  output mem_wvalid,
  input mem_wready,
  output [31:0] mem_wdata,
  output [3:0] mem_wstrb,
  output mem_wlast,

  // MEM AXI4 B
  input mem_bvalid,
  output mem_bready,
  input [1:0] mem_bresp,
  input [3:0] mem_bid
);

  localparam AR_NONE = 2'b00, AR_IFU = 2'b01, AR_LSU = 2'b10;
  localparam IFU_ID = 4'b0001, LSU_ID = 4'b0010;

  reg [1:0] ar_grant;
  reg lsu_read_clint;

  wire lsu_ar_is_clint = lsu_araddr[31:20] == 12'h020;
  wire lsu_aw_is_clint = lsu_awaddr[31:20] == 12'h020;
  wire ifu_ar_select = (ar_grant == AR_NONE) ? ifu_arvalid : (ar_grant == AR_IFU);
  wire lsu_ar_select = (ar_grant == AR_NONE) ? (!ifu_arvalid && lsu_arvalid) : (ar_grant == AR_LSU);

  assign mem_arvalid = ifu_ar_select || (lsu_ar_select && !lsu_ar_is_clint);
  assign mem_araddr = ifu_ar_select ? ifu_araddr : lsu_araddr;
  assign mem_arid = ifu_ar_select ? ifu_arid : lsu_arid;
  assign mem_arlen = ifu_ar_select ? ifu_arlen : lsu_arlen;
  assign mem_arsize = ifu_ar_select ? ifu_arsize : lsu_arsize;
  assign mem_arburst = ifu_ar_select ? ifu_arburst : lsu_arburst;

  assign clint_arvalid = lsu_ar_select && lsu_ar_is_clint;
  assign clint_araddr = lsu_araddr;
  assign clint_arid = lsu_arid;
  assign clint_arlen = lsu_arlen;
  assign clint_arsize = lsu_arsize;
  assign clint_arburst = lsu_arburst;

  assign ifu_arready = ifu_ar_select && mem_arready;
  assign ifu_rvalid = mem_rvalid && (mem_rid == IFU_ID);
  assign ifu_rresp = mem_rresp;
  assign ifu_rdata = mem_rdata;
  assign ifu_rlast = mem_rlast;
  assign ifu_rid = mem_rid;

  assign lsu_arready = lsu_ar_select &&
                       (lsu_ar_is_clint ? clint_arready : mem_arready);
  assign lsu_rvalid = lsu_read_clint ? clint_rvalid :
                      (mem_rvalid && (mem_rid == LSU_ID));
  assign lsu_rresp = lsu_read_clint ? clint_rresp : mem_rresp;
  assign lsu_rdata = lsu_read_clint ? clint_rdata : mem_rdata;
  assign lsu_rlast = lsu_read_clint ? clint_rlast : mem_rlast;
  assign lsu_rid = lsu_read_clint ? clint_rid : mem_rid;

  assign mem_rready = (mem_rid == IFU_ID) ? ifu_rready :
                      (!lsu_read_clint && lsu_rready);
  assign clint_rready = lsu_read_clint && lsu_rready;

  assign mem_awvalid = lsu_awvalid && !lsu_aw_is_clint;
  assign mem_awaddr = lsu_awaddr;
  assign mem_awid = lsu_awid;
  assign mem_awlen = lsu_awlen;
  assign mem_awsize = lsu_awsize;
  assign mem_awburst = lsu_awburst;
  assign clint_awvalid = lsu_awvalid && lsu_aw_is_clint;
  assign clint_awaddr = lsu_awaddr;
  assign clint_awid = lsu_awid;
  assign clint_awlen = lsu_awlen;
  assign clint_awsize = lsu_awsize;
  assign clint_awburst = lsu_awburst;
  assign lsu_awready = lsu_aw_is_clint ? clint_awready : mem_awready;

  assign mem_wvalid = lsu_wvalid && !lsu_aw_is_clint;
  assign mem_wdata = lsu_wdata;
  assign mem_wstrb = lsu_wstrb;
  assign mem_wlast = lsu_wlast;
  assign clint_wvalid = lsu_wvalid && lsu_aw_is_clint;
  assign clint_wdata = lsu_wdata;
  assign clint_wstrb = lsu_wstrb;
  assign clint_wlast = lsu_wlast;
  assign lsu_wready = lsu_aw_is_clint ? clint_wready : mem_wready;

  assign lsu_bvalid = lsu_aw_is_clint ? clint_bvalid : mem_bvalid;
  assign lsu_bresp = lsu_aw_is_clint ? clint_bresp : mem_bresp;
  assign lsu_bid = lsu_aw_is_clint ? clint_bid : mem_bid;
  assign mem_bready = !lsu_aw_is_clint && lsu_bready;
  assign clint_bready = lsu_aw_is_clint && lsu_bready;

  wire mem_ar_fire = mem_arvalid && mem_arready;
  wire clint_ar_fire = clint_arvalid && clint_arready;
  wire ar_fire = mem_ar_fire || clint_ar_fire;

  always @(posedge clk) begin
    if (rst) begin
      ar_grant <= AR_NONE;
      lsu_read_clint <= 1'b0;
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

      if (clint_ar_fire) begin
        lsu_read_clint <= 1'b1;
      end else if (clint_rvalid && clint_rready && clint_rlast) begin
        lsu_read_clint <= 1'b0;
      end
    end
  end

endmodule
